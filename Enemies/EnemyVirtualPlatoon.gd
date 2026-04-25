class_name EnemyVirtualPlatoon
extends Node
## Abstract representation of an enemy ground platoon.
## Moves as data until a friendly asset comes within ACTIVATE_RANGE_M,
## then spawns real VehicleEnemyLight instances inside a GroundVehiclePlatoon.
## When all friendlies leave DEACTIVATE_RANGE_M the real vehicles are freed
## and the platoon resumes as a map marker.
##
## Detection: ground units scan every DETECTION_SCAN_INTERVAL_S with a shorter
## range than air. Reports are delayed 40–90 s before reaching EnemyOpsManager.

enum Mission { PATROL, ATTACK_CARRIER, ATTACK_POSITION, RTB, HOLD }
enum VState  { VIRTUAL, ACTIVE }

const ACTIVATE_RANGE_M          := 1400.0
const DEACTIVATE_RANGE_M        := 2200.0
const PATROL_SPEED_MPS          := 8.0
const ATTACK_SPEED_MPS          := 10.0
const RTB_SPEED_MPS             := 9.0
const PATROL_WP_COUNT           := 4
const PATROL_WP_REACH_M         := 80.0
const DETECTION_RANGE_M         := 2500.0  # ground units see less than air
const DETECTION_SCAN_INTERVAL_S := 6.0
const REPORT_DELAY_MIN_S        := 40.0    # slower comms for ground
const REPORT_DELAY_MAX_S        := 90.0

# Configuration (set before adding to tree)
@export var platoon_name:  String = "EP-01"
@export var vehicle_count: int    = 5
@export var patrol_radius: float  = 2000.0
@export var faction_color: Color  = Color.RED

# Runtime state
var position:        Vector3 = Vector3.ZERO
var heading:         Vector3 = Vector3(1, 0, 0)
var home_position:   Vector3 = Vector3.ZERO
var mission:         Mission = Mission.PATROL
var vstate:          VState  = VState.VIRTUAL
var attack_position: Vector3 = Vector3.ZERO

var _vehicle_scenes:   Array[PackedScene] = []
var _patrol_waypoints: Array[Vector3] = []
var _patrol_wp_idx:    int = 0
var _platoon_node:     GroundVehiclePlatoon = null
var _active_vehicles:  Array[Node3D] = []
var _last_live_count:  int = 0
var _detection_timer:  float = 0.0
var _pending_reports:  Array[Dictionary] = []
var _rng:              RandomNumberGenerator = RandomNumberGenerator.new()

signal unit_destroyed(platoon: EnemyVirtualPlatoon)


func setup(home_pos: Vector3, scenes: Array[PackedScene], start_angle: float = 0.0) -> void:
	home_position   = home_pos
	_vehicle_scenes = scenes
	_rng.randomize()
	_generate_patrol_waypoints(start_angle)
	_patrol_wp_idx = _rng.randi() % maxi(_patrol_waypoints.size(), 1)
	if not _patrol_waypoints.is_empty():
		position = _patrol_waypoints[_patrol_wp_idx]
	else:
		var ix := home_pos.x + cos(start_angle) * patrol_radius
		var iz := home_pos.z + sin(start_angle) * patrol_radius
		var iy := TerrainNavGrid.sample_height(ix, iz)
		if iy <= TerrainNavGrid.IMPASSABLE * 0.5:
			iy = home_pos.y
		position = Vector3(ix, iy, iz)
	heading = Vector3(-sin(start_angle), 0.0, cos(start_angle)).normalized()
	_detection_timer = _rng.randf_range(0.0, DETECTION_SCAN_INTERVAL_S)


