class_name Flight
extends Node

## Manages a single named flight of 2-4 aircraft.
## Applies mission settings to each pilot and handles per-aircraft target
## distribution for CAS missions.
## Tactical decisions (intercept, recall) are made by AirOpsManager, not here.

enum Mission {
	NONE,
	CAP,    ## Combat Air Patrol — orbit carrier, engage air threats only
	CAS,    ## Close Air Support — attack ground targets in assigned area
	RTB,    ## Return all aircraft to carrier
}

@export var flight_name: String = ""
@export var debug_print: bool = true

var mission: Mission = Mission.NONE

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
	AIPilot.State.RTB,
]
const FORMATION_BREAK_STATES: Array = [
	AIPilot.State.DOGFIGHT,
	AIPilot.State.ATTACK_POSITIONING,
	AIPilot.State.ATTACK_INBOUND,
	AIPilot.State.ATTACK_DIVE,
	AIPilot.State.ATTACK_BREAK_OFF,
	AIPilot.State.APPROACH,
	AIPilot.State.LANDING,
	AIPilot.State.IDLE,
	AIPilot.State.LAUNCHING,
	AIPilot.State.CLIMBING,
]
const FORMATION_REJOIN_DISTANCE_M: float = 60.0
const FORMATION_CLOSE_DISTANCE_M: float = 25.0
const FORMATION_MATCH_SPEED_DISTANCE_M: float = 110.0
const FORMATION_SOFT_JOIN_START_M: float = 180.0
const FORMATION_REJOIN_EXTRA_TRAIL_M: float = 80.0
const FORMATION_FORWARD_HOLD_START_M: float = 8.0
const FORMATION_FORWARD_HOLD_AHEAD_BUFFER_M: float = 14.0
const FORMATION_FORWARD_HOLD_MAX_SHIFT_M: float = 120.0
const FORMATION_FORWARD_HOLD_LATERAL_BLEND: float = 0.35
const FORMATION_FORWARD_HOLD_VERTICAL_BLEND: float = 0.30
const FORMATION_REJOIN_LATERAL_FAR_SCALE: float = 0.35
const FORMATION_REJOIN_VERTICAL_FAR_BLEND: float = 0.45
const FORMATION_SLOT_FORWARD_CLOSE_M: float = 14.0
const FORMATION_SLOT_FORWARD_SOFT_M: float = 95.0
const FORMATION_SLOT_LATERAL_CLOSE_M: float = 10.0
const FORMATION_SLOT_LATERAL_SOFT_M: float = 65.0
const FORMATION_SLOT_VERTICAL_CLOSE_M: float = 8.0
const FORMATION_SLOT_VERTICAL_SOFT_M: float = 35.0
const FORMATION_WINGMAN_MAX_SPEED_BONUS_MPS: float = 20.0
const FORMATION_WINGMAN_MAX_SPEED_REDUCTION_MPS: float = 12.0
const FORMATION_WINGMAN_CLOSE_SPEED_BUFFER_MPS: float = 4.0
const FORMATION_WINGMAN_HOLD_SPEED_REDUCTION_MPS: float = 6.0
const FORMATION_LEAD_SLOWDOWN_START_M: float = 90.0
const FORMATION_LEAD_FULL_WAIT_M: float = 180.0
const FORMATION_LEAD_MAX_SLOWDOWN_MPS: float = 24.0
const FORMATION_LEAD_MIN_SPEED_MPS: float = 62.0
const CAP_ROUTE_ENTRY_SKIP_DISTANCE_M: float = 140.0

var _members_clean_frame: int = -1  # Frame when _members was last pruned

func _ready() -> void:
	add_to_group("origin_shifter")

func apply_origin_shift(offset: Vector3) -> void:
	_cas_area_center -= offset
	for i in range(_cap_route_points.size()):
		_cap_route_points[i] -= offset

func _physics_process(_delta: float) -> void:
	_prune_members_once()
	_apply_pending_mission_updates()
	if mission == Mission.CAS:
		_update_cas_assignments()
	if mission != Mission.NONE:
		_update_formation()

