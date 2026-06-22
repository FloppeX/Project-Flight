extends Node3D

const WIND_TURBINE_PROXY_SCRIPT: Script = preload("res://Buildings/WindTurbineProxy.gd")
const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")
const TEST_SCENARIO_SETTINGS_PATH := "user://physical_test_scenario.json"
const HELI_NAVIGATION_TEST_SCENARIO: int = 1

var restart_timer: Timer

@export var auto_place_carrier_on_flat_ground: bool = false
@export var carrier_node_path: NodePath = NodePath("LandCarrier")
@export var terrain_node_path: NodePath = NodePath("LowPolyTerrainPrototype")
@export var randomize_play_area_each_run: bool = true
@export var play_area_center_edge_margin_m: float = 2000.0
@export var play_area_randomization_debug: bool = false
# A known-good, deterministic region for navigation evolution. The terrain seed is
# already fixed by Main_Scene; fixing the bake center makes the actual test map fixed.
@export var navigation_test_fixed_play_area_xz := Vector2(25520.0, -27880.0)
@export var carrier_center_search_radius_m: float = 1400.0
@export var carrier_search_step_m: float = 120.0
@export var carrier_flat_probe_radius_m: float = 140.0
@export var carrier_ground_clearance_m: float = 40.0  # Carrier root floats 40m above terrain (tread ride height)
@export var carrier_placement_debug: bool = false

@export_group("Frame Profiler")
@export var frame_profiler_enabled: bool = false
@export var frame_profiler_report_interval_s: float = 1.0
@export var frame_profiler_summary_interval_s: float = 10.0
@export var frame_profiler_spike_threshold_ms: float = 8.0
@export var frame_profiler_top_count: int = 8

@export_group("Wind Turbines")
@export var spawn_wind_turbines_on_startup: bool = true
@export var wind_turbine_scene: PackedScene = preload("res://Buildings/building_wind_turbine.tscn")
@export var wind_turbine_team: int = 2
@export var wind_turbine_total_count: int = 25
@export var wind_turbine_group_min_size: int = 3
@export var wind_turbine_group_max_size: int = 4
@export var wind_turbine_activation_distance_m: float = 3000.0
@export var wind_turbine_deactivation_distance_m: float = 4000.0
@export var wind_turbine_activation_check_interval_s: float = 1.5
@export var wind_turbine_map_margin_m: float = 1200.0
@export var wind_turbine_min_start_distance_m: float = 2200.0
@export var wind_turbine_min_elevation_above_low_m: float = 160.0
@export var wind_turbine_max_group_height_span_m: float = 90.0
@export var wind_turbine_max_slope_delta_m: float = 55.0
@export var wind_turbine_min_neighbor_spacing_m: float = 80.0
@export var wind_turbine_max_neighbor_spacing_m: float = 120.0
@export var wind_turbine_group_search_attempts: int = 180
@export var wind_turbine_guard_emplacement_scene: PackedScene = preload("res://Buildings/gun_emplacement.tscn")
@export var dummy_emplacement_scene: PackedScene = preload("res://Buildings/dummy_gun_emplacement.tscn")
@export var wind_turbine_guard_emplacements_min: int = 2
@export var wind_turbine_guard_emplacements_max: int = 3
@export var wind_turbine_guard_min_distance_m: float = 140.0
@export var wind_turbine_guard_max_distance_m: float = 280.0
@export var wind_turbine_guard_activation_distance_m: float = 1700.0
@export var wind_turbine_guard_search_attempts: int = 32
@export var wind_turbine_spawn_debug: bool = false

var _scenario_play_area_center: Vector3 = Vector3.ZERO
var _scenario_play_area_center_valid: bool = false
var _wind_turbines_spawned: bool = false
var _wind_turbine_rng := RandomNumberGenerator.new()

func _enter_tree() -> void:
	_configure_play_area_for_run()

