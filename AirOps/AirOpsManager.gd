extends Node

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")

const Readiness = preload("res://Operations/OperationalReadiness.gd")

signal downed_pilot_registered(pilot: Node3D)
signal rescue_assigned(pilot: Node3D, helicopter: Node3D)
signal downed_pilot_rescued(pilot: Node3D, helicopter: Node3D)

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
const RESCUE_STATUS_META := "air_ops_rescue_status"
const RESCUE_STATUS_WAITING := "waiting"
const RESCUE_STATUS_LAUNCHING := "launching"
const RESCUE_STATUS_ASSIGNED := "assigned"

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

@export_group("Rescue Operations")
@export var rescue_dispatch_interval_s: float = 2.0
@export var rescue_launch_timeout_s: float = 180.0
@export var rescue_helicopter_model: String = "Aircraft_11"
@export_group("")

var flights: Array[Flight] = []

var _carrier: Node3D = null
var _assign_timer: float = 0.0
var _threat_timer: float = 0.0
var _sensor_picture_timer: float = 0.0
@export var sensor_batch_budget_ms: float = 1.0
@export var spatial_sensor_queries_enabled: bool = true
var _pending_sensor_observers: Array[WeakRef] = []
var _sensor_batch_candidates: Array[Node3D] = []
var _sensor_batch_index := 0
var sensor_diagnostics := {"cycles": 0, "observers": 0, "candidate_tests": 0, "max_batch_ms": 0.0}
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
@export var task_switch_hysteresis: float = 150.0     # Required priority advantage for emergency diversion
@export var min_cap_flights: int = 1                  # keep at least this many patrolling the carrier when possible
@export var dynamic_tasking_enabled: bool = true      # false = fall back to the legacy 3-slot updates
# Do not empty the hangar just because every scenario has a standing CAP board
# entry. AirOps can still assign an already-airborne flight to CAP, and an
# explicit player order can launch the selected flight.
@export var auto_scramble_for_cap_tasks: bool = false
@export var auto_scramble_for_intercept_tasks: bool = true
# Real detected threats remain valid reasons for AirOps to launch a flight.
@export var auto_scramble_for_strike_tasks: bool = true
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
var _downed_pilots: Array[Node3D] = []
var _rescue_assignments: Dictionary = {}  # Downed pilot -> assigned helicopter.
var _rescue_dispatch_timer_s: float = 0.0
var _pending_rescue_launch_pilot: Node3D = null
var _pending_rescue_launch_elapsed_s: float = 0.0

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	_create_flights()
	print("[AirOpsManager] Ready — flights: %s" % ", ".join(FLIGHT_NAMES))
	call_deferred("_apply_default_missions")


func _create_flights() -> void:
	for fname in FLIGHT_NAMES:
		var f := Flight.new()
		f.name = "Flight_" + fname
		f.flight_name = fname
		f.debug_print = debug_print
		f.mission = default_mission
		add_child(f)
		flights.append(f)


func reset_runtime_state() -> void:
	for flight in flights:
		if is_instance_valid(flight):
			remove_child(flight)
			flight.queue_free()
	flights.clear()
	_carrier = null
	_cap_flight = null
	_intercept_flight = null
	_cas_flight = null
	_scrambling_flight = null
	_scrambling_expected_count = 0
	_scrambling_elapsed_s = 0.0
	_pending_rescue_launch_pilot = null
	_pending_rescue_launch_elapsed_s = 0.0
	_next_flight_idx = 0
	_assign_timer = 0.0
	_threat_timer = 0.0
	_task_timer = 0.0
	_sensor_picture_timer = 0.0
	_sensor_batch_index = 0
	_recovery_supervision_timer_s = 0.0
	_recovery_supervision_elapsed_s = 0.0
	_rescue_dispatch_timer_s = 0.0
	_tasks.clear()
	_flight_task.clear()
	_flight_role.clear()
	_reported_contacts.clear()
	_acknowledged_order_keys.clear()
	_downed_pilots.clear()
	_rescue_assignments.clear()
	_recovery_supervision_records.clear()
	_pending_sensor_observers.clear()
	_sensor_batch_candidates.clear()
	_create_flights()

func _apply_default_missions() -> void:
	_refresh_carrier()
	for f in flights:
		if default_mission == Flight.Mission.CAP:
			f.set_cap(_carrier, default_cap_altitude_m)
		elif default_mission == Flight.Mission.CAS:
			order_cas(f.flight_name)

func _process(delta: float) -> void:
	if GameSession.has_pending_save_state():
		return
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
	_update_rescue_launch_timeout(delta)
	_rescue_dispatch_timer_s -= delta
	if _rescue_dispatch_timer_s <= 0.0 and not GameSession.is_trailer_scenario:
		_rescue_dispatch_timer_s = maxf(rescue_dispatch_interval_s, 0.25)
		_update_rescue_operations()
	if not mission_tasking_enabled:
		FrameProfiler.end("AirOpsManager.process", _profiler_start)
		return
	_sensor_picture_timer -= delta
	if _sensor_picture_timer <= 0.0 and _pending_sensor_observers.is_empty():
		_sensor_picture_timer = maxf(sensor_picture_update_interval_s, 0.1)
		_update_friendly_sensor_picture(true)
	_service_sensor_batch()
	# Keep sensors/recovery active, but let the trailer director own new tasking
	# and launch timing instead of reacting to the checkpoint's mission board.
	if GameSession.is_trailer_scenario:
		FrameProfiler.end("AirOpsManager.process", _profiler_start)
		return

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
	for member in f.get_members():
		OperationsCoordinator.clear_order(member, "superseded by flight recall")
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


