extends Node

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")

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
@export var debug_print: bool = false
@export var mission_tasking_enabled: bool = true

@export var default_mission: Flight.Mission = Flight.Mission.CAP
@export var default_cap_altitude_m: float = 800.0
@export var default_cas_altitude_m: float = 300.0
@export var carrier_air_threat_radius_m: float = 10000.0
@export var carrier_air_threat_close_radius_m: float = 3500.0
@export var carrier_air_threat_min_closing_speed_mps: float = 25.0
@export var carrier_air_threat_heading_dot: float = 0.25
@export var strike_target_scan_radius_m: float = 12000.0
@export var reported_contact_timeout_s: float = 12.0
@export var sensor_picture_update_interval_s: float = 1.0
@export var carrier_radar_enabled: bool = true
@export var carrier_radar_range_m: float = 5000.0
@export var ground_vehicle_radar_enabled: bool = true
@export var ground_vehicle_radar_range_m: float = 3500.0

## Recovery supervision observes mission progress without taking ownership of
## waypoints or controls. AIPilot remains the tactical route executor and the
## flight deck remains the sole landing-clearance authority.
@export var recovery_supervision_enabled: bool = true
@export var recovery_supervision_interval_s: float = 3.0
@export var recovery_supervision_stall_timeout_s: float = 40.0
@export var recovery_supervision_progress_step_m: float = 25.0
@export var recovery_supervision_replan_cooldown_s: float = 30.0
@export var recovery_supervision_max_replans: int = 3

## Aircraft to launch per scramble when a flight has no members.
@export var scramble_flight_size: int = 2

## Keep at least one dedicated flight patrolling over the carrier.
@export var maintain_carrier_cap: bool = true
@export var carrier_cap_overhead_radius_m: float = 4500.0

var flights: Array[Flight] = []

var _carrier: Node3D = null
var _assign_timer: float = 0.0
var _threat_timer: float = 0.0
var _sensor_picture_timer: float = 0.0
var _recovery_supervision_timer_s: float = 0.0
var _recovery_supervision_elapsed_s: float = 0.0
var _recovery_supervision_records: Dictionary = {}
var _next_flight_idx: int = 0

## Currently assigned missions. Null means no flight holds that role.
## (Legacy 3-slot model -- retained only while transitioning; the task board below supersedes it.)
var _cap_flight: Flight = null
var _intercept_flight: Flight = null
var _cas_flight: Flight = null

# ── Dynamic tasking (mission board) ─────────────────────────────────────────────
# Replaces the fixed 3-slot role model. Each tick we build a list of TASKS from the fused sensor
# picture (intercepts, strike clusters, standing CAP), score them, and assign available flights.
# A task is a Dictionary: {
#   "id": String,            # stable-ish key so a flight stays on the same task across ticks
#   "type": String,          # "intercept" | "strike" | "cap"
#   "priority": float,       # higher = assign first; carrier threats dominate
#   "target": Node3D,        # intercept: the bandit (may be null once cleared)
#   "area": Vector3,         # strike/cap center
#   "radius": float,         # strike area radius
#   "targets": Array,        # strike: the clustered enemy nodes
#   "flight": Flight,        # assigned flight (null = unfilled)
# }
@export var task_assign_interval_s: float = 2.0
@export var strike_cluster_radius_m: float = 1200.0   # enemy targets within this of each other form one strike task
@export var task_switch_hysteresis: float = 0.0       # (reserved) extra priority a new task must beat to steal a flight
@export var min_cap_flights: int = 1                  # keep at least this many patrolling the carrier when possible
@export var dynamic_tasking_enabled: bool = true      # false = fall back to the legacy 3-slot updates
var _tasks: Array = []
var _flight_task: Dictionary = {}                     # Flight -> task id currently assigned
var _flight_role: Dictionary = {}                     # Flight -> last task TYPE barked (so we only bark on a ROLE change, not target/cluster churn within a role)
var _task_timer: float = 0.0

## Flight currently being scrambled from the hangar (waiting for launches).
var _scrambling_flight: Flight = null
var _scrambling_expected_count: int = 0
var _scrambling_elapsed_s: float = 0.0
@export var scramble_timeout_s: float = 90.0  # if a scramble never completes launches in this long, release it
var _reported_contacts: Dictionary = {}  # Node3D target -> contact report dictionary
var _acknowledged_order_keys: Dictionary = {}  # flight name -> last order key that already got a reply

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
	var _profiler_start: int = FrameProfiler.begin("AirOpsManager.process")
	_recovery_supervision_elapsed_s += maxf(delta, 0.0)
	_recovery_supervision_timer_s -= delta
	if recovery_supervision_enabled and _recovery_supervision_timer_s <= 0.0:
		_recovery_supervision_timer_s = maxf(recovery_supervision_interval_s, 0.5)
		_update_recovery_supervision(_recovery_supervision_elapsed_s)
		_recovery_supervision_elapsed_s = 0.0
	elif not recovery_supervision_enabled:
		if not _recovery_supervision_records.is_empty():
			_recovery_supervision_records.clear()
		_recovery_supervision_elapsed_s = 0.0
	if not mission_tasking_enabled:
		FrameProfiler.end("AirOpsManager.process", _profiler_start)
		return
	_sensor_picture_timer -= delta
	if _sensor_picture_timer <= 0.0:
		_sensor_picture_timer = maxf(sensor_picture_update_interval_s, 0.1)
		_update_friendly_sensor_picture()

	# Release a scramble that never completed its launches (deck jammed / aircraft stuck) so it doesn't
	# block all future tasking forever.
	if _scrambling_flight != null:
		_scrambling_elapsed_s += delta
		if _scrambling_elapsed_s >= maxf(scramble_timeout_s, 5.0):
			if debug_print:
				print("[AirOpsManager] Scramble for %s timed out (%.0fs) — releasing" % [_scrambling_flight.flight_name, _scrambling_elapsed_s])
			_scrambling_flight = null
			_scrambling_expected_count = 0
			_scrambling_elapsed_s = 0.0
	if dynamic_tasking_enabled:
		_task_timer -= delta
		if _task_timer <= 0.0:
			_task_timer = maxf(task_assign_interval_s, 0.2)
			_refresh_carrier()
			_auto_assign_unassigned()   # registers newly-launched/idle aircraft into flights
			_update_tasking()           # the mission board: build tasks + assign flights
	else:
		# Legacy 3-slot path (kept as a fallback).
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
	FrameProfiler.end("AirOpsManager.process", _profiler_start)

