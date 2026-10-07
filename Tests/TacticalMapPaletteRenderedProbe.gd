extends Node3D

## Exercises the real map drawing paths with deliberately conflicting world paint.
## Run this scene with a display renderer; captures and pixel checks need pixels.
const PALETTE: Script = preload("res://UI/TacticalMapPalette.gd")
const MAP_TEXTURE: Script = preload("res://UI/WorldMapTextureBuilder.gd")
const OUTPUT_DIR := "res://captures/tactical_palette"

class MapUnit extends Node3D:
	var team := 1
	var waypoints: Array[Vector3] = []
	func get_team() -> int: return team
	func get_active_waypoints() -> Array[Vector3]: return waypoints

class MapBase extends EnemyBase:
	func _ready() -> void:
		add_to_group("enemy_bases")
	func _physics_process(_delta: float) -> void: pass

class MapStation extends EnemyOutpost:
	func _ready() -> void:
		add_to_group("enemy_outposts")
		add_to_group("enemies")
	func _physics_process(_delta: float) -> void: pass

var failures: Array[String] = []
var checks := 0
var _units: Dictionary = {}
var _layer: Control
var _original_livery: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for singleton in get_tree().root.get_children():
		if singleton != self:
			singleton.process_mode = Node.PROCESS_MODE_DISABLED
	FloatingOrigin.enabled = false
	GameSession.is_trailer_scenario = false
	EnemyOpsManager.reset_runtime_state()
	AirOpsManager._reported_contacts.clear()
	AirOpsManager.reported_contact_timeout_s = 3600.0
	_setup_grid()
	MapFogOfWar.reveal_circle(Vector3.ZERO, 30000.0)
	_save_livery()
	_setup_units()
	_setup_sites()
	_setup_map()

	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_check(directory_error == OK, "capture directory is available")
	if directory_error != OK:
		_finish()
		return

	_set_world_paint(Color("f2cc32"), "GREEN")
	_check_world_paint(Color("f2cc32"), "GREEN")
	_check_team_classification()
	var first := await _capture("player_yellow_enemy_green")
	_check_pixels(first)
	_set_world_paint(Color("2bad58"), "MUSTARD")
	_check_world_paint(Color("2bad58"), "MUSTARD")
	_check_team_classification()
	var second := await _capture("player_green_enemy_yellow")
	_check_pixels(second)
	_check(first != null and second != null and first.get_data() == second.get_data(),
		"rendered map pixels are identical after swapping yellow and green world paint")
	DisplayServer.window_set_size(Vector2i(1280, 800))
	get_tree().root.content_scale_size = Vector2i(1280, 800)
	await get_tree().process_frame
	WorldMapOverlay._root.size = Vector2(1280, 800)
	WorldMapOverlay._layout_ui()
	WorldMapOverlay._apply_map_view()
	for child in _layer.get_children():
		if child.has_meta("probe_world_position"):
			child.position = _layer._world_to_map(child.get_meta("probe_world_position")) + Vector2(-18, 26)
	await _capture("palette_1280")
	_finish()

func _setup_grid() -> void:
	TerrainNavGrid.cell_size_m = 200.0
	TerrainNavGrid._cols = 121
	TerrainNavGrid._rows = 121
	TerrainNavGrid._origin_x = -12000.0
	TerrainNavGrid._origin_z = -12000.0
	TerrainNavGrid._heights.resize(121 * 121)
	TerrainNavGrid._heights.fill(0.0)
	TerrainNavGrid._is_baked = true
	TerrainNavGrid._h_min_passable = 0.0
	TerrainNavGrid.query_cell_size_m = 200.0
	TerrainNavGrid._query_cols = 121
	TerrainNavGrid._query_rows = 121
	TerrainNavGrid._query_origin_x = -12000.0
	TerrainNavGrid._query_origin_z = -12000.0
	TerrainNavGrid._query_heights = TerrainNavGrid._heights.duplicate()
	TerrainNavGrid._query_height_variation = TerrainNavGrid._heights.duplicate()
	TerrainNavGrid._query_max_heights = TerrainNavGrid._heights.duplicate()
	TerrainNavGrid._query_is_baked = true
	MapFogOfWar._initialize_from_navgrid()

func _add_unit(key: String, at: Vector3, team: int, groups: Array[String]) -> MapUnit:
	var unit := MapUnit.new()
	unit.name = key
	unit.team = team
	unit.position = at
	add_child(unit)
	unit.add_to_group("friendlies" if team == 1 else "enemies")
	unit.add_to_group("team_%d" % team)
	for group in groups: unit.add_to_group(group)
	_units[key] = unit
	return unit