func get_reported_mobile_contact_count(prune_stale: bool = true) -> int:
	if prune_stale:
		_prune_reported_contacts()
	var count := 0
	for target_variant in _reported_contacts.keys():
		if not (target_variant is Node3D) or not is_instance_valid(target_variant):
			continue
		var target := target_variant as Node3D
		if target.is_in_group("aircraft") or target.is_in_group("ai_aircraft") \
		or target.is_in_group("ground_vehicles"):
			count += 1
	return count


func get_campaign_save_blocker(prune_stale_contacts: bool = true) -> String:
	var contacts := get_reported_mobile_contact_count(prune_stale_contacts)
	if contacts > 0:
		return "%d mobile enemy contact%s still tracked" % [contacts, "" if contacts == 1 else "s"]
	if _scrambling_flight != null or _scrambling_expected_count > 0:
		return "A flight is still launching"
	var downed_pilots := get_tracked_downed_pilots()
	if not downed_pilots.is_empty():
		return "Recover %d downed pilot%s before saving" % [
			downed_pilots.size(),
			"" if downed_pilots.size() == 1 else "s",
		]
	if is_instance_valid(_pending_rescue_launch_pilot) or not _rescue_assignments.is_empty():
		return "A rescue operation is still active"
	var assigned_aircraft: Dictionary = {}
	for flight in flights:
		for aircraft in flight.get_members():
			assigned_aircraft[aircraft] = true
		if flight.strength() <= 0:
			continue
		var flight_message := flight.get_campaign_save_blocker()
		if not flight_message.is_empty():
			return flight_message
	# Catch manually flown or otherwise unassigned friendly aircraft too.
	for node_variant in get_tree().get_nodes_in_group("friendlies"):
		if not (node_variant is Node3D) or not is_instance_valid(node_variant):
			continue
		var node := node_variant as Node3D
		if (node.is_in_group("aircraft") or node.is_in_group("ai_aircraft")) \
		and not assigned_aircraft.has(node):
			return "Recover %s before saving" % node.name
	return ""


func capture_save_state(flight_deck: Node) -> Dictionary:
	if flight_deck == null or not flight_deck.has_method("capture_deployed_aircraft_save_state"):
		return {}
	var flight_entries: Array[Dictionary] = []
	for flight in flights:
		var members := flight.get_members()
		if members.is_empty():
			continue
		var aircraft_entries: Array[Dictionary] = []
		for aircraft in members:
			var aircraft_variant: Variant = flight_deck.call(
				"capture_deployed_aircraft_save_state", aircraft
			)
			if not (aircraft_variant is Dictionary) or (aircraft_variant as Dictionary).is_empty():
				push_warning("[AirOpsManager] Could not capture %s for campaign save" % aircraft.name)
				return {}
			aircraft_entries.append(aircraft_variant as Dictionary)
		flight_entries.append({
			"flight_name": flight.flight_name,
			"mission_state": flight.capture_mission_save_state(),
			"aircraft": aircraft_entries,
		})
	return {"flights": flight_entries}


