extends Node

## Air Operations Manager — autoload singleton (Citadel).
##
## Manages four named flights (Archer, Bulldog, Crimson, Dingo).
## ALL tactical decisions live here: which flight intercepts, which does CAS,
## when to recall, and reassignment when a flight is wiped out.
## Flights and pilots only execute orders.
##
## Usage:
##   AirOpsManager.order_cap("Archer")
##   AirOpsManager.order_cas("Bulldog", area_center, 2500.0)
##   AirOpsManager.order_rtb("Crimson")

const FLIGHT_NAMES := ["Archer", "Bulldog", "Crimson", "Dingo"]

@export var assignment_interval_s: float = 3.0
@export var threat_scan_interval_s: float = 2.5
@export var debug_print: bool = true

@export var default_mission: Flight.Mission = Flight.Mission.CAP
@export var default_cap_altitude_m: float = 800.0
@export var default_cas_altitude_m: float = 300.0

## Aircraft to launch per scramble when a flight has no members.
@export var scramble_flight_size: int = 2

## Keep at least one dedicated flight patrolling over the carrier.
@export var maintain_carrier_cap: bool = true

var flights: Array[Flight] = []

var _carrier: Node3D = null
var _assign_timer: float = 0.0
var _threat_timer: float = 0.0
var _next_flight_idx: int = 0

## Currently assigned missions. Null means no flight holds that role.
var _cap_flight: Flight = null
var _intercept_flight: Flight = null
var _cas_flight: Flight = null

## Flight currently being scrambled from the hangar (waiting for launches).
var _scrambling_flight: Flight = null

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	for fname in FLIGHT_NAMES:
		var f := Flight.new()
		f.name = "Flight_" + fname
		f.flight_name = fname
		f.debug_print = debug_print
		f.mission = default_mission
		add_child(f)
		flights.append(f)
	print("[AirOpsManager] Ready — flights: %s" % ", ".join(FLIGHT_NAMES))
	call_deferred("_apply_default_missions")

func _apply_default_missions() -> void:
	_refresh_carrier()
	for f in flights:
		if default_mission == Flight.Mission.CAP:
			f.set_cap(_carrier, default_cap_altitude_m)
		elif default_mission == Flight.Mission.CAS:
			order_cas(f.flight_name)

func _process(delta: float) -> void:
	_assign_timer -= delta
	if _assign_timer <= 0.0:
		_assign_timer = assignment_interval_s
		_refresh_carrier()
		_auto_assign_unassigned()
		_ensure_carrier_cap()

	_threat_timer -= delta
	if _threat_timer <= 0.0:
		_threat_timer = threat_scan_interval_s
		_update_intercept()
		_update_cas()

# ── Ordering API ───────────────────────────────────────────────────────────────

func order_cap(fname: String, altitude_m: float = 800.0) -> void:
	var f := get_flight(fname)
	if not f:
		push_warning("[AirOpsManager] Unknown flight: " + fname)
		return
	_clear_role(f)
	_refresh_carrier()
	f.set_cap(_carrier, altitude_m)
	RadioComms.say_cap_order(fname, altitude_m)
	_ensure_flight_can_execute(f)

func order_cap_route(fname: String, route_points: Array[Vector3], altitude_m: float = 800.0) -> void:
	var f := get_flight(fname)
	if not f:
		push_warning("[AirOpsManager] Unknown flight: " + fname)
		return
	_clear_role(f)
	_refresh_carrier()
	f.set_cap_route(_carrier, route_points, altitude_m)
	RadioComms.say_cap_order(fname, altitude_m)
	_ensure_flight_can_execute(f)

func order_cas(fname: String, area_center: Vector3 = Vector3.ZERO, area_radius: float = 3000.0, altitude_m: float = -1.0) -> void:
	var f := get_flight(fname)
	if not f:
		push_warning("[AirOpsManager] Unknown flight: " + fname)
		return
	_clear_role(f)
	var center := area_center
	var mission_altitude := altitude_m if altitude_m > 0.0 else default_cas_altitude_m
	if center == Vector3.ZERO:
		_refresh_carrier()
		if _carrier and is_instance_valid(_carrier):
			center = _carrier.global_position
	f.set_cas(center, area_radius, mission_altitude)
	RadioComms.say_cas_order(fname)
	_ensure_flight_can_execute(f)

