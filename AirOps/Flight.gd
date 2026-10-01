class_name Flight
extends Node

const AirTaskModel: Script = preload("res://AI/AirTask.gd")
const InterceptTarget: Script = preload("res://AirOps/InterceptTarget.gd")
const GroundTargetPriority: Script = preload("res://AI/GroundTargetPriority.gd")

## Manages a single named flight of 2-4 aircraft.
## Applies mission settings to each pilot and handles per-aircraft target
## distribution for CAS missions.
## Tactical decisions (intercept, recall) are made by AirOpsManager, not here.

enum Mission {
	NONE,
	CAP,    ## Combat Air Patrol — orbit carrier, engage air threats only
	CAS,    ## Close Air Support — attack ground targets in assigned area
	INTERCEPT,
	RTB,    ## Return all aircraft to carrier
	ATTACK, ## Clear a small designated ground area, then return.
}

@export var flight_name: String = ""
@export var debug_print: bool = false

var mission: Mission = Mission.NONE
var mission_source := "automatic"
var mission_reason := "Standing orders"

var _members: Array[Node3D] = []
var _claimed_targets: Dictionary = {}  # Node3D target -> Node3D aircraft
var _mission_revision: int = 0
var _member_mission_revision: Dictionary = {}  # Node3D aircraft -> int

# CAP state
var _cap_carrier: Node3D = null
var _cap_altitude_m: float = 800.0
var _cap_route_points: Array[Vector3] = []
var _cap_route_lead: Node3D = null
var _cap_route_revision: int = 0
var _cap_route_lead_revision: int = -1

# CAS state
var _cas_area_center: Vector3 = Vector3.ZERO
var _cas_area_radius: float = 3000.0
var _cas_altitude_m: float = 300.0
var _attack_area_visited := false
var _attack_area_clear_s := 0.0
var _attack_platoon: Node = null
var _attack_tracks_platoon := false

var _intercept_target: Node3D = null
var _intercept_flight: Node = null
var _intercept_tracks_flight := false
var _intercept_update_s := 0.0
var _intercept_carrier: Node3D = null
var _intercept_altitude_m: float = 800.0

signal mission_changed(new_mission: Mission)

# ── Lifecycle ──────────────────────────────────────────────────────────────────

# Loose wedge offsets in leader-local space (right, up, forward).
# Lead is index 0 and flies its own mission guidance unmodified.
const FORMATION_OFFSETS: Array[Vector3] = [
	Vector3(  0,   0,    0),  # lead  — not used, flies own patrol
	Vector3( 35,   0,  -35),  # two   — right echelon
	Vector3(-35,   0,  -35),  # three — left echelon
	Vector3(  0,   0,  -75),  # four  — trail centre
]
const CAP_ROUTE_MIN_AGL_M: float = 260.0
const FORMATION_ACTIVE_STATES: Array = [
	AIPilot.State.SEARCH,
	AIPilot.State.TRANSIT,
]
const FORMATION_BREAK_STATES: Array = [
	AIPilot.State.DOGFIGHT,
	AIPilot.State.ATTACK_POSITIONING,
	AIPilot.State.ATTACK_INBOUND,
	AIPilot.State.ATTACK_DIVE,
	AIPilot.State.ATTACK_BREAK_OFF,
	AIPilot.State.RTB,
	AIPilot.State.RECOVERY_MARSHAL,
	AIPilot.State.RECOVERY_HOLD,
	AIPilot.State.RECOVERY_APPROACH,
	AIPilot.State.PRE_LANDING,
	AIPilot.State.APPROACH,
	AIPilot.State.LANDING,
	AIPilot.State.IDLE,
	AIPilot.State.LAUNCHING,
	AIPilot.State.CLIMBING,
]
const FORMATION_FORWARD_HOLD_START_M: float = 8.0
const FORMATION_SLOT_FORWARD_CLOSE_M: float = 14.0
const FORMATION_SLOT_FORWARD_SOFT_M: float = 95.0
const FORMATION_SLOT_LATERAL_CLOSE_M: float = 10.0
const FORMATION_SLOT_LATERAL_SOFT_M: float = 65.0
const FORMATION_SLOT_VERTICAL_CLOSE_M: float = 8.0
const FORMATION_SLOT_VERTICAL_SOFT_M: float = 35.0
const FORMATION_WINGMAN_MAX_SPEED_BONUS_MPS: float = 20.0
const FORMATION_WINGMAN_MAX_SPEED_REDUCTION_MPS: float = 12.0
const FORMATION_LEAD_SLOWDOWN_START_M: float = 40.0
const FORMATION_LEAD_FULL_WAIT_M: float = 120.0
const FORMATION_LEAD_MAX_SLOWDOWN_MPS: float = 24.0
const FORMATION_LEAD_MIN_SPEED_MPS: float = 62.0
const CAP_ROUTE_ENTRY_SKIP_DISTANCE_M: float = 140.0

var _members_clean_frame: int = -1  # Last frame when _members was pruned, for diagnostics/invalidation only

func _ready() -> void:
	add_to_group("origin_shifter")

func apply_origin_shift(offset: Vector3) -> void:
	_cas_area_center -= offset
	for i in range(_cap_route_points.size()):
		_cap_route_points[i] -= offset

func _physics_process(delta: float) -> void:
	_prune_members_once()
	_refresh_attack_platoon_position()
	_apply_pending_mission_updates()
	if mission == Mission.CAS:
		_update_cas_assignments()
	elif mission == Mission.ATTACK:
		_update_attack_assignment(delta)
	elif mission == Mission.INTERCEPT and _intercept_tracks_flight:
		_intercept_update_s -= delta
		if _intercept_update_s <= 0.0:
			_intercept_update_s = 1.0
			_update_intercept_assignment()
	if mission != Mission.NONE:
		_update_formation()

# ── Membership ────────────────────────────────────────────────────────────────

func _prune_members_once() -> void:
	var frame := Engine.get_physics_frames()
	_members_clean_frame = frame
	_members = _members.filter(func(a): return a and is_instance_valid(a))

func register(aircraft: Node3D) -> void:
	if not aircraft or not is_instance_valid(aircraft):
		return
	if _members.has(aircraft):
		return
	_members.append(aircraft)
	_members_clean_frame = -1  # Invalidate cache
	_member_mission_revision[aircraft] = -1
	_apply_current_mission(aircraft)
	if debug_print:
		print("[Flight %s] + %s  (strength: %d)" % [flight_name, aircraft.name, strength()])

func unregister(aircraft: Node3D) -> void:
	if aircraft == _cap_route_lead:
		_cap_route_lead = null
		_cap_route_lead_revision = -1
	_members.erase(aircraft)
	_members_clean_frame = -1  # Invalidate cache
	_member_mission_revision.erase(aircraft)
	_prune_stale_claims(false)
	var stale_claims: Array = []
	for target_ref in _claimed_targets.keys():
		var claimer_ref = _claimed_targets.get(target_ref)
		if not _is_live_node3d_ref(claimer_ref) or claimer_ref == aircraft:
			stale_claims.append(target_ref)
	for target_ref in stale_claims:
		_claimed_targets.erase(target_ref)

func get_members() -> Array[Node3D]:
	_prune_members_once()
	return _members

func strength() -> int:
	return get_members().size()

## Returns true if any member is currently in an air-to-air engagement.
func is_engaged() -> bool:
	for m in get_members():
		var p := _get_pilot(m)
		if p and p.current_state in [AIPilot.State.DOGFIGHT]:
			return true
	return false