# ── Ordering API ───────────────────────────────────────────────────────────────

func _update_recovery_supervision(sample_delta_s: float) -> void:
	## Observe only route-following recovery phases. Holding, final stabilization,
	## landing, and bolter states may intentionally fly away from the carrier and
	## therefore must never be "corrected" by this strategic watchdog.
	var supervised_aircraft: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft", "friendlies"]:
		for node_variant in get_tree().get_nodes_in_group(group_name):
			if not (node_variant is Node3D) or not is_instance_valid(node_variant):
				continue
			var aircraft := node_variant as Node3D
			if supervised_aircraft.has(aircraft):
				continue
			if not _is_aircraft_candidate_for_flight(aircraft):
				continue
			if not aircraft.has_method("get_team") or int(aircraft.call("get_team")) != 1:
				continue
			var pilot := aircraft.find_child("AIPilot", true, false) as AIPilot
			if not _pilot_needs_recovery_supervision(pilot):
				continue
			supervised_aircraft[aircraft] = true
			_supervise_recovering_aircraft(
				get_flight_of(aircraft),
				aircraft,
				pilot,
				maxf(sample_delta_s, 0.0)
			)

	for aircraft_ref in _recovery_supervision_records.keys():
		if not is_instance_valid(aircraft_ref) or not supervised_aircraft.has(aircraft_ref):
			_recovery_supervision_records.erase(aircraft_ref)


func _pilot_needs_recovery_supervision(pilot: AIPilot) -> bool:
	if pilot == null or not is_instance_valid(pilot):
		return false
	return pilot.current_state in [
		AIPilot.State.RTB,
		AIPilot.State.RECOVERY_APPROACH,
	]


func _supervise_recovering_aircraft(
		flight: Flight,
		aircraft: Node3D,
		pilot: AIPilot,
		sample_delta_s: float
	) -> void:
	var snapshot: Dictionary = pilot.get_recovery_navigation_snapshot()
	if not bool(snapshot.get("valid", false)):
		_recovery_supervision_records.erase(aircraft)
		return
	var progress: Dictionary = snapshot.get("progress", {})
	var progress_valid: bool = bool(progress.get("valid", false))
	var state: int = int(snapshot.get("state", int(pilot.current_state)))
	var revision: int = int(snapshot.get("flight_plan_revision", -1))
	var progress_index: int = int(progress.get("index", -1)) if progress_valid else -1
	var plan_remaining_m: float = float(progress.get("plan_remaining_m", INF)) \
		if progress_valid else INF
	var reacquire_active: bool = bool(snapshot.get("reacquire_active", false))

	var record: Dictionary = _recovery_supervision_records.get(aircraft, {})
	var route_identity_changed: bool = record.is_empty() \
		or int(record.get("state", -1)) != state \
		or int(record.get("revision", -1)) != revision \
		or int(record.get("progress_index", -1)) != progress_index
	if route_identity_changed:
		var prior_attempts: int = int(record.get("attempts", 0))
		record = {
			"state": state,
			"revision": revision,
			"progress_index": progress_index,
			"best_plan_remaining_m": plan_remaining_m,
			"stalled_s": 0.0,
			"cooldown_s": maxf(
				float(record.get("cooldown_s", 0.0)) - sample_delta_s,
				0.0
			),
			"attempts": prior_attempts,
			"exhausted_logged": false,
		}
		_recovery_supervision_records[aircraft] = record
		return

	record["cooldown_s"] = maxf(
		float(record.get("cooldown_s", 0.0)) - sample_delta_s,
		0.0
	)
	if reacquire_active:
		# The pilot has acknowledged a local or supervisory repair and temporarily
		# owns a stabilization manoeuvre. Do not stack another command on top of it.
		record["stalled_s"] = 0.0
		if progress_valid:
			record["best_plan_remaining_m"] = plan_remaining_m
		_recovery_supervision_records[aircraft] = record
		return

	var made_progress: bool = false
	if progress_valid and is_finite(plan_remaining_m):
		var best_remaining_m: float = float(record.get("best_plan_remaining_m", INF))
		made_progress = not is_finite(best_remaining_m) \
			or plan_remaining_m <= best_remaining_m \
				- maxf(recovery_supervision_progress_step_m, 1.0)
		if made_progress:
			record["best_plan_remaining_m"] = plan_remaining_m
	if made_progress:
		record["stalled_s"] = 0.0
		record["attempts"] = 0
		record["exhausted_logged"] = false
	else:
		record["stalled_s"] = float(record.get("stalled_s", 0.0)) + sample_delta_s

	var stalled_s: float = float(record.get("stalled_s", 0.0))
	if stalled_s < maxf(recovery_supervision_stall_timeout_s, 1.0) \
			or float(record.get("cooldown_s", 0.0)) > 0.0:
		_recovery_supervision_records[aircraft] = record
		return

	var attempts: int = int(record.get("attempts", 0))
	var flight_label: String = flight.flight_name \
		if flight != null and is_instance_valid(flight) else "UNASSIGNED"
	if attempts >= maxi(recovery_supervision_max_replans, 0):
		if not bool(record.get("exhausted_logged", false)):
			record["exhausted_logged"] = true
			push_warning(
				"[AirOps RECOVERY_WATCH] %s/%s still stalled after %d replans; leaving control with pilot" % [
					flight_label,
					aircraft.name,
					attempts,
				]
			)
		_recovery_supervision_records[aircraft] = record
		return

	var state_name: String = AIPilot.State.keys()[state] \
		if state >= 0 and state < AIPilot.State.size() else str(state)
	var reason := "no_route_progress_%.0fs_%s" % [stalled_s, state_name.to_lower()]
	var accepted: bool = pilot.request_recovery_replan(reason)
	record["stalled_s"] = 0.0
	if accepted:
		record["attempts"] = attempts + 1
		record["cooldown_s"] = maxf(recovery_supervision_replan_cooldown_s, 0.0)
		record["exhausted_logged"] = false
		print("[AirOps RECOVERY_WATCH] %s/%s requested replan attempt=%d state=%s remaining=%.0fm" % [
			flight_label,
			aircraft.name,
			attempts + 1,
			state_name,
			plan_remaining_m,
		])
	else:
		# A state transition between the snapshot and the command is harmless. A
		# short retry delay prevents log/command spam without manufacturing an ack.
		record["cooldown_s"] = maxf(recovery_supervision_interval_s, 5.0)
	_recovery_supervision_records[aircraft] = record


