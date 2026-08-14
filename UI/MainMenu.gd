extends Node3D

const MENU_FONT: FontFile = preload("res://UI/Orbitron-VariableFont_wght.ttf")
const MENU_TERRAIN_SCENE: PackedScene = preload("res://Environment/LowPolyTerrainPrototype.tscn")
const MENU_CARRIER_SCENE: PackedScene = preload("res://LandCarrier/LandCarrier2.tscn")
const GAME_SCENE := "res://Main_Scene.tscn"
const TEST_SCENARIO_SETTINGS_PATH := "user://physical_test_scenario.json"
const NORMAL_TEST_SCENARIO := 0
const LANDING_TEST_SCENARIO := 5
const CARRIER_COMBAT_TEST_SCENARIO := 6
const DEFAULT_CARRIER_NAME := "Land Carrier"
const SHIP_NAME_LIST_PATH := "res://Data/ShipNames.txt"
const MAP_IDS: Array[String] = ["open_canyons", "layered_badlands"]
const MAP_NAMES: Array[String] = ["OPEN CANYONS", "FRACTURED BADLANDS"]
const BASE_UI_SIZE := Vector2(1280.0, 720.0)
const CAMERA_LOOP_S := 56.0
const CARRIER_RIDE_HEIGHT_M := 40.0
const CAMERA_TERRAIN_CLEARANCE_M := 180.0
const SETUP_CAMERA_TERRAIN_CLEARANCE_M := 80.0
const INSIGNIA_CAMERA_TERRAIN_CLEARANCE_M := 16.0
const CAMERA_CARRIER_HEIGHT_M := 360.0
const CAMERA_CARRIER_BACK_M := 780.0
const CAMERA_CARRIER_SIDE_M := 520.0
const SETUP_CAMERA_HEIGHT_M := 135.0
const SETUP_CAMERA_BACK_M := 255.0
const SETUP_CAMERA_SIDE_M := 215.0
const INSIGNIA_CAMERA_HEIGHT_M := 2.0
const INSIGNIA_CAMERA_BACK_M := 20.0
const INSIGNIA_CAMERA_SIDE_M := 145.0
const MAIN_CAMERA_FOV := 48.0
const SETUP_CAMERA_FOV := 28.0
const INSIGNIA_CAMERA_FOV := 23.0
const CAMERA_FOV_BLEND := 0.010
const CAMERA_SETUP_BLEND := 0.018
const CAMERA_INSIGNIA_BLEND := 0.014
const SETUP_FRAME_POINT := Vector2(2.0 / 3.0, 0.5)
const ROUTE_SAMPLE_STEP_M := 90.0
const ROUTE_MAX_HEIGHT_SPAN_M := 70.0
const MENU_CARRIER_CLEARANCE_M := 120.0
const MENU_PATH_MAX_SLOPE_M := 12.0

const PAD_BUTTON_A := 0
const PAD_BUTTON_B := 1
const PAD_BUTTON_BACK := 4
const PAD_BUTTON_DPAD_UP := 11
const PAD_BUTTON_DPAD_DOWN := 12
const PAD_BUTTON_DPAD_LEFT := 13
const PAD_BUTTON_DPAD_RIGHT := 14

const DEFAULT_PRIMARY_COLOR_INDEX := 23
const DEFAULT_SECONDARY_COLOR_INDEX := 8
const FALLBACK_PATTERN_NAMES: Array[String] = ["SOLID", "STRIPES", "CHECKS", "CAMO"]
const FALLBACK_PATTERN_INDICES: Array[int] = [0, 1, 9, 4]

var _camera: Camera3D
var _path_follow: PathFollow3D
var _terrain: Node3D
var _carrier_root: Node3D
var _restored_autoloads := false
var _autoload_overrides: Array[Dictionary] = []
var _ui_root: Control
var _main_panel: Control
var _setup_panel: Control
var _message_label: Label
var _name_edit: LineEdit
var _carrier_colors: Array[Color] = []
var _carrier_color_names: Array[String] = []
var _ship_names: Array[String] = []
var _insignia_names: Array[String] = []
var _pattern_names: Array[String] = []
var _pattern_indices: Array[int] = []
var _primary_index := DEFAULT_PRIMARY_COLOR_INDEX
var _secondary_index := DEFAULT_SECONDARY_COLOR_INDEX
var _pattern_choice_index := 0
var _insignia_index := 0
var _map_index := 0
var _current_screen := ""
var _primary_value_button: Button
var _secondary_value_button: Button
var _pattern_value_button: Button
var _insignia_value_button: Button
var _map_value_button: Button
var _menu_rng := RandomNumberGenerator.new()
var _elapsed := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu_rng.randomize()
	_load_ship_names()
	_load_livery_palette()
	_randomize_setup_choices()
	_configure_menu_autoloads()
	_build_world()
	_build_ui()
	if not get_tree().root.size_changed.is_connected(_layout_ui_root):
		get_tree().root.size_changed.connect(_layout_ui_root)
	_layout_ui_root()
	_show_main_menu()


func _process(delta: float) -> void:
	_elapsed += delta
	if is_instance_valid(_path_follow):
		_path_follow.progress_ratio = fposmod(_elapsed / CAMERA_LOOP_S, 1.0)
	if is_instance_valid(_camera):
		_position_exterior_camera()
		var look_target := _camera_look_target()
		_camera.look_at(look_target, Vector3.UP)
		_apply_setup_screen_framing(look_target)
		_camera.fov = lerpf(_camera.fov, _target_camera_fov(), CAMERA_FOV_BLEND)
	_force_exterior_camera()


func _exit_tree() -> void:
	_restore_autoloads()


func _input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var pause_menu := get_node_or_null("/root/PauseMenu")
	if pause_menu != null and bool(pause_menu.get("visible")):
		return
	if _current_screen == "":
		return

	var focus_owner := viewport.gui_get_focus_owner()
	if focus_owner == null:
		focus_owner = _focus_first_button()

	if focus_owner is LineEdit:
		if _is_menu_back_event(event):
			_go_back()
			viewport.set_input_as_handled()
			return
		if _is_menu_accept_event(event) or _is_menu_down_event(event):
			_focus_first_button()
			viewport.set_input_as_handled()
			return
		if _is_menu_up_event(event):
			_focus_last_button()
			viewport.set_input_as_handled()
			return
		return

	if _is_menu_up_event(event):
		_move_focus(focus_owner, Side.SIDE_TOP)
		viewport.set_input_as_handled()
		return
	if _is_menu_down_event(event):
		_move_focus(focus_owner, Side.SIDE_BOTTOM)
		viewport.set_input_as_handled()
		return
	if _current_screen == "setup" and _is_menu_left_event(event):
		if _cycle_focused_setup_row(-1):
			viewport.set_input_as_handled()
			return
	if _current_screen == "setup" and _is_menu_right_event(event):
		if _cycle_focused_setup_row(1):
			viewport.set_input_as_handled()
			return
	if _is_menu_accept_event(event):
		if focus_owner is Button and not (focus_owner as Button).disabled:
			(focus_owner as Button).pressed.emit()
			viewport.set_input_as_handled()
			return
	if _is_menu_back_event(event):
		if _go_back():
			viewport.set_input_as_handled()


