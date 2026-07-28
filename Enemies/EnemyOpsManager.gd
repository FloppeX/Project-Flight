extends Node

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")
## Enemy Operations Manager — autoload singleton.
##
## Tactical brain for all enemy forces. Bases register themselves here
## on spawn. EnemyOpsManager handles:
##   - Deploying most of each base's aircraft and vehicle inventory
##   - Ticking all virtual units (EnemyVirtualFlight / EnemyVirtualPlatoon)
##   - Receiving delayed intel from virtual units and decaying stale contacts
##   - Threat assessment and mission reassignment based on received intel only
##   - Restoring patrol status when threats fade

const TARGET_DEPLOY_FRACTION := 0.75   # aim for ~3/4 of inventory deployed at all times
const EVALUATION_INTERVAL_S  := 1.0    # how often to check deployment balance
const THREAT_SCAN_INTERVAL_S :=  8.0   # how often to assess threats and reassign missions
const MAX_PATROL_PAIRS_PER_EVAL := 1
const MAX_PLATOONS_PER_EVAL := 2
const OPS_SERVICE_INTERVAL_S := 0.25
const VIRTUAL_UNIT_TICK_INTERVAL_S := 2.5
const MATERIALIZING_FLIGHT_TICK_INTERVAL_S := 0.25
const ACTIVE_UNIT_TICK_INTERVAL_S := 0.75
const UNIT_TICK_JITTER_S := 0.75
const MAX_UNIT_TICKS_PER_SERVICE := 5

const VEHICLES_PER_PLATOON   := 4
const MIN_PATROL_PAIR_SIZE   := 4  # minimum aircraft needed to launch a patrol pair

## Carrier within this range of the base triggers a ground attack platoon.
const CARRIER_THREAT_RANGE_M := 14000.0
## Friendly aircraft within this range of the base triggers an intercept.
const AIR_INTERCEPT_RANGE_M  :=  6000.0

# Intel TTLs — how long a contact remains actionable after the last report.
const INTEL_TTL_CARRIER_S := 180.0
const INTEL_TTL_AIR_S     := 120.0
const INTEL_TTL_GROUND_S  := 150.0

@export var debug_print: bool = true

var bases: Array[EnemyBase] = []

# Per-base live unit lists
var _base_flights:  Dictionary = {}   # EnemyBase → Array[EnemyVirtualFlight]
var _base_platoons: Dictionary = {}   # EnemyBase → Array[EnemyVirtualPlatoon]

# Known contacts received via delayed intel reports.
# Each entry: { "type": String, "position": Vector3, "strength": int, "ttl": float }
var _known_contacts: Array[Dictionary] = []

var _eval_timer:   float = 3.0   # slight delay so bases finish spawning first
var _threat_timer: float = 5.0
var _disabled_for_test: bool = false
var _ops_clock_s: float = 0.0
var _service_accum_s: float = 0.0
var _unit_schedule_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _flight_next_tick_s: Dictionary = {}
var _flight_last_tick_s: Dictionary = {}
var _platoon_next_tick_s: Dictionary = {}
var _platoon_last_tick_s: Dictionary = {}
var _last_due_unit_count: int = 0
var _last_ticked_unit_count: int = 0
var _service_pass_count: int = 0
var _unit_tick_count: int = 0
var _last_materializing_flight_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(true)
	add_to_group("origin_shifter")
	_unit_schedule_rng.randomize()


func _physics_process(delta: float) -> void:
	if _disabled_for_test:
		return
	_ops_clock_s += maxf(delta, 0.0)
	_service_accum_s += maxf(delta, 0.0)
	if _service_accum_s < OPS_SERVICE_INTERVAL_S:
		return
	var _profiler_start: int = FrameProfiler.begin("EnemyOpsManager.physics")
	var service_delta: float = _service_accum_s
	_service_accum_s = 0.0
	_service_pass_count += 1
	_service_due_units()

	_decay_intel(service_delta)

	# Deployment balance check
	_eval_timer -= service_delta
	if _eval_timer <= 0.0:
		_eval_timer = EVALUATION_INTERVAL_S
		_evaluate_deployment()

	# Threat response
	_threat_timer -= service_delta
	if _threat_timer <= 0.0:
		_threat_timer = THREAT_SCAN_INTERVAL_S
		_assess_threats()
	FrameProfiler.end("EnemyOpsManager.physics", _profiler_start)