func order_rtb(fname: String) -> void:
	var f := get_flight(fname)
	if not f:
		push_warning("[AirOpsManager] Unknown flight: " + fname)
		return
	_clear_role(f)
	f.set_rtb()
	RadioComms.say_rtb_order(fname)

func reassign(aircraft: Node3D, fname: String) -> void:
	for f in flights:
		f.unregister(aircraft)
	var target := get_flight(fname)
	if target:
		target.register(aircraft)

func get_flight_of(aircraft: Node3D) -> Flight:
	for f in flights:
		if f.get_members().has(aircraft):
			return f
	return null

func get_flight(fname: String) -> Flight:
	for f in flights:
		if f.flight_name == fname:
			return f
	return null

func get_flight_names() -> Array[String]:
	var result: Array[String] = []
	for flight_name in FLIGHT_NAMES:
		result.append(flight_name)
	return result

func get_flight_status(fname: String) -> Dictionary:
	var f := get_flight(fname)
	if not f:
		return {}
	var summary := f.get_status_summary()
	summary["kind"] = "flight"
	summary["role"] = _get_role_name(f)
	summary["is_scrambling"] = f == _scrambling_flight
	summary["empty"] = f.strength() <= 0
	return summary

func print_status() -> void:
	print("=== Air Ops Status ===")
	for f in flights:
		var role := ""
		if f == _intercept_flight: role = " [INTERCEPT]"
		elif f == _cas_flight: role = " [CAS]"
		elif f == _cap_flight: role = " [CAP]"
		print("  [%s] %d aircraft  mission=%s%s" % [
			f.flight_name, f.strength(), Flight.Mission.keys()[f.mission], role
		])
	print("======================")

# ── Intercept management ───────────────────────────────────────────────────────

func _update_intercept() -> void:
	var threats := _get_enemy_aircraft()

	# Check if the assigned intercept flight is still viable
	if _intercept_flight != null:
		if not _flight_is_active(_intercept_flight):
			_on_flight_lost(_intercept_flight, "intercept")
			_intercept_flight = null
		elif threats.is_empty() and not _intercept_flight.is_engaged():
			# Threat cleared — recall
			_recall_to_cap(_intercept_flight,
				"Threat neutralised. %s flight, resume CAP.",
				"%s flight, good work. Return to patrol.",
				"Skies clear. %s flight, back on station.")
			_intercept_flight = null
			return

	if threats.is_empty():
		return

	# Threats present and no assigned intercept flight — vector one now
	if _intercept_flight == null:
		_vector_intercept(threats[0])

func _vector_intercept(threat: Node3D) -> void:
	var best := _pick_flight(_cas_flight)
	if not best:
		var empty := _pick_empty_flight(_cas_flight)
		if empty:
			empty.set_cap(_carrier, default_cap_altitude_m)
			_intercept_flight = empty
			if empty == _cap_flight:
				_cap_flight = null
			_scramble_flight(empty, "intercept")
		return
	if best.strength() == 0:
		best.set_cap(_carrier, default_cap_altitude_m)
		_scramble_flight(best, "intercept")
		return

	# If this flight was on CAS, release that role
	if best == _cas_flight:
		_cas_flight = null

	_intercept_flight = best
	if best == _cap_flight:
		_cap_flight = null
	var fname := best.flight_name

	RadioComms.transmit("Citadel", "%s flight" % fname, RadioComms._pick([
		"%s flight, radar contact. Intercept and engage. Weapons free." % fname,
		"%s flight, bogeys inbound. Vector to intercept." % fname,
		"%s, bandits on scope. Intercept. Weapons free." % fname,
	]))
	RadioComms.transmit_delayed("%s lead" % fname, "Citadel", RadioComms._pick([
		"Copy. Going to intercept.",
		"Roger. Tally. Engaging.",
		"Wilco. Flight, weapons free.",
	]), randf_range(1.0, 2.2))

# ── CAS management ────────────────────────────────────────────────────────────