func _build_world() -> void:
	_build_environment()
	_build_actual_menu_world()
	_build_camera_path()


func _build_actual_menu_world() -> void:
	var terrain := MENU_TERRAIN_SCENE.instantiate() as LowPolyTerrain
	terrain.name = "MenuLowPolyTerrain"
	terrain.quads_x = 420
	terrain.quads_z = 420
	terrain.cell_size_m = 36.0
	terrain.seed = 22551
	terrain.plateau_height_m = 500.0
	terrain.base_height_offset_m = 220.0
	terrain.canyon_wall_color = Color(0.667926, 0.427286, 0.274156, 1.0)
	terrain.canyon_upper_color = Color(0.744223, 0.61311, 0.439865, 1.0)
	terrain.steep_slope_color = Color(0.338234, 0.326747, 0.303773, 1.0)
	terrain.generate_on_ready = true
	terrain.use_streaming = true
	terrain.chunk_quads_x = 24
	terrain.chunk_quads_z = 24
	terrain.load_radius_chunks = 3
	terrain.unload_margin_chunks = 1
	terrain.max_chunk_builds_per_update = 2
	terrain.stream_update_interval_s = 0.5
	terrain.stream_preload_ahead_m = 900.0
	_terrain = terrain
	_terrain.position.y = 62.0
	add_child(_terrain)
	NavGraph.rebuild_from_current_navgrid()

	var patrol_points: Array[Vector3] = _build_menu_patrol_points()
	var route: Array[Vector3] = []
	for i in range(patrol_points.size()):
		var pos := patrol_points[i]
		pos.y = _terrain_height_at(pos) + CARRIER_RIDE_HEIGHT_M
		route.append(pos)
		var marker := Marker3D.new()
		marker.name = "MenuCarrierWaypoint%d" % i
		marker.global_position = pos
		add_child(marker)

	_carrier_root = MENU_CARRIER_SCENE.instantiate() as Node3D
	_carrier_root.name = "MenuLandCarrier"
	_carrier_root.set("use_waypoint_pathfinding", false)
	_carrier_root.set("loop_waypoints", true)
	_carrier_root.set("max_speed", 5.5)
	_carrier_root.set("acceleration", 0.7)
	_carrier_root.set("deceleration", 1.4)
	_carrier_root.set("turn_speed", 0.18)
	_carrier_root.set("track_marks_enabled", true)
	_carrier_root.global_position = route[0]
	_strip_menu_carrier_systems(_carrier_root)
	add_child(_carrier_root)
	_carrier_root.remove_from_group("carrier")
	_apply_preview_livery()
	call_deferred("_start_menu_carrier_path", route)


func _terrain_height_at(world_pos: Vector3) -> float:
	if is_instance_valid(_terrain) and _terrain.has_method("get_height"):
		var height: Variant = _terrain.call("get_height", Vector3(world_pos.x, _terrain.global_position.y, world_pos.z))
		if (typeof(height) == TYPE_FLOAT or typeof(height) == TYPE_INT) and not is_nan(float(height)):
			return float(height)
		return NAN
	return 0.0


func _start_menu_carrier_path(route: Array[Vector3]) -> void:
	if not is_instance_valid(_carrier_root):
		return
	if not TerrainNavGrid.is_ready():
		var terrain_callback := Callable(self, "_start_menu_carrier_path").bind(route)
		if not TerrainNavGrid.bake_complete.is_connected(terrain_callback):
			TerrainNavGrid.bake_complete.connect(terrain_callback, CONNECT_ONE_SHOT)
		return
	if not NavGraph.is_ready():
		var callback := Callable(self, "_start_menu_carrier_path").bind(route)
		if not NavGraph.graph_ready.is_connected(callback):
			NavGraph.graph_ready.connect(callback, CONNECT_ONE_SHOT)
		return
	var nav_route := _build_nav_follow_route()
	if nav_route.size() >= 2:
		_carrier_root.global_position = nav_route[0]
		_face_carrier_toward(nav_route[1])
		route = nav_route
	_carrier_root.set("use_waypoint_pathfinding", true)
	_carrier_root.set("loop_waypoints", true)
	if _carrier_root.has_method("set_patrol_waypoints"):
		_carrier_root.call("set_patrol_waypoints", _ground_route_points(route))


func _build_nav_follow_route() -> Array[Vector3]:
	var edge_route := _build_edge_to_edge_route()
	if _route_has_nav_anchors(edge_route):
		return edge_route

	var rng := RandomNumberGenerator.new()
	rng.seed = 78431
	for _attempt in range(10):
		var start: Vector3 = TerrainNavGrid.get_random_passable_position(rng, MENU_PATH_MAX_SLOPE_M, 400)
		if start == Vector3.ZERO:
			continue
		var goal: Vector3 = TerrainNavGrid.get_furthest_edge_position(start, 7, MENU_PATH_MAX_SLOPE_M)
		if goal == start or goal == Vector3.ZERO:
			continue
		var random_route := _ground_route_points([start, goal])
		if _route_has_nav_anchors(random_route):
			return random_route

	return []


func _build_edge_to_edge_route() -> Array[Vector3]:
	if not TerrainNavGrid.is_ready():
		return []
	var bottom: Vector3 = TerrainNavGrid.get_centered_edge_position(
		"bottom",
		620.0,
		1800.0,
		1500.0,
		MENU_PATH_MAX_SLOPE_M
	)
	var top: Vector3 = TerrainNavGrid.get_centered_edge_position(
		"top",
		620.0,
		1800.0,
		1500.0,
		MENU_PATH_MAX_SLOPE_M
	)
	if bottom == Vector3.ZERO or top == Vector3.ZERO:
		return []
	return _ground_route_points([bottom, top])


func _route_has_nav_anchors(points: Array[Vector3]) -> bool:
	if points.size() < 2:
		return false
	for point in points:
		if not NavGraph.has_nearby_node(point, MENU_CARRIER_CLEARANCE_M):
			return false
	return true


func _ground_route_points(points: Array[Vector3]) -> Array[Vector3]:
	var grounded: Array[Vector3] = []
	for p in points:
		var grounded_point := _ground_menu_route_point(p)
		if not is_nan(grounded_point.y):
			grounded.append(grounded_point)
	return grounded


func _ground_menu_route_point(point: Vector3) -> Vector3:
	var h := TerrainNavGrid.sample_height(point.x, point.z) if TerrainNavGrid.is_ready() else NAN
	if is_nan(h) or h <= TerrainNavGrid.IMPASSABLE * 0.5:
		h = _terrain_height_at(point)
	if is_nan(h):
		return Vector3(point.x, NAN, point.z)
	return Vector3(point.x, h + CARRIER_RIDE_HEIGHT_M, point.z)


