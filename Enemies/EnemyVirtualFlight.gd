class_name EnemyVirtualFlight
extends Node
## Abstract representation of an enemy flight on the tactical map.
## Moves as data until a friendly asset comes within ACTIVATE_RANGE_M,
## then spawns real aircraft. When they retreat beyond DEACTIVATE_RANGE_M
## from all friendly assets, aircraft are removed and the flight resumes
## as a map marker.

enum Mission { PATROL, RTB, LANDED }
enum VState  { VIRTUAL, ACTIVE }

const ACTIVATE_RANGE_M   := 2000.0
const DEACTIVATE_RANGE_M := 3500.0
const PATROL_SPEED_MPS   := 82.0
const RTB_SPEED_MPS      := 95.0
const PATROL_ALTITUDE_M  := 680.0

# Configuration (set before adding to tree)
@export var flight_name:    String  = "XX-01"
@export var aircraft_count: int     = 2
@export var patrol_radius:  float   = 4000.0
@export var faction_color:  Color   = Color.WHITE

# Runtime state
var position:      Vector3 = Vector3.ZERO
var heading:       Vector3 = Vector3(1, 0, 0)
var home_position: Vector3 = Vector3.ZERO
var mission:       Mission = Mission.PATROL
var vstate:        VState  = VState.VIRTUAL
var active_aircraft: Array[Node3D] = []

var _patrol_angle:    float = 0.0
var _aircraft_scene:  PackedScene = null


func setup(home_pos: Vector3, scene: PackedScene, start_angle: float = 0.0) -> void:
	home_position = home_pos
	_aircraft_scene = scene
	_patrol_angle = start_angle
	position = Vector3(
		home_pos.x + cos(start_angle) * patrol_radius,
		home_pos.y + PATROL_ALTITUDE_M,
		home_pos.z + sin(start_angle) * patrol_radius
	)
	heading = Vector3(-sin(start_angle), 0.0, cos(start_angle)).normalized()


func tick(delta: float) -> void:
	# Purge freed references
	active_aircraft = active_aircraft.filter(func(a): return is_instance_valid(a))

	if vstate == VState.ACTIVE:
		if active_aircraft.is_empty():
			# All aircraft destroyed — flight wiped out
			vstate = VState.VIRTUAL
			aircraft_count = 0
			return
		# Track lead position so the map marker follows the real aircraft
		position = (active_aircraft[0] as Node3D).global_position
		_check_dematerialize()
		return

	if aircraft_count <= 0:
		return

	# Abstract movement
	match mission:
		Mission.PATROL: _tick_patrol(delta)
		Mission.RTB:    _tick_rtb(delta)
		Mission.LANDED: pass

	_check_materialize()


func _tick_patrol(delta: float) -> void:
	_patrol_angle += (PATROL_SPEED_MPS / maxf(patrol_radius, 100.0)) * delta
	position.x = home_position.x + cos(_patrol_angle) * patrol_radius
	position.z = home_position.z + sin(_patrol_angle) * patrol_radius
	position.y = home_position.y + PATROL_ALTITUDE_M
	heading = Vector3(-sin(_patrol_angle), 0.0, cos(_patrol_angle)).normalized()


func _tick_rtb(delta: float) -> void:
	var target := home_position + Vector3(0.0, PATROL_ALTITUDE_M, 0.0)
	var to_base := target - position
	if to_base.length() < 250.0:
		mission = Mission.LANDED
		position = home_position
		return
	var dir := to_base.normalized()
	position += dir * RTB_SPEED_MPS * delta
	heading = Vector3(dir.x, 0.0, dir.z).normalized()


func _check_materialize() -> void:
	if _aircraft_scene == null or vstate == VState.ACTIVE:
		return
	var nearest := _nearest_friendly_distance()
	if nearest <= ACTIVATE_RANGE_M:
		_materialize()


func _check_dematerialize() -> void:
	if _nearest_friendly_distance() > DEACTIVATE_RANGE_M:
		dematerialize()


func _materialize() -> void:
	if _aircraft_scene == null or vstate == VState.ACTIVE:
		return
	vstate = VState.ACTIVE
	var scene_root := get_tree().current_scene
	for i in range(aircraft_count):
		var ac := _aircraft_scene.instantiate() as Node3D
		if ac == null:
			continue
		scene_root.add_child(ac)
		ac.set_meta("faction_color", faction_color)
		var spread := Vector3(
			cos(float(i) * TAU / float(maxi(aircraft_count, 1))) * 110.0,
			float(i) * 30.0,
			sin(float(i) * TAU / float(maxi(aircraft_count, 1))) * 110.0
		)
		ac.global_position = position + spread
		if "linear_velocity" in ac:
			ac.set("linear_velocity", heading * 75.0)
		active_aircraft.append(ac)
	print("[EnemyVirtualFlight] %s materialized (%d ac) at %.0f,%.0f" % [
		flight_name, aircraft_count, position.x, position.z])


func dematerialize() -> void:
	for ac in active_aircraft:
		if is_instance_valid(ac):
			ac.queue_free()
	active_aircraft.clear()
	vstate = VState.VIRTUAL
	mission = Mission.RTB
	print("[EnemyVirtualFlight] %s dematerialized → RTB" % flight_name)


func _nearest_friendly_distance() -> float:
	var tree := get_tree()
	if tree == null:
		return INF
	var best_sq := INF

	var carrier := tree.get_first_node_in_group("carrier") as Node3D
	if carrier and is_instance_valid(carrier):
		best_sq = minf(best_sq, position.distance_squared_to(carrier.global_position))

	for ac in tree.get_nodes_in_group("aircraft"):
		if not (ac is Node3D) or not is_instance_valid(ac as Node3D):
			continue
		if (ac as Node3D).is_in_group("enemies"):
			continue
		best_sq = minf(best_sq, position.distance_squared_to((ac as Node3D).global_position))

	return sqrt(best_sq)


func apply_origin_shift(offset: Vector3) -> void:
	position      -= offset
	home_position -= offset