func _generate_patrol_waypoints(start_angle: float) -> void:
	_patrol_waypoints.clear()
	for i in range(PATROL_WP_COUNT):
		var angle := start_angle + float(i) * TAU / float(PATROL_WP_COUNT) + _rng.randf_range(-0.3, 0.3)
		var r     := patrol_radius * _rng.randf_range(0.45, 0.95)
		var wx    := home_position.x + cos(angle) * r
		var wz    := home_position.z + sin(angle) * r
		var wy    := TerrainNavGrid.sample_height(wx, wz)
		if wy <= TerrainNavGrid.IMPASSABLE * 0.5:
			wy = home_position.y
		_patrol_waypoints.append(Vector3(wx, wy, wz))
	_patrol_wp_idx = 0


func tick(delta: float) -> void:
	_active_vehicles = _active_vehicles.filter(func(v): return is_instance_valid(v))

	if vstate == VState.ACTIVE:
		if _platoon_node == null or not is_instance_valid(_platoon_node):
			_on_platoon_gone()
			return
		var live := _platoon_node.get_members().size()
		if live != _last_live_count:
			_last_live_count = live
			vehicle_count = live
			if live == 0:
				_on_platoon_gone()
				return
		var centroid := _platoon_node.get_contact_position()
		if centroid != Vector3.INF:
			position = centroid
		_check_dematerialize()
		# Materialized units report immediately
		_scan_for_contacts(true)
		return

	if vehicle_count <= 0:
		return

	match mission:
		Mission.PATROL:
			_tick_patrol(delta)
		Mission.ATTACK_CARRIER, Mission.ATTACK_POSITION:
			_tick_move_to(attack_position, ATTACK_SPEED_MPS, delta)
		Mission.RTB:
			_tick_rtb(delta)
		Mission.HOLD:
			pass

	_check_materialize()
	_tick_detection(delta)


# ── Movement ──────────────────────────────────────────────────────────────────

func _tick_patrol(delta: float) -> void:
	if _patrol_waypoints.is_empty():
		_generate_patrol_waypoints(0.0)
		return
	var target    := _patrol_waypoints[_patrol_wp_idx]
	var to_target := Vector3(target.x - position.x, 0.0, target.z - position.z)
	if to_target.length() < PATROL_WP_REACH_M:
		_patrol_wp_idx = (_patrol_wp_idx + 1) % _patrol_waypoints.size()
		return
	var dir   := to_target.normalized()
	position  += dir * PATROL_SPEED_MPS * delta
	heading    = dir


func _tick_move_to(target: Vector3, speed: float, delta: float) -> void:
	var to_target := Vector3(target.x - position.x, 0.0, target.z - position.z)
	if to_target.length() < 80.0:
		return
	var dir   := to_target.normalized()
	position  += dir * speed * delta
	heading    = dir


func _tick_rtb(delta: float) -> void:
	var to_base := Vector3(home_position.x - position.x, 0.0, home_position.z - position.z)
	if to_base.length() < 150.0:
		mission  = Mission.HOLD
		position = home_position
		return
	var dir   := to_base.normalized()
	position  += dir * RTB_SPEED_MPS * delta
	heading    = dir


# ── Detection & reporting ─────────────────────────────────────────────────────

func _tick_detection(delta: float) -> void:
	_detection_timer -= delta
	if _detection_timer <= 0.0:
		_detection_timer = DETECTION_SCAN_INTERVAL_S
		_scan_for_contacts(false)
	_process_pending_reports(delta)