func _setup_units() -> void:
	var plane := _add_unit("FriendlyPlane", Vector3(-8000, 800, -8500), 1, ["aircraft"])
	plane.waypoints = [Vector3(-2000, 800, -8500), Vector3(-2000, 800, -4000), Vector3(-4500, 800, -4000)]
	AirOpsManager.get_flight("Archer").register(plane)
	var helicopter := _add_unit("FriendlyHelicopter", Vector3(-8000, 400, -5000), 1, ["aircraft"])
	helicopter.set_meta("is_helicopter", true)
	_add_unit("FriendlyGround", Vector3(-8000, 0, -1500), 1, ["ground_vehicles"])
	_add_unit("FriendlyHarvester", Vector3(-8000, 0, 2500), 1, ["ground_vehicles", "harvesters"])
	var carrier := _add_unit("FriendlyCarrier", Vector3(-8000, 0, 6500), 1, ["carrier"])
	carrier.waypoints = [Vector3(-9500, 0, 9500)]
	var enemy_plane := _add_unit("HostilePlane", Vector3(1500, 800, -8500), 2, ["aircraft"])
	var enemy_heli := _add_unit("HostileHelicopter", Vector3(1500, 400, -5000), 2, ["aircraft"])
	enemy_heli.set_meta("is_helicopter", true)
	var enemy_ground := _add_unit("HostileGround", Vector3(1500, 0, -1500), 2, ["ground_vehicles"])
	_add_unit("RememberedHostile", Vector3(6500, 800, -8500), 2, ["aircraft"])
	for enemy in [enemy_plane, enemy_heli, enemy_ground]:
		AirOpsManager.report_contact(carrier, enemy)

	var base := MapBase.new()
	base.name = "HostileBase"
	base.position = Vector3(1500, 0, 2500)
	add_child(base)
	_units["HostileBase"] = base
	var station := MapStation.new()
	station.outpost_id = "OP-TEST"
	station.position = Vector3(1500, 0, 6500)
	station.observation_radius_m = 1800.0
	add_child(station)
	_units["HostileStation"] = station
	var flight := EnemyVirtualFlight.new()
	flight.flight_name = "VIRTUAL-TEST"
	flight.position = Vector3(6500, 800, -5000)
	flight.heading = Vector3.BACK
	add_child(flight)
	EnemyOpsManager._base_flights[base] = [flight]
	var platoon := EnemyVirtualPlatoon.new()
	platoon.platoon_name = "VIRTUAL-TEST"
	platoon.position = Vector3(6500, 0, -1500)
	add_child(platoon)
	EnemyOpsManager._base_platoons[base] = [platoon]

func _setup_sites() -> void:
	var field := POIManager.get_resource_field()
	field.reset()
	field.add_corium_seep("Test corium", Vector3(-4500, 0, 6500), 800.0, true, true)
	field.add_source("Test plasteel", Vector3(-4500, 0, 9000), "salvage", {"plasteel": 420.0}, true)
	field.add_source("Spent salvage", Vector3(-4500, 0, 10800), "salvage", {"plasteel": 0.0}, true)
	var poi := POIManager.POIInstance.new()
	poi.id = 1
	poi.world_pos = Vector3(6500, 0, 2500)
	poi.discovered = true
	# No awaiting-orders pulse: every map redraw must be deterministic.
	POIManager._pois.clear()
	POIManager._pois.append(poi)
	var consumed := POIManager.POIInstance.new()
	consumed.id = 2
	consumed.world_pos = Vector3(6500, 0, 6500)
	consumed.discovered = true
	consumed.revealed = true
	POIManager._pois.append(consumed)