func get_campaign_save_blocker() -> String:
	if mission in [Mission.CAS, Mission.ATTACK]:
		return "%s flight still has an attack order" % flight_name
	if mission == Mission.INTERCEPT:
		return "%s flight is still intercepting" % flight_name
	for aircraft in get_members():
		if aircraft.scene_file_path.is_empty():
			return "%s cannot be reconstructed from a saved scene" % aircraft.name
		if bool(aircraft.get_meta("carrier_transport_mode", false)):
			return "%s is still in carrier transport" % aircraft.name
		if bool(aircraft.get_meta("controls_disabled", false)):
			return "%s is still in a launch or recovery sequence" % aircraft.name
		var pilot := _get_pilot(aircraft)
		if pilot == null:
			return "%s has no restorable AI pilot" % aircraft.name
		if pilot.current_state in [
			AIPilot.State.ATTACK_POSITIONING,
			AIPilot.State.ATTACK_INBOUND,
			AIPilot.State.ATTACK_DIVE,
			AIPilot.State.ATTACK_BREAK_OFF,
			AIPilot.State.DOGFIGHT,
			AIPilot.State.ENGAGE,
		]:
			return "%s is still attacking" % aircraft.name
		if pilot.current_state in [
			AIPilot.State.IDLE,
			AIPilot.State.LAUNCHING,
			AIPilot.State.RECOVERY_MARSHAL,
			AIPilot.State.RECOVERY_HOLD,
			AIPilot.State.RECOVERY_APPROACH,
			AIPilot.State.PRE_LANDING,
			AIPilot.State.APPROACH,
			AIPilot.State.LANDING,
			AIPilot.State.MISSED_APPROACH,
		]:
			return "%s is still in a launch or recovery sequence" % aircraft.name
	return ""


func capture_mission_save_state() -> Dictionary:
	return {
		"mission": int(mission),
		"mission_source": mission_source,
		"mission_reason": mission_reason,
		"cap_altitude_m": _cap_altitude_m,
		"patrol_engagement": patrol_engagement,
		"cap_route_points": _cap_route_points.duplicate(),
		"cas_area_center": _cas_area_center,
		"cas_area_radius": _cas_area_radius,
		"cas_altitude_m": _cas_altitude_m,
		"intercept_altitude_m": _intercept_altitude_m,
	}


func restore_mission_save_state(state: Dictionary, carrier: Node3D) -> bool:
	mission_source = str(state.get("mission_source", "player"))
	mission_reason = str(state.get("mission_reason", "Restored order"))
	var restored_mission := int(state.get("mission", Mission.NONE))
	match restored_mission:
		Mission.NONE:
			mission = Mission.NONE
			_mark_mission_dirty()
			_cap_carrier = carrier
			_cap_route_points.clear()
			_cap_route_lead = null
			_cap_route_revision += 1
			_cap_route_lead_revision = -1
			_claimed_targets.clear()
			mission_changed.emit(mission)
		Mission.CAP:
			var route_points: Array[Vector3] = []
			var route_variant: Variant = state.get("cap_route_points", [])
			if route_variant is Array:
				for point_variant in route_variant:
					if point_variant is Vector3:
						route_points.append(point_variant)
			var altitude_m := float(state.get("cap_altitude_m", 800.0))
			if route_points.is_empty():
				set_cap(carrier, altitude_m)
			else:
				set_cap_route(carrier, route_points, altitude_m, str(state.get("patrol_engagement", "air")))
		Mission.CAS:
			set_cas(
				state.get("cas_area_center", Vector3.ZERO) as Vector3,
				float(state.get("cas_area_radius", 3000.0)),
				float(state.get("cas_altitude_m", 300.0))
			)
		Mission.RTB:
			set_rtb()
		Mission.INTERCEPT, Mission.ATTACK:
			# Target-specific missions depend on a live reference and are deliberately not
			# eligible for checkpoints. Reject one if a malformed save contains it.
			return false
		_:
			return false
	return true

# ── Mission orders ─────────────────────────────────────────────────────────────

var patrol_engagement: String = "air"

func set_cap(carrier: Node3D, altitude_m: float = 800.0) -> void:
	patrol_engagement = "air"
	mission = Mission.CAP
	_mark_mission_dirty()
	_cap_carrier = carrier
	_cap_altitude_m = altitude_m
	_cap_route_points.clear()
	_cap_route_lead = null
	_cap_route_revision += 1
	_cap_route_lead_revision = -1
	_claimed_targets.clear()
	for aircraft in get_members():
		_apply_cap(aircraft)
	mission_changed.emit(mission)
	print("[Flight %s] CAP  alt=%.0fm" % [flight_name, altitude_m])

func set_cap_route(carrier: Node3D, route_points: Array[Vector3], altitude_m: float = 800.0, engagement: String = "air") -> void:
	patrol_engagement = engagement if engagement in ["air", "ground", "both"] else "air"
	mission = Mission.CAP
	_mark_mission_dirty()
	_cap_carrier = carrier
	_cap_altitude_m = altitude_m
	_cap_route_points = _sanitize_cap_route_points(route_points, altitude_m)
	_cap_route_lead = null
	_cap_route_revision += 1
	_cap_route_lead_revision = -1
	_claimed_targets.clear()
	for aircraft in get_members():
		_apply_cap(aircraft)
	mission_changed.emit(mission)
	print("[Flight %s] CAP route  points=%d  alt=%.0fm" % [flight_name, _cap_route_points.size(), altitude_m])

func set_cas(area_center: Vector3, area_radius: float = 3000.0, altitude_m: float = 300.0) -> void:
	mission = Mission.CAS
	_mark_mission_dirty()
	_cas_area_center = area_center
	_cas_area_radius = area_radius
	_cas_altitude_m = altitude_m
	_cap_route_lead = null
	_cap_route_lead_revision = -1
	_claimed_targets.clear()
	for aircraft in get_members():
		_apply_cas(aircraft)
	mission_changed.emit(mission)
	print("[Flight %s] CAS  center=(%.0f,%.0f)  r=%.0fm" % [flight_name, area_center.x, area_center.z, area_radius])

func set_attack(area_center: Vector3, carrier: Node3D, area_radius: float = 100.0, altitude_m: float = 300.0, platoon: Node = null) -> void:
	mission = Mission.ATTACK
	_attack_platoon = platoon
	_attack_tracks_platoon = is_instance_valid(platoon)
	_cas_area_center = area_center
	_cas_area_radius = maxf(area_radius, 1.0)
	_attack_area_visited = false
	_attack_area_clear_s = 0.0
	_cap_carrier = carrier
	_cas_altitude_m = altitude_m
	_cap_route_points.clear()
	_claimed_targets.clear()
	_mark_mission_dirty()
	_apply_pending_mission_updates()
	mission_changed.emit(mission)