func _update_cas() -> void:
	var threats := _get_enemy_ground_vehicles()

	# Check if the assigned CAS flight is still viable
	if _cas_flight != null:
		if not _flight_is_active(_cas_flight):
			_on_flight_lost(_cas_flight, "CAS")
			_cas_flight = null
		elif threats.is_empty():
			# Ground threats cleared — recall
			_recall_to_cap(_cas_flight,
				"Ground targets clear. %s flight, return to CAP.",
				"Good hunting. %s flight, back on station.",
				"Area clear. %s flight, resume patrol.")
			_cas_flight = null
			return

	if threats.is_empty():
		return

	# Threats present and no assigned CAS flight — vector one now
	if _cas_flight == null:
		_vector_cas(threats[0])

func _vector_cas(threat: Node3D) -> void:
	var best := _pick_flight(_intercept_flight)
	if not best:
		var empty := _pick_empty_flight(_intercept_flight)
		if empty:
			empty.set_cas(threat.global_position, 3000.0, default_cas_altitude_m)
			_cas_flight = empty
			if empty == _cap_flight:
				_cap_flight = null
			_scramble_flight(empty, "cas")
		return
	if best.strength() == 0:
		var center_for_scramble := threat.global_position if (threat and is_instance_valid(threat)) else Vector3.ZERO
		best.set_cas(center_for_scramble, 3000.0, default_cas_altitude_m)
		_scramble_flight(best, "cas")
		return

	# If this flight was on intercept, release that role
	if best == _intercept_flight:
		_intercept_flight = null

	_cas_flight = best
	if best == _cap_flight:
		_cap_flight = null
	var fname := best.flight_name
	_refresh_carrier()
	var center := threat.global_position if (threat and is_instance_valid(threat)) else Vector3.ZERO
	if center == Vector3.ZERO and (_carrier and is_instance_valid(_carrier)):
		center = _carrier.global_position
	best.set_cas(center, 3000.0, default_cas_altitude_m)

	RadioComms.transmit("Citadel", "%s flight" % fname, RadioComms._pick([
		"%s flight, enemy ground forces spotted. Cleared hot. Attack at will." % fname,
		"%s flight, ground targets acquired. CAS mission. Cleared hot." % fname,
		"%s, hostiles on the deck. Prosecute ground attack. Weapons free." % fname,
	]))
	RadioComms.transmit_delayed("%s lead" % fname, "Citadel", RadioComms._pick([
		"Copy. Rolling in.",
		"Roger. Selecting targets.",
		"Wilco. Flight, going for the deck.",
	]), randf_range(1.0, 2.2))

# ── Recall ────────────────────────────────────────────────────────────────────

func _recall_to_cap(f: Flight, line_a: String, line_b: String, line_c: String) -> void:
	_refresh_carrier()
	f.set_cap(_carrier, default_cap_altitude_m)
	if _cap_flight == null and _flight_can_hold_cap(f):
		_cap_flight = f
	var fname := f.flight_name
	RadioComms.transmit("Citadel", "%s flight" % fname, RadioComms._pick([
		line_a % fname, line_b % fname, line_c % fname,
	]))
	RadioComms.transmit_delayed("%s lead" % fname, "Citadel", RadioComms._pick([
		"Copy. Resuming CAP.",
		"Roger. Back on patrol.",
		"Wilco. Flight, form up.",
	]), randf_range(0.8, 1.8))

func _on_flight_lost(f: Flight, role: String) -> void:
	## Called when a flight assigned to a role has been wiped out.
	if debug_print:
		print("[AirOpsManager] %s flight lost while on %s. Reassigning." % [f.flight_name, role])
	RadioComms.transmit("Citadel", "All flights",
		"%s flight is down. Reassigning %s mission." % [f.flight_name, role])

# ── Internal ───────────────────────────────────────────────────────────────────

