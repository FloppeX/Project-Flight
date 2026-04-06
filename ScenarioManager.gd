extends Node3D

var restart_timer: Timer

@export var auto_place_carrier_on_flat_ground: bool = false
@export var carrier_node_path: NodePath = NodePath("LandCarrier")
@export var terrain_node_path: NodePath = NodePath("LowPolyTerrainPrototype")
@export var randomize_play_area_each_run: bool = true
@export var play_area_center_edge_margin_m: float = 2000.0
@export var play_area_randomization_debug: bool = false
@export var carrier_center_search_radius_m: float = 1400.0
@export var carrier_search_step_m: float = 120.0
@export var carrier_flat_probe_radius_m: float = 140.0
@export var carrier_ground_clearance_m: float = 40.0  # Carrier root floats 40m above terrain (tread ride height)
@export var carrier_placement_debug: bool = false

var _scenario_play_area_center: Vector3 = Vector3.ZERO
var _scenario_play_area_center_valid: bool = false

func _enter_tree() -> void:
	_configure_play_area_for_run()

func _ready():
	add_to_group("origin_shifter")
	if not _scenario_play_area_center_valid:
		_configure_play_area_for_run()
	# Find any player aircraft (Aircraft_1, Aircraft_3, Aircraft_5, etc.)
	var aircraft: Node = null
	for child in get_children():
		if child is RigidBody3D and child.is_in_group("aircraft") and not child.is_in_group("ai_aircraft"):
			aircraft = child
			break
	if aircraft == null:
		# Fallback: try known names
		for name_candidate in ["Aircraft_1", "Aircraft_3", "Aircraft_5"]:
			aircraft = find_child(name_candidate)
			if aircraft:
				break
	if aircraft:
		if aircraft.has_signal("destroyed"):
			aircraft.destroyed.connect(_on_aircraft_destroyed)
		if aircraft.has_signal("crashed"):
			aircraft.crashed.connect(_on_aircraft_crashed)
	if auto_place_carrier_on_flat_ground:
		call_deferred("_place_carrier_on_flat_ground")


func _input(_event):
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()


func apply_origin_shift(offset: Vector3) -> void:
	if _scenario_play_area_center_valid:
		_scenario_play_area_center -= offset


func _on_aircraft_destroyed():
	print("Aircraft destroyed! Restarting scene in 10 seconds...")
	restart_scene_after_delay(10.0)


func _on_aircraft_crashed(impact_velocity: float):
	if impact_velocity > 15.0:
		print("Aircraft crashed hard! Restarting scene in 3 seconds...")
		restart_scene_after_delay(3.0)


func restart_scene_after_delay(delay_seconds: float):
	if restart_timer:
		restart_timer.queue_free()

	restart_timer = Timer.new()
	add_child(restart_timer)
	restart_timer.one_shot = true
	restart_timer.timeout.connect(restart_scene)
	restart_timer.start(delay_seconds)


func restart_scene():
	get_tree().reload_current_scene()


func _place_carrier_on_flat_ground() -> void:
	var carrier := get_node_or_null(carrier_node_path) as Node3D
	var terrain := get_node_or_null(terrain_node_path) as Node3D
	if not carrier or not terrain or not terrain.has_method("get_height"):
		return

	var center: Vector3 = _scenario_play_area_center if _scenario_play_area_center_valid else terrain.global_position
	var radius: float = maxf(carrier_center_search_radius_m, 0.0)
	var step: float = maxf(carrier_search_step_m, 20.0)
	var probe: float = maxf(carrier_flat_probe_radius_m, step * 0.5)
	var radius_sq: float = radius * radius

	var best_score: float = INF
	var best_ground_y: float = NAN
	var best_xz: Vector2 = Vector2(center.x, center.z)
	var x: float = -radius
	while x <= radius + 0.001:
		var z: float = -radius
		while z <= radius + 0.001:
			if (x * x + z * z) <= radius_sq:
				var sample_x: float = center.x + x
				var sample_z: float = center.z + z
				var eval: Dictionary = _evaluate_terrain_flatness(terrain, sample_x, sample_z, probe)
				if eval.get("valid", false):
					var score: float = float(eval.get("score", INF))
					if score < best_score:
						best_score = score
						best_ground_y = float(eval.get("ground_y", NAN))
						best_xz = Vector2(sample_x, sample_z)
			z += step
		x += step

	if is_nan(best_ground_y):
		var fallback_ground: float = _sample_terrain_world_height(terrain, center.x, center.z)
		if is_nan(fallback_ground):
			return
		best_ground_y = fallback_ground
		best_xz = Vector2(center.x, center.z)

	carrier.global_position = Vector3(best_xz.x, best_ground_y + carrier_ground_clearance_m, best_xz.y)
	if carrier_placement_debug:
		print("[Main_Scene] Carrier placed on flat ground at ", carrier.global_position, " (score=", snapped(best_score, 0.01), ")")

