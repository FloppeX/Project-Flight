extends Node3D

class CarrierFixture:
	extends Node3D
	var vehicle_bay: Node
	func is_initial_placement_complete() -> bool: return true

class BayFixture:
	extends Node
	signal vehicle_deployed(unit)
	signal vehicle_retrieved(unit)
	signal vehicle_spawned(unit)
	var stored_harvesters := 1
	var deploy_calls := 0
	func deploy_harvester() -> bool:
		deploy_calls += 1
		return false
	func can_retrieve_vehicles() -> bool: return false

var failures: Array[String] = []
var ops: Node
var field: Node
var carrier: Node3D
var harvester: Node3D
var near_id: int
var second_id: int
var dormant_id: int
var hidden_id: int
var far_id: int

func _ready() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("HARVESTER_MISSIONS_FAIL: " + message)

func _run() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(1))
	for service in get_tree().root.get_children():
		if service != self: service.process_mode = Node.PROCESS_MODE_DISABLED
	FloatingOrigin.enabled = false
	carrier = CarrierFixture.new()
	add_child(carrier)
	carrier.add_to_group("carrier")
	carrier.vehicle_bay = BayFixture.new()
	carrier.add_child(carrier.vehicle_bay)
	var stores := preload("res://LandCarrier/CarrierManager.gd").new()
	carrier.add_child(stores)
	stores.get_replicator().set_process(false)
	ops = stores.get_harvester_ops()
	ops.set_process(false)
	_setup_grid()
	field = POIManager.get_resource_field()
	field.reset()
	far_id = field.add_salvage_source("Distant wreck", Vector3(4500, 0, 0), 500.0, "far", true)
	hidden_id = field.add_salvage_source("Unscouted wreck", Vector3(-100, 0, 0), 240.0, "hidden", false)
	dormant_id = field.add_corium_seep("Dormant seep", Vector3(0, 0, 300), 320.0, true, false)
	near_id = field.add_salvage_source("Nearby ruin", Vector3(800, 0, 0), 240.0, "near", true)
	second_id = field.add_salvage_source("Second ruin", Vector3(1800, 0, -1000), 80.0, "second", true)
	check(ops.order_auto_harvest().is_empty(), "automatic mission accepted while stored")
	ops._process(0.1)
	check(ops.mission == "AUTO_HARVEST" and ops.source_id == near_id and ops.phase == "queued", "automatic selection prefers nearest known active site, excluding hidden, dormant and distant sites")
	ops.recall()
	ops._process(5.0)
	check(ops.phase == "stored" and carrier.vehicle_bay.deploy_calls == 0, "return cancels automatic deployment")
	check(ops.order_move(Vector3(1000, 0, 1000)).is_empty(), "stored move accepted")
	ops._process(0.1)
	check(carrier.vehicle_bay.deploy_calls == 1 and ops.mission == "MOVE", "move deploys without requiring a resource source")
	harvester = preload("res://GroundVehicle/Harvester.tscn").instantiate()
	add_child(harvester)
	harvester.set_physics_process(false)
	harvester.position = Vector3(50, 1, 50)
	ops.vehicle = harvester
	ops._on_deployed(harvester)
	check(ops.phase == "moving" and harvester.get_active_waypoints() == [Vector3(1000, 0, 1000)], "deployment executes pending move")
	harvester.load_cargo("plasteel", 37.0)
	harvester.position = Vector3(1000, 1, 1000)
	ops._process(0.1)
	ops._process(30.0)
	check(ops.phase == "holding" and not harvester.collecting and harvester.cargo.plasteel == 37.0, "move holds indefinitely and retains cargo despite available resources")
	var mission_before: Dictionary = ops.capture_save_state()
	check(not ops.order_move(Vector3(5900, 0, 5900)).is_empty() and ops.capture_save_state() == mission_before, "unknown move rejection preserves current mission and cargo")
	check(not ops.collect(hidden_id).is_empty() and ops.capture_save_state() == mission_before, "hidden harvest rejection preserves current mission")
	check(ops.order_auto_harvest().is_empty(), "deployed harvester accepts automation")
	# Returning cargo is not credited until the real bay unload handler runs.
	var stored_plasteel: float = stores.plasteel_units
	ops._process(0.1)
	ops._process(2.1)
	check(ops.source_id == near_id and ops.phase == "travelling" and stores.plasteel_units == stored_plasteel, "automatic mission navigates without remotely crediting cargo")
	harvester.navigation_status = "blocked"
	ops._process(0.1)
	ops._process(0.1)
	ops._process(2.1)
	check(ops.source_id == second_id and ops.phase == "travelling", "automation skips a blocked site instead of retrying it endlessly")
	check(ops.collect(dormant_id, true).is_empty(), "explicit harvest can target a dormant known seep")
	# Empty load waits at a specifically ordered dormant seep.
	harvester.cargo.plasteel = 0.0
	ops._process(0.1)
	check(ops.mission == "HARVEST" and ops.phase == "waiting_seep", "explicit dormant harvest waits for that source")
	check(ops.order_move(Vector3(700, 0, 700)).is_empty(), "move overrides waiting harvest")
	ops._process(0.1)
	check(ops.mission == "MOVE" and ops.phase == "moving" and not ops.repeat_collection, "move prevents repeat harvesting from resuming")
	# A new mission during physical ramp deployment only updates intent.
	ops.phase = "deploying"
	harvester.deploy_mode = true
	var ramp_points: Array = harvester.get_active_waypoints().duplicate()
	check(ops.collect(near_id, true).is_empty() and harvester.get_active_waypoints() == ramp_points, "reassignment during deployment leaves ramp movement alone")
	harvester.deploy_mode = false
	ops._on_deployed(harvester)
	check(ops.mission == "HARVEST" and ops.phase == "travelling", "new harvest executes after clearing ramp")
	ops.phase = "retrieving"
	harvester.retrieve_mode = true
	mission_before = ops.capture_save_state()
	check(not ops.order_move(Vector3.ZERO).is_empty() and not ops.order_auto_harvest().is_empty() and ops.capture_save_state() == mission_before, "new missions cannot interrupt physical recovery")
	harvester.retrieve_mode = false
	ops.phase = "holding"
	ops.order_move(Vector3(900, 0, 900))
	ops._process(0.1)
	var transform_before_save: Transform3D = harvester.global_transform
	harvester.load_cargo("corium", 19.0)
	var saved: Dictionary = SaveGameManager._decode_json_value(JSON.parse_string(JSON.stringify(SaveGameManager._encode_json_value(ops.capture_save_state()))))
	ops.restore_save_state(saved)
	await get_tree().process_frame
	ops._process(0.1)
	harvester = ops.vehicle
	harvester.set_physics_process(false)
	check(ops.mission == "MOVE" and ops.move_target == Vector3(900, 0, 900) and ops.phase == "moving", "JSON save restores move intent and target")
	check(harvester.global_transform.is_equal_approx(transform_before_save) and harvester.cargo.corium == 19.0, "JSON save preserves actual vehicle position, orientation and cargo")
	var offset := Vector3(1200, 0, -2300)
	ops.apply_origin_shift(offset)
	check(ops.move_target == Vector3(-300, 0, 3200), "mission coordinates shift with the world")
	ops.apply_origin_shift(-offset)
	await _test_map()
	ops.vehicle = null
	ops.phase = "stored"
	ops.order_auto_harvest()
	for source in field.sources: source.discovered = false
	ops._process(0.1)
	check(ops.phase == "auto_wait" and ops.source_id == -1, "automatic mission waits in bay when no eligible resources are known")
	field.get_source(second_id).discovered = true
	ops._process(2.1)
	check(ops.source_id == second_id and ops.phase == "queued", "newly discovered local resources wake automatic harvesting")
	var auto_save: Dictionary = ops.capture_save_state()
	ops.restore_save_state(auto_save)
	check(ops.mission == "AUTO_HARVEST" and ops.phase == "queued", "automatic mission persists across saves")
	ops.recall()
	ops._process(30.0)
	check(ops.phase == "stored" and ops.mission == "RTB", "return keeps automation off even as sources remain available")
	# Previous disk checkpoints encoded unsupported transforms as null.
	ops.restore_save_state({"mission": "RTB", "phase": "returning", "vehicle": {"transform": null, "cargo": {"plasteel": 11.0}}})
	ops._process(0.1)
	check(is_instance_valid(ops.vehicle) and ops.vehicle.global_position.is_finite() and ops.vehicle.cargo.plasteel == 11.0, "legacy missing placement recovers without losing cargo or crashing")
	print("HARVESTER_MISSIONS_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_map() -> void:
	var map := WorldMapOverlay
	map.select_harvester()
	await get_tree().process_frame
	check(map._selected_asset_kind == map.AssetKind.HARVESTER and map._mission_buttons.size() == 4, "tactical map has a selectable harvester and four mission buttons")
	check(map._mission_popup.visible, "selecting the harvester opens its mission popup")
	if "--rendered" in OS.get_cmdline_user_args():
		await _capture("orders")
		DisplayServer.window_set_size(Vector2i(1280, 800))
		get_tree().root.content_scale_size = Vector2i(1280, 800)
		await get_tree().process_frame
		map._root.size = Vector2(1280, 800)
		map._layout_ui()
		map._apply_map_view()
		map.select_harvester()
		await _capture("orders_1280")
	map._begin_mission_draft("MOVE")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = map._world_to_map_local(Vector3(600, 0, 600))
	map._on_map_gui_input(click)
	check(map._can_confirm_draft(), "move can be drafted by clicking explored terrain")
	map._confirm_draft()
	check(ops.mission == "MOVE" and ops.move_target.distance_to(Vector3(600, 0, 600)) < 1.0, "map confirmation dispatches move")
	map._begin_mission_draft("HARVEST")
	click.position = map._world_to_map_local(field.get_source(hidden_id).position)
	map._on_map_gui_input(click)
	check(map._draft_source_id != hidden_id, "map cannot target hidden resource markers, even near visible ones")
	click.position = map._world_to_map_local(field.get_source(near_id).position)
	map._on_map_gui_input(click)
	check(map._draft_source_id == near_id and map._can_confirm_draft(), "map harvest snaps to a known resource identity")
	if "--rendered" in OS.get_cmdline_user_args(): await _capture("harvest")
	map._confirm_draft()
	check(ops.mission == "HARVEST" and ops.source_id == near_id and ops.repeat_collection, "map harvest dispatches repeat trips to the selected site")
	map._begin_mission_draft("HARVEST")
	map._on_map_gui_input(click)
	field.get_source(near_id).materials.plasteel = 0.0
	check(not map._can_confirm_draft(), "depletion while drafting invalidates confirmation")
	field.get_source(near_id).materials.plasteel = 240.0
	map._cancel_draft()
	click.position = map._world_to_map_local(harvester.global_position)
	check(map._try_select_map_harvester(click), "deployed H marker is directly selectable")
	map._begin_mission_draft("AUTO_HARVEST")
	check(map._can_confirm_draft(), "automatic mission needs no map target")
	map._confirm_draft()
	check(ops.mission == "AUTO_HARVEST", "map dispatches automatic harvesting")
	if "--rendered" in OS.get_cmdline_user_args(): await _capture("automatic")
	map._begin_mission_draft("RTB")
	map._confirm_draft()
	check(ops.mission == "RTB" and not ops.repeat_collection, "map return cancels automation")
	map._refresh_ui()
	check("TYPE: HARVESTER" in map._info_body.text and "CARGO:" in map._info_body.text, "map details expose the actual harvester mission and cargo")
	CarrierConsole.set_open(false)

func _capture(label: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://captures/harvester_map_%s.png" % label)

func _setup_grid() -> void:
	TerrainNavGrid.cell_size_m = 200.0
	TerrainNavGrid._cols = 61
	TerrainNavGrid._rows = 61
	TerrainNavGrid._origin_x = -6000.0
	TerrainNavGrid._origin_z = -6000.0
	TerrainNavGrid._heights.resize(61 * 61)
	TerrainNavGrid._heights.fill(0.0)
	TerrainNavGrid._h_min_passable = 0.0
	TerrainNavGrid._is_baked = true
	TerrainNavGrid._query_is_baked = false
	NavGraph._is_ready = false
	MapFogOfWar._initialize_from_navgrid()
	MapFogOfWar.reveal_circle(Vector3.ZERO, 5000.0)
	# Keep the normal terrain shader and input geometry for rendered checks.
	var texture := ImageTexture.create_from_image(Image.create(61, 61, false, Image.FORMAT_RGB8))
	WorldMapOverlay._map_rect.texture = texture
	WorldMapOverlay._map_ready = true
	WorldMapOverlay._apply_map_view()
