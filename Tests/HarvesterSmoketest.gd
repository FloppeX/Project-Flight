extends Node3D
var root: Window:
	get: return get_tree().root
var failures: Array[String] = []
var world: Node3D
var field: Node
var stores: Node
var harvester: Node3D
var ops: Node

class TestBay extends VehicleBayManager:
	func _ready() -> void:
		stored_vehicles = 15
		stored_harvesters = 1
	func _physics_process(_delta: float) -> void: pass

class CarrierFixture extends Node3D:
	var vehicle_bay: Node
	func get_system_capability(_system: String) -> float: return 1.0
	func is_initial_placement_complete() -> bool: return true

class RampCarrier extends LandCarrier:
	func _ready() -> void:
		add_to_group("carrier")
		_setup_vehicle_ramp()
	func _physics_process(_delta: float) -> void: pass
	func is_initial_placement_complete() -> bool: return true

func _ready() -> void: _run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("HARVESTER_FAIL: " + message)

func _run() -> void:
	Engine.time_scale = 6.0
	get_tree().create_timer(1800.0).timeout.connect(func() -> void:
		push_error("HARVESTER_FAIL: test timed out")
		get_tree().quit(1)
	)
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	world = Node3D.new()
	root.add_child(world)
	get_tree().current_scene = world
	_setup_ground()
	_setup_navigation()
	_expect(NavGraph.can_traverse_segment(Vector3(0, 2, 0), Vector3(1, 0, 0), 6.0), "short final approach checks terrain grade, not suspension height")
	var carrier := CarrierFixture.new()
	world.add_child(carrier)
	carrier.position.x = -400.0
	carrier.add_to_group("carrier")
	var bay := TestBay.new()
	bay.name = "VehicleBayManager"
	carrier.add_child(bay)
	carrier.vehicle_bay = bay
	stores = preload("res://LandCarrier/CarrierManager.gd").new()
	carrier.add_child(stores)
	stores.get_replicator().set_process(false)
	ops = stores.get_harvester_ops()
	ops.set_process(false)
	field = root.get_node("POIManager").get_resource_field()
	field.reset()
	if "--auto-only" in OS.get_cmdline_user_args():
		await _test_ramp_cycle(carrier, true)
		print("HARVESTER_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	var id: int = field.add_source("Test corium", Vector3(30, 0, 20), "corium", {"corium": 220.0}, true)
	var salvage_id: int = field.add_source("Test salvage", Vector3(80, 0, 20), "salvage", {"plasteel": 90.0}, true)
	harvester = preload("res://GroundVehicle/Harvester.tscn").instantiate()
	world.add_child(harvester)
	harvester.position = Vector3(0, 1.02, 0)
	_expect(harvester.turret_controller == null and harvester.turret_range == 0 and harvester.passenger_capacity == 0, "vehicle must be unarmed and reserved for resources")
	_expect(harvester._wheel_contact_nodes.size() == 6, "six working suspension wheels")
	_test_authored_arm()
	ops.vehicle = harvester
	ops.phase = "stored"
	_expect(ops.collect(id, false).is_empty(), "collection order accepted")
	ops._process(0.1)
	var reached := false
	for tick in range(2400):
		ops._process(6.0 / 60.0)
		await get_tree().physics_frame
		if tick % 300 == 0:
			print("HARVESTER_DRIVING tick=%d phase=%s at=%s velocity=%s goal=%s path=%s throttle=%s" % [tick, ops.phase, harvester.global_position, harvester.velocity, harvester._get_raw_navigation_destination(), harvester._nav_path_positions, harvester._drive_command_throttle])
		if ops.phase == "harvesting":
			reached = true
			break
	_expect(reached, "real six-wheel driver must reach deposit without teleporting")
	var source_offset: Vector3 = harvester.to_local(field.get_source(id).position)
	_expect(harvester._flat_distance(harvester.global_position, field.get_source(id).position) > 7.0 and absf(source_offset.x) > 7.0 and absf(source_offset.z) < 1.0, "parks beside the seep with the intake outside the hull")
	_expect(not harvester.allow_reverse_navigation, "resource travel uses forward-only navigation")
	print("HARVESTER_DRIVER phase=%s at=%s velocity=%s goal=%s nav=%s" % [ops.phase, harvester.global_position, harvester.velocity, harvester._get_raw_navigation_destination(), harvester._nav_path_positions])
	if "--rendered" in OS.get_cmdline_user_args(): await _capture_actual_collection_pose()
	if "--approach-only" in OS.get_cmdline_user_args():
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	var initial_c: float = stores.corium_units
	var initial_p: float = stores.plasteel_units
	# The deposit cannot be collected remotely, in motion or before tool contact.
	var before: float = field.remaining(field.get_source(id))
	harvester.velocity = Vector3(5, 0, 0)
	field.extract(id, 100, harvester)
	_expect(field.remaining(field.get_source(id)) == before, "moving intake cannot extract")
	harvester.velocity = Vector3.ZERO
	for tick in range(1800):
		ops._process(6.0 / 60.0)
		await get_tree().physics_frame
		if ops.phase == "folding": break
	_expect(is_equal_approx(harvester.cargo_total(), 160.0), "one load respects combined capacity")
	_expect(is_equal_approx(field.remaining(field.get_source(id)), 60.0), "only loaded units leave source")
	_expect(stores.corium_units == initial_c and stores.plasteel_units == initial_p, "harvesting must not remotely credit carrier")
	var save: Dictionary = ops.capture_save_state()
	var field_save: Dictionary = field.capture_save_state()
	var live_transform: Transform3D = harvester.global_transform
	var intake_before_shift: Vector3 = harvester.collection_target
	field.apply_origin_shift(Vector3(100, 0, -200))
	harvester.apply_origin_shift(Vector3(100, 0, -200))
	_expect(field.get_source(id).position == Vector3(-70, 0, 220) and harvester.collection_target == intake_before_shift - Vector3(100, 0, -200), "origin shift preserves intake and source coordinates")
	field.restore_save_state(field_save)
	ops.restore_save_state(save)
	await get_tree().process_frame
	ops._process(0.1)
	harvester = ops.vehicle
	_expect(is_instance_valid(harvester) and harvester.global_transform.is_equal_approx(live_transform) and harvester.cargo_total() == 160.0, "active cargo and vehicle restored exactly once")
	_expect(is_equal_approx(field.remaining(field.get_source(id)), 60.0) and stores.corium_units == initial_c, "restore must not refill deposits or credit in-transit cargo")
	# Use the bay's production unload handler, including repeated-call protection.
	bay.stored_harvesters = 0
	bay._on_vehicle_retrieved(harvester)
	_expect(bay.stored_harvesters == 1 and bay.stored_vehicles == 15 and stores.corium_units == initial_c + 160.0, "bay unload credits only correct cargo and utility inventory")
	harvester.unload_cargo(stores)
	_expect(stores.corium_units == initial_c + 160.0, "cargo cannot unload twice")
	# Real contact on salvage accepts the remaining capacity shared with corium.
	harvester.set_physics_process(false)
	harvester.position = Vector3(74, 1.02, 20)
	harvester.velocity = Vector3.ZERO
	harvester.collecting = true
	harvester.collection_target = field.get_source(salvage_id).position
	harvester._physics_process(0.0)
	for tick in range(300):
		harvester.get_node("Body")._process(1.0 / 60.0)
	field.extract(salvage_id, 500, harvester)
	_expect(harvester.cargo.plasteel == 90.0 and field.remaining(field.get_source(salvage_id)) == 0.0, "finite plasteel salvage is collected through the arm")
	harvester.emit_signal("destroyed", harvester)
	_expect(stores.plasteel_units == initial_p and harvester.cargo_total() == 0.0, "destroyed cargo is not delivered")
	var recovered := false
	for source in field.sources:
		if source.label == "Lost harvester cargo" and source.materials.plasteel == 90.0: recovered = true
	_expect(recovered and ops.phase == "lost", "lost cargo remains as a recoverable physical source")
	_test_resource_generation_and_bay_saves(bay)
	if "--rendered" in OS.get_cmdline_user_args(): await _capture_visuals()
	await _test_ramp_cycle(carrier)
	print("HARVESTER_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _setup_ground() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(1600, 2, 1600)
	floor_body.add_child(shape)
	world.add_child(floor_body)
	floor_body.position.y = -1
	var mesh := MeshInstance3D.new()
	mesh.mesh = PlaneMesh.new()
	mesh.mesh.size = Vector2(1600, 1600)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("7c7161")
	mesh.material_override = mat
	world.add_child(mesh)

func _test_authored_arm() -> void:
	var body: Node3D = harvester.get_node("Body")
	_expect(body.has_node("AuthoredHull") and body.has_node("ExtractorHeadMount/AuthoredExtractorHead"), "authored Blender hull and extractor head are used")
	var hull_root := body.get_node("AuthoredHull")
	var hull_mesh := hull_root as MeshInstance3D
	if hull_mesh == null:
		var meshes := hull_root.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty(): hull_mesh = meshes[0] as MeshInstance3D
	_expect(hull_mesh != null, "export keeps the authored hull mesh")
	if hull_mesh != null:
		var material_names: Array[String] = []
		var glass_transparent := false
		for surface in range(hull_mesh.mesh.get_surface_count()):
			var mat := hull_mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if mat == null: continue
			material_names.append(mat.resource_name)
			if mat.resource_name == "glass":
				glass_transparent = mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and mat.albedo_color.a < 0.5
		_expect("Upper fuselage" in material_names and "Grey" in material_names and "Dark cockpit material" in material_names and glass_transparent, "export preserves authored paint, dark surfaces and translucent glass")
	_expect(body.has_node("UpperBoom") and body.has_node("OuterForearm") and body.has_node("TelescopicSection"), "three separate articulated boom sections")
	_expect(body.is_folded(), "replicator and parked vehicle start with boom folded on roof")
	var parked_tip: Vector3 = body._tip
	_expect(absf(parked_tip.x) < 0.01 and parked_tip.y > 1.98 and absf(parked_tip.z) < 3.7, "stowed head sits above and within authored hull footprint")
	for target in [Vector3(6, -1.2, -1.9), Vector3(-6, -1.2, -1.9), Vector3(0, -1.2, 6), Vector3(0, -1.2, -7)]:
		body.arm_target = target
		body.arm_extended = true
		_expect(not body.arm_ready(), "intake cannot extract before unfolding and making contact")
		for frame in range(300):
			body._process(1.0 / 60.0)
			_expect(is_equal_approx(body._upper.scale.y, 1.0) and is_equal_approx(body._lower.scale.y, 1.0) and is_equal_approx(body._slider.scale.y, 1.0), "mechanical sections retain their length while rotating and telescoping")
		_expect(body.arm_ready() and body._tip.distance_to(target) < 0.05, "authored head reaches front, rear and both sides")
		body.arm_extended = false
		for frame in range(300): body._process(1.0 / 60.0)
		_expect(body.is_folded() and body._tip.distance_to(parked_tip) < 0.01, "arm returns to the same roof fold before driving")
	# Clamping an unreachable target must never create false tool contact.
	body.arm_target = Vector3(30, -1.2, 0)
	body.arm_extended = true
	for frame in range(300): body._process(1.0 / 60.0)
	_expect(not body.arm_ready(), "out-of-reach sources cannot be collected through stretched geometry")
	body.arm_extended = false
	for frame in range(300): body._process(1.0 / 60.0)
	body.arm_target = Vector3(0, -1.2, -1.9)
	body.arm_extended = true
	for frame in range(300): body._process(1.0 / 60.0)
	_expect(not body.arm_ready() and body.is_folded(), "unsafe target underneath the hull cannot lower the head through the body")
	body.arm_extended = false
	_test_shared_ramp_orientation()

func _test_shared_ramp_orientation() -> void:
	var carrier := Node3D.new()
	carrier.position = Vector3(200, 0, 200)
	carrier.rotation.y = 0.71
	world.add_child(carrier)
	for scene in ["res://GroundVehicle/ground_vehicle_1.tscn", "res://GroundVehicle/ground_vehicle_2.tscn", "res://GroundVehicle/Harvester.tscn"]:
		var probe: Node3D = load(scene).instantiate()
		world.add_child(probe)
		probe.set_physics_process(false)
		probe.global_position = carrier.to_global(Vector3(0, 1.05, -60))
		probe.rotation.y = carrier.rotation.y + PI
		probe.start_retrieve(carrier, Vector3(0, 0, -60), -10, 20)
		probe._retrieve_phase = probe.RetrievePhase.WAITING
		probe.begin_ramp_ascent()
		var start_z: float = probe._retrieve_local_pos.z
		probe._retrieve_on_ramp(1.0 / 60.0)
		_expect(is_equal_approx(probe._retrieve_local_pos.z, start_z), "ramp waits for U-turn before moving: " + scene)
		for frame in range(80): probe._retrieve_on_ramp(1.0 / 60.0)
		var before := probe.global_position
		probe._retrieve_on_ramp(1.0 / 60.0)
		var travel := probe.global_position - before
		travel.y = 0.0
		_expect(travel.length() > 0.05 and probe.global_basis.z.dot(travel.normalized()) > 0.98, "ramp travel is nose-first on a rotated carrier: " + scene)
		probe.free()
	carrier.free()

func _test_resource_generation_and_bay_saves(bay: Node) -> void:
	var original_bay: Dictionary = bay.capture_save_state()
	var original: Dictionary = field.capture_save_state()
	field.reset()
	for frame in range(300):
		field._seed_terrain(Vector3.ZERO)
		if field.discovered_sources().size() >= 2: break
	var sources: Array = field.discovered_sources()
	_expect(sources.size() >= 2, "incremental campaign seed provides known reachable corium and ruin salvage")
	var found_c := false
	var found_p := false
	for source in sources:
		found_c = found_c or source.materials.corium > 0.0
		found_p = found_p or source.materials.plasteel > 0.0
	_expect(found_c and found_p, "both required materials have physical starting sources")
	var source_count: int = field.sources.size()
	var placement_complete: bool = field.seeded
	field.restore_save_state(field.capture_save_state())
	_expect(field.sources.size() == source_count and field.seeded == placement_complete, "resource saves do not duplicate or reseed sites")
	field.restore_save_state(original)
	bay.restore_save_state({"stored_vehicles": 16})
	_expect(bay.stored_vehicles == 15 and bay.stored_harvesters == 1 and bay.stored_total() == 16, "legacy saves gain one harvester in an existing bay slot")
	bay.restore_save_state({"stored_vehicles": 12, "stored_harvesters": 0})
	_expect(bay.stored_harvesters == 0 and bay.stored_vehicles == 12, "new saves preserve deployed or lost harvester rather than granting another")
	bay.restore_save_state(original_bay)

func _setup_navigation() -> void:
	var grid := root.get_node("TerrainNavGrid")
	var heights := PackedFloat32Array()
	heights.resize(41 * 41)
	heights.fill(0)
	grid._cols = 41
	grid._rows = 41
	grid.cell_size_m = 40.0
	grid._origin_x = -800.0
	grid._origin_z = -800.0
	grid._heights = heights
	grid._h_min_passable = 0.0
	grid._is_baked = true
	grid.query_cell_size_m = 40.0
	grid._query_cols = 41
	grid._query_rows = 41
	grid._query_origin_x = -800.0
	grid._query_origin_z = -800.0
	grid._query_heights = heights.duplicate()
	grid._query_max_heights = heights.duplicate()
	grid._query_height_variation = heights.duplicate()
	grid._query_is_baked = true
	var graph := root.get_node("NavGraph")
	graph._reset_graph()
	graph._build()
	graph._build_spatial_index()
	graph._is_ready = true
	var scheduler := root.get_node("NavPathScheduler")
	scheduler.process_mode = Node.PROCESS_MODE_ALWAYS
	scheduler.min_job_start_interval_s = 0.0
	scheduler.start_jitter_s = 0.0

func _capture_visuals() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("59646a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 46
	camera.look_at_from_position(Vector3(13, 8, 14), Vector3(0, 2.4, 0))
	camera.current = true
	harvester.position = Vector3(0, 1.02, 0)
	harvester.rotation = Vector3.ZERO
	harvester.collection_target = Vector3(8, 0, 0)
	harvester.collecting = true
	harvester.cargo = {"corium": 96.0, "plasteel": 40.0}
	field.add_source("Preview corium", Vector3(8, 0, 0), "corium", {"corium": 200.0}, true)
	harvester._physics_process(0.0)
	for tick in range(240): harvester.get_node("Body")._process(1.0 / 60.0)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/harvester_collecting.png")
	harvester.collecting = false
	harvester._physics_process(0.0)
	for tick in range(240): harvester.get_node("Body")._process(1.0 / 60.0)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/harvester_folded.png")
	var console := root.get_node("CarrierConsole")
	console.show_page("ground_bay", true)
	var page: Control = console.get("_ground_page")
	var panel := page.find_child("HarvesterPanel", true, false)
	panel._refresh()
	_expect(panel.get("_sources").item_count >= 1 and not "UNAVAILABLE" in str(panel.get("_status").text), "command page presents actual cargo and resource sources")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/harvester_command.png")
	console.set_open(false)

func _capture_actual_collection_pose() -> void:
	# Capture the real navigated parking position, not a hand-placed demonstration.
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("59646a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 46
	var center: Vector3 = (harvester.global_position + harvester.collection_target) * 0.5 + Vector3.UP * 1.4
	camera.look_at_from_position(harvester.global_position + Vector3(16, 11, 18), center)
	camera.make_current()
	harvester._physics_process(0.0)
	for tick in range(300): harvester.get_node("Body")._process(1.0 / 60.0)
	for frame in range(12): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_expect(root.get_texture().get_image().save_png("res://captures/harvester_actual_side_parking.png") == OK, "actual side-parking capture saved")
	camera.free()
	sun.free()
	env.free()

func _test_ramp_cycle(old_carrier: Node3D, auto_only := false) -> void:
	old_carrier.remove_from_group("carrier")
	if is_instance_valid(harvester): harvester.queue_free()
	var carrier := RampCarrier.new()
	carrier.position = Vector3(-400, 40, 0)
	var model := preload("res://Models/LandCarrier/Land carrier body.glb").instantiate()
	model.name = "CarrierModel"
	model.rotation.y = PI
	carrier.add_child(model)
	model.owner = carrier
	world.add_child(carrier)
	carrier.set_process(false)
	await get_tree().process_frame
	var bay: Node = carrier.vehicle_bay
	var ramp: Node3D = carrier.vehicle_ramp
	var at := carrier.to_global(Vector3(0, 0, ramp.position.z - 120.0))
	at.y = 0.0
	if auto_only:
		await _test_auto_cycle(bay, at)
		return
	var id: int = field.add_source("Ramp test corium", at, "corium", {"corium": 25.0}, true)
	ops.vehicle = null
	ops.phase = "stored"
	var before_c: float = stores.corium_units
	var before_stock: int = bay.stored_vehicles
	_expect(ops.collect(id, false).is_empty(), "stored harvester accepts physical bay mission")
	var saw_ramp := false
	var saw_cargo := false
	var reversed_return := false
	var backwards_ramp := false
	var deadline := Time.get_ticks_msec() + 55000
	while Time.get_ticks_msec() < deadline:
		ops._process(6.0 / 60.0)
		await get_tree().physics_frame
		if is_instance_valid(ops.vehicle):
			saw_cargo = saw_cargo or ops.vehicle.cargo_total() > 0
			if ops.vehicle.retrieve_mode and ops.vehicle._retrieve_phase >= 2: saw_ramp = true
			if ops.vehicle.retrieve_mode:
				reversed_return = reversed_return or ops.vehicle._reverse_driving
				if ops.vehicle._retrieve_phase == ops.vehicle.RetrievePhase.ON_RAMP:
					backwards_ramp = backwards_ramp or ops.vehicle.global_basis.z.dot(carrier.global_basis.z) < 0.95 and ops.vehicle._retrieve_local_pos.z > ramp.get_hinge_local().z
		if phase_complete(ops, bay): break
	print("HARVESTER_RAMP phase=%s bay=%s stocks=%s/%s corium=%.1f saw_cargo=%s saw_ramp=%s vehicle=%s" % [ops.phase, bay.state, bay.stored_vehicles, bay.stored_harvesters, stores.corium_units - before_c, saw_cargo, saw_ramp, ops.vehicle.global_position if is_instance_valid(ops.vehicle) else Vector3.ZERO])
	_expect(saw_cargo and saw_ramp and ops.phase == "stored" and is_equal_approx(stores.corium_units, before_c + 25.0), "deploy, navigate, collect, return, climb ramp and unload without teleport")
	_expect(bay.stored_harvesters == 1 and bay.stored_vehicles == before_stock, "complete utility journey preserves combat stock")
	_expect(not reversed_return and not backwards_ramp, "return trip and physical ramp climb are forward-facing")
	var recall_id: int = field.add_source("Recall test", at, "corium", {"corium": 30.0}, true)
	_expect(ops.collect(recall_id, true).is_empty(), "second collection accepted")
	ops._process(0.1)
	_expect(ops.phase == "deploying", "next harvester launch reserved the shared bay")
	ops.recall()
	deadline = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		ops._process(6.0 / 60.0)
		await get_tree().physics_frame
		if phase_complete(ops, bay): break
	_expect(ops.phase == "stored" and field.remaining(field.get_source(recall_id)) == 30.0 and is_equal_approx(stores.corium_units, before_c + 25.0), "recall during deployment finishes ramp clearance and returns without collecting")
	if "--auto-cycle" in OS.get_cmdline_user_args():
		await _test_auto_cycle(bay, at)

func _test_auto_cycle(bay: Node, at: Vector3) -> void:
	# Exercise autonomous selection across two complete physical unloads.
	for source in field.sources: source.discovered = false
	var first: int = field.add_salvage_source("Auto close ruin", at, 20.0, "auto_cycle_1", true)
	var second: int = field.add_salvage_source("Auto next ruin", at + Vector3(60, 0, -15), 25.0, "auto_cycle_2", true)
	var before_plasteel: float = stores.plasteel_units
	_expect(ops.order_auto_harvest().is_empty(), "automatic harvesting accepted in real bay")
	var selected_ids: Array[int] = []
	var deadline := Time.get_ticks_msec() + 95000
	var next_diagnostic := 0
	while Time.get_ticks_msec() < deadline:
		ops._process(6.0 / 60.0)
		await get_tree().physics_frame
		if ops.source_id >= 0 and not ops.source_id in selected_ids: selected_ids.append(ops.source_id)
		if is_instance_valid(ops.vehicle) and Time.get_ticks_msec() > next_diagnostic:
			next_diagnostic = Time.get_ticks_msec() + 10000
			var body: Node3D = ops.vehicle.get_node("Body")
			print("HARVESTER_AUTO_STATE phase=%s at=%s cargo=%s arm_ready=%s tip_error=%.2f target=%s" % [ops.phase, ops.vehicle.global_position, ops.vehicle.cargo, body.arm_ready(), body._tip.distance_to(body.arm_target), body.arm_target])
		if ops.phase == "auto_wait" and not is_instance_valid(ops.vehicle) and bay.state == 0 and is_equal_approx(stores.plasteel_units, before_plasteel + 45.0): break
	_expect(selected_ids == [first, second], "automatic harvesting completes closest site before selecting next")
	_expect(ops.phase == "auto_wait" and not is_instance_valid(ops.vehicle) and is_equal_approx(stores.plasteel_units, before_plasteel + 45.0), "two automatic trips physically unload all 45 plasteel")
	_expect(field.remaining(field.get_source(first)) == 0.0 and field.remaining(field.get_source(second)) == 0.0, "automatic extraction preserves finite stocks")
	ops.recall()
	ops._process(5.0)
	_expect(ops.phase == "stored" and ops.mission == "RTB", "return order disables automation after unloading")
	print("HARVESTER_AUTO_CYCLE selected=%s phase=%s delivered=%.1f" % [selected_ids, ops.phase, stores.plasteel_units - before_plasteel])

func phase_complete(service: Node, bay: Node) -> bool:
	return service.phase == "stored" and bay.state == 0 and not is_instance_valid(service.vehicle)