# ── Membership ────────────────────────────────────────────────────────────────

func _prune_members_once() -> void:
	var frame := Engine.get_physics_frames()
	if _members_clean_frame == frame:
		return
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

# ── Mission orders ─────────────────────────────────────────────────────────────

func set_cap(carrier: Node3D, altitude_m: float = 800.0) -> void:
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

func set_cap_route(carrier: Node3D, route_points: Array[Vector3], altitude_m: float = 800.0) -> void:
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
	pilot.ground_attack_enabled = false
	pilot.dogfight_enabled = true
	pilot.set_patrol_altitude(_cap_altitude_m)
	if aircraft == _get_lead_aircraft():
		_refresh_lead_guidance(aircraft, pilot)
	else:
		# Clear waypoints so AIPilot rebuilds its carrier-centered patrol.
		_clear_navigation_waypoints(pilot, true)
	if pilot.current_state not in [AIPilot.State.SEARCH]:
		pilot.change_state(AIPilot.State.SEARCH)
	return true

func _apply_cas(aircraft: Node3D) -> bool:
	var pilot := _get_pilot(aircraft)
	if not pilot or _is_deck_busy(pilot):
		return false
	pilot.ground_attack_enabled = true
	pilot.dogfight_enabled = true  # still defend themselves
	pilot.set_patrol_altitude(_cas_altitude_m)
	_clear_navigation_waypoints(pilot)
	return true

func _apply_rtb(aircraft: Node3D) -> bool:
	var pilot := _get_pilot(aircraft)
	if not pilot or _is_deck_busy(pilot):
		return false
	_clear_navigation_waypoints(pilot)
	if pilot.current_state not in [AIPilot.State.RTB, AIPilot.State.APPROACH, AIPilot.State.LANDING]:
		pilot.change_state(AIPilot.State.RTB)
	return true

# ── CAS target distribution ───────────────────────────────────────────────────

func _update_cas_assignments() -> void:
	# Prune stale claims (destroyed targets or lost aircraft)
	_prune_stale_claims(true)

	for aircraft in get_members():
		var pilot := _get_pilot(aircraft)
		if not pilot:
			continue

		# Only assign to aircraft that are free to accept a new target
		if pilot.current_state not in [AIPilot.State.SEARCH, AIPilot.State.ATTACK_BREAK_OFF]:
			continue

		# Skip if this aircraft already has a live claim
		if _aircraft_has_live_claim(aircraft):
			continue

		var target := _pick_unclaimed_target(aircraft.global_position)
		if not target or not is_instance_valid(target) or not is_instance_valid(aircraft):
			continue

		_claimed_targets[target] = aircraft
		pilot.set_target(target)
		if debug_print:
			print("[Flight %s] %s → %s" % [flight_name, aircraft.name, target.name])
		_say_cas_assignment(aircraft, target)