func restore_save_state(state: Dictionary, flight_deck: Node) -> bool:
	if flight_deck == null or not flight_deck.has_method("restore_deployed_aircraft_save_state"):
		return false
	for flight in flights:
		for aircraft in flight.get_members().duplicate():
			flight.unregister(aircraft)
	_cap_flight = null
	_intercept_flight = null
	_cas_flight = null
	_scrambling_flight = null
	_scrambling_expected_count = 0
	_scrambling_elapsed_s = 0.0
	_tasks.clear()
	_flight_task.clear()
	_flight_role.clear()
	_reported_contacts.clear()
	_recovery_supervision_records.clear()
	_refresh_carrier()

	var entries_variant: Variant = state.get("flights", [])
	if not (entries_variant is Array):
		return false
	for entry_variant in entries_variant:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		var flight := get_flight(str(entry.get("flight_name", "")))
		if flight == null:
			push_warning("[AirOpsManager] Saved flight no longer exists")
			continue
		var mission_variant: Variant = entry.get("mission_state", {})
		if not (mission_variant is Dictionary) \
		or not flight.restore_mission_save_state(mission_variant as Dictionary, _carrier):
			push_warning("[AirOpsManager] Could not restore mission for %s" % flight.flight_name)
			return false
		var aircraft_variant: Variant = entry.get("aircraft", [])
		if not (aircraft_variant is Array):
			return false
		for data_variant in aircraft_variant:
			if not (data_variant is Dictionary):
				continue
			var restored_variant: Variant = flight_deck.call(
				"restore_deployed_aircraft_save_state", data_variant as Dictionary
			)
			if not (restored_variant is RigidBody3D):
				push_warning("[AirOpsManager] Could not restore an aircraft in %s" % flight.flight_name)
				return false
			var aircraft := restored_variant as RigidBody3D
			flight.register(aircraft)
			_assign_pilot_identity(aircraft, flight)
		if flight.mission == Flight.Mission.CAP and _cap_flight == null:
			_cap_flight = flight
		elif flight.mission == Flight.Mission.CAS and _cas_flight == null:
			_cas_flight = flight
	return true

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
	summary.merge(get_flight_readiness(f), true)
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
	_supervise_flight_readiness()
	_tasks = _build_tasks()
	_tasks.sort_custom(func(a, b):
		var a_priority: float = 950.0 if a.type == "cap" and min_cap_flights > 0 else float(a.priority)
		var b_priority: float = 950.0 if b.type == "cap" and min_cap_flights > 0 else float(b.priority)
		return a_priority > b_priority)
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
		var prio: float = minf(900.0, 200.0 + value + clampf((strike_target_scan_radius_m - dist) / maxf(strike_target_scan_radius_m, 1.0), 0.0, 1.0) * 100.0)
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
	var live_ids: Dictionary = {}
	for task: Dictionary in _tasks:
		task["flight"] = null
		live_ids[task.id] = task
	for f: Flight in _flight_task.keys():
		var task: Dictionary = live_ids.get(_flight_task[f], {})
		var pending := _flight_has_pending_departure(f)
		if f.mission_source != "automatic" or task.is_empty() \
				or (not pending and not _flight_suitable_for_task(f, task)):
			_release_task(f, "Task ended or flight unavailable")
		else:
			task["flight"] = f
	for task: Dictionary in _tasks:
		if task.get("flight") != null:
			continue
		var f := _pick_flight_for_task(task)
		if f == null:
			f = _pick_diversion(task, live_ids)
		if f != null:
			var previous: String = str(_flight_task.get(f, ""))
			if not previous.is_empty():
				_release_task(f, "Diverting to carrier defence")
			_apply_task_to_flight(task, f)
			continue
		if _scrambling_flight == null and _task_allows_automatic_scramble(task):
			var empty := _pick_empty_flight(null)
			if empty != null and empty.mission_source == "automatic":
				if _scramble_flight(empty, _scramble_reason_for_task(task)):
					_apply_task_to_flight(task, empty, true)
	# A completed strike/intercept must not leave an aircraft flying an obsolete
	# attack. Spare automatic flights return to patrol without reserving extra tasks.
	for f in flights:
		if f.mission_source == "automatic" and not _flight_task.has(f) \
				and f.mission in [Flight.Mission.CAS, Flight.Mission.INTERCEPT] \
				and _flight_can_take_tactical_order(f) and _flight_safe_to_redirect(f):
			f.mission_reason = "Previous task ended; patrol pending new task"
			f.set_cap(_carrier, default_cap_altitude_m)
			_flight_role[f] = "cap"


func _release_task(f: Flight, reason: String) -> void:
	var previous := str(_flight_task.get(f, ""))
	_flight_task.erase(f)
	if not previous.is_empty():
		CombatLog.event("ORDER", "%s released from %s: %s" % [f.flight_name, previous.get_slice(":", 0), reason])
	if not _flight_is_active(f):
		_flight_role.erase(f)
	for task: Dictionary in _tasks:
		if task.get("flight") == f:
			task["flight"] = null
	f.mission_reason = reason


func _flight_has_pending_departure(f: Flight) -> bool:
	if f == _scrambling_flight:
		return true
	for member in f.get_members():
		var pilot := member.find_child("AIPilot", true, false) as AIPilot
		if pilot != null and pilot.current_state in [AIPilot.State.LAUNCHING, AIPilot.State.CLIMBING]:
			return true
	return false


func _flight_suitable_for_task(f: Flight, task: Dictionary) -> bool:
	for member in f.get_members():
		if Readiness.can_fill(Readiness.aircraft_status(member), str(task.get("type", ""))):
			return true
	return false


func _pick_diversion(task: Dictionary, live_ids: Dictionary) -> Flight:
	# Only carrier defence preempts a live mission. Small distance/cluster changes
	# must never repeatedly interrupt attacks or shuffle patrol assignments.
	if task.type != "intercept":
		return null
	var best: Flight = null
	var best_cost := INF
	for f: Flight in _flight_task.keys():
		var old: Dictionary = live_ids.get(_flight_task[f], {})
		if old.is_empty() or old.get("type") == "intercept" or f.mission_source != "automatic":
			continue
		if _flight_has_pending_departure(f) or not _flight_suitable_for_task(f, task):
			continue
		if float(task.priority) <= float(old.priority) + maxf(task_switch_hysteresis, 0.0):
			continue
		if not _flight_safe_to_redirect(f):
			continue
		var cost := _flight_center(f).distance_to(task.area)
		if cost < best_cost:
			best = f
			best_cost = cost
	return best


func _flight_safe_to_redirect(f: Flight) -> bool:
	for member in f.get_members():
		var pilot := member.find_child("AIPilot", true, false) as AIPilot
		if pilot != null and pilot.current_state in [AIPilot.State.ATTACK_DIVE, AIPilot.State.ATTACK_BREAK_OFF]:
			return false
	return true


func release_to_automatic(fname: String) -> void:
	var f := get_flight(fname)
	if f == null:
		return
	_release_task(f, "Released to AirOps")
	for member in f.get_members():
		OperationsCoordinator.clear_order(member, "released to AirOps")
	f.mission_source = "automatic"
	# Recovery remains protected even after releasing command ownership.
	if _flight_can_take_tactical_order(f):
		f.set_cap(_carrier, default_cap_altitude_m)


