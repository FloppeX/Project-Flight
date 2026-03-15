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

# CAP state
var _cap_carrier: Node3D = null
var _cap_altitude_m: float = 500.0

# CAS state
var _cas_area_center: Vector3 = Vector3.ZERO
var _cas_area_radius: float = 3000.0

signal mission_changed(new_mission: Mission)

# ── Lifecycle ──────────────────────────────────────────────────────────────────

# Loose wedge offsets in leader-local space (right, up, forward).
# Lead is index 0 and flies its own waypoints unmodified.
const FORMATION_OFFSETS: Array[Vector3] = [
	Vector3(  0,   0,    0),  # lead  — not used, flies own patrol
	Vector3(180,   0, -120),  # two   — right echelon
	Vector3(-180,  0, -120),  # three — left echelon
	Vector3(  0,   0, -260),  # four  — trail centre
]
const FORMATION_BREAK_STATES: Array = [
	AIPilot.State.DOGFIGHT,
	AIPilot.State.ATTACK_POSITIONING,
	AIPilot.State.ATTACK_INBOUND,
	AIPilot.State.ATTACK_DIVE,
	AIPilot.State.ATTACK_BREAK_OFF,
	AIPilot.State.RTB,
	AIPilot.State.APPROACH,
	AIPilot.State.LANDING,
	AIPilot.State.IDLE,
	AIPilot.State.LAUNCHING,
	AIPilot.State.CLIMBING,
]

func _physics_process(_delta: float) -> void:
	if mission == Mission.CAS:
		_update_cas_assignments()
	if mission == Mission.CAP:
		_update_formation()

# ── Membership ────────────────────────────────────────────────────────────────

func register(aircraft: Node3D) -> void:
	if not aircraft or not is_instance_valid(aircraft):
		return
	if _members.has(aircraft):
		return
	_members.append(aircraft)
	_apply_current_mission(aircraft)
	if debug_print:
		print("[Flight %s] + %s  (strength: %d)" % [flight_name, aircraft.name, strength()])

func unregister(aircraft: Node3D) -> void:
	_members.erase(aircraft)
	for target in _claimed_targets.keys():
		if _claimed_targets[target] == aircraft:
			_claimed_targets.erase(target)

func get_members() -> Array[Node3D]:
	_members = _members.filter(func(a): return a and is_instance_valid(a))
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

func set_cap(carrier: Node3D, altitude_m: float = 500.0) -> void:
	mission = Mission.CAP
	_cap_carrier = carrier
	_cap_altitude_m = altitude_m
	_claimed_targets.clear()
	for aircraft in get_members():
		_apply_cap(aircraft)
	mission_changed.emit(mission)
	print("[Flight %s] CAP  alt=%.0fm" % [flight_name, altitude_m])

func set_cas(area_center: Vector3, area_radius: float = 3000.0) -> void:
	mission = Mission.CAS
	_cas_area_center = area_center
	_cas_area_radius = area_radius
	_claimed_targets.clear()
	for aircraft in get_members():
		_apply_cas(aircraft)
	mission_changed.emit(mission)
	print("[Flight %s] CAS  center=(%.0f,%.0f)  r=%.0fm" % [flight_name, area_center.x, area_center.z, area_radius])

func set_rtb() -> void:
	mission = Mission.RTB
	_claimed_targets.clear()
	for aircraft in get_members():
		_apply_rtb(aircraft)
	mission_changed.emit(mission)
	print("[Flight %s] RTB" % flight_name)

# ── Per-aircraft application ───────────────────────────────────────────────────

func _apply_current_mission(aircraft: Node3D) -> void:
	match mission:
		Mission.CAP: _apply_cap(aircraft)
		Mission.CAS: _apply_cas(aircraft)
		Mission.RTB: _apply_rtb(aircraft)