func _face_carrier_toward(target: Vector3) -> void:
	if not is_instance_valid(_carrier_root):
		return
	var to_target := target - _carrier_root.global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 1.0:
		return
	var dir := to_target.normalized()
	_carrier_root.rotation.y = atan2(dir.x, dir.z)


func _build_menu_patrol_points() -> Array[Vector3]:
	var center := _find_menu_route_center()
	for radius in [760.0, 560.0, 380.0, 240.0]:
		var candidates: Array[Vector3] = [
			_find_nearby_flat_point(center + Vector3(-radius, 0.0, -radius * 0.45), radius * 0.28),
			_find_nearby_flat_point(center + Vector3(radius * 0.78, 0.0, -radius * 0.34), radius * 0.28),
			_find_nearby_flat_point(center + Vector3(radius, 0.0, radius * 0.55), radius * 0.28),
			_find_nearby_flat_point(center + Vector3(-radius * 0.62, 0.0, radius * 0.70), radius * 0.28),
		]
		if _is_route_reasonable(candidates):
			return candidates
	var fallback_radius := 170.0
	return [
		center + Vector3(-fallback_radius, 0.0, -fallback_radius),
		center + Vector3(fallback_radius, 0.0, -fallback_radius * 0.6),
		center + Vector3(fallback_radius, 0.0, fallback_radius),
		center + Vector3(-fallback_radius, 0.0, fallback_radius * 0.6),
	]


func _find_menu_route_center() -> Vector3:
	var best_pos := Vector3.ZERO
	var best_score := INF
	var search_extent := 1500.0
	var step := 180.0
	var x := -search_extent
	while x <= search_extent:
		var z := -search_extent
		while z <= search_extent:
			var pos := Vector3(x, 0.0, z)
			var score := _terrain_patch_score(pos, 190.0)
			if score < best_score:
				best_score = score
				best_pos = pos
			z += step
		x += step
	return best_pos


func _find_nearby_flat_point(target: Vector3, search_radius: float) -> Vector3:
	var best_pos := target
	var best_score := _terrain_patch_score(target, 150.0)
	var step := maxf(search_radius / 3.0, 45.0)
	var x := -search_radius
	while x <= search_radius:
		var z := -search_radius
		while z <= search_radius:
			if x * x + z * z <= search_radius * search_radius:
				var pos := target + Vector3(x, 0.0, z)
				var score := _terrain_patch_score(pos, 150.0)
				if score < best_score:
					best_score = score
					best_pos = pos
			z += step
		x += step
	return best_pos


func _terrain_patch_score(center: Vector3, radius: float) -> float:
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(radius, 0.0),
		Vector2(-radius, 0.0),
		Vector2(0.0, radius),
		Vector2(0.0, -radius),
		Vector2(radius * 0.7, radius * 0.7),
		Vector2(-radius * 0.7, radius * 0.7),
		Vector2(radius * 0.7, -radius * 0.7),
		Vector2(-radius * 0.7, -radius * 0.7),
	]
	var min_h := INF
	var max_h := -INF
	var avg_h := 0.0
	for offset in offsets:
		var h := _terrain_height_at(Vector3(center.x + offset.x, 0.0, center.z + offset.y))
		if is_nan(h):
			return INF
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
		avg_h += h
	avg_h /= float(offsets.size())
	var span := max_h - min_h
	var high_ground_penalty := maxf(avg_h - (_terrain.global_position.y + 420.0), 0.0) * 0.08
	return span + high_ground_penalty


func _is_route_reasonable(points: Array[Vector3]) -> bool:
	if points.size() < 2:
		return false
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		if _route_segment_height_span(a, b, ROUTE_SAMPLE_STEP_M) > ROUTE_MAX_HEIGHT_SPAN_M:
			return false
	return true


func _route_segment_height_span(a: Vector3, b: Vector3, step_m: float) -> float:
	var flat_a := Vector2(a.x, a.z)
	var flat_b := Vector2(b.x, b.z)
	var dist := flat_a.distance_to(flat_b)
	var samples := maxi(int(ceil(dist / maxf(step_m, 1.0))), 1)
	var min_h := INF
	var max_h := -INF
	for i in range(samples + 1):
		var t := float(i) / float(samples)
		var pos := a.lerp(b, t)
		var h := _terrain_height_at(pos)
		if is_nan(h):
			return INF
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
	return max_h - min_h


func _strip_menu_carrier_systems(carrier: Node3D) -> void:
	for child_name in ["LandCarrierInput", "FlightDeckManager", "BridgeHologram", "StandaloneCameraSwitcher", "CommanderWalkArea", "Commander"]:
		var child := carrier.get_node_or_null(child_name)
		if child != null:
			carrier.remove_child(child)
			child.free()
	_deactivate_descendant_cameras(carrier)


func _deactivate_descendant_cameras(node: Node) -> void:
	if node is Camera3D:
		(node as Camera3D).current = false
	for child in node.get_children():
		_deactivate_descendant_cameras(child)


func _force_exterior_camera() -> void:
	if not is_instance_valid(_camera):
		return
	var viewport := get_viewport()
	if viewport == null or viewport.get_camera_3d() == _camera:
		return
	if is_instance_valid(_carrier_root):
		_deactivate_descendant_cameras(_carrier_root)
	_camera.current = true


func _configure_menu_autoloads() -> void:
	_restored_autoloads = false
	_autoload_overrides.clear()
	_override_autoload_property("/root/AirOpsManager", "maintain_carrier_cap", false)
	_override_autoload_property("/root/AirOpsManager", "debug_print", false)
	_override_autoload_property("/root/AirOpsManager", "default_mission", 0)
	_override_autoload_property("/root/GroundOpsManager", "maintain_carrier_escort", false)
	_override_autoload_property("/root/GroundOpsManager", "debug_print", false)
	_override_autoload_property("/root/EnemyBaseManager", "_disabled_for_test", true)
	_override_autoload_property("/root/EnemyOpsManager", "_disabled_for_test", true)
	_override_autoload_property("/root/TerrainNavGrid", "cell_size_m", 60.0)
	_override_autoload_property("/root/TerrainNavGrid", "bake_half_extent_m", 1500.0)
	_override_autoload_property("/root/TerrainNavGrid", "query_cell_size_m", 48.0)
	_override_autoload_property("/root/TerrainNavGrid", "rows_per_frame", 12)
	var nav_grid := get_node_or_null("/root/TerrainNavGrid")
	if nav_grid != null:
		if nav_grid.has_method("set_bake_center_override"):
			nav_grid.call("set_bake_center_override", Vector3.ZERO)
		if nav_grid.has_method("_reset_bake_state"):
			nav_grid.call("_reset_bake_state")


func _override_autoload_property(node_path: NodePath, property_name: StringName, value: Variant) -> void:
	var node := get_node_or_null(node_path)
	if node == null:
		return
	_autoload_overrides.append({
		"node": node,
		"property": property_name,
		"value": node.get(property_name),
	})
	node.set(property_name, value)