func _setup_map() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	get_tree().root.content_scale_size = Vector2i(1920, 1080)
	var clearance := PackedFloat32Array()
	clearance.resize(TerrainNavGrid._heights.size())
	clearance.fill(160.0)
	var images: Dictionary = MAP_TEXTURE.build_images_from_data(TerrainNavGrid._heights, clearance, 121, 121, 200.0)
	WorldMapOverlay._map_texture = ImageTexture.create_from_image(images.relief)
	WorldMapOverlay._map_rect.texture = WorldMapOverlay._map_texture
	WorldMapOverlay._overview_map_rect.texture = WorldMapOverlay._map_texture
	WorldMapOverlay._map_ready = true
	WorldMapOverlay._map_zoom = 1.0
	WorldMapOverlay._map_view_center_uv = Vector2(0.5, 0.5)
	WorldMapOverlay.set_console_visible(true)
	WorldMapOverlay.set_process(false)
	WorldMapOverlay._observation_button.button_pressed = false
	WorldMapOverlay._selected_asset_kind = 1 # AssetKind.FLIGHT
	WorldMapOverlay._selected_asset_name = "Archer"
	WorldMapOverlay._refresh_ui()
	WorldMapOverlay._apply_map_view()
	_layer = WorldMapOverlay._symbol_layer
	_layer.set_continuous_updates(false)
	_layer.show_outpost_range_estimates = false
	_layer.set_selected_flight("Archer")
	_layer.set_selection_focus(_units.FriendlyPlane.global_position, PALETTE.SELECTION)
	for spec in [
		["FriendlyPlane", "SELECTED PLANE"], ["FriendlyHelicopter", "HELICOPTER"],
		["FriendlyGround", "VEHICLE"], ["FriendlyHarvester", "HARVESTER"],
		["FriendlyCarrier", "CARRIER"], ["HostilePlane", "PLANE"],
		["HostileHelicopter", "HELICOPTER"], ["HostileGround", "VEHICLE"],
		["RememberedHostile", "REMEMBERED"], ["HostileBase", "BASE"],
	]:
		_add_map_label(_units[spec[0]].global_position, spec[1])
	_add_map_label(Vector3(6500, 0, -5000), "VIRTUAL FLIGHT")
	_add_map_label(Vector3(6500, 0, -1500), "VIRTUAL PLATOON")
	_add_map_label(Vector3(6500, 0, 2500), "POI")
	_add_map_label(Vector3(6500, 0, 6500), "USED POI")