func _apply_cap(aircraft: Node3D) -> void:
	var pilot := _get_pilot(aircraft)
	if not pilot or _is_deck_busy(pilot):
		return
	pilot.ground_attack_enabled = false
	pilot.dogfight_enabled = true
	# Clear waypoints so AIPilot rebuilds its carrier-centered patrol
	pilot.waypoints.clear()
	if pilot.current_state not in [AIPilot.State.SEARCH]:
		pilot.change_state(AIPilot.State.SEARCH)

func _apply_cas(aircraft: Node3D) -> void:
	var pilot := _get_pilot(aircraft)
	if not pilot or _is_deck_busy(pilot):
		return
	pilot.ground_attack_enabled = true
	pilot.dogfight_enabled = true  # still defend themselves

func _apply_rtb(aircraft: Node3D) -> void:
	var pilot := _get_pilot(aircraft)
	if not pilot or _is_deck_busy(pilot):
		return
	if pilot.current_state not in [AIPilot.State.RTB, AIPilot.State.APPROACH, AIPilot.State.LANDING]:
		pilot.change_state(AIPilot.State.RTB)

# ── CAS target distribution ───────────────────────────────────────────────────

func _update_cas_assignments() -> void:
	# Prune stale claims (destroyed targets or lost aircraft)
	var stale: Array = []
	for target in _claimed_targets.keys():
		var claimer: Node3D = _claimed_targets[target]
		if not is_instance_valid(target):
			# Target destroyed — report splash if the claimer is still alive
			if is_instance_valid(claimer):
				var idx := get_members().find(claimer)
				if idx >= 0:
					RadioComms.say_splash("%s %s" % [flight_name, _member_suffix(idx)])
			stale.append(target)
		elif not is_instance_valid(claimer):
			stale.append(target)
	for t in stale:
		_claimed_targets.erase(t)

	for aircraft in get_members():
		var pilot := _get_pilot(aircraft)
		if not pilot:
			continue

		# Only assign to aircraft that are free to accept a new target
		if pilot.current_state not in [AIPilot.State.SEARCH, AIPilot.State.ATTACK_BREAK_OFF]:
			continue

		# Skip if this aircraft already has a live claim
		var has_claim := false
		for claimer in _claimed_targets.values():
			if claimer == aircraft:
				has_claim = true
				break
		if has_claim:
			continue

		var target := _pick_unclaimed_target(aircraft.global_position)
		if not target:
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

# ── Helpers ────────────────────────────────────────────────────────────────────

func _update_formation() -> void:
	var members := get_members()
	if members.size() < 2:
		return
	var lead := members[0]
	var lead_pilot := _get_pilot(lead)
	# Only form up while the lead is patrolling — break in combat
	if not lead_pilot or lead_pilot.current_state != AIPilot.State.SEARCH:
		return
	var lead_basis: Basis = lead.global_transform.basis
	for i in range(1, members.size()):
		var wingman := members[i]
		var pilot := _get_pilot(wingman)
		if not pilot:
			continue
		# Wingman in combat or deck ops — let them do their thing
		if pilot.current_state in FORMATION_BREAK_STATES:
			continue
		var form_pos := _formation_position(lead, lead_basis, i)
		var wps: Array[Vector3] = [form_pos]
		pilot.set_waypoints(wps)

func _formation_position(lead: Node3D, lead_basis: Basis, member_index: int) -> Vector3:
	var offset: Vector3 = FORMATION_OFFSETS[min(member_index, FORMATION_OFFSETS.size() - 1)]
	# Transform offset from leader-local (right/up/fwd) into world space
	var world_offset := lead_basis.x * offset.x \
					  + lead_basis.y * offset.y \
					  + lead_basis.z * offset.z
	var pos := lead.global_position + world_offset
	# Match lead altitude so they fly level
	pos.y = lead.global_position.y
	return pos

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

func _is_deck_busy(pilot: AIPilot) -> bool:
	## True when the pilot is in a deck/flight phase we should not interrupt.
	return pilot.current_state in [
		AIPilot.State.IDLE, AIPilot.State.LAUNCHING,
		AIPilot.State.CLIMBING, AIPilot.State.RTB,
		AIPilot.State.APPROACH, AIPilot.State.LANDING,
	]