func _apply_attack(aircraft: Node3D) -> bool:
	var pilot := _get_pilot(aircraft)
	if not pilot or _is_deck_busy(pilot):
		return false
	# Finish a committed pass or defensive engagement before accepting a new order.
	if pilot.current_state in [AIPilot.State.ATTACK_DIVE, AIPilot.State.ATTACK_BREAK_OFF, AIPilot.State.DOGFIGHT]:
		return false
	pilot.ground_attack_enabled = true
	pilot.dogfight_enabled = true
	pilot.clear_formation_guidance()
	# Release this member's previous pass, then distribute the next targets.
	for claimed in _claimed_targets.keys():
		if _claimed_targets[claimed] == aircraft:
			_claimed_targets.erase(claimed)
	var target := _pick_unclaimed_target(aircraft.global_position)
	var task: Variant
	if target != null:
		task = AirTaskModel.attack_target(target)
	else:
		var previous: Variant = pilot.get_current_air_task()
		if previous != null and previous.kind == AirTaskModel.Kind.PATROL \
				and bool(previous.metadata.get("attack_area", false)) \
				and int(previous.metadata.get("flight_mission_revision", -1)) == _mission_revision \
				and previous.metadata.get("search_route_center", Vector3.INF).distance_to(_cas_area_center) < 250.0 \
				and previous.area_radius_m == _cas_area_radius:
			previous.area_center = _cas_area_center
			return true
		task = AirTaskModel.patrol(_cas_area_center, _cas_area_radius, _cas_altitude_m)
	task.area_center = _cas_area_center
	task.area_radius_m = _cas_area_radius
	task.requested_altitude_m = _cas_altitude_m
	task.metadata = {"mission": "attack", "attack_area": true, "specific_ground_target": target != null}
	task.metadata["flight_mission_revision"] = _mission_revision
	if _attack_tracks_platoon:
		task.metadata["attack_platoon"] = weakref(_attack_platoon) if is_instance_valid(_attack_platoon) else null
	if not pilot.assign_air_task(task):
		return false
	if target != null:
		_claimed_targets[target] = aircraft
	else:
		# Fly through the area to search even when nothing has been reported yet.
		# The target radius constrains weapons, not the aircraft's turning circle.
		var center := Vector3(_cas_area_center.x, _cas_area_center.y + _cas_altitude_m, _cas_area_center.z)
		var route: Array[Vector3] = [center, center + Vector3(0, 0, 1200)]
		task.metadata["search_route_center"] = _cas_area_center
		pilot.set_waypoints(pilot.build_terrain_safe_waypoints(route, CAP_ROUTE_MIN_AGL_M, true), false)
	return true


func _update_attack_assignment(delta: float = 0.0) -> void:
	_refresh_attack_platoon_position()
	_prune_stale_claims(false)
	for target in _claimed_targets.keys():
		var claimer := _get_pilot(_claimed_targets[target])
		if not _attack_area_contains(target.global_position) or claimer == null or _is_deck_busy(claimer) \
				or (_attack_tracks_platoon and not attack_platoon_members(_attack_platoon).has(target)):
			_claimed_targets.erase(target)
	var targets_remain := not _claimed_targets.is_empty()
	if _attack_tracks_platoon:
		targets_remain = is_attack_platoon_valid(_attack_platoon)
		if not targets_remain:
			_attack_area_visited = true
	for target in _get_cas_target_nodes():
		if _is_valid_cas_target(target) and _attack_area_contains(target.global_position):
			targets_remain = true
			break
	var committed := false
	for aircraft in get_members():
		var pilot := _get_pilot(aircraft)
		if pilot and not _is_deck_busy(pilot):
			var distance := Vector2(aircraft.global_position.x - _cas_area_center.x, aircraft.global_position.z - _cas_area_center.z).length()
			_attack_area_visited = _attack_area_visited or distance <= maxf(_cas_area_radius, 750.0)
		if pilot and pilot.current_state in [AIPilot.State.ATTACK_DIVE, AIPilot.State.ATTACK_BREAK_OFF]:
			committed = true
		if pilot and pilot.current_state == AIPilot.State.SEARCH:
			_apply_attack(aircraft)
	# Allow a short on-station search, including time for sensor reports, before
	# declaring an empty area clear. Never cut off a committed pass's pull-out.
	if _attack_area_visited and not targets_remain and not committed:
		_attack_area_clear_s += maxf(delta, 0.0)
	else:
		_attack_area_clear_s = 0.0
	if _attack_area_clear_s >= 10.0:
		mission_reason = "Attack area clear — returning"
		set_rtb()


func _attack_area_contains(point: Vector3) -> bool:
	if _attack_tracks_platoon:
		return true # Membership, rather than a ground radius, defines this order.
	return Vector2(point.x - _cas_area_center.x, point.z - _cas_area_center.z).length_squared() <= _cas_area_radius * _cas_area_radius


static func is_attack_platoon_valid(platoon: Variant) -> bool:
	if not is_instance_valid(platoon):
		return false
	if platoon is EnemyVirtualPlatoon:
		return platoon.vehicle_count > 0
	if platoon is GroundVehiclePlatoon:
		if platoon.team != 2:
			return false
		for member in platoon.get_members():
			if member.is_queued_for_deletion():
				continue
			var health: float = float(member.get("current_health")) if "current_health" in member else float(member.get("health")) if "health" in member else 1.0
			if health > 0.0:
				return true
	return false


static func attack_platoon_position(platoon: Variant) -> Vector3:
	if not is_instance_valid(platoon):
		return Vector3.INF
	if platoon is EnemyVirtualPlatoon:
		return platoon.position
	if platoon is GroundVehiclePlatoon:
		return platoon.get_contact_position()
	return Vector3.INF


static func attack_platoon_members(platoon: Variant) -> Array[Node3D]:
	if is_instance_valid(platoon):
		if platoon is EnemyVirtualPlatoon:
			return platoon._active_vehicles.filter(func(member): return is_instance_valid(member))
		if platoon is GroundVehiclePlatoon:
			return platoon.get_members()
	return []


func _refresh_attack_platoon_position() -> void:
	if mission == Mission.ATTACK and _attack_tracks_platoon and is_instance_valid(_attack_platoon):
		_cas_area_center = attack_platoon_position(_attack_platoon)


func set_intercept(target: Node3D, carrier: Node3D, altitude_m: float = 800.0, target_flight: Node = null) -> void:
	mission = Mission.INTERCEPT
	_mark_mission_dirty()
	_intercept_flight = target_flight
	_intercept_tracks_flight = target_flight != null
	_intercept_update_s = 1.0
	_intercept_target = target
	_intercept_carrier = carrier
	_intercept_altitude_m = altitude_m
	_cap_carrier = carrier
	_cap_altitude_m = altitude_m
	_cap_route_points.clear()
	_cap_route_lead = null
	_cap_route_revision += 1
	_cap_route_lead_revision = -1
	_claimed_targets.clear()
	for aircraft in get_members():
		_apply_current_mission(aircraft)
	mission_changed.emit(mission)
	var target_name: String = InterceptTarget.label(target_flight) if _intercept_tracks_flight else str(target.name) if is_instance_valid(target) else "unknown"
	print("[Flight %s] INTERCEPT  target=%s  alt=%.0fm" % [flight_name, target_name, altitude_m])

func set_rtb() -> void:
	mission = Mission.RTB
	_mark_mission_dirty()
	_cap_route_points.clear()
	_cap_route_lead = null
	_cap_route_revision += 1
	_cap_route_lead_revision = -1
	_claimed_targets.clear()
	for aircraft in get_members():
		_apply_rtb(aircraft)
	mission_changed.emit(mission)
	print("[Flight %s] RTB" % flight_name)

# ── Per-aircraft application ───────────────────────────────────────────────────