func _restore_autoloads() -> void:
	if _restored_autoloads:
		return
	_restored_autoloads = true
	for i in range(_autoload_overrides.size() - 1, -1, -1):
		var entry := _autoload_overrides[i]
		var node: Node = entry.get("node", null)
		if is_instance_valid(node):
			node.set(entry.get("property", ""), entry.get("value"))
	_autoload_overrides.clear()
	var nav_grid := get_node_or_null("/root/TerrainNavGrid")
	if nav_grid != null:
		if nav_grid.has_method("clear_bake_center_override"):
			nav_grid.call("clear_bake_center_override")
		if nav_grid.has_method("_reset_bake_state"):
			nav_grid.call("_reset_bake_state")
	if NavGraph.has_method("reset_until_navgrid_bakes"):
		NavGraph.call("reset_until_navgrid_bakes")
	else:
		NavGraph.rebuild_from_current_navgrid()
	_enable_enemy_systems_for_game()


func _enable_enemy_systems_for_game() -> void:
	var enemy_ops := get_node_or_null("/root/EnemyOpsManager")
	if enemy_ops != null and enemy_ops.has_method("enable_for_game"):
		enemy_ops.call("enable_for_game")
	var enemy_bases := get_node_or_null("/root/EnemyBaseManager")
	if enemy_bases != null and enemy_bases.has_method("enable_for_game"):
		enemy_bases.call("enable_for_game")


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.19, 0.20, 0.22, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.52, 0.45, 1.0)
	env.ambient_light_energy = 0.55
	env.fog_enabled = false
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32.0, -42.0, 0.0)
	sun.light_color = Color(1.0, 0.72, 0.44, 1.0)
	sun.light_energy = 2.5
	add_child(sun)

	var cool_rim := DirectionalLight3D.new()
	cool_rim.rotation_degrees = Vector3(-8.0, 130.0, 0.0)
	cool_rim.light_color = Color(0.45, 0.56, 0.70, 1.0)
	cool_rim.light_energy = 0.65
	add_child(cool_rim)


func _build_terrain() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(520.0, 520.0)
	mesh.subdivide_width = 18
	mesh.subdivide_depth = 18
	var terrain := MeshInstance3D.new()
	terrain.name = "MenuTerrain"
	terrain.mesh = mesh
	terrain.rotation_degrees.x = 0.0
	terrain.material_override = _mat(Color(0.55, 0.32, 0.16, 1.0), 0.95)
	add_child(terrain)

	for i in range(34):
		var rock := MeshInstance3D.new()
		var box := BoxMesh.new()
		var s := 3.0 + float((i * 37) % 90) / 10.0
		box.size = Vector3(s, 0.6 + s * 0.18, s * 0.7)
		rock.mesh = box
		rock.position = Vector3(-220.0 + float((i * 61) % 440), box.size.y * 0.5 - 0.25, -230.0 + float((i * 97) % 460))
		rock.rotation_degrees.y = float((i * 41) % 360)
		rock.material_override = _mat(Color(0.48, 0.27, 0.13, 1.0), 0.9)
		add_child(rock)


func _build_cliffs() -> void:
	for i in range(20):
		var cliff := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var h := 22.0 + float((i * 19) % 32)
		mesh.size = Vector3(20.0 + float((i * 13) % 34), h, 12.0 + float((i * 17) % 22))
		cliff.mesh = mesh
		var side := -1.0 if i % 2 == 0 else 1.0
		cliff.position = Vector3(side * (150.0 + float((i * 11) % 70)), h * 0.5 - 4.0, -230.0 + float(i * 24))
		cliff.rotation_degrees = Vector3(0.0, float((i * 29) % 28) * side, 0.0)
		cliff.material_override = _mat(Color(0.69, 0.48, 0.28, 1.0), 0.92)
		add_child(cliff)


func _build_carrier() -> void:
	_carrier_root = Node3D.new()
	_carrier_root.name = "MenuCarrier"
	_carrier_root.position = Vector3(28.0, 9.0, 0.0)
	_carrier_root.rotation_degrees.y = -8.0
	add_child(_carrier_root)

	var hull_mat := _mat(Color(0.16, 0.17, 0.17, 1.0), 0.65)
	var deck_mat := _mat(Color(0.09, 0.10, 0.11, 1.0), 0.8)
	var tread_mat := _mat(Color(0.045, 0.045, 0.04, 1.0), 0.7)

	_add_box(_carrier_root, "Hull", Vector3(56.0, 10.0, 120.0), Vector3(0.0, 8.0, 0.0), hull_mat)
	_add_box(_carrier_root, "Deck", Vector3(70.0, 3.0, 132.0), Vector3(0.0, 15.0, -2.0), deck_mat)
	_add_box(_carrier_root, "Bridge", Vector3(18.0, 22.0, 20.0), Vector3(18.0, 28.0, -16.0), hull_mat)
	_add_box(_carrier_root, "Tower", Vector3(10.0, 18.0, 10.0), Vector3(23.0, 48.0, -20.0), hull_mat)
	for side in [-1.0, 1.0]:
		_add_box(_carrier_root, "Track", Vector3(14.0, 9.0, 118.0), Vector3(side * 42.0, 3.0, 0.0), tread_mat)
		for i in range(9):
			_add_box(_carrier_root, "TrackPlate", Vector3(15.5, 2.0, 7.5), Vector3(side * 42.0, 8.5, -50.0 + i * 12.5), tread_mat)
	for i in range(5):
		_add_box(_carrier_root, "DeckMark", Vector3(30.0, 0.4, 2.0), Vector3(0.0, 16.8, -48.0 + i * 22.0), _mat(Color(0.85, 0.72, 0.35, 1.0), 0.75))


func _build_escorts() -> void:
	var mat := _mat(Color(0.11, 0.12, 0.10, 1.0), 0.8)
	for i in range(5):
		var v := Node3D.new()
		v.name = "EscortVehicle"
		v.position = Vector3(-54.0 + i * 18.0, 2.0, -70.0 + i * 26.0)
		add_child(v)
		_add_box(v, "Body", Vector3(8.0, 3.0, 14.0), Vector3.ZERO, mat)
		_add_box(v, "Turret", Vector3(4.0, 2.0, 5.0), Vector3(0.0, 2.8, -1.5), mat)


func _build_camera_path() -> void:
	var path := Path3D.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(-1320.0, 1080.0, -1120.0))
	curve.add_point(Vector3(-980.0, 1020.0, -660.0))
	curve.add_point(Vector3(-120.0, 980.0, -480.0))
	curve.add_point(Vector3(780.0, 1040.0, -260.0))
	curve.add_point(Vector3(1060.0, 1180.0, 720.0))
	curve.add_point(Vector3(-1320.0, 1080.0, -1120.0))
	path.curve = curve
	add_child(path)

	_path_follow = PathFollow3D.new()
	_path_follow.loop = true
	_path_follow.rotation_mode = PathFollow3D.ROTATION_NONE
	path.add_child(_path_follow)

	_camera = Camera3D.new()
	_camera.fov = MAIN_CAMERA_FOV
	_camera.far = 7000.0
	_camera.top_level = true
	_camera.current = true
	_path_follow.add_child(_camera)