func get_aircraft_readiness(aircraft: Node3D) -> Dictionary:
	return Readiness.aircraft_status(aircraft) if is_instance_valid(aircraft) else {}


func get_flight_readiness(f: Flight) -> Dictionary:
	var members: Array[Dictionary] = []
	var ready := 0
	var recovering := 0
	var departing := 0
	for member in f.get_members():
		var status := Readiness.aircraft_status(member)
		members.append(status)
		ready += int(status.available)
		recovering += int(status.recovering)
		departing += int(status.departing)
	var phase := "ACTIVE"
	if members.is_empty():
		phase = "STORED"
	elif recovering == members.size():
		phase = "RETURNING"
	elif ready == 0:
		phase = "UNAVAILABLE"
	elif ready < members.size():
		phase = "PARTIAL"
	if f == _scrambling_flight or (departing > 0 and ready == 0):
		phase = "LAUNCHING"
	return {"member_readiness": members, "ready_count": ready, "recovering_count": recovering,
		"phase": phase, "task_id": str(_flight_task.get(f, ""))}


func _supervise_flight_readiness() -> void:
	for f in flights:
		for member in f.get_members():
			var status := Readiness.aircraft_status(member)
			if status.player_controlled or status.recovering or status.departing or status.reason in ["Individual order", "Deck operations", "Destroyed or initializing"]:
				continue
			var pilot := member.find_child("AIPilot", true, false) as AIPilot
			if pilot == null:
				continue
			# Reuse the pilot's health/fuel and recovery-queue budget policy.
			if pilot.supervise_return_resources():
				continue
			if status.available and status.weapons_known and status.guns + status.bombs + status.rockets == 0:
				member.set_meta("rtb_reason", "Weapons exhausted")
				pilot.assign_air_task(preload("res://AI/AirTask.gd").return_to_base())
				CombatLog.event("RTB", "%s returning: weapons exhausted" % member.name)

func _task_allows_automatic_scramble(task: Dictionary) -> bool:
	match str(task.get("type", "")):
		"cap":
			return auto_scramble_for_cap_tasks
		"intercept":
			return auto_scramble_for_intercept_tasks
		"strike":
			return auto_scramble_for_strike_tasks
	return false

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
	f.mission_source = "automatic"
	f.mission_reason = "Carrier defence" if t.get("type") == "intercept" else "Mission board assignment"
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
		if _flight_task.has(f) or f.mission_source != "automatic":
			continue
		if not _flight_suitable_for_task(f, t) or not _flight_safe_to_redirect(f):
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

## Called by FlightDeckManager after an AI aircraft is brought up for launch.
## The callback is shared by combat scrambles and autonomous rescue launches.
func notify_aircraft_launched(pilot: Node) -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	var aircraft := pilot.get("aircraft") as Node3D
	if is_instance_valid(_pending_rescue_launch_pilot) \
			and is_instance_valid(aircraft) \
			and _is_rescue_helicopter(aircraft) \
			and pilot.has_method("command_rescue"):
		var rescue_target := _pending_rescue_launch_pilot
		_pending_rescue_launch_pilot = null
		_pending_rescue_launch_elapsed_s = 0.0
		_assign_rescue_helicopter(rescue_target, aircraft, pilot)
		return
	if not _scrambling_flight:
		return
	# Aircraft_11 is a utility helicopter — never assign it to combat flights.
	if aircraft and aircraft.name.begins_with("Aircraft_11"):
		return
	if not (pilot is AIPilot):
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
	return is_instance_valid(aircraft) and bool(Readiness.aircraft_status(aircraft).available)

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
	if not maintain_carrier_cap or GameSession.is_trailer_scenario:
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
		if f.mission_source != "automatic":
			continue
		if f == exclude:
			continue
		if f == _scrambling_flight:
			continue
		if f == _intercept_flight or f == _cas_flight:
			continue
		if f.strength() > 0:
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
	if not PilotRoster.has_method("assign_aircraft_to_flight_callsign") \
	and not PilotRoster.has_method("assign_aircraft_to_callsign"):
		return
	var members := flight.get_members()
	var member_index := members.find(aircraft)
	if member_index < 0:
		return
	var callsign := "%s %s" % [flight.flight_name, _callsign_suffix_for_member_index(member_index)]
	if PilotRoster.has_method("assign_aircraft_to_flight_callsign"):
		PilotRoster.assign_aircraft_to_flight_callsign(aircraft, callsign)
	else:
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
	_release_task(f, "Player order")
	_flight_role.erase(f)
	f.mission_source = "player"
	f.mission_reason = "Player order"
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

## Called when a friendly pilot reaches the ground. Air Ops keeps the pilot on
## its board until pickup instead of treating a temporarily busy deck as a
## failed one-shot rescue request.
func request_rescue_for(pilot_node: Node3D) -> void:
	if not is_instance_valid(pilot_node):
		return
	if not _downed_pilots.has(pilot_node):
		_downed_pilots.append(pilot_node)
		pilot_node.set_meta(RESCUE_STATUS_META, RESCUE_STATUS_WAITING)
		downed_pilot_registered.emit(pilot_node)
		var callsign := _downed_pilot_callsign(pilot_node)
		RadioComms.transmit("Citadel", callsign, RadioComms._pick([
			"Your position is logged. Air Ops is tasking rescue.",
			"We have your position. Stand by for rescue tasking.",
		]))
		print("[AirOpsManager] Tracking downed pilot %s" % pilot_node.name)
	_update_rescue_operations()