func order_cap(fname: String, altitude_m: float = 800.0) -> void:
	var f := get_flight(fname)
	if not f:
		push_warning("[AirOpsManager] Unknown flight: " + fname)
		return
	_clear_role(f)
	_refresh_carrier()
	f.set_cap(_carrier, altitude_m)
	_cap_flight = f
	if _mark_order_acknowledgement_needed(f, "manual_cap"):
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
	if _mark_order_acknowledgement_needed(f, "manual_cap_route"):
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
	if _mark_order_acknowledgement_needed(f, "manual_cas"):
		RadioComms.say_cas_order(fname)
	_ensure_flight_can_execute(f)

func order_rtb(fname: String) -> void:
	var f := get_flight(fname)
	if not f:
		push_warning("[AirOpsManager] Unknown flight: " + fname)
		return
	_clear_role(f)
	f.set_rtb()
	if _mark_order_acknowledgement_needed(f, "manual_rtb"):
		RadioComms.say_rtb_order(fname)

func reassign(aircraft: Node3D, fname: String) -> void:
	for f in flights:
		f.unregister(aircraft)
	var target := get_flight(fname)
	if target:
		target.register(aircraft)
		_assign_pilot_identity(aircraft, target)

func report_contact(reporter: Node3D, target: Node3D) -> void:
	if not reporter or not is_instance_valid(reporter):
		return
	if not target or not is_instance_valid(target):
		return
	var reporter_team: int = _get_node_team(reporter, 1)
	if reporter_team != 1:
		return
	if not _is_valid_report_target_for_team(target, reporter_team):
		return
	_reported_contacts[target] = {
		"reporter": reporter,
		"team": reporter_team,
		"position": target.global_position,
		"last_seen_s": Time.get_ticks_msec() / 1000.0,
	}

func get_reported_ground_targets(center: Vector3 = Vector3.ZERO, radius_m: float = -1.0) -> Array[Node3D]:
	_prune_reported_contacts()
	var result: Array[Node3D] = []
	for target_ref in _reported_contacts.keys():
		if not is_instance_valid(target_ref) or not (target_ref is Node3D):
			continue
		var target := target_ref as Node3D
		if not _is_enemy_ground_target(target):
			continue
		if radius_m > 0.0:
			var flat_dist: float = Vector2(target.global_position.x - center.x, target.global_position.z - center.z).length()
			if flat_dist > radius_m:
				continue
		result.append(target)
	return result

func is_contact_detected(node: Node3D) -> bool:
	## True if this enemy node is currently in the fused friendly sensor picture (carrier radar + any
	## friendly aircraft/vehicle). Used by the map to show sensed contacts in full color and un-sensed
	## (remembered/off-radar) ones muted. Prunes stale reports first so a lost contact reads as hidden.
	if node == null or not is_instance_valid(node):
		return false
	_prune_reported_contacts()
	return _reported_contacts.has(node)

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

