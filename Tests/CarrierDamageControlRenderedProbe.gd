extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	# The console is an autoload: its preview already exists when the gameplay
	# scene installs an environment into the root world.
	var world_environment := WorldEnvironment.new()
	world_environment.environment = Environment.new()
	world_environment.environment.background_mode = Environment.BG_COLOR
	world_environment.environment.background_color = Color("777777")
	world.add_child(world_environment)
	var carrier := (load("res://LandCarrier/LandCarrier2.tscn") as PackedScene).instantiate() as Node3D
	carrier.set_script(load("res://Tests/Fixtures/ModularTurretCarrierFixture.gd"))
	carrier.process_mode = Node.PROCESS_MODE_DISABLED
	for child in carrier.get_children():
		if child.name not in ["CarrierModel", "CarrierDamageControl", "CarrierDefenseLoadout", "CarrierManager"] and not child.has_method("build_turret"):
			carrier.remove_child(child)
			child.free()
	world.add_child(carrier)
	await process_frame
	await process_frame
	var control := carrier.get_node("CarrierDamageControl")
	control.call("refresh_regions")
	control.set("structure", 1460.0)
	control.call("damage_system", "drive", 46.0)
	control.call("damage_system", "catapults", 77.0)
	control.call("damage_system", "island", 37.0)
	var systems: Dictionary = control.get("systems")
	systems.catapults.fire = 42.0
	control.call("advance", 0.25)
	carrier.get_node("CarrierManager").set("plasteel_units", 180.0)
	var console := root.get_node("CarrierConsole")
	console.call("show_page", "carrier", true)
	var page: Control = console.get("_carrier_page")
	page.call("bind_damage_control", control)
	page.call("_select_system", "catapults")
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var state: Dictionary = page.call("get_debug_snapshot")
		if state.wireframe.get("model_loaded", false):
			break
		await process_frame
	var state: Dictionary = page.call("get_debug_snapshot")
	var schematic: Control = page.get("_wireframe_view")
	var viewport: SubViewport = schematic.get("_preview_viewport")
	print("SCHEMATIC_DIAGNOSTIC camera=%s world=%s environment=%s" % [viewport.get_camera_3d(), viewport.find_world_3d(), viewport.find_world_3d().environment])
	var switcher := preload("res://Tests/Fixtures/SchematicCameraControllerFixture.gd").new()
	world.add_child(switcher)
	switcher.call("_deactivate_all_cameras")
	await process_frame
	if viewport.get_camera_3d() != schematic.get("_preview_camera"):
		push_error("Gameplay camera switching stole the schematic camera")
		quit(1)
		return
	console.call("show_page", "tactical", true)
	switcher.call("_deactivate_all_cameras")
	console.call("show_page", "carrier", true)
	if viewport.get_camera_3d() != schematic.get("_preview_camera"):
		push_error("Schematic camera missing after reopening the Carrier tab")
		quit(1)
		return
	if not state.wireframe.get("model_loaded", false):
		push_error("Damage control schematic failed to load")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/carrier_damage_control"))
	for size in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.content_scale_size = size
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/carrier_damage_control/status_%d.png" % size.x)
	print("CARRIER_DAMAGE_CONTROL_RENDERED_OK statuses=%s regions=%s" % [state.wireframe.region_statuses, state.wireframe.authored_region_geometry_counts])
	console.call("set_open", false)
	quit(0)