func notify_pilot_rescued(pilot_node: Node3D, helicopter: Node3D = null) -> void:
	if pilot_node == null:
		return
	_downed_pilots.erase(pilot_node)
	_rescue_assignments.erase(pilot_node)
	if _pending_rescue_launch_pilot == pilot_node:
		_pending_rescue_launch_pilot = null
		_pending_rescue_launch_elapsed_s = 0.0
	if is_instance_valid(pilot_node) and pilot_node.has_meta(RESCUE_STATUS_META):
		pilot_node.remove_meta(RESCUE_STATUS_META)
	downed_pilot_rescued.emit(pilot_node, helicopter)
	print("[AirOpsManager] Downed pilot %s recovered by %s" % [
		pilot_node.name if is_instance_valid(pilot_node) else "<freed>",
		helicopter.name if is_instance_valid(helicopter) else "rescue helicopter",
	])
	# Re-run tasking now that this survivor is aboard. A rescue helicopter with
	# another free passenger position can collect the next waiting survivor;
	# otherwise it is released to return to the carrier.
	_update_rescue_operations()
	if is_instance_valid(helicopter):
		var helicopter_pilot := helicopter.find_child("HelicopterPilot", true, false)
		if helicopter_pilot != null and helicopter_pilot.has_method("finish_rescue_pickups"):
			helicopter_pilot.call("finish_rescue_pickups")


func get_tracked_downed_pilots() -> Array[Node3D]:
	_prune_rescue_operations()
	return _downed_pilots.duplicate()


func get_downed_pilot_snapshot() -> Array[Dictionary]:
	_prune_rescue_operations()
	var snapshot: Array[Dictionary] = []
	for pilot_node in _downed_pilots:
		var helicopter := _get_valid_rescue_helicopter(pilot_node)
		snapshot.append({
			"pilot": pilot_node,
			"callsign": _downed_pilot_callsign(pilot_node),
			"position": pilot_node.global_position,
			"status": str(pilot_node.get_meta(RESCUE_STATUS_META, RESCUE_STATUS_WAITING)),
			"helicopter": helicopter,
			"helicopter_name": helicopter.name if is_instance_valid(helicopter) else "",
			"ground_platoon": str(pilot_node.get_meta("ground_rescue_platoon", "")),
		})
	return snapshot


func _update_rescue_operations() -> void:
	_prune_rescue_operations()
	for pilot_node in _downed_pilots:
		var assigned_helicopter := _get_valid_rescue_helicopter(pilot_node)
		if _rescue_assignment_is_active(pilot_node, assigned_helicopter):
			continue
		if assigned_helicopter != null:
			_rescue_assignments.erase(pilot_node)
			pilot_node.set_meta(RESCUE_STATUS_META, RESCUE_STATUS_WAITING)
		if pilot_node == _pending_rescue_launch_pilot:
			continue

		var available_helicopter := _find_available_rescue_helicopter()
		var ground_ops := get_node_or_null("/root/GroundOpsManager")
		if ground_ops != null and is_instance_valid(ground_ops.rescue_service) \
				and ground_ops.rescue_service.consider(pilot_node, available_helicopter):
			continue
		if available_helicopter != null:
			var helicopter_pilot := available_helicopter.find_child("HelicopterPilot", true, false)
			_assign_rescue_helicopter(pilot_node, available_helicopter, helicopter_pilot)
		elif _pending_rescue_launch_pilot == null:
			_queue_rescue_helicopter(pilot_node)


func _prune_rescue_operations() -> void:
	for index in range(_downed_pilots.size() - 1, -1, -1):
		var pilot_node := _downed_pilots[index]
		if not is_instance_valid(pilot_node) or pilot_node.is_queued_for_deletion():
			_rescue_assignments.erase(pilot_node)
			_downed_pilots.remove_at(index)
	for pilot_variant in _rescue_assignments.keys():
		if not is_instance_valid(pilot_variant) or not _downed_pilots.has(pilot_variant):
			_rescue_assignments.erase(pilot_variant)
			continue
		var helicopter_variant: Variant = _rescue_assignments.get(pilot_variant, null)
		if not is_instance_valid(helicopter_variant):
			_rescue_assignments.erase(pilot_variant)
			pilot_variant.set_meta(RESCUE_STATUS_META, RESCUE_STATUS_WAITING)
	if is_instance_valid(_pending_rescue_launch_pilot) \
			and not _downed_pilots.has(_pending_rescue_launch_pilot):
		_pending_rescue_launch_pilot = null
		_pending_rescue_launch_elapsed_s = 0.0
	elif _pending_rescue_launch_pilot != null and not is_instance_valid(_pending_rescue_launch_pilot):
		_pending_rescue_launch_pilot = null
		_pending_rescue_launch_elapsed_s = 0.0


func _get_valid_rescue_helicopter(pilot_node: Node3D) -> Node3D:
	var helicopter_variant: Variant = _rescue_assignments.get(pilot_node, null)
	if not is_instance_valid(helicopter_variant):
		return null
	return helicopter_variant as Node3D