func _position_exterior_camera() -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(_carrier_root):
		return
	var carrier_pos := _carrier_root.global_position
	var forward := _carrier_root.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := _carrier_root.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = Vector3(forward.z, 0.0, -forward.x)
	right = right.normalized()
	var desired: Vector3
	var blend := 0.035
	if _current_screen == "setup":
		if _is_insignia_row_focused():
			var marker := _carrier_insignia_marker()
			var marker_pos := marker.global_position if marker != null else carrier_pos + Vector3(0.0, 34.0, 0.0)
			var marker_local_x := marker.position.x if marker != null else -1.0
			var side_dir := right * (1.0 if marker_local_x < 0.0 else -1.0)
			desired = marker_pos + side_dir * INSIGNIA_CAMERA_SIDE_M - forward * INSIGNIA_CAMERA_BACK_M
			desired.y = marker_pos.y + INSIGNIA_CAMERA_HEIGHT_M
			blend = CAMERA_INSIGNIA_BLEND
		else:
			desired = carrier_pos - forward * SETUP_CAMERA_BACK_M + right * SETUP_CAMERA_SIDE_M
			desired.y = carrier_pos.y + SETUP_CAMERA_HEIGHT_M
			blend = CAMERA_SETUP_BLEND
	else:
		var side_sign := 1.0 if sin(_elapsed * 0.06) >= 0.0 else -1.0
		var side_amount := CAMERA_CARRIER_SIDE_M * (0.55 + absf(sin(_elapsed * 0.06)) * 0.45)
		desired = carrier_pos - forward * CAMERA_CARRIER_BACK_M + right * side_amount * side_sign
		desired.y = carrier_pos.y + CAMERA_CARRIER_HEIGHT_M
	_camera.global_position = _camera.global_position.lerp(desired, blend) if _elapsed > 0.2 else desired
	_keep_camera_above_ground()


func _keep_camera_above_ground() -> void:
	if not is_instance_valid(_camera):
		return
	var pos := _camera.global_position
	var ground_y := _terrain_height_at(pos)
	if is_nan(ground_y):
		return
	var clearance := CAMERA_TERRAIN_CLEARANCE_M
	if _current_screen == "setup":
		clearance = INSIGNIA_CAMERA_TERRAIN_CLEARANCE_M if _is_insignia_row_focused() else SETUP_CAMERA_TERRAIN_CLEARANCE_M
	var min_y := ground_y + clearance
	if pos.y < min_y:
		_camera.global_position.y = min_y


func _target_camera_fov() -> float:
	if _current_screen != "setup":
		return MAIN_CAMERA_FOV
	return INSIGNIA_CAMERA_FOV if _is_insignia_row_focused() else SETUP_CAMERA_FOV


func _apply_setup_screen_framing(_look_target: Vector3) -> void:
	if _current_screen != "setup" or not is_instance_valid(_camera):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var aspect := viewport_size.x / viewport_size.y
	var vertical_half_angle := deg_to_rad(_camera.fov) * 0.5
	var horizontal_half_angle := atan(tan(vertical_half_angle) * aspect)
	var ndc_x := (SETUP_FRAME_POINT.x - 0.5) * 2.0
	var ndc_y := (0.5 - SETUP_FRAME_POINT.y) * 2.0
	var yaw := atan(ndc_x * tan(horizontal_half_angle))
	var pitch := atan(ndc_y * tan(vertical_half_angle))
	_camera.rotate_object_local(Vector3.UP, yaw)
	_camera.rotate_object_local(Vector3.RIGHT, pitch)


func _camera_look_target() -> Vector3:
	if not is_instance_valid(_carrier_root):
		return Vector3.ZERO
	if _current_screen == "setup":
		if _is_insignia_row_focused():
			var marker := _carrier_insignia_marker()
			if marker != null:
				var lift := 3.0
				return marker.global_position + Vector3(0.0, lift, 0.0)
			return _carrier_root.global_position + Vector3(0.0, 6.0, -6.0)
		return _carrier_root.global_position + Vector3(0.0, 2.0, -18.0)
	var t := fposmod(_elapsed / CAMERA_LOOP_S, 1.0)
	if t < 0.20:
		return _carrier_root.global_position + Vector3(0.0, 14.0, 90.0)
	if t < 0.48:
		return _carrier_root.global_position + Vector3(0.0, 20.0, 0.0)
	if t < 0.73:
		return _carrier_root.global_position + Vector3(12.0, 34.0, -32.0)
	return _carrier_root.global_position + Vector3(0.0, 26.0, 80.0)


func _is_insignia_row_focused() -> bool:
	if _current_screen != "setup" or _insignia_value_button == null:
		return false
	var viewport := get_viewport()
	return viewport != null and viewport.gui_get_focus_owner() == _insignia_value_button


func _carrier_insignia_marker() -> Marker3D:
	if not is_instance_valid(_carrier_root):
		return null
	var preferred := _carrier_root.get_node_or_null("InsigniaHullR") as Marker3D
	if preferred != null:
		return preferred
	for child in _carrier_root.get_children():
		if child is Marker3D and String(child.name).begins_with("InsigniaHull"):
			return child as Marker3D
	return null


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_ui_root = Control.new()
	_ui_root.name = "ScaledUIRoot"
	_ui_root.size = BASE_UI_SIZE
	layer.add_child(_ui_root)

	var shade_gradient := Gradient.new()
	shade_gradient.offsets = PackedFloat32Array([0.0, 0.72, 1.0])
	shade_gradient.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.66),
		Color(0.0, 0.0, 0.0, 0.40),
		Color(0.0, 0.0, 0.0, 0.0),
	])
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = shade_gradient
	shade_texture.fill_from = Vector2.ZERO
	shade_texture.fill_to = Vector2.RIGHT
	var shade := TextureRect.new()
	shade.texture = shade_texture
	shade.position = Vector2.ZERO
	shade.size = Vector2(560.0, BASE_UI_SIZE.y)
	_ui_root.add_child(shade)

	var vignette := ColorRect.new()
	vignette.color = Color(0.0, 0.0, 0.0, 0.07)
	vignette.position = Vector2.ZERO
	vignette.size = BASE_UI_SIZE
	_ui_root.add_child(vignette)

	_message_label = _make_label("", Vector2(64.0, 665.0), 16, Color(1.0, 1.0, 1.0, 0.52))
	_message_label.size = Vector2(440.0, 24.0)
	_ui_root.add_child(_message_label)

	var version := _make_label("MAIN MENU PROTOTYPE", Vector2(64.0, 632.0), 14, Color(1.0, 0.85, 0.60, 0.42))
	_ui_root.add_child(version)

	_main_panel = Control.new()
	_main_panel.position = Vector2(64.0, 108.0)
	_main_panel.size = Vector2(400.0, 430.0)
	_ui_root.add_child(_main_panel)
	_build_main_menu(_main_panel)

	_setup_panel = Control.new()
	_setup_panel.position = Vector2(64.0, 20.0)
	_setup_panel.size = Vector2(480.0, 620.0)
	_ui_root.add_child(_setup_panel)
	_build_setup_menu(_setup_panel)


