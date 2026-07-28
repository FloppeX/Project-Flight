extends Node3D
class_name WindTurbineProxy

@export var turbine_scene: PackedScene
@export var team: int = 2
@export var activation_distance_m: float = 1200.0
@export var deactivation_distance_m: float = 1800.0
@export var check_interval_s: float = 1.5

var _check_timer_s: float = 0.0
var _activated: bool = false
var _active_turbine: Node3D = null
var _saved_health: float = -1.0


func _ready() -> void:
	add_to_group("wind_turbine_proxies")
	_set_marker_groups_enabled(true)
	_check_timer_s = randf_range(0.0, maxf(check_interval_s, 0.25))


func _process(delta: float) -> void:
	if _activated and (_active_turbine == null or not is_instance_valid(_active_turbine) or bool(_active_turbine.get("is_destroyed"))):
		# If the live turbine was destroyed by gameplay, do not later respawn it from the marker.
		queue_free()
		return

	_check_timer_s -= delta
	if _check_timer_s > 0.0:
		return
	_check_timer_s = maxf(check_interval_s, 0.25)

	var nearest_distance: float = _nearest_player_distance()
	if not is_finite(nearest_distance):
		return
	if not _activated and nearest_distance <= activation_distance_m:
		_activate()
	elif _activated and nearest_distance > maxf(deactivation_distance_m, activation_distance_m):
		_deactivate()


func _activate() -> void:
	if _activated or turbine_scene == null:
		return
	_activated = true
	_set_marker_groups_enabled(false)

	var turbine := turbine_scene.instantiate() as Node3D
	if turbine == null:
		_activated = false
		_set_marker_groups_enabled(true)
		queue_free()
		return
	if "team" in turbine:
		turbine.set("team", team)

	var parent := get_parent()
	if parent == null:
		parent = get_tree().current_scene
	parent.add_child(turbine)
	turbine.global_transform = global_transform
	if _saved_health >= 0.0 and "current_health" in turbine:
		turbine.set("current_health", _saved_health)
	_active_turbine = turbine


func _deactivate() -> void:
	if not _activated:
		return
	if _active_turbine != null and is_instance_valid(_active_turbine):
		global_transform = _active_turbine.global_transform
		if "current_health" in _active_turbine:
			_saved_health = float(_active_turbine.get("current_health"))
		_active_turbine.queue_free()
	_active_turbine = null
	_activated = false
	_set_marker_groups_enabled(true)


func get_team() -> int:
	return team


func is_activated() -> bool:
	return _activated


func _nearest_player_distance() -> float:
	var best_sq: float = INF
	var viewport := get_viewport()
	if viewport != null:
		var camera := viewport.get_camera_3d()
		if camera != null and is_instance_valid(camera):
			best_sq = minf(best_sq, global_position.distance_squared_to(camera.global_position))

	var seen: Dictionary = {}
	for group_name in ["aircraft", "friendlies", "carrier", "ground_vehicles"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is Node3D):
				continue
			var node_3d := node as Node3D
			if not is_instance_valid(node_3d):
				continue
			if node_3d.is_in_group("enemies") or node_3d.is_in_group("ai_aircraft"):
				continue
			var id := node_3d.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			best_sq = minf(best_sq, global_position.distance_squared_to(node_3d.global_position))

	return sqrt(best_sq)


func _set_marker_groups_enabled(enabled: bool) -> void:
	if enabled:
		add_to_group("buildings")
		add_to_group("team_" + str(team))
		if team == 1:
			add_to_group("friendlies")
		else:
			add_to_group("enemies")
	else:
		remove_from_group("buildings")
		remove_from_group("team_" + str(team))
		remove_from_group("friendlies")
		remove_from_group("enemies")
