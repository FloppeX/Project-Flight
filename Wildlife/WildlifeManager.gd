extends Node3D
class_name WildlifeManager

const VULTURE_SCENE: PackedScene = preload("res://Wildlife/CanyonVulture.tscn")

@export var enabled := true
@export_range(0.0, 1.0, 0.01) var encounter_chance := 0.22
@export var first_encounter_delay_s := 18.0
@export var encounter_check_interval_s := 180.0
@export var max_active_birds := 2
@export var spawn_distance_min_m := 450.0
@export var spawn_distance_max_m := 900.0
@export var altitude_above_terrain_min_m := 120.0
@export var altitude_above_terrain_max_m := 240.0

var _active_birds: Array[Node3D] = []
var _encounter_timer_s := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("wildlife_manager")
	_rng.randomize()
	_encounter_timer_s = first_encounter_delay_s
	set_process(enabled and not _is_development_scenario())


func _process(delta: float) -> void:
	_prune_birds()
	if _active_birds.size() >= max_active_birds:
		return
	_encounter_timer_s -= delta
	if _encounter_timer_s > 0.0:
		return
	_encounter_timer_s = encounter_check_interval_s
	if _rng.randf() <= encounter_chance:
		_spawn_encounter()


func _spawn_encounter() -> void:
	var camera := get_viewport().get_camera_3d()
	var terrain := TerrainReference.get_terrain_node()
	if camera == null or terrain == null or not terrain.has_method("get_height"):
		return
	var best_sample := _choose_canyon_sample(camera.global_position, terrain)
	if best_sample.is_empty():
		return
	var center: Vector3 = best_sample.center
	var highest_ground := float(best_sample.highest_ground)
	center.y = highest_ground + _rng.randf_range(
		altitude_above_terrain_min_m,
		altitude_above_terrain_max_m
	)
	var flock_size := 2 if max_active_birds >= 2 and _rng.randf() < 0.18 else 1
	for i in mini(flock_size, max_active_birds - _active_birds.size()):
		spawn_vulture(
			center + Vector3(0.0, float(i) * 8.0, 0.0),
			_rng.randf_range(140.0, 240.0),
			_rng.randf_range(0.0, TAU) + float(i) * 0.35,
			-1.0 if _rng.randf() < 0.5 else 1.0
		)


func _choose_canyon_sample(focus: Vector3, terrain: Node) -> Dictionary:
	var best: Dictionary = {}
	var best_relief := -INF
	for attempt in 12:
		var bearing := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(spawn_distance_min_m, spawn_distance_max_m)
		var center := focus + Vector3(cos(bearing) * distance, 0.0, sin(bearing) * distance)
		var lowest := INF
		var highest := -INF
		for sample_index in 8:
			var sample_angle := TAU * float(sample_index) / 8.0
			var sample_position := center + Vector3(cos(sample_angle), 0.0, sin(sample_angle)) * 220.0
			var height_variant: Variant = terrain.call("get_height", sample_position)
			if not (height_variant is float) or is_nan(float(height_variant)):
				continue
			lowest = minf(lowest, float(height_variant))
			highest = maxf(highest, float(height_variant))
		if highest == -INF:
			continue
		var relief := highest - lowest
		if relief > best_relief:
			best_relief = relief
			best = {"center": center, "highest_ground": highest, "relief": relief}
	return best


func spawn_vulture(center: Vector3, radius_m: float, start_angle: float, direction: float) -> Node3D:
	var bird := VULTURE_SCENE.instantiate() as Node3D
	if bird == null:
		return null
	add_child(bird)
	bird.configure_soaring(center, radius_m, start_angle, direction)
	bird.killed.connect(_on_vulture_killed)
	_active_birds.append(bird)
	return bird


func _on_vulture_killed(_bird: Node3D, attacker: Node) -> void:
	if not _is_player_attacker(attacker):
		return
	var approval := GameSession.record_wildlife_kill()
	CombatLog.event("CIV", "Protected canyon vulture killed; public approval now %d" % approval)
	RadioComms.transmit(
		"Citadel",
		"All units",
		"That was protected wildlife. Public approval has fallen to %d." % approval
	)


func _is_player_attacker(attacker: Node) -> bool:
	if attacker == null or not is_instance_valid(attacker):
		return false
	var node := attacker
	while node != null:
		if node.is_in_group("aircraft") and not node.is_in_group("ai_aircraft"):
			return true
		if FlightDirector != null and FlightDirector.get("player_controlled_plane") == node:
			return true
		node = node.get_parent()
	return false


func _prune_birds() -> void:
	var kept: Array[Node3D] = []
	for bird in _active_birds:
		if is_instance_valid(bird) and not bird.is_queued_for_deletion():
			kept.append(bird)
	_active_birds = kept


func _is_development_scenario() -> bool:
	if GameSession.is_trailer_scenario:
		return true
	const SETTINGS_PATH := "user://physical_test_scenario.json"
	if not FileAccess.file_exists(SETTINGS_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	return parsed is Dictionary and bool((parsed as Dictionary).get("enabled", false))