func _service_due_units() -> void:
	var due_units: Array[Dictionary] = []
	var materializing_flights: int = 0
	for base in bases:
		if not is_instance_valid(base):
			continue
		for flight: EnemyVirtualFlight in _get_flights(base):
			if flight.vstate == EnemyVirtualFlight.VState.MATERIALIZING:
				materializing_flights += 1
			_ensure_flight_schedule(flight)
			var flight_id: int = flight.get_instance_id()
			var flight_due_s: float = float(_flight_next_tick_s.get(flight_id, _ops_clock_s))
			if _ops_clock_s >= flight_due_s:
				due_units.append({
					"kind": "flight",
					"unit": flight,
					"due": flight_due_s,
				})
		for platoon: EnemyVirtualPlatoon in _get_platoons(base):
			_ensure_platoon_schedule(platoon)
			var platoon_id: int = platoon.get_instance_id()
			var platoon_due_s: float = float(_platoon_next_tick_s.get(platoon_id, _ops_clock_s))
			if _ops_clock_s >= platoon_due_s:
				due_units.append({
					"kind": "platoon",
					"unit": platoon,
					"due": platoon_due_s,
				})

	due_units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["due"]) < float(b["due"])
	)
	_last_materializing_flight_count = materializing_flights
	_last_due_unit_count = due_units.size()

	var ticked: int = 0
	for entry: Dictionary in due_units:
		if ticked >= MAX_UNIT_TICKS_PER_SERVICE:
			break
		var kind: String = String(entry["kind"])
		var unit_value: Variant = entry.get("unit", null)
		if not is_instance_valid(unit_value):
			continue
		if kind == "flight":
			if unit_value is EnemyVirtualFlight:
				var flight: EnemyVirtualFlight = unit_value
				_tick_scheduled_flight(flight)
				ticked += 1
		elif kind == "platoon":
			if unit_value is EnemyVirtualPlatoon:
				var platoon: EnemyVirtualPlatoon = unit_value
				_tick_scheduled_platoon(platoon)
				ticked += 1
	_last_ticked_unit_count = ticked
	_unit_tick_count += ticked


func get_report_stats() -> Dictionary:
	return {
		"service_interval_s": OPS_SERVICE_INTERVAL_S,
		"virtual_tick_interval_s": VIRTUAL_UNIT_TICK_INTERVAL_S,
		"materializing_flight_tick_interval_s": MATERIALIZING_FLIGHT_TICK_INTERVAL_S,
		"active_tick_interval_s": ACTIVE_UNIT_TICK_INTERVAL_S,
		"max_ticks_per_service": MAX_UNIT_TICKS_PER_SERVICE,
		"last_due": _last_due_unit_count,
		"last_ticked": _last_ticked_unit_count,
		"materializing_flights": _last_materializing_flight_count,
		"service_passes": _service_pass_count,
		"unit_ticks": _unit_tick_count,
		"flight_schedules": _flight_next_tick_s.size(),
		"platoon_schedules": _platoon_next_tick_s.size(),
	}


func _ensure_flight_schedule(flight: EnemyVirtualFlight) -> void:
	if flight == null or not is_instance_valid(flight):
		return
	var flight_id: int = flight.get_instance_id()
	if _flight_next_tick_s.has(flight_id):
		return
	var interval_s: float = _flight_tick_interval_s(flight)
	_flight_last_tick_s[flight_id] = _ops_clock_s
	_flight_next_tick_s[flight_id] = _ops_clock_s + _unit_schedule_rng.randf_range(0.0, interval_s)