func get_carrier_pilot_roster() -> Array[Dictionary]:
	if PilotRoster == null or not is_instance_valid(PilotRoster):
		return []
	if not PilotRoster.has_method("get_carrier_roster"):
		return []
	return PilotRoster.get_carrier_roster()

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
	var threats := _get_inbound_enemy_aircraft()

	# Check if the assigned intercept flight is still viable
	if _intercept_flight != null:
		if not _flight_is_active(_intercept_flight):
			_on_flight_lost(_intercept_flight, "intercept")
			_intercept_flight = null
		elif threats.is_empty() and not _intercept_flight.is_engaged():
			# Threat cleared — recall
			_recall_to_cap(_intercept_flight,
				"Threat neutralised. %s flight, resume patrol.",
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
		if _scrambling_flight != null:
			return
		var empty := _pick_empty_flight(_cas_flight)
		if empty:
			if _scramble_flight(empty, "intercept"):
				empty.set_intercept(threat, _carrier, default_cap_altitude_m)
				_intercept_flight = empty
				if empty == _cap_flight:
					_cap_flight = null
		return
	if best.strength() == 0:
		if _scramble_flight(best, "intercept"):
			best.set_intercept(threat, _carrier, default_cap_altitude_m)
			_intercept_flight = best
			if best == _cap_flight:
				_cap_flight = null
		return

	# If this flight was on CAS, release that role
	if best == _cas_flight:
		_cas_flight = null

	_intercept_flight = best
	if best == _cap_flight:
		_cap_flight = null
	var fname := best.flight_name
	best.set_intercept(threat, _carrier, default_cap_altitude_m)

	if _mark_order_acknowledgement_needed(best, "auto_intercept"):
		RadioComms.transmit("Citadel", "%s flight" % fname, RadioComms._pick([
			"%s flight, radar contact. Intercept and engage. Weapons free." % fname,
			"%s flight, bogeys inbound. Vector to intercept." % fname,
			"%s flight, bandits on scope. Intercept. Weapons free." % fname,
		]))
		RadioComms.transmit_delayed("%s lead" % fname, "Citadel", RadioComms._pick([
			"Copy. Going after them. Bozhe miy, here we go.",
			"Tally. I'm in. Engaging.",
			"Wilco. Flight. Weapons free. Call your targets.",
		]), randf_range(1.0, 2.2))

# ── CAS management ────────────────────────────────────────────────────────────

func _update_cas() -> void:
	var threats := _get_enemy_ground_targets()

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
		if _scrambling_flight != null:
			return
		var empty := _pick_empty_flight(_intercept_flight)
		if empty:
			if _scramble_flight(empty, "cas"):
				empty.set_cas(threat.global_position, 3000.0, default_cas_altitude_m)
				_cas_flight = empty
				if empty == _cap_flight:
					_cap_flight = null
		return
	if best.strength() == 0:
		var center_for_scramble := threat.global_position if (threat and is_instance_valid(threat)) else Vector3.ZERO
		if _scramble_flight(best, "cas"):
			best.set_cas(center_for_scramble, 3000.0, default_cas_altitude_m)
			_cas_flight = best
			if best == _cap_flight:
				_cap_flight = null
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

	if _mark_order_acknowledgement_needed(best, "auto_cas"):
		RadioComms.transmit("Citadel", "%s flight" % fname, RadioComms._pick([
			"%s flight, enemy ground forces spotted. Cleared hot. Attack at will." % fname,
			"%s flight, ground targets acquired. CAS mission. Cleared hot." % fname,
			"Hostiles on the deck. %s flight, prosecute ground attack. Don't go in the sand." % fname,
		]))
		RadioComms.transmit_delayed("%s lead" % fname, "Citadel", RadioComms._pick([
			"Copy. Nosing over. Committing.",
			"Roger. Got targets. Flight, sort yourselves out.",
			"Wilco. Flight. Push it low. Watch for ground fire.",
		]), randf_range(1.0, 2.2))

# ── Recall ────────────────────────────────────────────────────────────────────

func _recall_to_cap(f: Flight, line_a: String, line_b: String, line_c: String) -> void:
	_refresh_carrier()
	f.set_cap(_carrier, default_cap_altitude_m)
	if _cap_flight == null and _flight_can_hold_cap(f):
		_cap_flight = f
	var fname := f.flight_name
	if _mark_order_acknowledgement_needed(f, "auto_recall_cap"):
		RadioComms.transmit("Citadel", "%s flight" % fname, RadioComms._pick([
			line_a % fname, line_b % fname, line_c % fname,
		]))
		RadioComms.transmit_delayed("%s lead" % fname, "Citadel", RadioComms._pick([
			"Copy. Back on patrol.",
			"Roger. Back on station. Stay sharp.",
			"Wilco. Flight, form up. Back on the clock.",
		]), randf_range(0.8, 1.8))

func _on_flight_lost(f: Flight, role: String) -> void:
	## Called when a flight assigned to a role has been wiped out.
	if debug_print:
		print("[AirOpsManager] %s flight lost while on %s. Reassigning." % [f.flight_name, role])
	RadioComms.transmit("Citadel", "All flights",
		"%s flight is down. Reassigning mission." % f.flight_name)

# ── Dynamic tasking (mission board) ─────────────────────────────────────────────

func _update_tasking() -> void:
	## Rebuild the task board from the fused sensor picture, then assign flights.
	_refresh_carrier()
	_tasks = _build_tasks()
	_tasks.sort_custom(func(a, b): return float(a.get("priority", 0.0)) > float(b.get("priority", 0.0)))
	_assign_flights_to_tasks()
	if debug_print:
		_print_task_board()

func _print_task_board() -> void:
	var parts: Array[String] = []
	for t in _tasks:
		var f: Variant = t.get("flight")
		var fname: String = (f.flight_name if (f != null and is_instance_valid(f)) else "-")
		var n: int = (t.get("targets") as Array).size()
		parts.append("%s[p%.0f n%d ->%s]" % [t.get("type"), float(t.get("priority", 0.0)), n, fname])
	print("[AirOps BOARD] contacts=%d tasks: %s" % [_reported_contacts.size(), " ".join(parts)])

func _build_tasks() -> Array:
	var tasks: Array = []
	# --- INTERCEPT tasks: one per inbound enemy aircraft (defense -- always top priority). ---
	for bandit in _get_inbound_enemy_aircraft():
		if not (bandit is Node3D) or not is_instance_valid(bandit):
			continue
		var node := bandit as Node3D
		var dist_to_carrier: float = _flat_dist_to_carrier(node.global_position)
		# Closer to the carrier = more urgent. Base 1000 keeps all intercepts above all strikes.
		var prio: float = 1000.0 + clampf(carrier_air_threat_radius_m - dist_to_carrier, 0.0, carrier_air_threat_radius_m)
		tasks.append({
			"id": "intercept:%d" % node.get_instance_id(),
			"type": "intercept",
			"priority": prio,
			"target": node,
			"area": node.global_position,
			"radius": 0.0,
			"targets": [node],
			"flight": null,
		})
	# --- STRIKE tasks: cluster nearby enemy ground/structure targets into strike areas. ---
	for cluster in _cluster_ground_targets(_get_enemy_ground_targets()):
		var members: Array = cluster
		if members.is_empty():
			continue
		var center: Vector3 = _cluster_center(members)
		var value: float = 0.0
		for t in members:
			value += _ground_target_value(t)
		# Strikes rank below intercepts (base < 1000). Closer + higher-value clusters first.
		var dist: float = _flat_dist_to_carrier(center)
		var prio: float = 200.0 + value + clampf((strike_target_scan_radius_m - dist) / strike_target_scan_radius_m, 0.0, 1.0) * 100.0
		tasks.append({
			"id": "strike:%d" % _cluster_id(members),
			"type": "strike",
			"priority": prio,
			"target": null,
			"area": center,
			"radius": maxf(strike_cluster_radius_m, 800.0),
			"targets": members,
			"flight": null,
		})
	# --- Standing CAP over the carrier (baseline low priority; defense-first still honors min_cap). ---
	if _carrier and is_instance_valid(_carrier):
		tasks.append({
			"id": "cap:carrier",
			"type": "cap",
			"priority": 100.0,
			"target": null,
			"area": _carrier.global_position,
			"radius": carrier_cap_overhead_radius_m,
			"targets": [],
			"flight": null,
		})
	return tasks

func _assign_flights_to_tasks() -> void:
	# Reconcile: drop stale flight->task links (flight gone, or task id no longer exists).
	var live_ids: Dictionary = {}
	for t in _tasks:
		live_ids[t["id"]] = t
	for f in _flight_task.keys():
		if not _flight_is_active(f) or not live_ids.has(_flight_task[f]):
			_flight_task.erase(f)
			# Wiped flight -> forget its role so a rebuilt flight barks fresh. (A flight that merely lost
			# its task but is still alive keeps its role, so re-tasking to the SAME role stays quiet.)
			if not _flight_is_active(f):
				_flight_role.erase(f)
	# Re-attach flights already on a still-live task (hysteresis: they stay put).
	for f in _flight_task.keys():
		var t: Dictionary = live_ids[_flight_task[f]]
		t["flight"] = f
	# Assign unfilled tasks, highest priority first, to the best available flight.
	var min_cap_reserved: int = 0
	for t in _tasks:
		if t.get("flight") != null:
			continue
		# Defense-first: if this is CAP and we've already met the CAP minimum, only fill it with leftovers.
		if t["type"] == "cap":
			if min_cap_reserved >= max(min_cap_flights, 0) and not _tasks_all_higher_filled(t):
				# Still assign CAP if a flight is genuinely idle (handled by _pick below returning idle only).
				pass
		var f := _pick_flight_for_task(t)
		if f == null:
			# No available flight -> scramble one if this task warrants it (intercept/strike/ or CAP if none up).
			if _scrambling_flight == null:
				var empty := _pick_empty_flight(null)
				if empty != null:
					var reason: String = _scramble_reason_for_task(t)
					if _scramble_flight(empty, reason):
						# Silent: the scramble bark already announced the launch; no redundant second order.
						_apply_task_to_flight(t, empty, true)
			continue
		_apply_task_to_flight(t, f)
		if t["type"] == "cap":
			min_cap_reserved += 1

func _tasks_all_higher_filled(cap_task: Dictionary) -> bool:
	for t in _tasks:
		if t == cap_task:
			continue
		if float(t.get("priority", 0.0)) > float(cap_task.get("priority", 0.0)) and t.get("flight") == null:
			return false
	return true

func _apply_task_to_flight(t: Dictionary, f: Flight, silent: bool = false) -> void:
	## Assign flight f to task t. `silent` suppresses the radio order (used at scramble time -- the
	## scramble bark already covers it, and the flight isn't airborne yet). Otherwise a radio order is
	## issued ONLY when the flight's ROLE actually changes (cap<->intercept<->strike), not when the
	## specific bandit/cluster within the same role changes -- that repeated re-vectoring was the
	## "random, not tied to what's happening" chatter.
	if f == null or not is_instance_valid(f):
		return
	t["flight"] = f
	_flight_task[f] = t["id"]
	_clear_legacy_role(f)
	var role: String = str(t["type"])
	var role_changed: bool = not silent and str(_flight_role.get(f, "")) != role
	match role:
		"intercept":
			if t.get("target") and is_instance_valid(t["target"]):
				f.set_intercept(t["target"], _carrier, default_cap_altitude_m)
				if role_changed:
					RadioComms.transmit("Citadel", "%s flight" % f.flight_name, RadioComms._pick([
						"%s flight, bandits inbound. Vector to intercept. Weapons free." % f.flight_name,
						"%s flight, radar contact. Intercept and engage." % f.flight_name,
					]))
		"strike":
			f.set_cas(t["area"], t["radius"], default_cas_altitude_m)
			if role_changed:
				RadioComms.transmit("Citadel", "%s flight" % f.flight_name, RadioComms._pick([
					"%s flight, enemy ground targets. Cleared hot. Attack at will." % f.flight_name,
					"%s flight, ground targets marked. Prosecute. Cleared hot." % f.flight_name,
				]))
		"cap":
			f.set_cap(_carrier, default_cap_altitude_m)
			if role_changed:
				RadioComms.say_cap_order(f.flight_name, default_cap_altitude_m)
	if role_changed:
		var cl := get_node_or_null("/root/CombatLog")
		if cl != null and cl.has_method("event"):
			var n: int = (t.get("targets") as Array).size()
			var detail: String = " (%d targets)" % n if role == "strike" else ""
			cl.call("event", "ORDER", "%s flight -> %s%s" % [f.flight_name, role.to_upper(), detail])
	_flight_role[f] = role
	_ensure_flight_can_execute(f)

func _pick_flight_for_task(t: Dictionary) -> Flight:
	## Best available (active, order-capable, not already on a live task) flight, nearest to the task.
	var best: Flight = null
	var best_cost: float = INF
	var task_pos: Vector3 = t.get("area", Vector3.ZERO)
	for f in flights:
		if not _flight_is_active(f):
			continue
		if _flight_task.has(f):
			continue  # already on a task this tick
		if not _flight_can_take_tactical_order(f):
			continue
		var cost: float = _flight_center(f).distance_to(task_pos)
		if cost < best_cost:
			best_cost = cost
			best = f
	return best

func _scramble_reason_for_task(t: Dictionary) -> String:
	match t.get("type", ""):
		"intercept": return "intercept"
		"strike": return "cas"
		_: return "cap"

func _clear_legacy_role(f: Flight) -> void:
	if f == _cap_flight: _cap_flight = null
	if f == _intercept_flight: _intercept_flight = null
	if f == _cas_flight: _cas_flight = null

# --- Ground-target clustering + valuation ---

func _cluster_ground_targets(targets: Array) -> Array:
	var remaining: Array = []
	for t in targets:
		if t is Node3D and is_instance_valid(t):
			remaining.append(t)
	var clusters: Array = []
	while not remaining.is_empty():
		var seed: Node3D = remaining.pop_back()
		var group: Array = [seed]
		var i: int = remaining.size() - 1
		while i >= 0:
			var other: Node3D = remaining[i]
			if _cluster_center(group).distance_to(other.global_position) <= strike_cluster_radius_m:
				group.append(other)
				remaining.remove_at(i)
			i -= 1
		clusters.append(group)
	return clusters

func _cluster_center(group: Array) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for t in group:
		if t is Node3D and is_instance_valid(t):
			sum += (t as Node3D).global_position
			n += 1
	return sum / float(max(n, 1))

func _cluster_id(group: Array) -> int:
	## Stable-ish id: smallest instance id in the cluster (so a growing/shrinking cluster keeps its key).
	var best: int = 0x7fffffff
	for t in group:
		if t is Node3D and is_instance_valid(t):
			best = min(best, int((t as Node3D).get_instance_id()))
	return best

func _ground_target_value(node: Node3D) -> float:
	## Priority by type: mobile/AAA (threat to friendlies) > structures > low value.
	if node == null or not is_instance_valid(node):
		return 0.0
	if node.is_in_group("gun_emplacements"):
		return 120.0   # AAA -- dangerous to our aircraft, kill first
	if node.is_in_group("ground_vehicles"):
		return 90.0    # mobile threat
	if node.is_in_group("enemy_bases"):
		return 70.0
	if node.is_in_group("buildings"):
		return 40.0    # structures (e.g. wind turbines)
	return 30.0

func _flat_dist_to_carrier(pos: Vector3) -> float:
	if not _carrier or not is_instance_valid(_carrier):
		return INF
	var cp := _carrier.global_position
	return Vector2(pos.x - cp.x, pos.z - cp.z).length()

# ── Internal ───────────────────────────────────────────────────────────────────

func _scramble_flight(f: Flight, reason: String = "intercept"):
	## Launch aircraft from the hangar and assign them to flight f.
	## AirOpsManager acts as the callback target so launched pilots get registered.
	if f == null or not is_instance_valid(f):
		return false
	var fdm := get_tree().get_first_node_in_group("flight_deck_manager")
	if not fdm or not fdm.has_method("queue_ai_flight"):
		push_warning("[AirOpsManager] No FlightDeckManager — cannot scramble %s" % f.flight_name)
		return
	if _scrambling_flight != null:
		if debug_print:
			print("[AirOpsManager] Scramble already in progress for %s, skipping" % _scrambling_flight.flight_name)
		return
	var accepted_count := int(fdm.queue_ai_flight(scramble_flight_size, self, _loadout_profile_for_scramble_reason(reason)))
	if accepted_count <= 0:
		if debug_print:
			print("[AirOpsManager] Scramble request for %s flight was not accepted" % f.flight_name)
		return
	_scrambling_flight = f
	_scrambling_expected_count = accepted_count
	_scrambling_elapsed_s = 0.0
	print("[AirOpsManager] Scrambling %s flight (%d aircraft)" % [f.flight_name, accepted_count])
	var _cl := get_node_or_null("/root/CombatLog")
	if _cl != null and _cl.has_method("event"):
		_cl.call("event", "LAUNCH", "%s flight scrambling (%d ac, %s)" % [f.flight_name, accepted_count, reason])
	if reason == "cap":
		if _mark_order_acknowledgement_needed(f, "scramble_cap"):
			RadioComms.transmit("Citadel", "%s flight" % f.flight_name, RadioComms._pick([
				"%s flight, launch for carrier CAP." % f.flight_name,
				"%s, launch and establish patrol over the carrier." % f.flight_name,
				"%s flight, launch to maintain air cover." % f.flight_name,
			]))
	elif reason == "cas":
		if _mark_order_acknowledgement_needed(f, "scramble_cas"):
			RadioComms.transmit("Citadel", "%s flight" % f.flight_name, RadioComms._pick([
				"%s flight, launch for close air support." % f.flight_name,
				"%s, launch immediately. Ground targets marked." % f.flight_name,
				"%s flight, scramble for CAS. Cleared hot after departure." % f.flight_name,
			]))
	else:
		if _mark_order_acknowledgement_needed(f, "scramble_intercept"):
			RadioComms.transmit("Citadel", "%s flight" % f.flight_name, RadioComms._pick([
				"%s flight, scramble. Threat inbound." % f.flight_name,
				"%s, launch immediately. Threat on scope." % f.flight_name,
				"All hands, scramble %s flight. Weapons free." % f.flight_name,
			]))
	return true

## Called by FlightDeckManager after each aircraft launches during a scramble.
func notify_aircraft_launched(pilot: AIPilot) -> void:
	if not _scrambling_flight:
		return
	var aircraft := pilot.aircraft as Node3D
	# Aircraft_11 is a utility helicopter — never assign it to combat flights.
	if aircraft and aircraft.name.begins_with("Aircraft_11"):
		return
	if aircraft:
		reassign(aircraft, _scrambling_flight.flight_name)
		if debug_print:
			print("[AirOpsManager] %s launched → %s flight (%d members)" % [
				aircraft.name, _scrambling_flight.flight_name, _scrambling_flight.strength()])
	# Once the deck has launched everything it accepted, clear the in-progress flag.
	var expected_count := maxi(_scrambling_expected_count, 1)
	if _scrambling_flight.strength() >= expected_count:
		RadioComms.transmit_delayed("%s lead" % _scrambling_flight.flight_name, "Citadel",
			RadioComms._pick([
				"Off the deck. Gear up, climbing to station.",
				"Airborne. Coming around. What is the picture?",
				"Up and away. Blyad. Flight, form on my wing.",
			]),
			randf_range(1.5, 3.0))
		_scrambling_flight = null
		_scrambling_expected_count = 0
		_scrambling_elapsed_s = 0.0

func _flight_is_active(f: Flight) -> bool:
	## A flight is active if it exists and has at least one living member.
	return f != null and f.strength() > 0

func _flight_can_take_tactical_order(f: Flight) -> bool:
	if not _flight_is_active(f):
		return false
	for aircraft in f.get_members():
		if _aircraft_can_take_tactical_order(aircraft):
			return true
	return false

func _aircraft_can_take_tactical_order(aircraft: Node3D) -> bool:
	if aircraft == null or not is_instance_valid(aircraft):
		return false
	if bool(aircraft.get_meta("controls_disabled", false)):
		return false
	if bool(aircraft.get_meta("parking_brake", false)):
		return false
	if bool(aircraft.get_meta("carrier_transport_mode", false)):
		return false
	if bool(aircraft.get_meta("arresting_engaged", false)):
		return false
	var pilot := aircraft.find_child("AIPilot", true, false) as AIPilot
	if pilot == null:
		return false
	return pilot.current_state not in [
		AIPilot.State.IDLE,
		AIPilot.State.LAUNCHING,
		AIPilot.State.CLIMBING,
		AIPilot.State.RTB,
		AIPilot.State.RECOVERY_MARSHAL,
		AIPilot.State.RECOVERY_HOLD,
		AIPilot.State.RECOVERY_APPROACH,
		AIPilot.State.PRE_LANDING,
		AIPilot.State.APPROACH,
		AIPilot.State.LANDING,
		AIPilot.State.MISSED_APPROACH,
	]

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
		if not _flight_can_take_tactical_order(f):
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
			if _flight_is_active(f) and _flight_can_take_tactical_order(f) and f.mission != Flight.Mission.RTB:
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

	if _flight_can_hold_carrier_cap(_cap_flight):
		return

	var overhead := _pick_cap_candidate(true)
	if overhead:
		_cap_flight = overhead
		if overhead.mission != Flight.Mission.CAP:
			overhead.set_cap(_carrier, default_cap_altitude_m)
		if debug_print:
			print("[AirOpsManager] %s flight assigned overhead carrier CAP" % overhead.flight_name)
		return

	if _scrambling_flight != null:
		return

	var empty := _pick_empty_flight()
	if empty:
		if _scramble_flight(empty, "cap"):
			_cap_flight = empty
			empty.set_cap(_carrier, default_cap_altitude_m)
			return

	var best := _pick_cap_candidate()
	if best:
		_cap_flight = best
		if best.mission != Flight.Mission.CAP:
			best.set_cap(_carrier, default_cap_altitude_m)
		if debug_print:
			print("[AirOpsManager] %s flight assigned carrier CAP" % best.flight_name)

func _flight_can_hold_cap(f: Flight) -> bool:
	return f != null \
		and is_instance_valid(f) \
		and _flight_is_active(f) \
		and f.mission == Flight.Mission.CAP \
		and f != _intercept_flight \
		and f != _cas_flight

func _flight_can_hold_carrier_cap(f: Flight) -> bool:
	return _flight_can_hold_cap(f) and _flight_is_over_carrier(f)

func _flight_is_over_carrier(f: Flight) -> bool:
	if not _flight_is_active(f):
		return false
	_refresh_carrier()
	if not _carrier or not is_instance_valid(_carrier):
		return false
	return _flight_flat_distance_to_carrier(f) <= carrier_cap_overhead_radius_m

func _flight_flat_distance_to_carrier(f: Flight) -> float:
	_refresh_carrier()
	if f == null or not is_instance_valid(f) or not _carrier or not is_instance_valid(_carrier):
		return INF
	var center := _flight_center(f)
	var carrier_pos := _carrier.global_position
	return Vector2(center.x - carrier_pos.x, center.z - carrier_pos.z).length()

func _pick_cap_candidate(require_overhead: bool = false) -> Flight:
	_refresh_carrier()
	var best: Flight = null
	var best_score := INF
	for f in flights:
		if not _flight_is_active(f):
			continue
		if not _flight_can_take_tactical_order(f):
			continue
		if f.mission == Flight.Mission.RTB:
			continue
		if f == _intercept_flight or f == _cas_flight:
			continue
		var score := _flight_flat_distance_to_carrier(f)
		if require_overhead and score > carrier_cap_overhead_radius_m:
			continue
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
		if f == _scrambling_flight:
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
	if reason == "intercept":
		return "intercept"
	if reason == "cas":
		return "strike"
	return "cap"

func _assign_pilot_identity(aircraft: Node3D, flight: Flight) -> void:
	if not is_instance_valid(aircraft) or flight == null or not is_instance_valid(flight):
		return
	if PilotRoster == null or not is_instance_valid(PilotRoster):
		return
	if not PilotRoster.has_method("assign_aircraft_to_callsign"):
		return
	var members := flight.get_members()
	var member_index := members.find(aircraft)
	if member_index < 0:
		return
	var callsign := "%s %s" % [flight.flight_name, _callsign_suffix_for_member_index(member_index)]
	PilotRoster.assign_aircraft_to_callsign(aircraft, callsign)

func _callsign_suffix_for_member_index(index: int) -> String:
	match index:
		0:
			return "lead"
		1:
			return "two"
		2:
			return "three"
		3:
			return "four"
		_:
			return str(index + 1)

func _clear_role(f: Flight) -> void:
	## When a flight is manually ordered, release any automatic role it held.
	if f == _cap_flight:
		_cap_flight = null
	if f == _intercept_flight:
		_intercept_flight = null
	if f == _cas_flight:
		_cas_flight = null
	if f != null and is_instance_valid(f):
		_acknowledged_order_keys.erase(f.flight_name)

func _mark_order_acknowledgement_needed(f: Flight, order_key: String) -> bool:
	if f == null or not is_instance_valid(f):
		return false
	var previous_key: String = str(_acknowledged_order_keys.get(f.flight_name, ""))
	if previous_key == order_key:
		return false
	_acknowledged_order_keys[f.flight_name] = order_key
	return true

## Called when a friendly pilot has landed as a downed pilot and needs pickup.
## Finds the best available friendly helicopter and dispatches it via command_rescue().
func request_rescue_for(pilot_node: Node3D) -> void:
	if not is_instance_valid(pilot_node):
		return

	var best_heli: Node3D = null
	var best_priority := -1
	for node in get_tree().get_nodes_in_group("friendlies"):
		var friendly := node as Node3D
		if friendly == null or not is_instance_valid(friendly):
			continue
		if not (friendly.has_meta("is_helicopter") and bool(friendly.get_meta("is_helicopter"))):
			continue
		var heli_pilot := friendly.find_child("HelicopterPilot", true, false)
		if heli_pilot == null or not heli_pilot.has_method("command_rescue"):
			continue
		var phase := int(heli_pilot.get("mission_phase"))
		# Skip INBOUND (2) and already on a RESCUE (4)
		if phase == 2 or phase == 4:
			continue
		# Aircraft_11 is the dedicated rescue/utility type — strongly prefer it.
		# Priority bands: 10-13 for Aircraft_11, 0-3 for other helis.
		var is_utility := friendly.name.begins_with("Aircraft_11")
		var base := 10 if is_utility else 0
		var priority := -1
		if phase == 3:   # AT_CARRIER: on deck, ready to launch
			priority = base + 3
		elif phase == 0: # OUTBOUND: airborne, can be rerouted
			priority = base + 2
		elif phase == 1: # AT_LZ: on ground elsewhere, reroutable
			priority = base + 1
		if priority > best_priority:
			best_priority = priority
			best_heli = friendly

	var callsign: String = str(pilot_node.get_meta("pilot_callsign")) if pilot_node.has_meta("pilot_callsign") else "Downed pilot"

	if best_heli != null:
		var heli_pilot := best_heli.find_child("HelicopterPilot", true, false)
		heli_pilot.call("command_rescue", pilot_node)
		RadioComms.transmit("Citadel", callsign, RadioComms._pick([
			"Rescue helo is on the way. Hold position.",
			"We have you on scope. Rescue is inbound.",
			"Hang tight. Rescue helo is en route.",
		]))
		print("[AirOpsManager] Dispatched %s on rescue mission for %s" % [best_heli.name, pilot_node.name])
	else:
		RadioComms.transmit("Citadel", callsign, RadioComms._pick([
			"No rescue assets available. Sit tight.",
			"All rescue assets are tasked. Stay hidden.",
		]))
		print("[AirOpsManager] No helicopter available to rescue %s" % pilot_node.name)


func issue_ops_order(unit: Node, order: OpsOrder) -> bool:
	## Public domain-neutral tasking boundary used by scenario and gameplay-level
	## directors. OperationsCoordinator validates capability before dispatch.
	if unit == null or not is_instance_valid(unit) or order == null:
		return false
	return OperationsCoordinator.issue_order(unit, order)


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

func _update_friendly_sensor_picture() -> void:
	_refresh_carrier()
	var target_candidates := _collect_contact_candidates()
	if carrier_radar_enabled and _carrier and is_instance_valid(_carrier):
		_report_contacts_seen_by_sensor(_carrier, carrier_radar_range_m, target_candidates)
	if ground_vehicle_radar_enabled:
		for sensor_ref in get_tree().get_nodes_in_group("ground_vehicles"):
			if not is_instance_valid(sensor_ref) or not (sensor_ref is Node3D):
				continue
			var sensor := sensor_ref as Node3D
			if _get_node_team(sensor, 0) != 1:
				continue
			if bool(sensor.get_meta("carrier_transport_mode", false)):
				continue
			_report_contacts_seen_by_sensor(sensor, ground_vehicle_radar_range_m, target_candidates)
	_prune_reported_contacts()

func _collect_contact_candidates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for group_name in ["enemies", "enemy_bases", "aircraft", "ai_aircraft", "ground_vehicles", "gun_emplacements", "buildings"]:
		for node_ref in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node_ref) or not (node_ref is Node3D):
				continue
			var node := node_ref as Node3D
			if result.has(node):
				continue
			result.append(node)
	return result