func _scramble_flight(f: Flight, reason: String = "intercept") -> void:
	## Launch aircraft from the hangar and assign them to flight f.
	## AirOpsManager acts as the callback target so launched pilots get registered.
	var fdm := get_tree().get_first_node_in_group("flight_deck_manager")
	if not fdm or not fdm.has_method("queue_ai_flight"):
		push_warning("[AirOpsManager] No FlightDeckManager — cannot scramble %s" % f.flight_name)
		return
	if _scrambling_flight != null:
		if debug_print:
			print("[AirOpsManager] Scramble already in progress for %s, skipping" % _scrambling_flight.flight_name)
		return
	_scrambling_flight = f
	print("[AirOpsManager] Scrambling %s flight (%d aircraft)" % [f.flight_name, scramble_flight_size])
	if reason == "cap":
		RadioComms.transmit("Citadel", "%s flight" % f.flight_name, RadioComms._pick([
			"%s flight, launch for carrier CAP." % f.flight_name,
			"%s, launch and establish patrol over the carrier." % f.flight_name,
			"%s flight, launch to maintain air cover." % f.flight_name,
		]))
	elif reason == "cas":
		RadioComms.transmit("Citadel", "%s flight" % f.flight_name, RadioComms._pick([
			"%s flight, launch for close air support." % f.flight_name,
			"%s, launch immediately. Ground targets marked." % f.flight_name,
			"%s flight, scramble for CAS. Cleared hot after departure." % f.flight_name,
		]))
	else:
		RadioComms.transmit("Citadel", "%s flight" % f.flight_name, RadioComms._pick([
			"%s flight, scramble. Threat inbound." % f.flight_name,
			"%s, launch immediately. Threat on scope." % f.flight_name,
			"All hands, scramble %s flight. Weapons free." % f.flight_name,
		]))
	fdm.queue_ai_flight(scramble_flight_size, self, _loadout_profile_for_scramble_reason(reason))

## Called by FlightDeckManager after each aircraft launches during a scramble.
func notify_aircraft_launched(pilot: AIPilot) -> void:
	if not _scrambling_flight:
		return
	var aircraft := pilot.aircraft as Node3D
	if aircraft:
		reassign(aircraft, _scrambling_flight.flight_name)
		if debug_print:
			print("[AirOpsManager] %s launched → %s flight (%d members)" % [
				aircraft.name, _scrambling_flight.flight_name, _scrambling_flight.strength()])
	# Once expected number launched, clear the in-progress flag
	if _scrambling_flight.strength() >= scramble_flight_size:
		RadioComms.transmit_delayed("%s lead" % _scrambling_flight.flight_name, "Citadel",
			RadioComms._pick(["Airborne. Climbing to station.", "Off the deck. Coming around.", "Up and away."]),
			randf_range(1.5, 3.0))
		_scrambling_flight = null

func _flight_is_active(f: Flight) -> bool:
	## A flight is active if it exists and has at least one living member.
	return f != null and f.strength() > 0

func _pick_flight(exclude: Flight = null) -> Flight:
	## Pick the best available flight for a new mission, excluding one flight
	## if possible (so we don't pull the same flight off two duties at once).
	## Prefers flights not already engaged, closest to carrier.
	_refresh_carrier()
	var origin := _carrier.global_position if (_carrier and is_instance_valid(_carrier)) else Vector3.ZERO

	var best: Flight = null
	var best_score: float = INF
	for f in flights:
		if not _flight_is_active(f):
			continue
		if f.mission == Flight.Mission.RTB:
			continue
		if f == exclude:
			continue
		var dist := _flight_center(f).distance_to(origin)
		# Penalty for flights already in a special role or engaged
		var penalty := 0.0
		if f == _intercept_flight or f == _cas_flight:
			penalty = 10000.0
		if f.is_engaged():
			penalty += 5000.0
		var score := dist + penalty
		if score < best_score:
			best_score = score
			best = f

	# Fallback: ignore the exclude restriction if nothing else is available
	if not best:
		for f in flights:
			if _flight_is_active(f) and f.mission != Flight.Mission.RTB:
				best = f
				break

	return best

func _ensure_carrier_cap() -> void:
	if not maintain_carrier_cap:
		return
	_refresh_carrier()
	if not _carrier or not is_instance_valid(_carrier):
		return

	if _cap_flight != null \
			and is_instance_valid(_cap_flight) \
			and _cap_flight == _scrambling_flight \
			and _cap_flight.mission == Flight.Mission.CAP:
		return

	if _flight_can_hold_cap(_cap_flight):
		return
	_cap_flight = null

	var best := _pick_cap_candidate()
	if best:
		_cap_flight = best
		if best.mission != Flight.Mission.CAP:
			best.set_cap(_carrier, default_cap_altitude_m)
		if debug_print:
			print("[AirOpsManager] %s flight assigned carrier CAP" % best.flight_name)
		return

	if _scrambling_flight != null:
		return

	var empty := _pick_empty_flight()
	if empty:
		_cap_flight = empty
		empty.set_cap(_carrier, default_cap_altitude_m)
		_scramble_flight(empty, "cap")