func _layout_ui_root() -> void:
	if not is_instance_valid(_ui_root):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var ui_scale := minf(viewport_size.x / BASE_UI_SIZE.x, viewport_size.y / BASE_UI_SIZE.y)
	_ui_root.size = BASE_UI_SIZE
	_ui_root.scale = Vector2(ui_scale, ui_scale)
	_ui_root.position = Vector2.ZERO


func _build_main_menu(parent: Control) -> void:
	var title := _make_label("LAND CARRIER", Vector2.ZERO, 39, Color(1.0, 0.82, 0.34, 1.0))
	parent.add_child(title)

	var entries := [
		["CONTINUE", Callable(self, "_continue_game")],
		["NEW CAMPAIGN", Callable(self, "_show_setup_menu")],
		["SKIRMISH / TEST FLIGHT", Callable(self, "_start_test_flight")],
		["LANDING TEST", Callable(self, "_start_landing_test")],
		["CARRIER COMBAT TEST", Callable(self, "_start_carrier_combat_test")],
		["SETTINGS", Callable(self, "_show_options_menu")],
		["CREDITS", Callable(self, "_show_credits_stub")],
		["QUIT", Callable(self, "_quit_game")],
	]
	for i in range(entries.size()):
		var btn := _make_menu_button(str(entries[i][0]), Vector2(0.0, 88.0 + i * 58.0), 390.0)
		btn.pressed.connect(entries[i][1] as Callable)
		if i == 0:
			btn.disabled = true
		parent.add_child(btn)


func _build_setup_menu(parent: Control) -> void:
	parent.add_child(_make_label("NEW CAMPAIGN", Vector2.ZERO, 34, Color(1.0, 0.82, 0.34, 1.0)))
	parent.add_child(_make_label("CARRIER NAME", Vector2(0.0, 58.0), 18, Color(1.0, 1.0, 1.0, 0.66)))

	_name_edit = LineEdit.new()
	_name_edit.text = _random_default_carrier_name()
	_name_edit.position = Vector2(0.0, 86.0)
	_name_edit.size = Vector2(430.0, 42.0)
	_name_edit.max_length = 32
	_name_edit.add_theme_font_override("font", MENU_FONT)
	_name_edit.add_theme_font_size_override("font_size", 22)
	parent.add_child(_name_edit)

	parent.add_child(_make_label("PRIMARY", Vector2(0.0, 146.0), 18, Color(1.0, 1.0, 1.0, 0.66)))
	_primary_value_button = _build_cycle_row(parent, Vector2(0.0, 172.0), Callable(self, "_change_primary"))
	parent.add_child(_make_label("SECONDARY", Vector2(0.0, 218.0), 18, Color(1.0, 1.0, 1.0, 0.66)))
	_secondary_value_button = _build_cycle_row(parent, Vector2(0.0, 244.0), Callable(self, "_change_secondary"))
	parent.add_child(_make_label("TEXTURE", Vector2(0.0, 290.0), 18, Color(1.0, 1.0, 1.0, 0.66)))
	_pattern_value_button = _build_cycle_row(parent, Vector2(0.0, 316.0), Callable(self, "_change_pattern"))
	parent.add_child(_make_label("INSIGNIA", Vector2(0.0, 362.0), 18, Color(1.0, 1.0, 1.0, 0.66)))
	_insignia_value_button = _build_cycle_row(parent, Vector2(0.0, 388.0), Callable(self, "_change_insignia"))
	parent.add_child(_make_label("MAP", Vector2(0.0, 434.0), 18, Color(1.0, 1.0, 1.0, 0.66)))
	_map_value_button = _build_cycle_row(parent, Vector2(0.0, 460.0), Callable(self, "_change_map"))

	var start_btn := _make_menu_button("START", Vector2(0.0, 538.0), 185.0)
	start_btn.pressed.connect(_start_new_campaign)
	parent.add_child(start_btn)
	var back_btn := _make_small_button("< BACK", Vector2(226.0, 548.0), 170.0)
	back_btn.pressed.connect(_show_main_menu)
	parent.add_child(back_btn)
	_refresh_setup_buttons()


func _build_cycle_row(parent: Control, pos: Vector2, callback: Callable) -> Button:
	var left_btn := _make_arrow_button("<", pos)
	left_btn.pressed.connect(callback.bind(-1))
	parent.add_child(left_btn)
	var value_btn := _make_value_button(pos + Vector2(52.0, 0.0), 286.0)
	value_btn.pressed.connect(callback.bind(1))
	parent.add_child(value_btn)
	var right_btn := _make_arrow_button(">", pos + Vector2(352.0, 0.0))
	right_btn.pressed.connect(callback.bind(1))
	parent.add_child(right_btn)
	return value_btn


func _show_main_menu() -> void:
	_current_screen = "main"
	_main_panel.visible = true
	_setup_panel.visible = false
	_message_label.text = ""
	var first := _first_button(_main_panel)
	if first:
		first.grab_focus()


func _show_setup_menu() -> void:
	_current_screen = "setup"
	_main_panel.visible = false
	_setup_panel.visible = true
	_message_label.text = ""
	_refresh_setup_buttons()
	_apply_preview_livery()
	_name_edit.grab_focus()


func _continue_game() -> void:
	_message_label.text = "NO SAVE FOUND"


func _start_test_flight() -> void:
	_configure_session(DEFAULT_CARRIER_NAME, _carrier_colors[_primary_index], _carrier_colors[_secondary_index], _selected_pattern_index(), _insignia_index)
	_start_game_with_scenario(NORMAL_TEST_SCENARIO)


func _start_landing_test() -> void:
	_configure_session(DEFAULT_CARRIER_NAME, _carrier_colors[_primary_index], _carrier_colors[_secondary_index], _selected_pattern_index(), _insignia_index)
	_start_game_with_scenario(LANDING_TEST_SCENARIO)


func _start_carrier_combat_test() -> void:
	_configure_session(DEFAULT_CARRIER_NAME, _carrier_colors[_primary_index], _carrier_colors[_secondary_index], _selected_pattern_index(), _insignia_index)
	_start_game_with_scenario(CARRIER_COMBAT_TEST_SCENARIO)


func _show_options_menu() -> void:
	var pause_menu := get_node_or_null("/root/PauseMenu")
	if pause_menu == null or not pause_menu.has_method("_open"):
		_message_label.text = "SETTINGS NOT READY"
		return
	pause_menu.call("_open")
	if pause_menu.has_method("_show_screen"):
		pause_menu.call("_show_screen", "options")