func _ensure_platoon_schedule(platoon: EnemyVirtualPlatoon) -> void:
	if platoon == null or not is_instance_valid(platoon):
		return
	var platoon_id: int = platoon.get_instance_id()
	if _platoon_next_tick_s.has(platoon_id):
		return
	var interval_s: float = _platoon_tick_interval_s(platoon)
	_platoon_last_tick_s[platoon_id] = _ops_clock_s
	_platoon_next_tick_s[platoon_id] = _ops_clock_s + _unit_schedule_rng.randf_range(0.0, interval_s)


func _tick_scheduled_flight(flight: EnemyVirtualFlight) -> void:
	var flight_id: int = flight.get_instance_id()
	var last_tick_s: float = float(_flight_last_tick_s.get(flight_id, _ops_clock_s))
	var elapsed_s: float = maxf(_ops_clock_s - last_tick_s, OPS_SERVICE_INTERVAL_S)
	flight.tick(elapsed_s)
	_flight_last_tick_s[flight_id] = _ops_clock_s
	_flight_next_tick_s[flight_id] = _ops_clock_s + _jittered_unit_interval_s(_flight_tick_interval_s(flight))


func _tick_scheduled_platoon(platoon: EnemyVirtualPlatoon) -> void:
	var platoon_id: int = platoon.get_instance_id()
	var last_tick_s: float = float(_platoon_last_tick_s.get(platoon_id, _ops_clock_s))
	var elapsed_s: float = maxf(_ops_clock_s - last_tick_s, OPS_SERVICE_INTERVAL_S)
	platoon.tick(elapsed_s)
	_platoon_last_tick_s[platoon_id] = _ops_clock_s
	_platoon_next_tick_s[platoon_id] = _ops_clock_s + _jittered_unit_interval_s(_platoon_tick_interval_s(platoon))


func _flight_tick_interval_s(flight: EnemyVirtualFlight) -> float:
	if flight != null and flight.vstate == EnemyVirtualFlight.VState.MATERIALIZING:
		return MATERIALIZING_FLIGHT_TICK_INTERVAL_S
	if flight != null and flight.vstate == EnemyVirtualFlight.VState.ACTIVE:
		return ACTIVE_UNIT_TICK_INTERVAL_S
	return VIRTUAL_UNIT_TICK_INTERVAL_S


func _platoon_tick_interval_s(platoon: EnemyVirtualPlatoon) -> float:
	if platoon != null and platoon.vstate == EnemyVirtualPlatoon.VState.ACTIVE:
		return ACTIVE_UNIT_TICK_INTERVAL_S
	return VIRTUAL_UNIT_TICK_INTERVAL_S


func _jittered_unit_interval_s(base_interval_s: float) -> float:
	var jitter_limit_s: float = minf(UNIT_TICK_JITTER_S, base_interval_s * 0.35)
	return maxf(OPS_SERVICE_INTERVAL_S, base_interval_s + _unit_schedule_rng.randf_range(-jitter_limit_s, jitter_limit_s))


func _forget_flight_schedule(flight: EnemyVirtualFlight) -> void:
	if flight == null:
		return
	var flight_id: int = flight.get_instance_id()
	_flight_next_tick_s.erase(flight_id)
	_flight_last_tick_s.erase(flight_id)


func _forget_platoon_schedule(platoon: EnemyVirtualPlatoon) -> void:
	if platoon == null:
		return
	var platoon_id: int = platoon.get_instance_id()
	_platoon_next_tick_s.erase(platoon_id)
	_platoon_last_tick_s.erase(platoon_id)


# ── Base registration ─────────────────────────────────────────────────────────

func register_base(base: EnemyBase) -> void:
	if _disabled_for_test:
		if is_instance_valid(base):
			base.queue_free()
		return
	if bases.has(base):
		return
	bases.append(base)
	_base_flights[base]  = []
	_base_platoons[base] = []
	if debug_print:
		print("[EnemyOps] Base registered: %s" % base.faction_name)


