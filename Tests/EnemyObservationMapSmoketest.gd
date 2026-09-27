extends Node3D

class TestTerrain extends Node3D:
	func get_height(point: Vector3) -> float:
		return 180.0 if point.x > -700 and point.x < -300 and absf(point.z) < 3800 else 0.0

class ActiveFlight extends EnemyVirtualFlight:
	func _check_dematerialize() -> void: pass
	func _tick_active_contact_scan(_delta: float) -> void:
		_queue_report("carrier", Vector3(500, 0, 500), 1, 0.0)

class TestFormation extends GroundVehiclePlatoon:
	func _ready() -> void: set_physics_process(false)
	func get_contact_position() -> Vector3: return Vector3.ZERO

class ActivePlatoon extends EnemyVirtualPlatoon:
	func _check_dematerialize() -> void: pass
	func _scan_for_contacts(_immediate: bool) -> void:
		_queue_report("carrier", Vector3(700, 0, 700), 1, 0.0)

var failures: Array[String] = []
var messages: Array[String] = []
var checks := 0

func _ready() -> void: _run.call_deferred()
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
		push_error(reason)

func _run() -> void:
	for node in get_tree().root.get_children():
		if node != self: node.process_mode = Node.PROCESS_MODE_DISABLED
	FloatingOrigin.enabled = false
	EnemyOpsManager.reset_runtime_state()
	RadioComms.use_tts = false
	RadioComms.use_citadel_voice_clips = false
	RadioComms.transmitted.connect(func(sender: String, _recipient: String, body: String):
		if sender == "Citadel": messages.append(body))
	_setup_grid()
	var terrain := TestTerrain.new()
	add_child(terrain)
	TerrainReference.terrain_node = terrain
	var station := load("res://Buildings/building_enemy_outpost.tscn").instantiate() as EnemyOutpost
	station.position = Vector3(-2000, 0, -1000)
	add_child(station)
	station.set_physics_process(false)
	station.add_vehicle_bay(Vector3(90, 0, 0))
	var unknown := load("res://Buildings/building_enemy_outpost.tscn").instantiate() as EnemyOutpost
	unknown.position = Vector3(10000, 0, 10000)
	unknown.outpost_id = "OP-SECRET"
	add_child(unknown)
	unknown.set_physics_process(false)
	MapFogOfWar.reveal_circle(Vector3(-1000, 0, -1000), 8000.0)
	var overlay: Node = WorldMapOverlay
	_setup_map_texture(overlay)
	overlay.set_console_visible(true)
	var layer: Control = overlay._observation_layer
	layer.set_process(false)
	layer._refresh_stations()
	check(layer._stations.size() == 1, "undiscovered station leaked into overlay")
	for slice in 10000:
		layer._build_slice()
		if not layer.is_building_coverage(): break
	check(not layer.is_building_coverage(), "coverage never completed")
	check(layer.get_exposure_status(Vector3(-3000, 0, -1000)) == "FIXED OBSERVATION", "open ground missing from observation coverage")
	check(layer.get_exposure_status(Vector3(1000, 0, -1000)) == "POSSIBLE PATROLS", "ridge did not create a fixed-observation shadow")
	check(layer.get_exposure_status(unknown.position) == "UNKNOWN", "unexplored land was shown as safe")
	check(overlay._overview_observation_layer.coverage_source == layer, "overview duplicates coverage calculations")
	check(layer.get_index() < overlay._fog_rect.get_index(), "coverage can draw over unexplored fog")
	check(layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "overlay intercepts route input")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = overlay._world_to_map_local(station.position)
	check(overlay._try_select_outpost(click), "click did not select known outpost")
	check(overlay._info_body.text.contains("Observation: ACTIVE") and overlay._info_body.text.contains("Patrol replacements: ACTIVE"), "selected outpost capabilities missing")
	overlay._map_zoom = 2.0
	overlay._apply_map_view()
	check(layer.world_to_map(station.position).distance_to(overlay._world_to_map_local(station.position)) < 0.01, "coverage drifted from markers while zooming")
	overlay._map_zoom = 1.0
	overlay._apply_map_view()
	overlay._observation_button.button_pressed = false
	check(not layer.visible and not overlay._overview_observation_layer.visible, "toggle did not hide both overlays")
	overlay._observation_button.button_pressed = true
	if "--render" in OS.get_cmdline_user_args(): await _capture("enemy_observation_active")
	station.get_node("VehicleBay").take_damage(10000)
	check(layer.get_outpost_description(station).contains("Patrol replacements: OFFLINE"), "bay loss did not update capabilities")
	_check_reports(station)
	station._set_destroyed_state()
	check(layer.get_exposure_status(Vector3(-3000, 0, -1000)) == "POSSIBLE PATROLS", "destroyed station retained fixed coverage or erased patrol risk")
	overlay._refresh_ui()
	if "--render" in OS.get_cmdline_user_args(): await _capture("enemy_observation_offline")
	print("ENEMY_OBSERVATION_MAP_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_reports(station: EnemyOutpost) -> void:
	EnemyOpsManager.reset_runtime_state()
	messages.clear()
	station._queue_report("carrier", Vector3(10, 0, 20))
	check(messages.size() == 1 and messages[0].contains("outpost has spotted"), "outpost sighting warning missing")
	station._queue_report("carrier", Vector3(30, 0, 40))
	check(messages.size() == 1, "duplicate sighting spammed Citadel")
	station._service_reports(14.0)
	check(EnemyOpsManager.get_reported_carrier_position() == Vector3.INF, "outpost reported before delay")
	station._service_reports(1.0)
	check(EnemyOpsManager.get_reported_carrier_position() == Vector3(10, 0, 20), "outpost report lost original observed position")
	check(messages.size() == 2 and messages[-1].contains("transmission confirmed"), "confirmed report warning missing")
	EnemyOpsManager.apply_origin_shift(Vector3(5, 0, 5))
	check(EnemyOpsManager.get_reported_carrier_position() == Vector3(5, 0, 15), "reported marker ignored origin shift")
	EnemyOpsManager._decay_intel(181.0)
	check(EnemyOpsManager.get_reported_carrier_position() == Vector3.INF, "stale reported marker did not expire")

	EnemyOpsManager.reset_runtime_state()
	messages.clear()
	var patrol := EnemyVirtualPlatoon.new()
	patrol.vehicle_count = 3
	add_child(patrol)
	patrol._queue_report("carrier", Vector3(100, 0, 100), 1, 0.0)
	check(float(patrol._pending_reports[0].countdown) >= 40, "materialized patrol did not receive a reporting window")
	check(messages.size() == 1 and messages[0].contains("patrol has spotted"), "patrol sighting warning missing")
	patrol.vehicle_count = 0
	patrol._process_pending_reports(100.0)
	EnemyOpsManager._service_carrier_report_notices()
	check(EnemyOpsManager.get_reported_carrier_position() == Vector3.INF, "destroyed patrol transmitted")
	check(messages.size() == 2 and messages[-1].contains("did not get through"), "interrupted report was not acknowledged")
	patrol.free()

	EnemyOpsManager.reset_runtime_state()
	messages.clear()
	var flight := ActiveFlight.new()
	flight.flight_name = "REPORT-TEST"
	flight.aircraft_count = 2
	flight.vstate = EnemyVirtualFlight.VState.ACTIVE
	add_child(flight)
	var aircraft := Node3D.new()
	aircraft.position.y = 500
	add_child(aircraft)
	flight.active_aircraft.append(aircraft)
	flight.tick(0.25)
	check(EnemyOpsManager.get_reported_carrier_position() == Vector3.INF, "active flight reported immediately")
	for i in 310: flight.tick(0.25)
	check(EnemyOpsManager.get_reported_carrier_position() == Vector3(500, 0, 500), "active flight never serviced its reporting timer")
	check(messages.size() == 2, "active flight report notifications repeated")
	flight.aircraft_count = 0
	flight._process_pending_reports(100.0)
	EnemyOpsManager._service_carrier_report_notices()
	check(messages.size() == 2, "destroying a previously reported patrol claimed intel was prevented")
	flight.free()
	aircraft.free()

	EnemyOpsManager.reset_runtime_state()
	messages.clear()
	var active_patrol := ActivePlatoon.new()
	add_child(active_patrol)
	active_patrol.vstate = EnemyVirtualPlatoon.VState.ACTIVE
	active_patrol.vehicle_count = 1
	active_patrol._last_live_count = 1
	active_patrol._platoon_node = TestFormation.new()
	add_child(active_patrol._platoon_node)
	var vehicle := Node3D.new()
	add_child(vehicle)
	active_patrol._active_vehicles.append(vehicle)
	active_patrol._active_slot_indices.append(0)
	active_patrol.tick(0.25)
	check(EnemyOpsManager.get_reported_carrier_position() == Vector3.INF, "active ground patrol reported immediately")
	for i in 370: active_patrol.tick(0.25)
	check(EnemyOpsManager.get_reported_carrier_position() == Vector3(700, 0, 700), "active ground patrol never serviced its report")
	check(messages.size() == 2, "active ground patrol report notifications repeated")
	active_patrol._platoon_node.free()
	active_patrol.free()
	vehicle.free()

func _setup_grid() -> void:
	TerrainNavGrid.cell_size_m = 200.0
	TerrainNavGrid._cols = 121
	TerrainNavGrid._rows = 121
	TerrainNavGrid._origin_x = -12000.0
	TerrainNavGrid._origin_z = -12000.0
	TerrainNavGrid._heights.resize(121 * 121)
	TerrainNavGrid._heights.fill(0.0)
	TerrainNavGrid._is_baked = true
	MapFogOfWar._initialize_from_navgrid()

func _setup_map_texture(overlay: Node) -> void:
	var heights := TerrainNavGrid._heights.duplicate()
	var clearance := PackedFloat32Array()
	clearance.resize(heights.size())
	clearance.fill(160.0)
	for y in 121:
		for x in 121:
			if x >= 57 and x <= 59 and y > 41 and y < 79:
				heights[y * 121 + x] = 180.0
				clearance[y * 121 + x] = 0.0
	var images := preload("res://UI/WorldMapTextureBuilder.gd").build_images_from_data(heights, clearance, 121, 121, 200.0)
	overlay._map_texture = ImageTexture.create_from_image(images.relief)
	overlay._map_rect.texture = overlay._map_texture
	overlay._overview_map_rect.texture = overlay._map_texture
	overlay._map_ready = true

func _capture(label: String) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	WorldMapOverlay.process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	WorldMapOverlay._refresh_ui()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://captures/%s.png" % label)