func _ready():
	Engine.time_scale = 1.0
	add_to_group("origin_shifter")
	_reset_helicopter_log()
	FrameProfiler.configure(frame_profiler_report_interval_s, frame_profiler_spike_threshold_ms, frame_profiler_top_count, frame_profiler_summary_interval_s)
	FrameProfiler.set_enabled(frame_profiler_enabled, "ScenarioManager")
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
	if spawn_wind_turbines_on_startup:
		_schedule_startup_wind_turbines()


func disable_structures_for_navigation_test() -> void:
	# The navigation range measures terrain following, not obstacle avoidance.
	# Cancel both immediate and bake-deferred turbine generation; scene reload
	# restores the exported normal-game setting.
	spawn_wind_turbines_on_startup = false
	_wind_turbines_spawned = true
	var spawn_callback := Callable(self, "_spawn_startup_wind_turbine_groups")
	if TerrainNavGrid.bake_complete.is_connected(spawn_callback):
		TerrainNavGrid.bake_complete.disconnect(spawn_callback)
	var root := get_tree().current_scene
	if root != null:
		var turbine_container := root.get_node_or_null("WindTurbines")
		if is_instance_valid(turbine_container):
			turbine_container.queue_free()


func _input(_event):
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()


func _process(delta: float) -> void:
	FrameProfiler.configure(frame_profiler_report_interval_s, frame_profiler_spike_threshold_ms, frame_profiler_top_count, frame_profiler_summary_interval_s)
	FrameProfiler.tick(delta)


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
	var navigation_test_requested := _is_navigation_test_requested()
	if navigation_test_requested:
		center.x = navigation_test_fixed_play_area_xz.x
		center.z = navigation_test_fixed_play_area_xz.y
	elif randomize_play_area_each_run:
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
	elif navigation_test_requested:
		print("[ScenarioManager] Navigation test fixed play area center set to ", center)