# ── Turbine degradation ───────────────────────────────────────────────────────

func enable_for_game() -> void:
	_disabled_for_test = false
	set_physics_process(true)
	_eval_timer = 1.0
	_threat_timer = 5.0
	_service_accum_s = 0.0


func on_turbine_destroyed() -> void:
	for base in bases:
		if not is_instance_valid(base):
			continue
		base.aircraft_max             = maxi(floori(float(base.aircraft_max) * 0.98), 1)
		base.aircraft_reserve         = mini(base.aircraft_reserve, base.aircraft_max)
		base.vehicle_max              = maxi(floori(float(base.vehicle_max) * 0.98), 1)
		base.vehicle_reserve          = mini(base.vehicle_reserve, base.vehicle_max)
		base.aircraft_replenish_interval_s *= 1.02
		base.vehicle_replenish_interval_s  *= 1.02
	if debug_print:
		print("[EnemyOps] Turbine destroyed — enemy capacity and production degraded by 2%%")


# ── Deployment ────────────────────────────────────────────────────────────────

func _evaluate_deployment() -> void:
	for base in bases:
		if not is_instance_valid(base):
			continue
		_evaluate_air(base)
		_evaluate_ground(base)


func _evaluate_air(base: EnemyBase) -> void:
	_clean_flights(base)
	var deployed := _count_deployed_aircraft(base)
	var target   := int(float(base.aircraft_max) * TARGET_DEPLOY_FRACTION)

	var launched_pairs := 0
	while deployed < target and base.aircraft_reserve >= MIN_PATROL_PAIR_SIZE and launched_pairs < MAX_PATROL_PAIRS_PER_EVAL:
		var deploy_start: int = FrameProfiler.begin("EnemyOps.deploy_air")
		var pair: Array[EnemyVirtualFlight] = base.deploy_patrol_pair()
		FrameProfiler.end("EnemyOps.deploy_air", deploy_start)
		if pair.is_empty():
			break
		launched_pairs += 1
		for f: EnemyVirtualFlight in pair:
			_base_flights[base].append(f)
			get_tree().current_scene.add_child(f)
			deployed += f.aircraft_count
		if debug_print and pair.size() >= 2:
			print("[EnemyOps] Patrol %s/%s launched (%d+%d ac, reserve now %d)" % [
				pair[0].flight_name, pair[1].flight_name,
				pair[0].aircraft_count, pair[1].aircraft_count,
				base.aircraft_reserve])


func _evaluate_ground(base: EnemyBase) -> void:
	_clean_platoons(base)
	var deployed := _count_deployed_vehicles(base)
	var target   := int(float(base.vehicle_max) * TARGET_DEPLOY_FRACTION)

	var deployed_platoons := 0
	while deployed < target and base.vehicle_reserve >= VEHICLES_PER_PLATOON and deployed_platoons < MAX_PLATOONS_PER_EVAL:
		var deploy_start: int = FrameProfiler.begin("EnemyOps.deploy_platoon")
		var p: EnemyVirtualPlatoon = base.deploy_platoon(VEHICLES_PER_PLATOON)
		FrameProfiler.end("EnemyOps.deploy_platoon", deploy_start)
		if p == null:
			break
		deployed_platoons += 1
		_base_platoons[base].append(p)
		get_tree().current_scene.add_child(p)
		deployed += VEHICLES_PER_PLATOON
		if debug_print:
			print("[EnemyOps] Deployed platoon %s (reserve now %d)" % [p.platoon_name, base.vehicle_reserve])


func _count_deployed_aircraft(base: EnemyBase) -> int:
	var n := 0
	for f: EnemyVirtualFlight in _get_flights(base):
		n += f.aircraft_count
	return n