func _scan_for_contacts(immediate: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var delay_s := 0.0 if immediate else _rng.randf_range(REPORT_DELAY_MIN_S, REPORT_DELAY_MAX_S)

	var carrier := tree.get_first_node_in_group("carrier") as Node3D
	if carrier and is_instance_valid(carrier):
		if position.distance_to(carrier.global_position) <= DETECTION_RANGE_M:
			_queue_report("carrier", carrier.global_position, 1, delay_s)

	var friendly_air_pos   := Vector3.ZERO
	var friendly_air_count := 0
	for aircraft in _get_friendly_air_nodes():
		if position.distance_to(aircraft.global_position) <= DETECTION_RANGE_M:
			friendly_air_pos += aircraft.global_position
			friendly_air_count += 1
	if friendly_air_count > 0:
		_queue_report("air", friendly_air_pos / float(friendly_air_count), friendly_air_count, delay_s)

	var friendly_gnd_pos   := Vector3.ZERO
	var friendly_gnd_count := 0
	for node in tree.get_nodes_in_group("ground_vehicles"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		if (node as Node3D).is_in_group("enemies"):
			continue
		if position.distance_to((node as Node3D).global_position) <= DETECTION_RANGE_M:
			friendly_gnd_pos   += (node as Node3D).global_position
			friendly_gnd_count += 1
	if friendly_gnd_count > 0:
		_queue_report("ground", friendly_gnd_pos / float(friendly_gnd_count), friendly_gnd_count, delay_s)


func _queue_report(contact_type: String, contact_pos: Vector3, strength: int, delay_s: float) -> void:
	for r in _pending_reports:
		if r["type"] == contact_type:
			r["position"] = contact_pos
			r["strength"] = strength
			return
	_pending_reports.append({
		"type":      contact_type,
		"position":  contact_pos,
		"strength":  strength,
		"countdown": delay_s,
	})


func _process_pending_reports(delta: float) -> void:
	var sent: Array[int] = []
	for i in range(_pending_reports.size()):
		_pending_reports[i]["countdown"] -= delta
		if _pending_reports[i]["countdown"] <= 0.0:
			var r: Dictionary = _pending_reports[i]
			EnemyOpsManager.receive_intel(platoon_name, r["type"], r["position"], r["strength"])
			sent.append(i)
	for i in range(sent.size() - 1, -1, -1):
		_pending_reports.remove_at(sent[i])


# ── Materialize / dematerialize ───────────────────────────────────────────────

func _check_materialize() -> void:
	if _vehicle_scenes.is_empty() or vstate == VState.ACTIVE:
		return
	if _nearest_friendly_distance() <= ACTIVATE_RANGE_M:
		_materialize()


func _check_dematerialize() -> void:
	if _nearest_friendly_distance() > DEACTIVATE_RANGE_M:
		dematerialize()


func _materialize() -> void:
	if _vehicle_scenes.is_empty() or vstate == VState.ACTIVE or vehicle_count <= 0:
		return
	vstate = VState.ACTIVE
	var scene_root := get_tree().current_scene

	_platoon_node = GroundVehiclePlatoon.new()
	_platoon_node.name      = "EnemyPlatoon_" + platoon_name
	_platoon_node.platoon_id = platoon_name
	_platoon_node.team      = 2
	scene_root.add_child(_platoon_node)
	_platoon_node.global_position = position

	for i in range(vehicle_count):
		var scene := _vehicle_scenes[_rng.randi() % _vehicle_scenes.size()]
		var veh   := scene.instantiate() as Node3D
		if veh == null:
			continue
		scene_root.add_child(veh)
		var angle  := float(i) * TAU / float(maxi(vehicle_count, 1))
		var spread := Vector3(cos(angle) * 28.0, 0.0, sin(angle) * 28.0)
		veh.global_position = position + spread
		veh.set_meta("faction_color", faction_color)
		if "team" in veh:
			veh.set("team", 2)
		if veh.has_method("assign_platoon"):
			veh.call("assign_platoon", _platoon_node)
		_active_vehicles.append(veh)

	_last_live_count = vehicle_count
	_apply_mission_to_platoon()
	# Immediate intel — we can see the player
	_scan_for_contacts(true)
	print("[EnemyVirtualPlatoon] %s materialized (%d vehicles) at (%.0f, %.0f)" % [
		platoon_name, vehicle_count, position.x, position.z])


func _apply_mission_to_platoon() -> void:
	if _platoon_node == null or not is_instance_valid(_platoon_node):
		return
	match mission:
		Mission.ATTACK_CARRIER:
			var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
			if carrier and is_instance_valid(carrier):
				_platoon_node.attack_node = carrier
				_platoon_node.objective_type = GroundVehiclePlatoon.ObjectiveType.ATTACK_NODE
				return
			_platoon_node.objective_position = attack_position
			_platoon_node.objective_type = GroundVehiclePlatoon.ObjectiveType.ATTACK_POSITION
		Mission.ATTACK_POSITION:
			_platoon_node.objective_position = attack_position
			_platoon_node.objective_type = GroundVehiclePlatoon.ObjectiveType.ATTACK_POSITION
		_:
			# PATROL / RTB / HOLD — move to next patrol waypoint
			var dest := _current_patrol_waypoint()
			_platoon_node.objective_position = dest
			_platoon_node.objective_type = GroundVehiclePlatoon.ObjectiveType.MOVE_TO_POSITION


func _current_patrol_waypoint() -> Vector3:
	if _patrol_waypoints.is_empty():
		return home_position
	return _patrol_waypoints[_patrol_wp_idx % _patrol_waypoints.size()]


func _on_platoon_gone() -> void:
	vehicle_count    = 0
	vstate           = VState.VIRTUAL
	_platoon_node    = null
	_active_vehicles.clear()
	unit_destroyed.emit(self)


func dematerialize() -> void:
	for veh in _active_vehicles:
		if is_instance_valid(veh):
			veh.queue_free()
	_active_vehicles.clear()
	if _platoon_node != null and is_instance_valid(_platoon_node):
		_platoon_node.queue_free()
	_platoon_node = null
	vstate  = VState.VIRTUAL
	mission = Mission.RTB
	print("[EnemyVirtualPlatoon] %s dematerialized → RTB" % platoon_name)


# ── Mission orders ────────────────────────────────────────────────────────────

func set_mission_patrol() -> void:
	mission = Mission.PATROL
	if vstate == VState.ACTIVE:
		_apply_mission_to_platoon()


func set_mission_attack_carrier() -> void:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier and is_instance_valid(carrier):
		attack_position = carrier.global_position
	mission = Mission.ATTACK_CARRIER
	if vstate == VState.ACTIVE:
		_apply_mission_to_platoon()


func set_mission_attack_position(target: Vector3) -> void:
	attack_position = target
	mission         = Mission.ATTACK_POSITION
	if vstate == VState.ACTIVE:
		_apply_mission_to_platoon()


func set_mission_rtb() -> void:
	mission = Mission.RTB
	if vstate == VState.ACTIVE:
		_apply_mission_to_platoon()


# ── Proximity helpers ─────────────────────────────────────────────────────────

func _nearest_friendly_distance() -> float:
	var tree := get_tree()
	if tree == null:
		return INF
	var best_sq := INF
	var carrier := tree.get_first_node_in_group("carrier") as Node3D
	if carrier and is_instance_valid(carrier):
		best_sq = minf(best_sq, position.distance_squared_to(carrier.global_position))
	for aircraft in _get_friendly_air_nodes():
		best_sq = minf(best_sq, position.distance_squared_to(aircraft.global_position))
	for node in tree.get_nodes_in_group("ground_vehicles"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		if (node as Node3D).is_in_group("enemies"):
			continue
		best_sq = minf(best_sq, position.distance_squared_to((node as Node3D).global_position))
	return sqrt(best_sq)


func _get_friendly_air_nodes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var tree := get_tree()
	if tree == null:
		return result
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft", "friendlies"]:
		for node in tree.get_nodes_in_group(group_name):
			if not is_instance_valid(node) or not (node is Node3D):
				continue
			var aircraft := node as Node3D
			if aircraft.is_in_group("enemies"):
				continue
			var id := aircraft.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			result.append(aircraft)
	return result


# ── Origin shift ──────────────────────────────────────────────────────────────

func apply_origin_shift(offset: Vector3) -> void:
	position        -= offset
	home_position   -= offset
	attack_position -= offset
	for i in range(_patrol_waypoints.size()):
		_patrol_waypoints[i] -= offset
	for r in _pending_reports:
		r["position"] = (r["position"] as Vector3) - offset