func _add_map_label(at: Vector3, label_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.position = _layer._world_to_map(at) + Vector2(-18, 26)
	label.add_theme_font_override("font", _layer.DATA_FONT)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("abb9bd"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("probe_world_position", at)
	_layer.add_child(label)

func _save_livery() -> void:
	for property in ["upper_color", "_player_custom_livery_enabled", "_player_custom_primary_color", "_player_custom_secondary_color", "_player_custom_pattern_index", "_team_upper_preset_indices", "_team_secondary_preset_indices"]:
		var value: Variant = Livery.get(property)
		_original_livery[property] = value.duplicate(true) if value is Dictionary else value

func _set_world_paint(friendly: Color, enemy_preset: String) -> void:
	# Change the real livery service without recolouring fixture geometry or touching saves.
	Livery._player_custom_livery_enabled = true
	Livery._player_custom_primary_color = friendly
	Livery.upper_color = friendly
	var preset: int = Livery.PRESET_UPPER_COLOR_NAMES.find(enemy_preset)
	_check(preset >= 0, "requested enemy world paint preset exists")
	Livery._team_upper_preset_indices[2] = preset
	Livery._team_secondary_preset_indices[2] = preset
	_layer.refresh_now()

func _check_world_paint(friendly: Color, enemy_preset: String) -> void:
	var enemy_index: int = Livery.PRESET_UPPER_COLOR_NAMES.find(enemy_preset)
	_check(Livery.get_team_upper_color(1).is_equal_approx(friendly), "friendly world paint remains selected livery")
	_check(Livery.get_team_upper_color(2).is_equal_approx(Livery.PRESET_UPPER_COLORS[enemy_index]), "hostile world paint remains selected livery")
	_check(not Livery.get_team_hud_color(1).is_equal_approx(PALETTE.FRIENDLY), "friendly livery HUD hue actually differs from map blue")
	_check(not Livery.get_team_hud_color(2).is_equal_approx(PALETTE.HOSTILE), "hostile livery HUD hue actually differs from map red")

func _check_team_classification() -> void:
	for key in ["FriendlyPlane", "FriendlyHelicopter", "FriendlyGround", "FriendlyHarvester", "FriendlyCarrier"]:
		_check(_layer._color_for_team_node(_units[key]).is_equal_approx(PALETTE.FRIENDLY), key + " is blue regardless of world paint")
	for key in ["HostilePlane", "HostileHelicopter", "HostileGround"]:
		_check(_layer._color_for_team_node(_units[key]).is_equal_approx(PALETTE.HOSTILE), key + " is red regardless of world paint")
	_check(AirOpsManager.is_contact_detected(_units.HostilePlane), "active hostile uses the actual sensor report path")
	_check(not AirOpsManager.is_contact_detected(_units.RememberedHostile), "remembered hostile remains outside the sensor picture")
	_check(not AirOpsManager.is_contact_detected(_units.HostileBase), "explored hostile base has no mobile sensor report")
	_check(not AirOpsManager.is_contact_detected(_units.HostileStation), "explored hostile station has no mobile sensor report")
	var remembered: Color = _layer._color_for_team_node(_units.RememberedHostile)
	_check(remembered.is_equal_approx(_layer._mute_color(PALETTE.HOSTILE)), "remembered contact dims map red")
	_check(remembered.r > remembered.g and remembered.r > remembered.b, "remembered contact retains a red tint")

func _capture(name_hint: String) -> Image:
	_layer.refresh_now()
	for frame in range(4): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var full_image := get_viewport().get_texture().get_image()
	var save_error := full_image.save_png(OUTPUT_DIR.path_join(name_hint + ".png"))
	_check(save_error == OK, "full map capture saves: " + name_hint)
	var region := Rect2i(_layer.global_position.round(), _layer.size.round())
	var map_image := full_image.get_region(region)
	save_error = map_image.save_png(OUTPUT_DIR.path_join(name_hint + "_map.png"))
	_check(save_error == OK, "map crop saves: " + name_hint)
	print("TACTICAL_PALETTE_CAPTURE %s map_region=%s" % [ProjectSettings.globalize_path(OUTPUT_DIR.path_join(name_hint + ".png")), region])
	return map_image

func _check_pixels(map_image: Image) -> void:
	_check(map_image != null and map_image.get_width() > 300, "map capture contains usable rendered pixels")
	if map_image == null: return
	for key in ["FriendlyPlane", "FriendlyHelicopter", "FriendlyGround", "FriendlyHarvester", "FriendlyCarrier"]:
		_check(_count_color(map_image, _layer._world_to_map(_units[key].global_position), 25, PALETTE.FRIENDLY) >= 2,
			key + " renders blue pixels")
	for key in ["HostilePlane", "HostileHelicopter", "HostileGround", "HostileBase", "HostileStation"]:
		_check(_count_color(map_image, _layer._world_to_map(_units[key].global_position), 25, PALETTE.HOSTILE) >= 2,
			key + " renders red pixels")
	for at in [Vector3(6500, 800, -5000), Vector3(6500, 0, -1500)]:
		var point: Vector2 = _layer._world_to_map(at)
		var background := map_image.get_pixelv(Vector2i(point + Vector2(20, -20)))
		var half_red := background.lerp(PALETTE.HOSTILE, 0.5)
		_check(_count_color(map_image, point, 22, half_red) >= 2,
			"unreported virtual contact retains half-opacity tactical red at %s" % at)
	_check(_count_color(map_image, _layer._world_to_map(_units.FriendlyPlane.global_position), 27, PALETTE.SELECTION) >= 4,
		"selected blue aircraft retains a white outline")
	for at in [Vector3(-4500, 0, 6500), Vector3(-4500, 0, 9000), Vector3(6500, 0, 2500)]:
		_check(_count_color(map_image, _layer._world_to_map(at), 16, PALETTE.RESOURCE) >= 2,
			"resource or POI renders yellow at %s" % at)
	_check(_count_color(map_image, _layer._world_to_map(Vector3(-2000, 800, -8500)), 16, PALETTE.ROUTE) >= 2,
		"route waypoint renders green")
	_check(_count_color(map_image, _layer._world_to_map(Vector3(6500, 0, 6500)), 12, PALETTE.NEUTRAL) >= 2,
		"used POI renders neutral grey")
	_check(_count_color(map_image, _layer._world_to_map(Vector3(-4500, 0, 10800)), 14, PALETTE.NEUTRAL) >= 2,
		"exhausted salvage renders neutral grey")

func _count_color(image: Image, point: Vector2, radius: int, expected: Color) -> int:
	var count := 0
	for y in range(maxi(0, int(point.y) - radius), mini(image.get_height(), int(point.y) + radius + 1)):
		for x in range(maxi(0, int(point.x) - radius), mini(image.get_width(), int(point.x) + radius + 1)):
			var pixel := image.get_pixel(x, y)
			if absf(pixel.r - expected.r) < 0.025 and absf(pixel.g - expected.g) < 0.025 and absf(pixel.b - expected.b) < 0.025:
				count += 1
	return count

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("TACTICAL_PALETTE_RENDER " + message)

func _finish() -> void:
	for property in _original_livery: Livery.set(property, _original_livery[property])
	WorldMapOverlay.set_console_visible(false)
	print("TACTICAL_PALETTE_RENDER_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