func _pick_unclaimed_target(from_pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("ground_vehicles"):
		if not is_instance_valid(node):
			continue
		if node.has_method("get_team") and int(node.get_team()) == 1:
			continue  # skip friendlies
		if _claimed_targets.has(node):
			continue  # already claimed by a flight-mate
		var flat_dist := Vector2(node.global_position.x - _cas_area_center.x,
								node.global_position.z - _cas_area_center.z).length()
		if flat_dist > _cas_area_radius:
			continue  # outside assigned area
		var d := from_pos.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best

func _prune_stale_claims(report_splashes: bool) -> void:
	var stale_claims: Array = []
	for target_ref in _claimed_targets.keys():
		var claimer_ref = _claimed_targets.get(target_ref)
		var target_valid: bool = _is_live_node3d_ref(target_ref)
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
	var lead := _get_active_formation_lead_aircraft()
	if not lead:
		return
	var lead_pilot := _get_pilot(lead)
	if _is_aircraft_unavailable_for_formation(lead, lead_pilot):
		return
	if not _can_pilot_hold_formation(lead_pilot):
		return
	_refresh_lead_guidance(lead, lead_pilot)
	var lead_basis: Basis = lead.global_transform.basis.orthonormalized()
	var lead_speed_mps := _get_aircraft_speed_mps(lead, lead_pilot)
	var formation_members: Array[Dictionary] = []
	var formation_slot: int = 1
	var max_slot_error_m: float = 0.0
	for wingman in members:
		if wingman == lead:
			continue
		var pilot := _get_pilot(wingman)
		if _is_aircraft_unavailable_for_formation(wingman, pilot):
			continue
		if not _can_pilot_hold_formation(pilot):
			continue
		var form_pos := _formation_position(lead, lead_basis, formation_slot)
		var guidance_anchor := _formation_guidance_anchor(wingman, lead, lead_basis, formation_slot, form_pos)
		var slot_quality := _formation_slot_quality(wingman, lead_basis, form_pos)
		var ahead_hold_t := _formation_ahead_hold_t(wingman, lead_basis, form_pos)
		formation_members.append({
			"aircraft": wingman,
			"pilot": pilot,
			"slot": formation_slot,
			"slot_anchor": form_pos,
			"anchor": guidance_anchor,
			"slot_quality": slot_quality,
			"ahead_hold_t": ahead_hold_t,
		})
		max_slot_error_m = maxf(max_slot_error_m, wingman.global_position.distance_to(form_pos))
		formation_slot += 1

	if formation_members.is_empty():
		return

	for entry in formation_members:
		var wingman: Node3D = entry.get("aircraft")
		var pilot: AIPilot = entry.get("pilot")
		var anchor: Vector3 = entry.get("anchor")
		var slot_anchor: Vector3 = entry.get("slot_anchor")
		var slot_quality: float = entry.get("slot_quality", 0.0)
		var ahead_hold_t: float = entry.get("ahead_hold_t", 0.0)
		var speed_bias_mps := _formation_wingman_speed_bias(wingman, lead_basis, slot_anchor, slot_quality, ahead_hold_t)
		var speed_cap_mps := _formation_wingman_speed_cap(wingman, lead_basis, slot_anchor, lead_speed_mps, slot_quality, ahead_hold_t)
		pilot.set_formation_anchor(anchor)
		pilot.set_formation_speed_guidance(speed_cap_mps, speed_bias_mps)
		pilot.set_formation_handling(slot_quality, ahead_hold_t)

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

func _formation_guidance_anchor(wingman: Node3D, lead: Node3D, lead_basis: Basis, formation_slot: int, slot_anchor: Vector3) -> Vector3:
	if not wingman or not is_instance_valid(wingman) or not lead or not is_instance_valid(lead):
		return slot_anchor
	var error_vec := wingman.global_position - slot_anchor
	var forward_error_m := error_vec.dot(lead_basis.z)
	var lateral_error_m := error_vec.dot(lead_basis.x)
	var slot_error_m := error_vec.length()
	if forward_error_m > FORMATION_FORWARD_HOLD_START_M:
		var hold_offset := FORMATION_OFFSETS[min(formation_slot, FORMATION_OFFSETS.size() - 1)]
		var hold_shift_m := clampf(
			forward_error_m + FORMATION_FORWARD_HOLD_AHEAD_BUFFER_M,
			0.0,
			FORMATION_FORWARD_HOLD_MAX_SHIFT_M
		)
		hold_offset.z += hold_shift_m
		hold_offset.x = lerpf(hold_offset.x, hold_offset.x + lateral_error_m, FORMATION_FORWARD_HOLD_LATERAL_BLEND)
		var hold_world_offset := lead_basis.x * hold_offset.x \
							   + lead_basis.y * hold_offset.y \
							   + lead_basis.z * hold_offset.z
		var hold_anchor := lead.global_position + hold_world_offset
		hold_anchor.y = lerpf(wingman.global_position.y, slot_anchor.y, FORMATION_FORWARD_HOLD_VERTICAL_BLEND)
		return hold_anchor
	if slot_error_m <= FORMATION_REJOIN_DISTANCE_M:
		return slot_anchor
	var soften_t := clampf(
		(slot_error_m - FORMATION_REJOIN_DISTANCE_M) / maxf(FORMATION_SOFT_JOIN_START_M - FORMATION_REJOIN_DISTANCE_M, 1.0),
		0.0,
		1.0
	)
	var softened_offset := FORMATION_OFFSETS[min(formation_slot, FORMATION_OFFSETS.size() - 1)]
	softened_offset.x *= lerpf(1.0, FORMATION_REJOIN_LATERAL_FAR_SCALE, soften_t)
	if forward_error_m < -10.0:
		softened_offset.z -= FORMATION_REJOIN_EXTRA_TRAIL_M * soften_t
	var world_offset := lead_basis.x * softened_offset.x \
					  + lead_basis.y * softened_offset.y \
					  + lead_basis.z * softened_offset.z
	var guidance_anchor := lead.global_position + world_offset
	var vertical_blend := lerpf(1.0, FORMATION_REJOIN_VERTICAL_FAR_BLEND, soften_t)
	guidance_anchor.y = lerpf(wingman.global_position.y, slot_anchor.y, vertical_blend)
	return guidance_anchor

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
	return pilot != null and pilot.current_state in FORMATION_ACTIVE_STATES

func _get_aircraft_speed_mps(aircraft: Node3D, pilot: AIPilot) -> float:
	if aircraft and is_instance_valid(aircraft) and "linear_velocity" in aircraft:
		return maxf(aircraft.linear_velocity.length(), FORMATION_LEAD_MIN_SPEED_MPS)
	if pilot:
		return maxf(pilot.target_speed, FORMATION_LEAD_MIN_SPEED_MPS)
	return FORMATION_LEAD_MIN_SPEED_MPS

func _formation_wingman_speed_bias(wingman: Node3D, lead_basis: Basis, slot_anchor: Vector3, slot_quality: float = 0.0, ahead_hold_t: float = 0.0) -> float:
	if not wingman or not is_instance_valid(wingman):
		return 0.0
	var error_vec := wingman.global_position - slot_anchor
	var slot_error_m := error_vec.length()
	var forward_error_m := error_vec.dot(lead_basis.z)
	var speed_bias_mps: float = 0.0
	if forward_error_m < -10.0:
		speed_bias_mps += clampf((-forward_error_m - 10.0) * 0.20, 0.0, FORMATION_WINGMAN_MAX_SPEED_BONUS_MPS)
	elif forward_error_m > FORMATION_FORWARD_HOLD_START_M:
		speed_bias_mps -= lerpf(
			clampf((forward_error_m - FORMATION_FORWARD_HOLD_START_M) * 0.16, 0.0, FORMATION_WINGMAN_MAX_SPEED_REDUCTION_MPS),
			clampf((forward_error_m - FORMATION_FORWARD_HOLD_START_M) * 0.24, 0.0, FORMATION_WINGMAN_MAX_SPEED_REDUCTION_MPS),
			ahead_hold_t
		)
	if slot_error_m > FORMATION_REJOIN_DISTANCE_M and forward_error_m < FORMATION_FORWARD_HOLD_START_M:
		speed_bias_mps += clampf((slot_error_m - FORMATION_REJOIN_DISTANCE_M) * 0.06, 0.0, 6.0)
	speed_bias_mps -= lerpf(0.0, 3.0, slot_quality)
	return clampf(speed_bias_mps, -FORMATION_WINGMAN_MAX_SPEED_REDUCTION_MPS, FORMATION_WINGMAN_MAX_SPEED_BONUS_MPS)

func _formation_wingman_speed_cap(wingman: Node3D, lead_basis: Basis, anchor: Vector3, lead_speed_mps: float, slot_quality: float = 0.0, ahead_hold_t: float = 0.0) -> float:
	if not wingman or not is_instance_valid(wingman):
		return -1.0
	var error_vec := wingman.global_position - anchor
	var slot_error_m := error_vec.length()
	var forward_error_m := error_vec.dot(lead_basis.z)
	if slot_error_m > FORMATION_MATCH_SPEED_DISTANCE_M and forward_error_m < -20.0:
		return -1.0
	var speed_cap_mps := lead_speed_mps + FORMATION_WINGMAN_CLOSE_SPEED_BUFFER_MPS
	speed_cap_mps = minf(
		speed_cap_mps,
		lerpf(lead_speed_mps + 1.5, lead_speed_mps - FORMATION_WINGMAN_HOLD_SPEED_REDUCTION_MPS, slot_quality)
	)
	if forward_error_m > 10.0:
		var ahead_cap_mps := lead_speed_mps - lerpf(
			clampf(forward_error_m * 0.12, 1.0, FORMATION_WINGMAN_HOLD_SPEED_REDUCTION_MPS),
			clampf(forward_error_m * 0.20, 2.0, FORMATION_WINGMAN_HOLD_SPEED_REDUCTION_MPS + 4.0),
			ahead_hold_t
		)
		speed_cap_mps = minf(speed_cap_mps, ahead_cap_mps)
	return maxf(speed_cap_mps, FORMATION_LEAD_MIN_SPEED_MPS)

func _formation_lead_speed_cap(lead_pilot: AIPilot, max_slot_error_m: float) -> float:
	if not lead_pilot or max_slot_error_m <= FORMATION_LEAD_SLOWDOWN_START_M:
		return -1.0
	var wait_t := clampf(
		(max_slot_error_m - FORMATION_LEAD_SLOWDOWN_START_M) / maxf(FORMATION_LEAD_FULL_WAIT_M - FORMATION_LEAD_SLOWDOWN_START_M, 1.0),
		0.0,
		1.0
	)
	var nominal_speed_mps := maxf(lead_pilot.target_speed, 80.0)
	return maxf(nominal_speed_mps - FORMATION_LEAD_MAX_SLOWDOWN_MPS * wait_t, FORMATION_LEAD_MIN_SPEED_MPS)

func _say_cas_assignment(aircraft: Node3D, target: Node3D) -> void:
	var members := get_members()
	var member_index := members.find(aircraft)
	var suffix := _member_suffix(member_index)
	var callsign := "%s %s" % [flight_name, suffix]
	var target_type := _ground_target_type(target)

	if member_index == 0:
		RadioComms.transmit(callsign, "%s flight" % flight_name,
			RadioComms._pick([
				"Target acquired. Rolling in on the %s." % target_type,
				"Lead's on the %s. Flight, find your targets." % target_type,
				"Engaging the %s. Tally." % target_type,
			]))
	else:
		RadioComms.transmit(callsign, "%s lead" % flight_name,
			RadioComms._pick([
				"Two, tally. On the %s." % target_type,
				"%s, engaging the %s." % [suffix, target_type],
				"Copy. I've got the %s." % target_type,
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
	for member in members:
		sum += member.global_position
	return sum / float(members.size())

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
		Mission.RTB:
			if _cap_carrier and is_instance_valid(_cap_carrier):
				return [_cap_carrier.global_position]
			return []
		_:
			return []

func has_looped_mission_map() -> bool:
	return mission == Mission.CAP and get_mission_map_points().size() >= 2

func get_mission_name() -> String:
	return Mission.keys()[mission]

func get_lead_state_name() -> String:
	var lead_pilot := _get_lead_pilot()
	if not lead_pilot:
		return "INACTIVE"
	return AIPilot.State.keys()[lead_pilot.current_state]

func get_status_summary() -> Dictionary:
	return {
		"name": flight_name,
		"mission": get_mission_name(),
		"strength": strength(),
		"position": get_center_position(),
		"active_waypoints": get_active_waypoints(),
		"mission_map_points": get_mission_map_points(),
		"mission_map_closed_loop": has_looped_mission_map(),
		"lead_state": get_lead_state_name(),
	}

func _is_deck_busy(pilot: AIPilot) -> bool:
	## True when the pilot is in a deck/flight phase we should not interrupt.
	return pilot.current_state in [
		AIPilot.State.IDLE, AIPilot.State.LAUNCHING,
		AIPilot.State.CLIMBING, AIPilot.State.RTB,
		AIPilot.State.APPROACH, AIPilot.State.LANDING,
	]

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
		pilot.set_waypoints(cap_route, false)
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
	_cap_route_lead = aircraft
	_cap_route_lead_revision = _cap_route_revision

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