func _apply_current_mission(aircraft: Node3D) -> bool:
	var applied: bool = false
	match mission:
		Mission.CAP:
			applied = _apply_cap(aircraft)
		Mission.CAS:
			applied = _apply_cas(aircraft)
		Mission.ATTACK:
			applied = _apply_attack(aircraft)
		Mission.INTERCEPT:
			applied = _apply_intercept(aircraft)
		Mission.RTB:
			applied = _apply_rtb(aircraft)
		_:
			applied = false
	if applied:
		_member_mission_revision[aircraft] = _mission_revision
	return applied

func _apply_cap(aircraft: Node3D) -> bool:
	var pilot := _get_pilot(aircraft)
	if not pilot or _is_deck_busy(pilot):
		return false
	if pilot.current_state in [AIPilot.State.ATTACK_DIVE, AIPilot.State.ATTACK_BREAK_OFF]:
		return false
	pilot.ground_attack_enabled = patrol_engagement != "air"
	pilot.dogfight_enabled = true
	var cap_center: Vector3 = _cap_carrier.global_position \
		if _cap_carrier != null and is_instance_valid(_cap_carrier) else Vector3.INF
	var cap_task: Variant = AirTaskModel.patrol(cap_center, NAN, _cap_altitude_m)
	cap_task.metadata = {"mission": "patrol", "patrol_engagement": patrol_engagement, "carrier_relative": _cap_route_points.is_empty()}
	if not _cap_route_points.is_empty():
		cap_task.metadata["patrol_route"] = _cap_route_points.duplicate()
	if aircraft == _get_lead_aircraft():
		_refresh_lead_guidance(aircraft, pilot)
	elif not _cap_route_points.is_empty():
		# Wingmen retain the assigned route if they leave formation or become lead.
		_assign_cap_route_waypoints(aircraft, pilot)
	else:
		# Clear waypoints so AIPilot rebuilds its carrier-centered patrol.
		_clear_navigation_waypoints(pilot, true)
	if not pilot.assign_air_task(cap_task) and pilot.current_state not in [AIPilot.State.SEARCH]:
		pilot.set_patrol_altitude(_cap_altitude_m)
		pilot.change_state(AIPilot.State.SEARCH)
	return true

func _apply_cas(aircraft: Node3D) -> bool:
	var pilot := _get_pilot(aircraft)
	if not pilot or _is_deck_busy(pilot):
		return false
	pilot.ground_attack_enabled = true
	pilot.dogfight_enabled = true  # still defend themselves
	# Keep an already-committed attack uninterrupted while updating the mission's
	# eventual patrol altitude. Idle/searching pilots receive the full AirTask below.
	pilot.set_patrol_altitude(_cas_altitude_m)
	_clear_navigation_waypoints(pilot)
	if pilot.current_state not in [
		AIPilot.State.ATTACK_POSITIONING,
		AIPilot.State.ATTACK_INBOUND,
		AIPilot.State.ATTACK_DIVE,
		AIPilot.State.ATTACK_BREAK_OFF,
		AIPilot.State.DOGFIGHT,
	]:
		var cas_task: Variant = AirTaskModel.patrol(
			_cas_area_center,
			_cas_area_radius,
			_cas_altitude_m
		)
		cas_task.metadata = {"mission": "cas", "awaiting_target": true}
		if not pilot.assign_air_task(cas_task):
			pilot.set_patrol_altitude(_cas_altitude_m)
			pilot.change_state(AIPilot.State.SEARCH)
	return true

func _apply_intercept(aircraft: Node3D) -> bool:
	if _intercept_tracks_flight:
		return _apply_flight_intercept(aircraft)
	var pilot := _get_pilot(aircraft)
	if not pilot or _is_deck_busy(pilot):
		return false
	pilot.ground_attack_enabled = false
	pilot.dogfight_enabled = true
	pilot.set_patrol_altitude(_intercept_altitude_m)
	if _intercept_target and is_instance_valid(_intercept_target):
		var intercept_task: Variant = AirTaskModel.intercept_target(_intercept_target)
		intercept_task.requested_altitude_m = _intercept_altitude_m
		if not pilot.assign_air_task(intercept_task):
			pilot.set_target(_intercept_target)
	else:
		_clear_navigation_waypoints(pilot, true)
		if pilot.current_state not in [AIPilot.State.SEARCH]:
			pilot.change_state(AIPilot.State.SEARCH)
	return true

func _update_intercept_assignment() -> void:
	if not InterceptTarget.is_valid(_intercept_flight):
		mission_reason = "Intercept target gone — returning"
		set_rtb()
		return
	for aircraft in get_members():
		_apply_flight_intercept(aircraft)


func _apply_flight_intercept(aircraft: Node3D) -> bool:
	var pilot := _get_pilot(aircraft)
	if not pilot or _is_deck_busy(pilot) or not InterceptTarget.is_valid(_intercept_flight):
		return false
	if pilot.current_state in [AIPilot.State.ATTACK_DIVE, AIPilot.State.ATTACK_BREAK_OFF]:
		return false
	var candidates: Array[Node3D] = InterceptTarget.members(_intercept_flight)
	var previous: Variant = pilot.get_current_air_task()
	var same_order: bool = previous != null and int(previous.metadata.get("flight_mission_revision", -1)) == _mission_revision \
		and previous.metadata.has("intercept_flight")
	# Keep a live engagement stable; controller reports guide pursuit but do not grant visual firing permission.
	if same_order and pilot.current_state == AIPilot.State.DOGFIGHT and is_instance_valid(pilot.combat_target) \
			and candidates.has(pilot.combat_target):
		previous.set_target(pilot.combat_target)
		pilot.receive_intercept_contact_report(pilot.combat_target, pilot.combat_target.global_position, pilot.combat_target.linear_velocity)
		return true
	pilot.ground_attack_enabled = false
	pilot.dogfight_enabled = true
	pilot.clear_formation_guidance()
	var target: Node3D = null
	var nearest := INF
	for candidate in candidates:
		var distance := aircraft.global_position.distance_squared_to(candidate.global_position)
		if distance < nearest:
			nearest = distance
			target = candidate
	var center: Vector3 = InterceptTarget.position(_intercept_flight)
	var task: Variant
	if target != null:
		task = AirTaskModel.intercept_target(target)
	else:
		if same_order and previous.kind == AirTaskModel.Kind.PATROL \
				and previous.metadata.get("search_route_center", Vector3.INF).distance_to(center) < 250.0:
			return true
		task = AirTaskModel.patrol(center, NAN, maxf(center.y, _intercept_altitude_m))
	task.metadata = {"mission": "intercept", "intercept_flight": weakref(_intercept_flight), "flight_mission_revision": _mission_revision}
	task.requested_altitude_m = maxf(center.y, _intercept_altitude_m)
	if not pilot.assign_air_task(task):
		return false
	if target == null:
		var heading: Vector3 = _intercept_flight.heading
		var route: Array[Vector3] = [center, center + heading * 1200.0]
		task.metadata["search_route_center"] = center
		pilot.set_waypoints(pilot.build_terrain_safe_waypoints(route, CAP_ROUTE_MIN_AGL_M, true), false)
	return true

func _apply_rtb(aircraft: Node3D) -> bool:
	var pilot := _get_pilot(aircraft)
	if not pilot or _is_deck_busy(pilot):
		return false
	_clear_navigation_waypoints(pilot)
	if pilot.current_state not in [AIPilot.State.RTB, AIPilot.State.APPROACH, AIPilot.State.LANDING]:
		if not pilot.assign_air_task(AirTaskModel.return_to_base()):
			pilot.change_state(AIPilot.State.RTB)
	return true