func _is_navigation_test_requested() -> bool:
	if not FileAccess.file_exists(TEST_SCENARIO_SETTINGS_PATH):
		return false
	var file := FileAccess.open(TEST_SCENARIO_SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed is Dictionary \
			and int((parsed as Dictionary).get("scenario", -1)) == HELI_NAVIGATION_TEST_SCENARIO


func _schedule_startup_wind_turbines() -> void:
	if _wind_turbines_spawned:
		return
	if TerrainNavGrid.is_ready():
		call_deferred("_spawn_startup_wind_turbine_groups")
	elif not TerrainNavGrid.bake_complete.is_connected(_spawn_startup_wind_turbine_groups):
		TerrainNavGrid.bake_complete.connect(_spawn_startup_wind_turbine_groups, CONNECT_ONE_SHOT)


func _spawn_startup_wind_turbine_groups() -> void:
	if _wind_turbines_spawned or wind_turbine_scene == null or not TerrainNavGrid.is_ready():
		return
	_wind_turbines_spawned = true
	_wind_turbine_rng.randomize()

	var root := get_tree().current_scene
	if root == null:
		return

	var container := root.get_node_or_null("WindTurbines") as Node3D
	if container == null:
		container = Node3D.new()
		container.name = "WindTurbines"
		root.add_child(container)

	var group_sizes: Array[int] = _build_wind_turbine_group_sizes(
		wind_turbine_total_count,
		wind_turbine_group_min_size,
		wind_turbine_group_max_size
	)
	var avoid_pos: Vector3 = _get_wind_turbine_start_avoid_position()
	var group_centers: Array[Vector3] = []
	var spawned_count: int = 0

	for group_size in group_sizes:
		var positions: Array[Vector3] = _find_wind_turbine_group_positions(group_size, avoid_pos, group_centers)
		if positions.is_empty():
			push_warning("[ScenarioManager] Could not find elevated ground for wind turbine group of %d" % group_size)
			continue

		var center := Vector3.ZERO
		for pos in positions:
			center += pos
		center /= float(positions.size())
		group_centers.append(center)

		for pos in positions:
			var proxy := WIND_TURBINE_PROXY_SCRIPT.new() as Node3D
			if proxy == null:
				continue
			proxy.name = "WindTurbineProxy_%02d" % spawned_count
			var yaw: float = _wind_turbine_rng.randf_range(-PI, PI)
			proxy.set("turbine_scene", wind_turbine_scene)
			proxy.set("team", wind_turbine_team)
			proxy.set("activation_distance_m", wind_turbine_activation_distance_m)
			proxy.set("deactivation_distance_m", wind_turbine_deactivation_distance_m)
			proxy.set("check_interval_s", wind_turbine_activation_check_interval_s)
			container.add_child(proxy)
			proxy.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
			spawned_count += 1

		_spawn_wind_turbine_guard_emplacements(container, center, positions)

	if wind_turbine_spawn_debug:
		print("[ScenarioManager] Wind turbine proxies placed: %d/%d in %d groups" % [
			spawned_count,
			wind_turbine_total_count,
			group_centers.size()
		])


func _build_wind_turbine_group_sizes(total_count: int, min_size: int, max_size: int) -> Array[int]:
	var sizes: Array[int] = []
	var total: int = maxi(total_count, 0)
	if total <= 0:
		return sizes

	var group_min: int = maxi(min_size, 1)
	var group_max: int = maxi(max_size, group_min)
	if total < group_min:
		sizes.append(total)
		return sizes

	var group_count: int = maxi(1, int(ceil(float(total) / float(group_max))))
	while group_count > 1 and group_count * group_min > total:
		group_count -= 1

	for _i in range(group_count):
		sizes.append(group_min)

	var assigned: int = group_count * group_min
	var safety: int = 0
	while assigned < total and safety < 10000:
		safety += 1
		var index: int = _wind_turbine_rng.randi_range(0, sizes.size() - 1)
		if sizes[index] >= group_max:
			continue
		sizes[index] += 1
		assigned += 1

	sizes.shuffle()
	return sizes


func _find_wind_turbine_group_positions(group_size: int, avoid_pos: Vector3, existing_centers: Array[Vector3]) -> Array[Vector3]:
	var attempts: int = maxi(wind_turbine_group_search_attempts, 1)
	var best_positions: Array[Vector3] = []
	var best_score: float = -INF

	for _attempt in range(attempts):
		var center_xz: Vector2 = _pick_wind_turbine_group_center_xz()
		if center_xz == Vector2.INF:
			continue
		var center_height: float = TerrainNavGrid.sample_height(center_xz.x, center_xz.y)
		if center_height <= TerrainNavGrid.IMPASSABLE * 0.5:
			continue

		var center := Vector3(center_xz.x, center_height, center_xz.y)
		if _is_wind_turbine_group_too_close(center, avoid_pos, existing_centers):
			continue

		var candidate_positions: Array[Vector3] = _make_wind_turbine_cluster_ring(center, group_size)
		var result: Dictionary = _evaluate_wind_turbine_group(candidate_positions, avoid_pos)
		if not bool(result.get("valid", false)):
			continue

		var score: float = float(result.get("score", -INF))
		var placed_positions: Array[Vector3] = result.get("positions", [])
		if score > best_score:
			best_score = score
			best_positions = placed_positions

	return best_positions


func _pick_wind_turbine_group_center_xz() -> Vector2:
	if TerrainNavGrid._cols <= 1 or TerrainNavGrid._rows <= 1:
		return Vector2.INF

	var span_x: float = float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m
	var span_z: float = float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	var margin: float = clampf(wind_turbine_map_margin_m, 0.0, minf(span_x, span_z) * 0.45)
	var min_x: float = TerrainNavGrid._origin_x + margin
	var max_x: float = TerrainNavGrid._origin_x + span_x - margin
	var min_z: float = TerrainNavGrid._origin_z + margin
	var max_z: float = TerrainNavGrid._origin_z + span_z - margin
	if min_x >= max_x or min_z >= max_z:
		return Vector2.INF

	return Vector2(
		_wind_turbine_rng.randf_range(min_x, max_x),
		_wind_turbine_rng.randf_range(min_z, max_z)
	)


func _is_wind_turbine_group_too_close(center: Vector3, avoid_pos: Vector3, existing_centers: Array[Vector3]) -> bool:
	var min_start_dist: float = maxf(wind_turbine_min_start_distance_m, wind_turbine_activation_distance_m + 200.0)
	if avoid_pos != Vector3.INF and _xz_distance(center, avoid_pos) < min_start_dist:
		return true

	var min_group_spacing: float = maxf(wind_turbine_activation_distance_m * 0.35, 500.0)
	for existing in existing_centers:
		if _xz_distance(center, existing) < min_group_spacing:
			return true
	return false


func _make_wind_turbine_cluster_ring(center: Vector3, group_size: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var count: int = maxi(group_size, 1)
	if count == 1:
		positions.append(center)
		return positions

	var min_spacing: float = maxf(wind_turbine_min_neighbor_spacing_m, 1.0)
	var max_spacing: float = maxf(wind_turbine_max_neighbor_spacing_m, min_spacing)
	var forward_angle: float = _wind_turbine_rng.randf_range(-PI, PI)
	var forward := Vector3(cos(forward_angle), 0.0, sin(forward_angle))
	var right := Vector3(-forward.z, 0.0, forward.x)
	var chain_offsets: Array[float] = []
	var total_length: float = 0.0
	for i in range(count):
		chain_offsets.append(total_length)
		if i < count - 1:
			total_length += _wind_turbine_rng.randf_range(min_spacing, max_spacing)
	var center_offset: float = total_length * 0.5
	var bend_step: float = _wind_turbine_rng.randf_range(-18.0, 18.0)
	for i in range(count):
		var along: float = chain_offsets[i] - center_offset
		var lateral: float = (float(i) - float(count - 1) * 0.5) * bend_step
		positions.append(center + forward * along + right * lateral)
	return positions


func _evaluate_wind_turbine_group(positions: Array[Vector3], avoid_pos: Vector3) -> Dictionary:
	if positions.is_empty():
		return {"valid": false}

	var placed_positions: Array[Vector3] = []
	var min_h: float = INF
	var max_h: float = -INF
	var sum_h: float = 0.0
	var min_allowed_h: float = TerrainNavGrid._h_min_passable + maxf(wind_turbine_min_elevation_above_low_m, 0.0)

	for pos in positions:
		if avoid_pos != Vector3.INF and _xz_distance(pos, avoid_pos) < wind_turbine_min_start_distance_m:
			return {"valid": false}

		var h: float = TerrainNavGrid.sample_height(pos.x, pos.z)
		if h <= TerrainNavGrid.IMPASSABLE * 0.5:
			return {"valid": false}

		var grid: Vector2i = _wind_turbine_world_to_grid(pos)
		if TerrainNavGrid.is_cell_near_steep_slope(grid.x, grid.y, wind_turbine_max_slope_delta_m, 1):
			return {"valid": false}

		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
		sum_h += h
		placed_positions.append(Vector3(pos.x, h, pos.z))

	if min_h < min_allowed_h:
		return {"valid": false}
	if max_h - min_h > wind_turbine_max_group_height_span_m:
		return {"valid": false}
	if not _wind_turbine_group_spacing_is_valid(placed_positions):
		return {"valid": false}

	var avg_h: float = sum_h / float(placed_positions.size())
	return {
		"valid": true,
		"positions": placed_positions,
		"score": avg_h - (max_h - min_h) * 0.25,
	}


func _wind_turbine_group_spacing_is_valid(positions: Array[Vector3]) -> bool:
	var min_spacing: float = maxf(wind_turbine_min_neighbor_spacing_m, 1.0)
	var max_spacing: float = maxf(wind_turbine_max_neighbor_spacing_m, min_spacing)
	for i in range(positions.size()):
		var nearest_dist: float = INF
		for j in range(i + 1, positions.size()):
			var dist: float = _xz_distance(positions[i], positions[j])
			nearest_dist = minf(nearest_dist, dist)
		for j in range(0, i):
			var dist: float = _xz_distance(positions[i], positions[j])
			nearest_dist = minf(nearest_dist, dist)
		if nearest_dist < min_spacing or nearest_dist > max_spacing:
			return false
	return true


func _spawn_wind_turbine_guard_emplacements(container: Node3D, group_center: Vector3, turbine_positions: Array[Vector3]) -> void:
	if wind_turbine_guard_emplacement_scene == null:
		return
	var min_count: int = maxi(wind_turbine_guard_emplacements_min, 0)
	var max_count: int = maxi(wind_turbine_guard_emplacements_max, min_count)
	var guard_count: int = _wind_turbine_rng.randi_range(min_count, max_count)
	for guard_idx in range(guard_count):
		var guard_pos: Vector3 = _find_wind_turbine_guard_position(group_center, turbine_positions, guard_idx, guard_count)
		if guard_pos == Vector3.INF:
			continue
		var guard := wind_turbine_guard_emplacement_scene.instantiate() as Node3D
		if guard == null:
			continue
		guard.name = "WindFarmGuard_%02d" % guard_idx
		if "team" in guard:
			guard.set("team", wind_turbine_team)
		if "activation_distance_m" in guard:
			guard.set("activation_distance_m", wind_turbine_guard_activation_distance_m)
		container.add_child(guard)
		var yaw: float = _wind_turbine_rng.randf_range(-PI, PI)
		guard.global_transform = Transform3D(Basis(Vector3.UP, yaw), guard_pos)
		if guard.has_method("snap_collider_to_ground"):
			guard.call_deferred("snap_collider_to_ground")


func _find_wind_turbine_guard_position(group_center: Vector3, turbine_positions: Array[Vector3], guard_idx: int, guard_count: int) -> Vector3:
	var attempts: int = maxi(wind_turbine_guard_search_attempts, 1)
	var base_angle: float = TAU * float(guard_idx) / float(maxi(guard_count, 1)) + _wind_turbine_rng.randf_range(-0.45, 0.45)
	for attempt in range(attempts):
		var angle: float = base_angle + _wind_turbine_rng.randf_range(-0.9, 0.9)
		var dist: float = _wind_turbine_rng.randf_range(
			maxf(wind_turbine_guard_min_distance_m, 20.0),
			maxf(wind_turbine_guard_max_distance_m, wind_turbine_guard_min_distance_m)
		)
		var candidate := Vector3(
			group_center.x + cos(angle) * dist,
			group_center.y,
			group_center.z + sin(angle) * dist
		)
		var h: float = TerrainNavGrid.sample_height(candidate.x, candidate.z)
		if h <= TerrainNavGrid.IMPASSABLE * 0.5:
			continue
		candidate.y = h
		var grid: Vector2i = _wind_turbine_world_to_grid(candidate)
		if TerrainNavGrid.is_cell_near_steep_slope(grid.x, grid.y, wind_turbine_max_slope_delta_m, 1):
			continue
		if _is_guard_too_close_to_turbines(candidate, turbine_positions):
			continue
		return candidate
	return Vector3.INF


func _is_guard_too_close_to_turbines(candidate: Vector3, turbine_positions: Array[Vector3]) -> bool:
	var min_clearance: float = maxf(wind_turbine_min_neighbor_spacing_m * 0.75, 55.0)
	for turbine_pos in turbine_positions:
		if _xz_distance(candidate, turbine_pos) < min_clearance:
			return true
	return false


func _wind_turbine_world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(round((world_pos.x - TerrainNavGrid._origin_x) / TerrainNavGrid.cell_size_m)),
		int(round((world_pos.z - TerrainNavGrid._origin_z) / TerrainNavGrid.cell_size_m))
	)


func _get_wind_turbine_start_avoid_position() -> Vector3:
	var carrier := get_node_or_null(carrier_node_path) as Node3D
	if carrier != null and is_instance_valid(carrier):
		return carrier.global_position
	if _scenario_play_area_center_valid:
		return _scenario_play_area_center
	return Vector3.INF


func _xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

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


func _reset_helicopter_log() -> void:
	var log_path := "user://heli_crash_report.log"
	var f := FileAccess.open(log_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("HELICOPTER FLIGHT LOG — session started %s" % Time.get_datetime_string_from_system())
	f.store_line("%-20s  %-30s  %-10s  %s" % ["Aircraft", "Type", "Outcome", "Notes"])
	f.store_line("-".repeat(100))
	f.close()