func _update_rescue_launch_timeout(delta: float) -> void:
	if not is_instance_valid(_pending_rescue_launch_pilot):
		_pending_rescue_launch_elapsed_s = 0.0
		return
	_pending_rescue_launch_elapsed_s += maxf(delta, 0.0)
	if _pending_rescue_launch_elapsed_s < maxf(rescue_launch_timeout_s, 10.0):
		return
	var timed_out_pilot := _pending_rescue_launch_pilot
	_pending_rescue_launch_pilot = null
	_pending_rescue_launch_elapsed_s = 0.0
	if is_instance_valid(timed_out_pilot):
		timed_out_pilot.set_meta(RESCUE_STATUS_META, RESCUE_STATUS_WAITING)
		push_warning("[AirOpsManager] Rescue launch timed out for %s; returning it to the task board" % timed_out_pilot.name)


func _find_available_rescue_helicopter() -> Node3D:
	if not is_inside_tree():
		return null
	var best_heli: Node3D = null
	var best_priority := -1
	for node in get_tree().get_nodes_in_group("friendlies"):
		var friendly := node as Node3D
		if friendly == null or not is_instance_valid(friendly):
			continue
		if not friendly.is_in_group("ai_aircraft"):
			continue
		if not _is_rescue_helicopter(friendly):
			continue
		if bool(friendly.get_meta("carrier_transport_mode", false)) \
				or bool(friendly.get_meta("controls_disabled", false)):
			continue
		var heli_pilot := friendly.find_child("HelicopterPilot", true, false)
		if heli_pilot == null or not heli_pilot.has_method("command_rescue"):
			continue
		if heli_pilot.has_method("can_accept_passenger") \
				and not bool(heli_pilot.call("can_accept_passenger")):
			continue
		var phase := int(heli_pilot.get("mission_phase"))
		# Skip INBOUND (2) and helicopters already flying an assigned RESCUE (4).
		# A landed rescue helicopter with no current target can take another.
		var rescue_target: Variant = heli_pilot.get("_rescue_target") if phase == 4 else null
		if phase == 2 or (phase == 4 and is_instance_valid(rescue_target)):
			continue
		# Aircraft_11 is the dedicated rescue/utility type — strongly prefer it.
		var is_utility := friendly.name.begins_with("Aircraft_11")
		var base := 10 if is_utility else 0
		var priority := -1
		if phase == 4:   # RESCUE, landed after pickup with another seat free
			priority = base + 4
		elif phase == 3: # AT_CARRIER: on deck, ready to launch
			priority = base + 3
		elif phase == 0: # OUTBOUND: airborne, can be rerouted
			priority = base + 2
		elif phase == 1: # AT_LZ: on ground elsewhere, reroutable
			priority = base + 1
		if priority > best_priority:
			best_priority = priority
			best_heli = friendly
	return best_heli


func _queue_rescue_helicopter(pilot_node: Node3D) -> bool:
	if not is_instance_valid(pilot_node) or not is_inside_tree():
		return false
	var flight_deck_manager := get_tree().get_first_node_in_group("flight_deck_manager")
	if flight_deck_manager == null or not flight_deck_manager.has_method("queue_ai_helicopters"):
		return false
	if flight_deck_manager.has_method("can_queue_ai_helicopters") \
			and not bool(flight_deck_manager.call("can_queue_ai_helicopters", rescue_helicopter_model)):
		return false
	var accepted_count := int(flight_deck_manager.call(
		"queue_ai_helicopters", 1, self, rescue_helicopter_model
	))
	if accepted_count <= 0:
		return false
	_pending_rescue_launch_pilot = pilot_node
	_pending_rescue_launch_elapsed_s = 0.0
	pilot_node.set_meta(RESCUE_STATUS_META, RESCUE_STATUS_LAUNCHING)
	RadioComms.transmit("Citadel", _downed_pilot_callsign(pilot_node), RadioComms._pick([
		"Rescue helicopter is coming up from the hangar now.",
		"Rescue launch is in progress. Hold position.",
	]))
	print("[AirOpsManager] Queued %s from the hangar for %s" % [rescue_helicopter_model, pilot_node.name])
	return true


func _assign_rescue_helicopter(pilot_node: Node3D, helicopter: Node3D, helicopter_pilot: Node) -> bool:
	if not is_instance_valid(pilot_node) or not is_instance_valid(helicopter) \
			or helicopter_pilot == null or not helicopter_pilot.has_method("command_rescue"):
		return false
	helicopter_pilot.call("command_rescue", pilot_node)
	_rescue_assignments[pilot_node] = helicopter
	pilot_node.set_meta(RESCUE_STATUS_META, RESCUE_STATUS_ASSIGNED)
	RadioComms.transmit("Citadel", _downed_pilot_callsign(pilot_node), RadioComms._pick([
		"Rescue helo is on the way. Hold position.",
		"We have you on scope. Rescue is inbound.",
		"Hang tight. Rescue helo is en route.",
	]))
	rescue_assigned.emit(pilot_node, helicopter)
	print("[AirOpsManager] Dispatched %s on rescue mission for %s" % [helicopter.name, pilot_node.name])
	return true