func _flight_can_hold_cap(f: Flight) -> bool:
	return f != null \
		and is_instance_valid(f) \
		and _flight_is_active(f) \
		and f.mission == Flight.Mission.CAP \
		and f != _intercept_flight \
		and f != _cas_flight

func _pick_cap_candidate() -> Flight:
	_refresh_carrier()
	var origin := _carrier.global_position if (_carrier and is_instance_valid(_carrier)) else Vector3.ZERO
	var best: Flight = null
	var best_score := INF
	for f in flights:
		if not _flight_is_active(f):
			continue
		if f.mission == Flight.Mission.RTB:
			continue
		if f == _intercept_flight or f == _cas_flight:
			continue
		var score := _flight_center(f).distance_to(origin)
		if f.mission != Flight.Mission.CAP:
			score += 2000.0
		if f.is_engaged():
			score += 5000.0
		if score < best_score:
			best_score = score
			best = f
	return best

func _pick_empty_flight(exclude: Flight = null) -> Flight:
	for f in flights:
		if f == exclude:
			continue
		if f == _intercept_flight or f == _cas_flight:
			continue
		if f.strength() > 0:
			continue
		if f.mission == Flight.Mission.RTB:
			continue
		return f
	return null

func _loadout_profile_for_scramble_reason(reason: String) -> String:
	if reason == "cas":
		return "strike"
	return "cap"

func _clear_role(f: Flight) -> void:
	## When a flight is manually ordered, release any automatic role it held.
	if f == _cap_flight:
		_cap_flight = null
	if f == _intercept_flight:
		_intercept_flight = null
	if f == _cas_flight:
		_cas_flight = null

func _ensure_flight_can_execute(f: Flight) -> void:
	if f == null or not is_instance_valid(f):
		return
	if f.strength() > 0:
		return
	var reason := "intercept"
	if f.mission == Flight.Mission.CAP:
		reason = "cap"
	elif f.mission == Flight.Mission.CAS:
		reason = "cas"
	_scramble_flight(f, reason)

func _refresh_carrier() -> void:
	if not _carrier or not is_instance_valid(_carrier):
		_carrier = get_tree().get_first_node_in_group("carrier") as Node3D

func _get_role_name(f: Flight) -> String:
	if f == _intercept_flight:
		return "INTERCEPT"
	if f == _cas_flight:
		return "CAS"
	if f == _cap_flight:
		return "CAP"
	return "STANDBY"

func _auto_assign_unassigned() -> void:
	var candidates: Array[Node3D] = []
	for group in ["aircraft", "friendlies"]:
		for node in get_tree().get_nodes_in_group(group):
			if not (node is Node3D) or not is_instance_valid(node):
				continue
			if not node.has_method("get_team") or int(node.get_team()) != 1:
				continue
			if get_flight_of(node) != null:
				continue
			if bool(node.get_meta("controls_disabled", false)):
				continue
			if bool(node.get_meta("parking_brake", false)):
				continue
			if bool(node.get_meta("carrier_transport_mode", false)):
				continue
			if not candidates.has(node):
				candidates.append(node)

	for aircraft in candidates:
		var f := flights[_next_flight_idx % flights.size()]
		f.register(aircraft)
		_next_flight_idx += 1

func _get_enemy_ground_vehicles() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("ground_vehicles"):
		if node and is_instance_valid(node) and node.has_method("get_team") \
				and int(node.get_team()) != 1:
			result.append(node)
	return result

func _get_enemy_aircraft() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if node and is_instance_valid(node) \
				and node is RigidBody3D \
				and not node.is_in_group("ground_vehicles"):
			result.append(node)
	return result

func _flight_center(f: Flight) -> Vector3:
	var members := f.get_members()
	if members.is_empty():
		return _carrier.global_position if (_carrier and is_instance_valid(_carrier)) else Vector3.ZERO
	var sum := Vector3.ZERO
	for m in members:
		sum += m.global_position
	return sum / float(members.size())