func _show_credits_stub() -> void:
	_message_label.text = "CREDITS COMING SOON"


func _quit_game() -> void:
	get_tree().quit()


func _start_new_campaign() -> void:
	_configure_session(_name_edit.text, _carrier_colors[_primary_index], _carrier_colors[_secondary_index], _selected_pattern_index(), _insignia_index)
	_start_game_with_scenario(NORMAL_TEST_SCENARIO)


func _start_game_with_scenario(scenario: int) -> void:
	var file := FileAccess.open(TEST_SCENARIO_SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		_message_label.text = "COULD NOT SAVE GAME MODE"
		push_warning("[MainMenu] Could not save %s" % TEST_SCENARIO_SETTINGS_PATH)
		return
	file.store_string(JSON.stringify({"scenario": scenario}))
	file.close()
	_restore_autoloads()
	var loading_screen: Node = get_node_or_null("/root/LoadingScreen")
	if loading_screen != null and loading_screen.has_method("begin_scenario_load"):
		loading_screen.call("begin_scenario_load")
	get_tree().change_scene_to_file(GAME_SCENE)


func _configure_session(carrier_name: String, primary: Color, secondary: Color, pattern_index: int, insignia_index: int) -> void:
	var session := get_node_or_null("/root/GameSession")
	if session != null and session.has_method("configure_new_game"):
		session.call("configure_new_game", carrier_name, primary, secondary, pattern_index, insignia_index, _selected_map_id())


func _change_primary(delta: int) -> void:
	_primary_index = _wrap_index(_primary_index + delta, _carrier_colors.size())
	_refresh_setup_buttons()
	_apply_preview_livery()


func _change_secondary(delta: int) -> void:
	_secondary_index = _wrap_index(_secondary_index + delta, _carrier_colors.size())
	_refresh_setup_buttons()
	_apply_preview_livery()


func _change_pattern(delta: int) -> void:
	_pattern_choice_index = _wrap_index(_pattern_choice_index + delta, _pattern_names.size())
	_refresh_setup_buttons()
	_apply_preview_livery()


func _change_insignia(delta: int) -> void:
	_insignia_index = _wrap_index(_insignia_index + delta, _insignia_names.size())
	_refresh_setup_buttons()
	_apply_preview_livery()


func _change_map(delta: int) -> void:
	_map_index = _wrap_index(_map_index + delta, MAP_IDS.size())
	_refresh_setup_buttons()


func _refresh_setup_buttons() -> void:
	_refresh_color_value_button(_primary_value_button, _primary_index)
	_refresh_color_value_button(_secondary_value_button, _secondary_index)
	if _pattern_value_button != null:
		_pattern_value_button.text = _pattern_names[_wrap_index(_pattern_choice_index, _pattern_names.size())] if not _pattern_names.is_empty() else "SOLID"
		_apply_plain_button_style(_pattern_value_button)
	if _insignia_value_button != null:
		_insignia_value_button.text = _insignia_names[_wrap_index(_insignia_index, _insignia_names.size())] if not _insignia_names.is_empty() else "NONE"
		_apply_plain_button_style(_insignia_value_button)
	if _map_value_button != null:
		_map_value_button.text = MAP_NAMES[_wrap_index(_map_index, MAP_NAMES.size())]
		_apply_plain_button_style(_map_value_button)


func _apply_preview_livery() -> void:
	if not is_instance_valid(_carrier_root) or _carrier_colors.is_empty():
		return
	var livery := get_node_or_null("/root/Livery")
	if livery == null:
		return
	var primary := _carrier_colors[_wrap_index(_primary_index, _carrier_colors.size())]
	var secondary := _carrier_colors[_wrap_index(_secondary_index, _carrier_colors.size())]
	if livery.has_method("set_player_livery"):
		livery.call("set_player_livery", primary, secondary, _selected_pattern_index())
	if livery.has_method("set_player_insignia"):
		livery.call("set_player_insignia", _insignia_index)
	if livery.has_method("apply"):
		var added_carrier_group := false
		if not _carrier_root.is_in_group("carrier"):
			_carrier_root.add_to_group("carrier")
			added_carrier_group = true
		livery.call("apply", _carrier_root)
		if added_carrier_group:
			_carrier_root.remove_from_group("carrier")


func _refresh_color_value_button(button: Button, index: int) -> void:
	if button == null:
		return
	var color := _carrier_colors[index]
	button.text = _carrier_color_names[index]
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(1.0, 0.85, 0.55, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)
	var readable := Color.BLACK if color.get_luminance() > 0.58 else Color.WHITE
	button.add_theme_color_override("font_color", readable)
	button.add_theme_color_override("font_hover_color", readable)
	button.add_theme_color_override("font_focus_color", readable)


func _load_livery_palette() -> void:
	_carrier_colors.clear()
	_carrier_color_names.clear()
	_insignia_names.clear()
	_pattern_names.clear()
	_pattern_indices.clear()
	var livery := get_node_or_null("/root/Livery")
	if livery != null and livery.has_method("get_preset_upper_color_count"):
		var count: int = int(livery.call("get_preset_upper_color_count"))
		for i in range(count):
			var color_variant: Variant = livery.call("get_preset_upper_color", i)
			var name_variant: Variant = livery.call("get_preset_upper_color_name", i)
			_carrier_colors.append(color_variant as Color if color_variant is Color else Color.WHITE)
			_carrier_color_names.append(str(name_variant))
	if livery != null and livery.has_method("get_insignia_count"):
		var insignia_count: int = int(livery.call("get_insignia_count"))
		for i in range(insignia_count):
			var name_variant: Variant = livery.call("get_insignia_name", i) if livery.has_method("get_insignia_name") else "INSIGNIA %02d" % (i + 1)
			_insignia_names.append(str(name_variant))
	if livery != null and livery.has_method("get_livery_pattern_count"):
		var pattern_count: int = int(livery.call("get_livery_pattern_count"))
		for i in range(pattern_count):
			var name_variant: Variant = livery.call("get_livery_pattern_name", i) if livery.has_method("get_livery_pattern_name") else "TEXTURE %02d" % (i + 1)
			var index_variant: Variant = livery.call("get_livery_pattern_index", i) if livery.has_method("get_livery_pattern_index") else i
			_pattern_names.append(str(name_variant))
			_pattern_indices.append(int(index_variant))
	if _carrier_colors.is_empty():
		_carrier_colors = [Color(0.36, 0.40, 0.44, 1.0), Color(0.90, 0.66, 0.18, 1.0)]
		_carrier_color_names = ["STEEL GREY", "AMBER"]
		_primary_index = 0
		_secondary_index = 1
	else:
		_primary_index = clampi(DEFAULT_PRIMARY_COLOR_INDEX, 0, _carrier_colors.size() - 1)
		_secondary_index = clampi(DEFAULT_SECONDARY_COLOR_INDEX, 0, _carrier_colors.size() - 1)
	if _insignia_names.is_empty():
		_insignia_names = ["NONE"]
	_insignia_index = clampi(_insignia_index, 0, _insignia_names.size() - 1)
	if _pattern_names.is_empty() or _pattern_indices.is_empty():
		_pattern_names.assign(FALLBACK_PATTERN_NAMES)
		_pattern_indices.assign(FALLBACK_PATTERN_INDICES)
	_pattern_choice_index = clampi(_pattern_choice_index, 0, _pattern_names.size() - 1)


func _randomize_setup_choices() -> void:
	if not _carrier_colors.is_empty():
		_primary_index = _menu_rng.randi_range(0, _carrier_colors.size() - 1)
		_secondary_index = _menu_rng.randi_range(0, _carrier_colors.size() - 1)
		if _carrier_colors.size() > 1:
			var guard := 8
			while _secondary_index == _primary_index and guard > 0:
				_secondary_index = _menu_rng.randi_range(0, _carrier_colors.size() - 1)
				guard -= 1
	if not _pattern_names.is_empty():
		_pattern_choice_index = _menu_rng.randi_range(0, _pattern_names.size() - 1)
	if not _insignia_names.is_empty():
		_insignia_index = _menu_rng.randi_range(0, _insignia_names.size() - 1)


func _selected_pattern_index() -> int:
	if _pattern_indices.is_empty():
		return 0
	return _pattern_indices[_wrap_index(_pattern_choice_index, _pattern_indices.size())]


func _selected_map_id() -> String:
	if MAP_IDS.is_empty():
		return "open_canyons"
	return MAP_IDS[_wrap_index(_map_index, MAP_IDS.size())]


func _load_ship_names() -> void:
	_ship_names.clear()
	if not FileAccess.file_exists(SHIP_NAME_LIST_PATH):
		return
	var file := FileAccess.open(SHIP_NAME_LIST_PATH, FileAccess.READ)
	if file == null:
		return
	var seen: Dictionary = {}
	while not file.eof_reached():
		var ship_name := file.get_line().strip_edges()
		if ship_name == "" or seen.has(ship_name):
			continue
		seen[ship_name] = true
		_ship_names.append(ship_name)


func _random_default_carrier_name() -> String:
	if _ship_names.is_empty():
		return DEFAULT_CARRIER_NAME
	return _ship_names[_menu_rng.randi_range(0, _ship_names.size() - 1)]


func _add_box(parent: Node, node_name: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = material
	parent.add_child(mi)
	return mi


func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material


func _make_label(text: String, pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_override("font", MENU_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_menu_button(text: String, pos: Vector2, width: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = Vector2(width, 54.0)
	btn.custom_minimum_size = Vector2(width, 54.0)
	btn.focus_mode = Control.FOCUS_ALL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_apply_plain_button_style(btn)
	btn.add_theme_font_size_override("font_size", 28)
	btn.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.18))
	return btn


func _make_small_button(text: String, pos: Vector2, width: float) -> Button:
	var btn := _make_menu_button(text, pos, width)
	btn.size = Vector2(width, 38.0)
	btn.custom_minimum_size = Vector2(width, 38.0)
	btn.add_theme_font_size_override("font_size", 21)
	return btn


func _make_arrow_button(text: String, pos: Vector2) -> Button:
	var btn := _make_small_button(text, pos, 40.0)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	return btn


func _make_value_button(pos: Vector2, width: float) -> Button:
	var btn := _make_small_button("", pos, width)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return btn


func _apply_plain_button_style(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, empty)
	button.add_theme_font_override("font", MENU_FONT)
	button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.62))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.84, 0.44, 0.9))