# ── CAS target distribution ───────────────────────────────────────────────────

func _update_cas_assignments() -> void:
	# Prune stale claims (destroyed targets or lost aircraft)
	_prune_stale_claims(true)

	for aircraft in get_members():
		var pilot := _get_pilot(aircraft)
		if not pilot or _is_deck_busy(pilot):
			continue

		# Only assign to aircraft that are free to accept a new target
		# The pilot owns physical pull-out/egress. Assigning a fresh attack during
		# BREAK_OFF used to cancel that recovery as soon as a claim disappeared.
		if pilot.current_state != AIPilot.State.SEARCH:
			continue

		# Skip if this aircraft already has a live claim
		if _aircraft_has_live_claim(aircraft):
			continue

		var target := _pick_unclaimed_target(aircraft.global_position)
		if not target or not is_instance_valid(target) or not is_instance_valid(aircraft):
			continue

		_claimed_targets[target] = aircraft
		if not pilot.assign_air_task(AirTaskModel.attack_target(target)):
			pilot.set_target(target)
		if debug_print:
			print("[Flight %s] %s → %s" % [flight_name, aircraft.name, target.name])
		_say_cas_assignment(aircraft, target)

func _pick_unclaimed_target(from_pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist: float = INF
	var best_threat_tier: int = 2
	for node in _get_cas_target_nodes():
		if not is_instance_valid(node):
			continue
		if not _is_valid_cas_target(node):
			continue
		if _claimed_targets.has(node):
			continue  # already claimed by a flight-mate
		var flat_dist := Vector2(node.global_position.x - _cas_area_center.x,
								node.global_position.z - _cas_area_center.z).length()
		if not (mission == Mission.ATTACK and _attack_tracks_platoon) and flat_dist > _cas_area_radius:
			continue  # outside assigned area
		var d := from_pos.distance_to(node.global_position)
		var threat_tier: int = GroundTargetPriority.threat_tier(node)
		if threat_tier < best_threat_tier or (threat_tier == best_threat_tier and d < best_dist):
			best_threat_tier = threat_tier
			best_dist = d
			best = node
	return best

func _get_cas_target_nodes() -> Array[Node3D]:
	if mission == Mission.ATTACK and _attack_tracks_platoon:
		return attack_platoon_members(_attack_platoon)
	if AirOpsManager != null and is_instance_valid(AirOpsManager) and AirOpsManager.has_method("get_reported_ground_targets"):
		var reported: Array = AirOpsManager.get_reported_ground_targets(_cas_area_center, _cas_area_radius)
		var reported_targets: Array[Node3D] = []
		for node in reported:
			if node is Node3D and is_instance_valid(node as Node3D):
				reported_targets.append(node as Node3D)
		return reported_targets
	var result: Array[Node3D] = []
	for group_name in ["ground_vehicles", "gun_emplacements", "buildings", "enemy_bases"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node3D and is_instance_valid(node as Node3D) and not result.has(node):
				result.append(node as Node3D)
	return result

func _is_valid_cas_target(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	for health_key in ["current_health", "health"]:
		if health_key in node:
			var health: Variant = node.get(health_key)
			if typeof(health) in [TYPE_FLOAT, TYPE_INT] and float(health) <= 0.0:
				return false
	if node.has_method("get_team") and int(node.get_team()) == 1:
		return false
	if node.is_in_group("carrier"):
		return false
	if node.is_in_group("ground_vehicles"):
		return true
	if node.is_in_group("gun_emplacements") or node.is_in_group("buildings") or node.is_in_group("enemy_bases"):
		if node.has_method("get_team"):
			return int(node.get_team()) != 1
		return node.is_in_group("enemies") or node.is_in_group("enemy_bases")
	return false

func _prune_stale_claims(report_splashes: bool) -> void:
	var stale_claims: Array = []
	for target_ref in _claimed_targets.keys():
		var claimer_ref = _claimed_targets.get(target_ref)
		var target_valid: bool = _is_live_node3d_ref(target_ref) and _is_valid_cas_target(target_ref as Node3D)
		var claimer_valid: bool = _is_live_node3d_ref(claimer_ref)
		if not target_valid:
			if report_splashes and claimer_valid:
				var claimer := claimer_ref as Node3D
				var idx := get_members().find(claimer)
				if idx >= 0:
					RadioComms.say_splash("%s %s" % [flight_name, _member_suffix(idx)])
			stale_claims.append(target_ref)
		elif not claimer_valid:
			stale_claims.append(target_ref)
	for target_ref in stale_claims:
		_claimed_targets.erase(target_ref)

func _aircraft_has_live_claim(aircraft: Node3D) -> bool:
	for claimer_ref in _claimed_targets.values():
		if _is_live_node3d_ref(claimer_ref) and claimer_ref == aircraft:
			return true
	return false

func _is_live_node3d_ref(value) -> bool:
	if typeof(value) != TYPE_OBJECT:
		return false
	if not is_instance_valid(value):
		return false
	return value is Node3D

# ── Helpers ────────────────────────────────────────────────────────────────────

func _update_formation() -> void:
	var members := get_members()
	if members.is_empty():
		return
	for aircraft in members:
		var member_pilot := _get_pilot(aircraft)
		if member_pilot and member_pilot.has_method("clear_formation_guidance"):
			member_pilot.clear_formation_guidance()
	# Designated targets supply each aircraft's own ingress/pursuit route, even
	# while the target is virtual and pilots remain in SEARCH. Reattaching the
	# cruise formation here overrides those routes and caps the leader's turn.
	if mission == Mission.ATTACK or (mission == Mission.INTERCEPT and _intercept_tracks_flight):
		return
	var lead := _get_active_formation_lead_aircraft()
	if not lead:
		return
	var lead_pilot := _get_pilot(lead)
	if _is_aircraft_unavailable_for_formation(lead, lead_pilot):
		return
	if not _can_pilot_hold_formation(lead_pilot):
		return
	_refresh_lead_guidance(lead, lead_pilot)
	var lead_basis := _formation_heading_basis(lead)
	var lead_speed_mps := _get_aircraft_speed_mps(lead, lead_pilot)
	var formation_members: Array[Dictionary] = []
	var formation_slot: int = 1
	var max_slot_error_m: float = 0.0
	for wingman in members:
		if wingman == lead:
			continue
		var member_slot := formation_slot
		formation_slot += 1
		var pilot := _get_pilot(wingman)
		if _is_aircraft_unavailable_for_formation(wingman, pilot):
			continue
		if not _can_pilot_hold_formation(pilot):
			continue
		var form_pos := _formation_position(lead, lead_basis, member_slot)
		var guidance_anchor := _formation_guidance_anchor(wingman, lead, lead_basis, member_slot, form_pos)
		var slot_quality := _formation_slot_quality(wingman, lead_basis, form_pos)
		var ahead_hold_t := _formation_ahead_hold_t(wingman, lead_basis, form_pos)
		formation_members.append({
			"aircraft": wingman,
			"pilot": pilot,
			"slot": member_slot,
			"slot_anchor": form_pos,
			"anchor": guidance_anchor,
			"slot_quality": slot_quality,
			"ahead_hold_t": ahead_hold_t,
		})
		max_slot_error_m = maxf(max_slot_error_m, wingman.global_position.distance_to(form_pos))

	if formation_members.is_empty():
		return

	var peer_ids := PackedInt64Array([lead.get_instance_id()])
	for entry in formation_members:
		peer_ids.append(entry["aircraft"].get_instance_id())
	lead_pilot.formation_peer_ids = peer_ids.duplicate()
	for entry in formation_members:
		var wingman: Node3D = entry.get("aircraft")
		var pilot: AIPilot = entry.get("pilot")
		var anchor: Vector3 = entry.get("anchor")
		var slot_anchor: Vector3 = entry.get("slot_anchor")
		var slot_quality: float = entry.get("slot_quality", 0.0)
		var ahead_hold_t: float = entry.get("ahead_hold_t", 0.0)
		var desired_speed_mps := _formation_wingman_target_speed(wingman, lead, lead_basis, slot_anchor, lead_speed_mps)
		var speed_bias_mps := desired_speed_mps - pilot.target_speed
		var speed_cap_mps := desired_speed_mps
		pilot.formation_peer_ids = peer_ids.duplicate()
		pilot.set_formation_anchor(anchor)
		pilot.set_formation_speed_guidance(speed_cap_mps, speed_bias_mps)
		var lead_bank_rad := atan2(lead.global_basis.x.y, lead.global_basis.y.y)
		var lead_vertical_speed_mps: float = lead.linear_velocity.y if "linear_velocity" in lead else 0.0
		pilot.set_formation_handling(slot_quality, ahead_hold_t, lead_bank_rad, lead_vertical_speed_mps)

	var leader_speed_cap := _formation_lead_speed_cap(lead_pilot, max_slot_error_m)
	lead_pilot.set_formation_speed_guidance(leader_speed_cap, 0.0)

func _formation_position(lead: Node3D, lead_basis: Basis, formation_slot: int) -> Vector3:
	var offset: Vector3 = FORMATION_OFFSETS[min(formation_slot, FORMATION_OFFSETS.size() - 1)]
	# Transform offset from leader-local (right/up/fwd) into world space
	var world_offset := lead_basis.x * offset.x \
					  + lead_basis.y * offset.y \
					  + lead_basis.z * offset.z
	var pos := lead.global_position + world_offset
	# Match lead altitude so they fly level
	pos.y = lead.global_position.y
	return pos

func _formation_heading_basis(lead: Node3D) -> Basis:
	# Roll must not squeeze the horizontal spacing during a turn.
	var forward := lead.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.BACK
	forward = forward.normalized()
	return Basis(Vector3.UP.cross(forward), Vector3.UP, forward)

func _formation_guidance_anchor(wingman: Node3D, lead: Node3D, lead_basis: Basis, _formation_slot: int, slot_anchor: Vector3) -> Vector3:
	if not is_instance_valid(wingman) or not is_instance_valid(lead):
		return slot_anchor
	# Fly parallel to the moving slot. A waypoint at the slot itself makes a
	# correctly positioned aircraft turn around as soon as it passes the point.
	# Fore/aft error belongs to throttle, not to a turn back through the flight.
	var error_vec := slot_anchor - wingman.global_position
	var lookahead_m := clampf(_get_aircraft_speed_mps(lead, _get_pilot(lead)) * 2.0, 120.0, 260.0)
	var lateral_m := clampf(error_vec.dot(lead_basis.x), -lookahead_m * 0.6, lookahead_m * 0.6)
	var anchor := wingman.global_position + lead_basis.z * lookahead_m + lead_basis.x * lateral_m
	anchor.y = slot_anchor.y
	return anchor

func _formation_wingman_target_speed(wingman: Node3D, lead: Node3D, lead_basis: Basis, slot_anchor: Vector3, lead_speed_mps: float) -> float:
	var forward_error_m := (slot_anchor - wingman.global_position).dot(lead_basis.z)
	# The outer slot travels faster in a turn; the inner slot travels slower.
	var turn_speed_mps := 0.0
	if "angular_velocity" in lead:
		var slot_velocity: Vector3 = lead.angular_velocity.cross(slot_anchor - lead.global_position)
		turn_speed_mps = slot_velocity.dot(lead_basis.z)
	var correction_mps := clampf(forward_error_m * 0.12, -FORMATION_WINGMAN_MAX_SPEED_REDUCTION_MPS, FORMATION_WINGMAN_MAX_SPEED_BONUS_MPS)
	return maxf(lead_speed_mps + turn_speed_mps + correction_mps, FORMATION_LEAD_MIN_SPEED_MPS)

func _formation_slot_quality(wingman: Node3D, lead_basis: Basis, slot_anchor: Vector3) -> float:
	if not wingman or not is_instance_valid(wingman):
		return 0.0
	var error_vec := wingman.global_position - slot_anchor
	var forward_t := _formation_soft_band_t(absf(error_vec.dot(lead_basis.z)), FORMATION_SLOT_FORWARD_CLOSE_M, FORMATION_SLOT_FORWARD_SOFT_M)
	var lateral_t := _formation_soft_band_t(absf(error_vec.dot(lead_basis.x)), FORMATION_SLOT_LATERAL_CLOSE_M, FORMATION_SLOT_LATERAL_SOFT_M)
	var vertical_t := _formation_soft_band_t(absf(error_vec.y), FORMATION_SLOT_VERTICAL_CLOSE_M, FORMATION_SLOT_VERTICAL_SOFT_M)
	return clampf(forward_t * 0.45 + lateral_t * 0.40 + vertical_t * 0.15, 0.0, 1.0)

func _formation_ahead_hold_t(wingman: Node3D, lead_basis: Basis, slot_anchor: Vector3) -> float:
	if not wingman or not is_instance_valid(wingman):
		return 0.0
	var error_vec := wingman.global_position - slot_anchor
	var forward_error_m := error_vec.dot(lead_basis.z)
	if forward_error_m <= FORMATION_FORWARD_HOLD_START_M:
		return 0.0
	return clampf(
		(forward_error_m - FORMATION_FORWARD_HOLD_START_M) / maxf(FORMATION_SLOT_FORWARD_SOFT_M - FORMATION_FORWARD_HOLD_START_M, 1.0),
		0.0,
		1.0
	)

func _formation_soft_band_t(error_m: float, close_m: float, soft_m: float) -> float:
	if error_m <= close_m:
		return 1.0
	return 1.0 - clampf((error_m - close_m) / maxf(soft_m - close_m, 1.0), 0.0, 1.0)

func _can_pilot_hold_formation(pilot: AIPilot) -> bool:
	return pilot != null and pilot.current_state in FORMATION_ACTIVE_STATES \
		and not pilot.is_air_contact_search_active()

func _get_aircraft_speed_mps(aircraft: Node3D, pilot: AIPilot) -> float:
	if aircraft and is_instance_valid(aircraft) and "linear_velocity" in aircraft:
		return maxf(aircraft.linear_velocity.length(), FORMATION_LEAD_MIN_SPEED_MPS)
	if pilot:
		return maxf(pilot.target_speed, FORMATION_LEAD_MIN_SPEED_MPS)
	return FORMATION_LEAD_MIN_SPEED_MPS

func _formation_lead_speed_cap(lead_pilot: AIPilot, max_slot_error_m: float) -> float:
	if not lead_pilot:
		return -1.0
	var wait_t := clampf(
		(max_slot_error_m - FORMATION_LEAD_SLOWDOWN_START_M) / maxf(FORMATION_LEAD_FULL_WAIT_M - FORMATION_LEAD_SLOWDOWN_START_M, 1.0),
		0.0,
		1.0
	)
	var nominal_speed_mps := maxf(lead_pilot.target_speed, 80.0)
	# Reserve cruise headroom so identical aircraft can catch up and fly the
	# longer outer arc without requiring more than their available full power.
	return maxf(nominal_speed_mps * 0.9 - FORMATION_LEAD_MAX_SLOWDOWN_MPS * wait_t, FORMATION_LEAD_MIN_SPEED_MPS)

func _say_cas_assignment(aircraft: Node3D, target: Node3D) -> void:
	var members := get_members()
	var member_index := members.find(aircraft)
	var suffix := _member_suffix(member_index)
	var callsign := "%s %s" % [flight_name, suffix]
	var target_type := _ground_target_type(target)

	if member_index == 0:
		RadioComms.transmit(callsign, "%s flight" % flight_name,
			RadioComms._pick([
				"Lead's in on target. Committing.",
				"Tally. Rolling in hot. Flight, find your marks.",
				"Target acquired. I'm going in. Cover my six.",
			]))
	else:
		RadioComms.transmit(callsign, "%s lead" % flight_name,
			RadioComms._pick([
				"Two, tally. Target is mine.",
				"In on target. Engaging.",
				"Copy lead. Pickle is hot.",
			]))

func _member_suffix(index: int) -> String:
	match index:
		0: return "lead"
		1: return "two"
		2: return "three"
		3: return "four"
		_: return str(index + 1)

func _ground_target_type(node: Node3D) -> String:
	if not node or not is_instance_valid(node):
		return "target"
	var n := node.name.to_lower()
	if "tank" in n or "armor" in n:
		return "armor"
	if "apc" in n:
		return "APC"
	if "truck" in n or "transport" in n:
		return "truck"
	if node.is_in_group("carrier"):
		return "carrier"
	return "vehicle"

func _get_pilot(aircraft: Node3D) -> AIPilot:
	return aircraft.find_child("AIPilot", true, false) as AIPilot

func get_center_position() -> Vector3:
	var members := get_members()
	if members.is_empty():
		if mission == Mission.CAS:
			return _cas_area_center
		if _cap_carrier and is_instance_valid(_cap_carrier):
			return _cap_carrier.global_position
		if not _cap_route_points.is_empty():
			return _cap_route_points[0]
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var live_count := 0
	for member in members:
		if not member or not is_instance_valid(member):
			continue
		sum += member.global_position
		live_count += 1
	if live_count <= 0:
		if mission == Mission.CAS:
			return _cas_area_center
		if _cap_carrier and is_instance_valid(_cap_carrier):
			return _cap_carrier.global_position
		if not _cap_route_points.is_empty():
			return _cap_route_points[0]
		return Vector3.ZERO
	return sum / float(live_count)

func get_active_waypoints() -> Array[Vector3]:
	var active_waypoints: Array[Vector3] = []
	var lead_pilot := _get_lead_pilot()
	if not lead_pilot:
		return active_waypoints
	var start_index: int = clampi(lead_pilot.current_waypoint_index, 0, lead_pilot.waypoints.size())
	for i in range(start_index, lead_pilot.waypoints.size()):
		active_waypoints.append(lead_pilot.waypoints[i])
	return active_waypoints

func get_mission_map_points() -> Array[Vector3]:
	match mission:
		Mission.CAP:
			var cap_display_route := _get_cap_display_route_points()
			if not cap_display_route.is_empty():
				return cap_display_route
			var active_waypoints := get_active_waypoints()
			if not active_waypoints.is_empty():
				return active_waypoints
			if _cap_carrier and is_instance_valid(_cap_carrier):
				var carrier_pos := _cap_carrier.global_position
				return [Vector3(carrier_pos.x, _cap_altitude_m, carrier_pos.z)]
			return []
		Mission.CAS:
			return [_cas_area_center]
		Mission.ATTACK:
			_refresh_attack_platoon_position()
			return [_cas_area_center]
		Mission.INTERCEPT:
			if _intercept_tracks_flight:
				var center: Vector3 = InterceptTarget.position(_intercept_flight)
				if center.is_finite():
					return [center]
				return []
			if _intercept_target and is_instance_valid(_intercept_target):
				return [_intercept_target.global_position]
			if _intercept_carrier and is_instance_valid(_intercept_carrier):
				return [_intercept_carrier.global_position]
			return []
		Mission.RTB:
			if _cap_carrier and is_instance_valid(_cap_carrier):
				return [_cap_carrier.global_position]
			return []
		_:
			return []

func has_looped_mission_map() -> bool:
	return mission == Mission.CAP and get_mission_map_points().size() >= 2

func get_mission_name() -> String:
	if mission in [Mission.CAP, Mission.CAS]:
		return "PATROL"
	if mission == Mission.INTERCEPT:
		return "ATTACK"
	return Mission.keys()[mission]

func get_lead_state_name() -> String:
	var lead_pilot := _get_lead_pilot()
	if not lead_pilot:
		return "INACTIVE"
	return AIPilot.State.keys()[lead_pilot.current_state]

func get_status_summary() -> Dictionary:
	_refresh_attack_platoon_position()
	return {
		"intercept_target_center": InterceptTarget.position(_intercept_flight) if mission == Mission.INTERCEPT and _intercept_tracks_flight else Vector3.INF,
		"attack_area_radius_m": _cas_area_radius if mission == Mission.ATTACK and not _attack_tracks_platoon else 0.0,
		"attack_tracks_platoon": mission == Mission.ATTACK and _attack_tracks_platoon,
		"attack_area_center": _cas_area_center,
		"name": flight_name,
		"mission": get_mission_name(),
		"patrol_engagement": "ground" if mission == Mission.CAS else patrol_engagement,
		"order_source": mission_source,
		"order_reason": mission_reason,
		"strength": strength(),
		"position": get_center_position(),
		"active_waypoints": get_active_waypoints(),
		"mission_map_points": get_mission_map_points(),
		"mission_map_closed_loop": has_looped_mission_map(),
		"lead_state": get_lead_state_name(),
	}

func _is_deck_busy(pilot: AIPilot) -> bool:
	var director := get_node_or_null("/root/FlightDirector")
	if director != null and is_instance_valid(pilot.aircraft) and director.get("player_controlled_plane") == pilot.aircraft:
		return true
	var coordinator := get_node_or_null("/root/OperationsCoordinator")
	if coordinator != null and is_instance_valid(pilot.aircraft) and coordinator.has_individual_order(pilot.aircraft):
		return true
	## True when the pilot is in a deck/flight phase we should not interrupt.
	return pilot.is_recovering() or pilot.is_departing()

func _mark_mission_dirty() -> void:
	_mission_revision += 1
	for aircraft in get_members():
		_member_mission_revision[aircraft] = -1

func _apply_pending_mission_updates() -> void:
	if mission == Mission.NONE:
		return
	for aircraft in get_members():
		if int(_member_mission_revision.get(aircraft, -1)) == _mission_revision:
			continue
		_apply_current_mission(aircraft)

func _clear_navigation_waypoints(pilot: AIPilot, follow_carrier: bool = false) -> void:
	if not pilot:
		return
	pilot.waypoints.clear()
	pilot.current_waypoint_index = 0
	pilot.waypoints_follow_carrier = follow_carrier

func _is_aircraft_unavailable_for_formation(aircraft: Node3D, pilot: AIPilot) -> bool:
	if pilot != null and _is_deck_busy(pilot):
		return true
	if not aircraft or not is_instance_valid(aircraft):
		return true
	if not pilot:
		return true
	if pilot.current_state in FORMATION_BREAK_STATES:
		return true
	if aircraft.get_meta("controls_disabled", false):
		return true
	if aircraft.get_meta("parking_brake", false):
		return true
	if aircraft.get_meta("carrier_transport_mode", false):
		return true
	if aircraft.get_meta("arresting_engaged", false):
		return true
	return false

func _get_active_formation_lead_aircraft() -> Node3D:
	if _cap_route_lead and is_instance_valid(_cap_route_lead):
		var cap_lead_pilot := _get_pilot(_cap_route_lead)
		if not _is_aircraft_unavailable_for_formation(_cap_route_lead, cap_lead_pilot) and _can_pilot_hold_formation(cap_lead_pilot):
			return _cap_route_lead
	for aircraft in get_members():
		var pilot := _get_pilot(aircraft)
		if _is_aircraft_unavailable_for_formation(aircraft, pilot):
			continue
		if _can_pilot_hold_formation(pilot):
			return aircraft
	return null

func _refresh_lead_guidance(aircraft: Node3D, pilot: AIPilot) -> void:
	if not aircraft or not is_instance_valid(aircraft) or not pilot:
		return
	if mission == Mission.CAP:
		_assign_cap_lead_waypoints(aircraft, pilot)
		return
	_cap_route_lead = null
	_cap_route_lead_revision = -1
	# Outside CAP, a promoted lead should drop any stale one-point
	# leader-following waypoint and return to its own mission logic.
	if pilot.waypoints.size() <= 1:
		_clear_navigation_waypoints(pilot)

func _assign_cap_lead_waypoints(aircraft: Node3D, pilot: AIPilot) -> void:
	if not aircraft or not is_instance_valid(aircraft) or not pilot:
		return
	if aircraft == _cap_route_lead and _cap_route_lead_revision == _cap_route_revision:
		return
	_assign_cap_route_waypoints(aircraft, pilot)
	_cap_route_lead = aircraft
	_cap_route_lead_revision = _cap_route_revision

func _assign_cap_route_waypoints(aircraft: Node3D, pilot: AIPilot) -> void:
	if _cap_route_points.is_empty():
		pilot.waypoints.clear()
		pilot.waypoints_follow_carrier = true
	else:
		var cap_route := _cap_route_points.duplicate()
		if pilot.has_method("build_effective_altitude_waypoints"):
			cap_route = pilot.build_effective_altitude_waypoints(cap_route, CAP_ROUTE_MIN_AGL_M, true)
		elif pilot.has_method("build_terrain_safe_waypoints"):
			cap_route = pilot.build_terrain_safe_waypoints(cap_route, CAP_ROUTE_MIN_AGL_M, true, true)
		cap_route = _rotate_route_to_nearest_waypoint(cap_route, aircraft.global_position)
		pilot.set_patrol_route(cap_route)
		if debug_print and cap_route.size() > 1:
			var first: Vector3 = cap_route[0]
			var second: Vector3 = cap_route[1]
			print("[Flight %s CAPDBG] lead=%s points=%d first=(%.0f,%.0f,%.0f) second=(%.0f,%.0f,%.0f)" % [
				flight_name,
				aircraft.name,
				cap_route.size(),
				first.x, first.y, first.z,
				second.x, second.y, second.z
			])

func _get_lead_aircraft() -> Node3D:
	var active_lead := _get_active_formation_lead_aircraft()
	if active_lead:
		return active_lead
	var members := get_members()
	if _cap_route_lead and is_instance_valid(_cap_route_lead) and members.has(_cap_route_lead):
		return _cap_route_lead
	return members[0] if not members.is_empty() else null

func _get_lead_pilot() -> AIPilot:
	var lead := _get_lead_aircraft()
	return _get_pilot(lead) if lead else null

func _sanitize_cap_route_points(route_points: Array[Vector3], altitude_m: float) -> Array[Vector3]:
	var sanitized: Array[Vector3] = []
	for point in route_points:
		var waypoint := point
		if not is_finite(waypoint.x) or not is_finite(waypoint.z):
			continue
		waypoint.y = altitude_m
		sanitized.append(waypoint)
	if sanitized.size() == 1:
		return _build_cap_loop(sanitized[0], altitude_m)
	return sanitized

func _build_cap_loop(anchor: Vector3, altitude_m: float) -> Array[Vector3]:
	var half_side_m: float = 900.0
	return [
		Vector3(anchor.x + half_side_m, altitude_m, anchor.z + half_side_m),
		Vector3(anchor.x - half_side_m, altitude_m, anchor.z + half_side_m),
		Vector3(anchor.x - half_side_m, altitude_m, anchor.z - half_side_m),
		Vector3(anchor.x + half_side_m, altitude_m, anchor.z - half_side_m),
	]

func _get_cap_display_route_points() -> Array[Vector3]:
	var lead := _get_lead_aircraft()
	var lead_pilot := _get_pilot(lead) if lead else null
	if lead and is_instance_valid(lead) and lead_pilot and lead_pilot.waypoints.size() >= 2 and not lead_pilot.waypoints_follow_carrier:
		return _build_display_route_from_current_waypoint(
			lead_pilot.waypoints,
			lead_pilot.current_waypoint_index,
			lead.global_position
		)
	if not _cap_route_points.is_empty():
		var entry_pos := lead.global_position if lead and is_instance_valid(lead) else get_center_position()
		return _rotate_route_to_nearest_waypoint(_cap_route_points.duplicate(), entry_pos)
	return []

func _build_display_route_from_current_waypoint(route_points: Array[Vector3], current_index: int, from_pos: Vector3) -> Array[Vector3]:
	if route_points.is_empty():
		return []
	if route_points.size() == 1:
		return route_points.duplicate()
	var start_index: int = clampi(current_index, 0, route_points.size() - 1)
	var current_point := route_points[start_index]
	var dx: float = current_point.x - from_pos.x
	var dz: float = current_point.z - from_pos.z
	var dist_sq := dx * dx + dz * dz
	if dist_sq <= CAP_ROUTE_ENTRY_SKIP_DISTANCE_M * CAP_ROUTE_ENTRY_SKIP_DISTANCE_M:
		start_index = (start_index + 1) % route_points.size()
	var rotated: Array[Vector3] = []
	for offset in range(route_points.size()):
		rotated.append(route_points[(start_index + offset) % route_points.size()])
	return rotated

func _rotate_route_to_nearest_waypoint(route_points: Array[Vector3], from_pos: Vector3) -> Array[Vector3]:
	if route_points.size() <= 1:
		return route_points
	var best_index: int = 0
	var best_dist_sq: float = INF
	for i in range(route_points.size()):
		var point := route_points[i]
		var dx: float = point.x - from_pos.x
		var dz: float = point.z - from_pos.z
		var dist_sq := dx * dx + dz * dz
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_index = i
	if best_dist_sq <= CAP_ROUTE_ENTRY_SKIP_DISTANCE_M * CAP_ROUTE_ENTRY_SKIP_DISTANCE_M:
		best_index = (best_index + 1) % route_points.size()
	if best_index == 0:
		return route_points
	var rotated: Array[Vector3] = []
	for i in range(best_index, route_points.size()):
		rotated.append(route_points[i])
	for i in range(best_index):
		rotated.append(route_points[i])
	return rotated