func _count_deployed_vehicles(base: EnemyBase) -> int:
	var n := 0
	for p: EnemyVirtualPlatoon in _get_platoons(base):
		n += p.vehicle_count
	return n


# ── Intel reception ───────────────────────────────────────────────────────────

## Called by EnemyVirtualFlight / EnemyVirtualPlatoon after their radio-delay timer fires.
func receive_intel(reporter_name: String, contact_type: String, contact_pos: Vector3, strength: int) -> void:
	var ttl := _ttl_for_type(contact_type)
	# Update existing entry if present, otherwise append.
	for c in _known_contacts:
		if c["type"] == contact_type:
			c["position"] = contact_pos
			c["strength"] = strength
			c["ttl"]      = ttl
			if debug_print:
				print("[EnemyOps] Intel update from %s: %s at (%.0f, %.0f)" % [
					reporter_name, contact_type, contact_pos.x, contact_pos.z])
			return
	_known_contacts.append({
		"type":     contact_type,
		"position": contact_pos,
		"strength": strength,
		"ttl":      ttl,
	})
	if debug_print:
		print("[EnemyOps] New intel from %s: %s at (%.0f, %.0f)" % [
			reporter_name, contact_type, contact_pos.x, contact_pos.z])


func _ttl_for_type(contact_type: String) -> float:
	match contact_type:
		"carrier": return INTEL_TTL_CARRIER_S
		"air":     return INTEL_TTL_AIR_S
		_:         return INTEL_TTL_GROUND_S