func _rescue_assignment_is_active(pilot_node: Node3D, helicopter: Node3D) -> bool:
	if not is_instance_valid(pilot_node) or not is_instance_valid(helicopter):
		return false
	var helicopter_pilot := helicopter.find_child("HelicopterPilot", true, false)
	if helicopter_pilot == null:
		return false
	if int(helicopter_pilot.get("mission_phase")) != 4: # HelicopterPilot.MissionPhase.RESCUE
		return false
	return helicopter_pilot.get("_rescue_target") == pilot_node


func _is_rescue_helicopter(aircraft: Node3D) -> bool:
	return is_instance_valid(aircraft) \
			and bool(aircraft.get_meta("is_helicopter", false))


func _downed_pilot_callsign(pilot_node: Node3D) -> String:
	if is_instance_valid(pilot_node) and pilot_node.has_meta("pilot_callsign"):
		return str(pilot_node.get_meta("pilot_callsign"))
	return "Downed pilot"


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

func _update_friendly_sensor_picture(budgeted: bool = false) -> void:
	var started: int = FrameProfiler.begin("AirOpsManager.sensor_collect")
	_refresh_carrier()
	_sensor_batch_candidates = _collect_contact_candidates()
	_pending_sensor_observers.clear()
	_sensor_batch_index = 0
	sensor_diagnostics.cycles += 1
	if carrier_radar_enabled and _carrier and is_instance_valid(_carrier):
		_pending_sensor_observers.append(weakref(_carrier))
	if ground_vehicle_radar_enabled:
		for sensor_ref in get_tree().get_nodes_in_group("ground_vehicles"):
			if not is_instance_valid(sensor_ref) or not (sensor_ref is Node3D):
				continue
			var sensor := sensor_ref as Node3D
			if _get_node_team(sensor, 0) != 1:
				continue
			if bool(sensor.get_meta("carrier_transport_mode", false)):
				continue
			_pending_sensor_observers.append(weakref(sensor))
	FrameProfiler.end("AirOpsManager.sensor_collect", started)
	_prune_reported_contacts()
	if not budgeted: _service_sensor_batch(false)

func _service_sensor_batch(budgeted: bool = true) -> void:
	if _pending_sensor_observers.is_empty(): return
	var started: int = FrameProfiler.begin("AirOpsManager.sensor_batch")
	var clock_start := Time.get_ticks_usec()
	var snapshot := WorldUnitIndex.build_spatial_snapshot(_sensor_batch_candidates) if spatial_sensor_queries_enabled else {}
	while _sensor_batch_index < _pending_sensor_observers.size():
		var sensor: Variant = _pending_sensor_observers[_sensor_batch_index].get_ref()
		_sensor_batch_index += 1
		if is_instance_valid(sensor) and sensor.is_inside_tree():
			var is_carrier: bool = sensor == _carrier
			var enabled_now: bool = carrier_radar_enabled if is_carrier else ground_vehicle_radar_enabled
			if enabled_now and not bool(sensor.get_meta("carrier_transport_mode", false)):
				var radius := _carrier_sensor_radius(sensor) if is_carrier else ground_vehicle_radar_range_m
				var candidates := WorldUnitIndex.query_spatial_snapshot(snapshot, sensor.global_position, radius) if spatial_sensor_queries_enabled else _sensor_batch_candidates
				sensor_diagnostics.observers += 1
				sensor_diagnostics.candidate_tests += candidates.size()
				_report_contacts_seen_by_sensor(sensor, radius, candidates)
		if budgeted and Time.get_ticks_usec() - clock_start >= maxf(sensor_batch_budget_ms, 0.1) * 1000.0: break
	if _sensor_batch_index >= _pending_sensor_observers.size():
		_pending_sensor_observers.clear()
		_sensor_batch_candidates.clear()
	sensor_diagnostics.max_batch_ms = maxf(sensor_diagnostics.max_batch_ms, (Time.get_ticks_usec() - clock_start) / 1000.0)
	FrameProfiler.end("AirOpsManager.sensor_batch", started)

func _carrier_sensor_radius(carrier: Node3D) -> float:
	var factor := 1.0
	if is_instance_valid(carrier) and carrier.has_method("get_system_capability"):
		factor = float(carrier.call("get_system_capability", "island"))
	return maxf(carrier_radar_range_m, 0.0) * factor

func get_carrier_sensor_contacts(carrier: Node3D) -> Array[Node3D]:
	## Live carrier-local radar picture, independent of weapon assignments and
	## stale reports from other observers. Reading it does not issue combat orders.
	var result: Array[Node3D] = []
	if not carrier_radar_enabled or not is_instance_valid(carrier) \
			or not carrier.is_inside_tree() or _get_node_team(carrier, 1) != 1:
		return result
	var radius := _carrier_sensor_radius(carrier)
	if radius <= 0.0:
		return result
	var candidates: Array[Node3D] = []
	if WorldUnitIndex.enabled and WorldUnitIndex.spatial_queries_enabled:
		candidates = WorldUnitIndex.query_nodes_in_groups(carrier.global_position, radius,
			["enemies", "aircraft", "ai_aircraft", "ground_vehicles"])
		# Static objectives need not belong to the mobile-unit spatial directory.
		for group_name in ["enemy_bases", "gun_emplacements", "buildings"]:
			for node in get_tree().get_nodes_in_group(group_name):
				if node is Node3D:
					candidates.append(node as Node3D)
	else:
		candidates = _collect_contact_candidates()
	var seen: Dictionary = {}
	for target in candidates:
		if not is_instance_valid(target) or target == carrier \
				or not target.is_inside_tree() or target.is_queued_for_deletion():
			continue
		if ("is_destroyed" in target and bool(target.get("is_destroyed"))) \
				or ("is_dying" in target and bool(target.get("is_dying"))):
			continue
		if not _is_valid_report_target_for_team(target, 1) \
				or carrier.global_position.distance_squared_to(target.global_position) > radius * radius:
			continue
		var id := target.get_instance_id()
		if not seen.has(id):
			seen[id] = true
			result.append(target)
	return result

