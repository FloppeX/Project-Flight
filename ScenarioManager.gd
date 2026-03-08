extends Node3D

var restart_timer: Timer
@export var auto_place_carrier_on_flat_ground: bool = true
@export var carrier_node_path: NodePath = NodePath("LandCarrier")
@export var terrain_node_path: NodePath = NodePath("LowPolyTerrainPrototype")
@export var carrier_center_search_radius_m: float = 1400.0
@export var carrier_search_step_m: float = 120.0
@export var carrier_flat_probe_radius_m: float = 140.0
@export var carrier_ground_clearance_m: float = 32.0  # Carrier root floats 32m above terrain (tread ride height)
@export var carrier_placement_debug: bool = false

func _ready():
	# Find the aircraft and connect to its destruction signal
	var aircraft = find_child("Aircraft_1")
	if aircraft:
		aircraft.destroyed.connect(_on_aircraft_destroyed)
		aircraft.crashed.connect(_on_aircraft_crashed)
	if auto_place_carrier_on_flat_ground:
		call_deferred("_place_carrier_on_flat_ground")

func _input(event):
	if Input.is_action_just_pressed("ui_cancel"):  # ESC key
		get_tree().quit()

func _on_aircraft_destroyed():
	print("Aircraft destroyed! Restarting scene in 3 seconds...")
	restart_scene_after_delay(10.0)

func _on_aircraft_crashed(impact_velocity: float):
	# Only restart on hard crashes (high impact)
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

	var center: Vector3 = terrain.global_position
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
	var local_height: float = float(sampled_height)
	if is_nan(local_height):
		return NAN

	# LowPolyTerrain.get_height currently returns local-space Y; convert to world Y.
	var local_point: Vector3 = terrain.to_local(world_query)
	local_point.y = local_height
	return terrain.to_global(local_point).y