func _configure_play_area_for_run() -> void:
	var terrain := get_node_or_null(terrain_node_path) as Node3D
	if terrain == null:
		return

	var center: Vector3 = terrain.global_position
	if randomize_play_area_each_run:
		center = _pick_random_play_area_center(terrain)
	center = _snap_play_area_center_to_nav_grid(center)

	_scenario_play_area_center = center
	_scenario_play_area_center_valid = true
	var current_bake_center: Vector3 = TerrainNavGrid.get_bake_center()
	var needs_rebake: bool = TerrainNavGrid.is_ready() and current_bake_center.distance_to(center) > 0.1
	if needs_rebake:
		TerrainNavGrid.rebake_at_center(center)
		NavGraph.rebuild_from_current_navgrid()
	else:
		TerrainNavGrid.set_bake_center_override(center)

	if play_area_randomization_debug:
		print("[ScenarioManager] Play area center set to ", center)

func _pick_random_play_area_center(terrain: Node3D) -> Vector3:
	var quads_x_variant = terrain.get("quads_x")
	var quads_z_variant = terrain.get("quads_z")
	var cell_size_variant = terrain.get("cell_size_m")
	var terrain_quads_x: int = int(quads_x_variant) if quads_x_variant != null else 0
	var terrain_quads_z: int = int(quads_z_variant) if quads_z_variant != null else 0
	var terrain_cell_size_m: float = float(cell_size_variant) if cell_size_variant != null else 0.0
	if terrain_quads_x <= 0 or terrain_quads_z <= 0 or terrain_cell_size_m <= 0.0:
		return terrain.global_position

	var terrain_half_span_x: float = float(terrain_quads_x) * terrain_cell_size_m * 0.5
	var terrain_half_span_z: float = float(terrain_quads_z) * terrain_cell_size_m * 0.5
	var required_margin_x: float = TerrainNavGrid.bake_half_extent_m + maxf(play_area_center_edge_margin_m, 0.0)
	var required_margin_z: float = TerrainNavGrid.bake_half_extent_m + maxf(play_area_center_edge_margin_m, 0.0)
	var max_offset_x: float = terrain_half_span_x - required_margin_x
	var max_offset_z: float = terrain_half_span_z - required_margin_z
	if max_offset_x <= 0.0 or max_offset_z <= 0.0:
		return terrain.global_position

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return Vector3(
		terrain.global_position.x + rng.randf_range(-max_offset_x, max_offset_x),
		terrain.global_position.y,
		terrain.global_position.z + rng.randf_range(-max_offset_z, max_offset_z)
	)

func _snap_play_area_center_to_nav_grid(center: Vector3) -> Vector3:
	var step_m: float = maxf(TerrainNavGrid.cell_size_m, 1.0)
	return Vector3(
		round(center.x / step_m) * step_m,
		center.y,
		round(center.z / step_m) * step_m
	)


func _evaluate_terrain_flatness(terrain: Node3D, x: float, z: float, probe_radius: float) -> Dictionary:
	var diag: float = probe_radius * 0.70710678
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(probe_radius, 0.0),
		Vector2(-probe_radius, 0.0),
		Vector2(0.0, probe_radius),
		Vector2(0.0, -probe_radius),
		Vector2(diag, diag),
		Vector2(-diag, diag),
		Vector2(diag, -diag),
		Vector2(-diag, -diag)
	]

	var heights: Array[float] = []
	for offset in offsets:
		var h: float = _sample_terrain_world_height(terrain, x + offset.x, z + offset.y)
		if is_nan(h):
			return {"valid": false}
		heights.append(h)

	var center_h: float = heights[0]
	var min_h: float = center_h
	var max_h: float = center_h
	var sum_h: float = 0.0
	for h in heights:
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
		sum_h += h

	var avg_h: float = sum_h / float(heights.size())
	var span: float = max_h - min_h
	var center_bias: float = absf(avg_h - center_h)
	var score: float = span + center_bias * 0.5
	return {
		"valid": true,
		"score": score,
		"ground_y": center_h
	}


func _sample_terrain_world_height(terrain: Node3D, world_x: float, world_z: float) -> float:
	var world_query := Vector3(world_x, terrain.global_position.y, world_z)
	var sampled_height: Variant = terrain.call("get_height", world_query)
	if typeof(sampled_height) != TYPE_FLOAT:
		return NAN
	var world_height: float = float(sampled_height)
	if is_nan(world_height):
		return NAN
	return world_height