func _report_contacts_seen_by_sensor(sensor: Node3D, range_m: float, candidates: Array[Node3D]) -> void:
	if sensor == null or not is_instance_valid(sensor):
		return
	var sensor_team: int = _get_node_team(sensor, 1)
	if sensor_team != 1:
		return
	var range_sq: float = maxf(range_m, 1.0) * maxf(range_m, 1.0)
	for target in candidates:
		if target == null or not is_instance_valid(target):
			continue
		if target == sensor:
			continue
		if not _is_valid_report_target_for_team(target, sensor_team):
			continue
		if sensor.global_position.distance_squared_to(target.global_position) > range_sq:
			continue
		report_contact(sensor, target)

func _get_node_team(node: Node, fallback_team: int = 0) -> int:
	if node == null or not is_instance_valid(node):
		return fallback_team
	if node.has_method("get_team"):
		return int(node.call("get_team"))
	if node.is_in_group("team_1") or node.is_in_group("friendlies") or node.is_in_group("carrier"):
		return 1
	if node.is_in_group("team_2") or node.is_in_group("enemies") or node.is_in_group("enemy_bases"):
		return 2
	return fallback_team

func _is_valid_report_target_for_team(target: Node3D, reporter_team: int) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.is_in_group("carrier"):
		return false
	var target_team: int = _get_node_team(target, 0)
	if target_team == reporter_team:
		return false
	if reporter_team == 1:
		if target_team > 0:
			return true
		return target.is_in_group("enemies") or target.is_in_group("enemy_bases")
	return target_team == 1 or target.is_in_group("friendlies") or target.is_in_group("carrier")

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
			if not _is_aircraft_candidate_for_flight(node):
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