func _wrap_index(value: int, size: int) -> int:
	if size <= 0:
		return 0
	return ((value % size) + size) % size


func _go_back() -> bool:
	if _current_screen == "setup":
		_show_main_menu()
		return true
	return false


func _cycle_focused_setup_row(delta: int) -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var focus_owner := viewport.gui_get_focus_owner()
	if focus_owner == _primary_value_button:
		_change_primary(delta)
		return true
	if focus_owner == _secondary_value_button:
		_change_secondary(delta)
		return true
	if focus_owner == _pattern_value_button:
		_change_pattern(delta)
		return true
	if focus_owner == _insignia_value_button:
		_change_insignia(delta)
		return true
	if focus_owner == _map_value_button:
		_change_map(delta)
		return true
	return false


func _move_focus(focus_owner: Control, side: int) -> void:
	if focus_owner == null:
		_focus_first_button()
		return
	var next_focus := focus_owner.find_valid_focus_neighbor(side)
	if next_focus:
		next_focus.grab_focus()
		return
	var buttons: Array[Button] = _buttons_in_current_screen()
	if buttons.is_empty():
		return
	var idx := buttons.find(focus_owner as Button)
	if idx < 0:
		buttons[0].grab_focus()
		return
	var dir := -1 if side == Side.SIDE_TOP else 1
	buttons[(idx + dir + buttons.size()) % buttons.size()].grab_focus()


func _focus_first_button() -> Control:
	var buttons: Array[Button] = _buttons_in_current_screen()
	if buttons.is_empty():
		return null
	buttons[0].grab_focus()
	return buttons[0]


func _focus_last_button() -> Control:
	var buttons: Array[Button] = _buttons_in_current_screen()
	if buttons.is_empty():
		return null
	buttons[buttons.size() - 1].grab_focus()
	return buttons[buttons.size() - 1]


func _buttons_in_current_screen() -> Array[Button]:
	var out: Array[Button] = []
	var screen: Control = _main_panel if _current_screen == "main" else _setup_panel
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back() as Node
		if n is Button:
			var btn := n as Button
			if btn.visible and not btn.disabled and btn.focus_mode != Control.FOCUS_NONE:
				out.append(btn)
		for child in n.get_children():
			stack.append(child as Node)
	out.reverse()
	return out


func _first_button(node: Node) -> Button:
	if node == null:
		return null
	if node is Button and not (node as Button).disabled:
		return node as Button
	for child in node.get_children():
		var found := _first_button(child)
		if found:
			return found
	return null


func _is_menu_up_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_up", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		return key == KEY_UP or key == KEY_W
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_DPAD_UP
	return false


func _is_menu_down_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_down", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		return key == KEY_DOWN or key == KEY_S
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_DPAD_DOWN
	return false


func _is_menu_left_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_left", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		return key == KEY_LEFT or key == KEY_A
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_DPAD_LEFT
	return false


func _is_menu_right_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_right", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		return key == KEY_RIGHT or key == KEY_D
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_DPAD_RIGHT
	return false


func _is_menu_accept_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		return key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_A
	return false


func _is_menu_back_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		return (event as InputEventKey).physical_keycode == KEY_ESCAPE
	if event is InputEventJoypadButton and event.pressed:
		var button_index := (event as InputEventJoypadButton).button_index
		return button_index == PAD_BUTTON_B or button_index == PAD_BUTTON_BACK
	return false