func get_carrier_monitor_contacts(carrier: Node3D) -> Array[Node3D]:
	# Observation includes live friendly aircraft and ground units; never feed this mixed list to
	# hostile-contact reporting or weapon allocation.
	var result := get_carrier_sensor_contacts(carrier)
	if not is_instance_valid(carrier) or not carrier.is_inside_tree():
		return result
	var radius := _carrier_sensor_radius(carrier)
	if radius <= 0.0:
		return result
	var candidates: Array[Node3D] = []
	if WorldUnitIndex.enabled and WorldUnitIndex.spatial_queries_enabled:
		candidates = WorldUnitIndex.query_nodes_in_groups(carrier.global_position, radius,
			["aircraft", "ai_aircraft", "friendlies", "ground_vehicles"])
	else:
		for group_name in ["aircraft", "ai_aircraft", "friendlies", "ground_vehicles"]:
			for node in get_tree().get_nodes_in_group(group_name):
				if node is Node3D:
					candidates.append(node as Node3D)
	for aircraft in candidates:
		if _is_friendly_monitor_contact(aircraft, carrier) \
				and carrier.global_position.distance_squared_to(aircraft.global_position) <= radius * radius \
				and not result.has(aircraft):
			result.append(aircraft)
	return result

func _is_friendly_monitor_contact(unit: Node3D, carrier: Node3D) -> bool:
	if not is_instance_valid(unit) or unit == carrier or not unit.is_inside_tree() \
			or unit.is_queued_for_deletion() or _get_node_team(unit, 0) != 1:
		return false
	if ("is_destroyed" in unit and bool(unit.get("is_destroyed"))) \
			or ("is_dying" in unit and bool(unit.get("is_dying"))):
		return false
	if unit is RigidBody3D and unit.freeze:
		return false
	for flag in ["carrier_transport_mode", "carrier_manual_transport", "parking_brake"]:
		if bool(unit.get_meta(flag, false)):
			return false
	return true

func is_friendly_carrier_recovery_contact(aircraft: Node3D, carrier: Node3D) -> bool:
	if not is_instance_valid(aircraft) or not aircraft.is_inside_tree() \
			or aircraft.is_queued_for_deletion() or _get_node_team(aircraft, 0) != 1:
		return false
	if not (aircraft.is_in_group("aircraft") or aircraft.is_in_group("ai_aircraft")) \
			or aircraft.is_in_group("ground_vehicles"):
		return false
	if ("is_destroyed" in aircraft and bool(aircraft.get("is_destroyed"))) \
			or ("is_dying" in aircraft and bool(aircraft.get("is_dying"))):
		return false
	if aircraft is RigidBody3D and aircraft.freeze:
		return false
	for flag in ["carrier_transport_mode", "carrier_manual_transport", "parking_brake"]:
		if bool(aircraft.get_meta(flag, false)):
			return false
	var deck := carrier.get_node_or_null("FlightDeckManager")
	if deck != null and aircraft is RigidBody3D \
			and deck.has_method("is_aircraft_physically_settled_on_landing_deck") \
			and bool(deck.call("is_aircraft_physically_settled_on_landing_deck", aircraft)):
		return false
	var pilot := aircraft.find_child("AIPilot", true, false)
	if pilot == null or not "current_state" in pilot:
		return false
	if "_cached_carrier_node" in pilot:
		var destination: Variant = pilot.get("_cached_carrier_node")
		if is_instance_valid(destination) and destination != carrier:
			return false
	return int(pilot.get("current_state")) in [AIPilot.State.RTB,
		AIPilot.State.RECOVERY_MARSHAL, AIPilot.State.RECOVERY_HOLD,
		AIPilot.State.RECOVERY_APPROACH, AIPilot.State.APPROACH,
		AIPilot.State.PRE_LANDING, AIPilot.State.LANDING, AIPilot.State.MISSED_APPROACH]

func _collect_contact_candidates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var seen := {}
	for group_name in ["enemies", "enemy_bases", "aircraft", "ai_aircraft", "ground_vehicles", "gun_emplacements", "buildings"]:
		for node_ref in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node_ref) or not (node_ref is Node3D):
				continue
			var node := node_ref as Node3D
			if seen.has(node.get_instance_id()):
				continue
			seen[node.get_instance_id()] = true
			result.append(node)
	return result

func _report_contacts_seen_by_sensor(sensor: Node3D, range_m: float, candidates: Array[Node3D]) -> void:
	if sensor == null or not is_instance_valid(sensor) or range_m <= 0.0:
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
	return f.get_mission_name()

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