func _decay_intel(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for c in _known_contacts:
		c["ttl"] -= delta
		if c["ttl"] > 0.0:
			alive.append(c)
		elif debug_print:
			print("[EnemyOps] Intel expired: %s contact" % c["type"])
	_known_contacts = alive


func _get_contact(contact_type: String) -> Dictionary:
	for c in _known_contacts:
		if c["type"] == contact_type:
			return c
	return {}


# ── Threat assessment (intel-driven) ─────────────────────────────────────────

func _assess_threats() -> void:
	for base in bases:
		if not is_instance_valid(base):
			continue
		_clean_flights(base)
		_clean_platoons(base)

		var flights:  Array = _get_flights(base)
		var platoons: Array = _get_platoons(base)

		# ── Air threat: redirect one patrol flight to intercept ────────────────
		var air_contact := _get_contact("air")
		var has_intercept := false
		for f: EnemyVirtualFlight in flights:
			if f.mission == EnemyVirtualFlight.Mission.INTERCEPT:
				has_intercept = true
				break

		if not air_contact.is_empty():
			var air_dist := base.global_position.distance_to(air_contact["position"] as Vector3)
			if not has_intercept and air_dist < AIR_INTERCEPT_RANGE_M:
				# Only send fighters on intercept — bombers stick to ground attack
				for f: EnemyVirtualFlight in flights:
					if f.mission == EnemyVirtualFlight.Mission.PATROL \
							and f.role == EnemyVirtualFlight.AircraftRole.FIGHTER:
						f.mission = EnemyVirtualFlight.Mission.INTERCEPT
						if debug_print:
							print("[EnemyOps] Flight %s → INTERCEPT (intel: air %.0fm away)" % [
								f.flight_name, air_dist])
						break
		elif has_intercept:
			# No current air intel — stand down
			for f: EnemyVirtualFlight in flights:
				if f.mission == EnemyVirtualFlight.Mission.INTERCEPT:
					f.mission = EnemyVirtualFlight.Mission.PATROL
					if debug_print:
						print("[EnemyOps] Flight %s → PATROL (no air intel)" % f.flight_name)
					break

		# ── Ground threat: redirect one patrol platoon to attack carrier ───────
		var carrier_contact := _get_contact("carrier")
		var attacking := 0
		for p: EnemyVirtualPlatoon in platoons:
			if p.mission in [EnemyVirtualPlatoon.Mission.ATTACK_CARRIER, EnemyVirtualPlatoon.Mission.ATTACK_POSITION]:
				attacking += 1

		if not carrier_contact.is_empty():
			var carrier_pos  := carrier_contact["position"] as Vector3
			var carrier_dist := base.global_position.distance_to(carrier_pos)
			if attacking == 0 and carrier_dist < CARRIER_THREAT_RANGE_M:
				for p: EnemyVirtualPlatoon in platoons:
					if p.mission == EnemyVirtualPlatoon.Mission.PATROL:
						p.set_mission_attack_position(carrier_pos)
						if debug_print:
							print("[EnemyOps] Platoon %s → ATTACK CARRIER POSITION (intel: %.0fm away)" % [
								p.platoon_name, carrier_dist])
						break
		elif attacking > 0:
			# No carrier intel — recall
			for p: EnemyVirtualPlatoon in platoons:
				if p.mission in [EnemyVirtualPlatoon.Mission.ATTACK_CARRIER, EnemyVirtualPlatoon.Mission.ATTACK_POSITION]:
					p.set_mission_patrol()
					if debug_print:
						print("[EnemyOps] Platoon %s → PATROL (carrier intel expired)" % p.platoon_name)


# ── Unit cleanup ──────────────────────────────────────────────────────────────

func _clean_flights(base: EnemyBase) -> void:
	var valid: Array[EnemyVirtualFlight] = []
	for f: EnemyVirtualFlight in _get_flights(base):
		if f.aircraft_count > 0:
			valid.append(f)
		else:
			# Flight wiped out — remove from scene
			_forget_flight_schedule(f)
			f.queue_free()
			if debug_print:
				print("[EnemyOps] Flight %s wiped out" % f.flight_name)
	_base_flights[base] = valid


func _clean_platoons(base: EnemyBase) -> void:
	var valid: Array[EnemyVirtualPlatoon] = []
	for p: EnemyVirtualPlatoon in _get_platoons(base):
		if p.vehicle_count > 0:
			valid.append(p)
		else:
			_forget_platoon_schedule(p)
			p.queue_free()
			if debug_print:
				print("[EnemyOps] Platoon %s wiped out" % p.platoon_name)
	_base_platoons[base] = valid


func _get_flights(base: EnemyBase) -> Array[EnemyVirtualFlight]:
	var result: Array[EnemyVirtualFlight] = []
	var raw: Variant = _base_flights.get(base, [])
	for item in raw:
		if is_instance_valid(item) and item is EnemyVirtualFlight:
			var flight: EnemyVirtualFlight = item
			result.append(flight)
	return result


func _get_platoons(base: EnemyBase) -> Array[EnemyVirtualPlatoon]:
	var result: Array[EnemyVirtualPlatoon] = []
	var raw: Variant = _base_platoons.get(base, [])
	for item in raw:
		if is_instance_valid(item) and item is EnemyVirtualPlatoon:
			var platoon: EnemyVirtualPlatoon = item
			result.append(platoon)
	return result


func disable_for_heli_test() -> void:
	_disabled_for_test = true
	set_physics_process(false)
	_known_contacts.clear()
	for base in bases:
		if not is_instance_valid(base):
			continue
		for f: EnemyVirtualFlight in _get_flights(base):
			_forget_flight_schedule(f)
			f.dematerialize()
			f.queue_free()
		for p: EnemyVirtualPlatoon in _get_platoons(base):
			_forget_platoon_schedule(p)
			p.dematerialize()
			p.queue_free()
	_base_flights.clear()
	_base_platoons.clear()
	_flight_next_tick_s.clear()
	_flight_last_tick_s.clear()
	_platoon_next_tick_s.clear()
	_platoon_last_tick_s.clear()
	bases.clear()
	print("[EnemyOps] disabled for helicopter test")


# ── Origin shift ──────────────────────────────────────────────────────────────

func apply_origin_shift(offset: Vector3) -> void:
	for c in _known_contacts:
		c["position"] = (c["position"] as Vector3) - offset
