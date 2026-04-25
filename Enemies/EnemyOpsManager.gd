extends Node
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
const EVALUATION_INTERVAL_S  := 15.0   # how often to check deployment balance
const THREAT_SCAN_INTERVAL_S :=  8.0   # how often to assess threats and reassign missions

const VEHICLES_PER_PLATOON   := 7
const AIRCRAFT_PER_FLIGHT    := 2  # Smaller flights create more patrol routes without raising total aircraft.

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(true)
	add_to_group("origin_shifter")


func _physics_process(delta: float) -> void:
	# Tick all virtual units every frame (they self-regulate internally)
	for base in bases:
		if not is_instance_valid(base):
			continue
		for f: EnemyVirtualFlight in _get_flights(base):
			f.tick(delta)
		for p: EnemyVirtualPlatoon in _get_platoons(base):
			p.tick(delta)

	_decay_intel(delta)

	# Deployment balance check
	_eval_timer -= delta
	if _eval_timer <= 0.0:
		_eval_timer = EVALUATION_INTERVAL_S
		_evaluate_deployment()

	# Threat response
	_threat_timer -= delta
	if _threat_timer <= 0.0:
		_threat_timer = THREAT_SCAN_INTERVAL_S
		_assess_threats()


# ── Base registration ─────────────────────────────────────────────────────────

func register_base(base: EnemyBase) -> void:
	if bases.has(base):
		return
	bases.append(base)
	_base_flights[base]  = []
	_base_platoons[base] = []
	if debug_print:
		print("[EnemyOps] Base registered: %s" % base.faction_name)


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

	while deployed < target and base.aircraft_reserve >= AIRCRAFT_PER_FLIGHT:
		var role := _pick_next_flight_role(base)
		var f := base.deploy_flight(AIRCRAFT_PER_FLIGHT, role)
		if f == null:
			break
		_base_flights[base].append(f)
		get_tree().current_scene.add_child(f)
		deployed += AIRCRAFT_PER_FLIGHT
		if debug_print:
			print("[EnemyOps] Launched %s flight %s (reserve now %d)" % [
				"BOMBER" if role == EnemyVirtualFlight.AircraftRole.BOMBER else "FIGHTER",
				f.flight_name, base.aircraft_reserve])


func _evaluate_ground(base: EnemyBase) -> void:
	_clean_platoons(base)
	var deployed := _count_deployed_vehicles(base)
	var target   := int(float(base.vehicle_max) * TARGET_DEPLOY_FRACTION)

	while deployed < target and base.vehicle_reserve >= VEHICLES_PER_PLATOON:
		var p := base.deploy_platoon(VEHICLES_PER_PLATOON)
		if p == null:
			break
		_base_platoons[base].append(p)
		get_tree().current_scene.add_child(p)
		deployed += VEHICLES_PER_PLATOON
		if debug_print:
			print("[EnemyOps] Deployed platoon %s (reserve now %d)" % [p.platoon_name, base.vehicle_reserve])


## Deploy roughly 3 fighters for every 1 bomber.
func _pick_next_flight_role(base: EnemyBase) -> EnemyVirtualFlight.AircraftRole:
	var fighter_count := 0
	var bomber_count  := 0
	for f: EnemyVirtualFlight in _get_flights(base):
		if f.role == EnemyVirtualFlight.AircraftRole.BOMBER:
			bomber_count += 1
		else:
			fighter_count += 1
	# Add a bomber when we have ≥2 fighters and no bombers, then return to fighters
	if fighter_count >= 2 and bomber_count == 0:
		return EnemyVirtualFlight.AircraftRole.BOMBER
	return EnemyVirtualFlight.AircraftRole.FIGHTER


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
			p.queue_free()
			if debug_print:
				print("[EnemyOps] Platoon %s wiped out" % p.platoon_name)
	_base_platoons[base] = valid


func _get_flights(base: EnemyBase) -> Array[EnemyVirtualFlight]:
	var result: Array[EnemyVirtualFlight] = []
	var raw: Variant = _base_flights.get(base, [])
	for item in raw:
		if item is EnemyVirtualFlight and is_instance_valid(item as EnemyVirtualFlight):
			result.append(item as EnemyVirtualFlight)
	return result


func _get_platoons(base: EnemyBase) -> Array[EnemyVirtualPlatoon]:
	var result: Array[EnemyVirtualPlatoon] = []
	var raw: Variant = _base_platoons.get(base, [])
	for item in raw:
		if item is EnemyVirtualPlatoon and is_instance_valid(item as EnemyVirtualPlatoon):
			result.append(item as EnemyVirtualPlatoon)
	return result


# ── Origin shift ──────────────────────────────────────────────────────────────

func apply_origin_shift(offset: Vector3) -> void:
	for c in _known_contacts:
		c["position"] = (c["position"] as Vector3) - offset