func _is_aircraft_candidate_for_flight(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.is_in_group("ground_vehicles"):
		return false
	# Utility helicopters (Aircraft_11) are rescue/transport assets -- never pull them into combat flights.
	# (notify_aircraft_launched already excludes them on the scramble path; this covers the auto-assign
	# path that was grabbing the pre-stored hangar helicopters into Archer/Bulldog/Crimson at startup.)
	if node is Node3D and (node as Node3D).name.begins_with("Aircraft_11"):
		return false
	if node.find_child("HelicopterPilot", true, false) != null and node.find_child("AIPilot", true, false) == null:
		return false  # helicopter-only asset, not a fixed-wing combat flight member
	if node.is_in_group("aircraft") or node.is_in_group("ai_aircraft"):
		return true
	return node.find_child("AIPilot", true, false) != null

func _get_enemy_ground_targets() -> Array:
	var result: Array = []
	_refresh_carrier()
	_prune_reported_contacts()
	for target_ref in _reported_contacts.keys():
		if not is_instance_valid(target_ref) or not (target_ref is Node3D):
			continue
		var node_3d := target_ref as Node3D
		if not _is_enemy_ground_target(node_3d):
			continue
		if _carrier and is_instance_valid(_carrier) \
				and _carrier.global_position.distance_to(node_3d.global_position) > strike_target_scan_radius_m:
			continue
		result.append(node_3d)
	return result

func _get_inbound_enemy_aircraft() -> Array:
	var result: Array = []
	_refresh_carrier()
	if not _carrier or not is_instance_valid(_carrier):
		return result
	_prune_reported_contacts()
	for target_ref in _reported_contacts.keys():
		if not is_instance_valid(target_ref) or not (target_ref is RigidBody3D):
			continue
		var aircraft := target_ref as RigidBody3D
		if not aircraft.is_in_group("ground_vehicles") and _is_aircraft_threatening_carrier(aircraft):
			result.append(aircraft)
	return result

func _is_enemy_ground_target(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.is_in_group("carrier"):
		return false
	if (node.is_in_group("aircraft") or node.is_in_group("ai_aircraft")) and not node.is_in_group("ground_vehicles"):
		return false
	return _is_valid_report_target_for_team(node, 1)

func _is_aircraft_threatening_carrier(aircraft: RigidBody3D) -> bool:
	if aircraft == null or not is_instance_valid(aircraft) or not _carrier or not is_instance_valid(_carrier):
		return false
	var to_carrier: Vector3 = _carrier.global_position - aircraft.global_position
	to_carrier.y = 0.0
	var distance_m: float = to_carrier.length()
	if distance_m > carrier_air_threat_radius_m:
		return false
	if distance_m <= carrier_air_threat_close_radius_m:
		return true
	var velocity: Vector3 = aircraft.linear_velocity
	velocity.y = 0.0
	var speed_mps: float = velocity.length()
	if speed_mps < maxf(carrier_air_threat_min_closing_speed_mps, 1.0):
		return false
	var to_carrier_dir: Vector3 = to_carrier / maxf(distance_m, 0.001)
	var heading_dot: float = velocity.normalized().dot(to_carrier_dir)
	var closing_speed_mps: float = velocity.dot(to_carrier_dir)
	return heading_dot >= carrier_air_threat_heading_dot and closing_speed_mps >= carrier_air_threat_min_closing_speed_mps

func _prune_reported_contacts() -> void:
	var now_s: float = Time.get_ticks_msec() / 1000.0
	var timeout_s: float = maxf(reported_contact_timeout_s, 0.5)
	var stale: Array = []
	for target_ref in _reported_contacts.keys():
		if not is_instance_valid(target_ref) or not (target_ref is Node3D):
			stale.append(target_ref)
			continue
		var report: Dictionary = _reported_contacts.get(target_ref, {})
		if now_s - float(report.get("last_seen_s", -INF)) > timeout_s:
			stale.append(target_ref)
	for target_ref in stale:
		_reported_contacts.erase(target_ref)

func _flight_center(f: Flight) -> Vector3:
	var members := f.get_members()
	if members.is_empty():
		return _carrier.global_position if (_carrier and is_instance_valid(_carrier)) else Vector3.ZERO
	var sum := Vector3.ZERO
	for m in members:
		sum += m.global_position
	return sum / float(members.size())
