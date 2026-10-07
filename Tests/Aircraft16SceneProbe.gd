extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)
		push_error("AIRCRAFT16: " + reason)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var aircraft := load("res://Aircraft/Aircraft_16.tscn").instantiate() as RigidBody3D
	aircraft.freeze = true
	world.add_child(aircraft)
	await process_frame
	check(aircraft.get_node("Model").scene_file_path == "res://Models/Aircraft_16/aircraft_16.blend", "model must use the editable Blender asset directly")
	aircraft.get_node("AIPilot").set_physics_process(false)
	aircraft.get_node("AIPilot").set_process(false)
	var reference := load("res://Aircraft/Aircraft_3.tscn").instantiate() as RigidBody3D
	check(aircraft.max_health > reference.max_health, "durability must exceed Aircraft 3")
	check(aircraft.get_node("Engine").PowerFactor > reference.get_node("Engine").PowerFactor, "engine must be more powerful")
	for axis in ["pitch_power", "roll_power", "yaw_power"]:
		check(aircraft.get_node("SimpleAero").get(axis) < reference.get_node("SimpleAero").get(axis), axis + " must be less agile")
	reference.free()
	check(aircraft.get_node("Engine").propeller != null, "propeller did not bind")
	var gear := aircraft.get_node("LandingGear")
	check(gear.gear_collision_shapes.size() == 3 and gear.gear_visuals.size() == 3, "three moving wheel assemblies required")
	for index in 3:
		check(is_instance_valid(gear.gear_visuals[index]), "missing wheel visual %d" % index)
		check(is_instance_valid(gear.gear_collision_shapes[index]) and not gear.gear_collision_shapes[index].disabled, "missing deployed wheel collider %d" % index)
	check(gear.move_colliders_with_suspension, "physical suspension must move wheel colliders")
	var weapons := aircraft.get_node("ControlWeapons")
	check(weapons.hardpoints.size() == 5, "five weapon stations required")
	for hardpoint in weapons.hardpoints:
		check(hardpoint.weapon_instance != null, "unmounted weapon: " + str(hardpoint.name))
	check(weapons.weapon_types.has("Guns") and weapons.weapon_types.has("Bomb") and weapons.weapon_types.has("Rocket Pod"), "gun/bomb/rocket loadout: " + str(weapons.weapon_types))
	var panel := aircraft.get_node("InstrumentPanel")
	panel.set_view_updates_active(true)
	await process_frame
	var display := panel.get_live_panel() as Node3D
	check(display != null, "pooled instrument display failed")
	if display:
		check(display.get("model_panel_mesh") == panel.resolve_model_panel_mesh(), "display not bound to instrument surface")
	var damage := aircraft.get_node("PartDamageModel")
	check(damage.get("_zone_colliders").size() == 6, "six structural damage zones required")
	var pilot := aircraft.get_node("CockpitPilot")
	check(pilot.ensure_static_preview_visual() != null, "pilot visual failed")
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("273340")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -35, 0)
	world.add_child(sun)
	if DisplayServer.get_name() != "headless":
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.make_current()
		camera.fov = 65
		var capture_dir := "res://captures/aircraft16"
		if "--normals-before" in OS.get_cmdline_user_args():
			capture_dir += "/normals_before"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_dir))
		for view in ["exterior", "side", "opposite", "underside", "rear", "folded", "cockpit"]:
			if view == "exterior":
				camera.position = Vector3(9, 4.5, 10.5)
				camera.look_at(Vector3(0, -0.1, 0))
			elif view == "side":
				camera.position = Vector3(15, 1, 0)
				camera.look_at(Vector3(0, 0, 0))
			elif view == "opposite":
				camera.position = Vector3(-9, 4.5, 10.5)
				camera.look_at(Vector3(0, 0, 0))
			elif view == "underside":
				camera.position = Vector3(7, -7, 8)
				camera.look_at(Vector3(0, 0, 0))
			elif view == "rear":
				camera.position = Vector3(-7, 4, -10)
				camera.look_at(Vector3(0, 0, -1))
			elif view == "folded":
				aircraft.set_meta("parking_brake", true)
				aircraft.get_node("WingFold").set_technical_index_preview_fraction(1.0)
				camera.position = Vector3(9, 4.5, 10.5)
				camera.look_at(Vector3(0, 0, 0))
			else:
				aircraft.set_meta("parking_brake", false)
				aircraft.get_node("WingFold").set_technical_index_preview_fraction(0.0)
				camera.current = false
				var cockpit := aircraft.get_node("CameraCockpit/Camera3D") as Camera3D
				cockpit.make_current()
				panel.set_view_updates_active(true)
			for frame in 30:
				await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(capture_dir + "/" + view + ".png") == OK, "capture failed")
	print("AIRCRAFT16_SCENE_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	aircraft.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
