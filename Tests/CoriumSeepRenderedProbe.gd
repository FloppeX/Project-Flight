extends SceneTree

const SEEP_SCRIPT: Script = preload("res://POI/World/CoriumSeepVisual.gd")
const OUTPUT_DIR := "res://captures/corium"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var scene := Node3D.new()
	scene.name = "CoriumSeepRenderedProbe"
	root.add_child(scene)
	current_scene = scene
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("697275")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bcc0cc")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	scene.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(80.0, 80.0)
	ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("807164")
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	scene.add_child(ground)
	var seep: Node3D = SEEP_SCRIPT.new()
	scene.add_child(seep)
	seep.setup(7)
	var harvester_scene := load("res://GroundVehicle/Harvester.tscn") as PackedScene
	var harvester := harvester_scene.instantiate() as Node3D
	scene.add_child(harvester)
	harvester.position = Vector3(-6.5, 1.02, 0.0)
	harvester.set_physics_process(false)
	var arm := harvester.get_node("Body")
	arm.arm_target = arm.to_local(Vector3(0.0, 0.15, 0.0))
	arm.arm_extended = true
	arm.suction = true
	for frame in range(360):
		arm._process(1.0 / 60.0)
	var camera := Camera3D.new()
	camera.fov = 45.0
	scene.add_child(camera)
	camera.look_at_from_position(Vector3(11.0, 10.0, 15.0), Vector3(-2.2, 1.1, 0.0))
	camera.current = true
	var overlay := CanvasLayer.new()
	scene.add_child(overlay)
	var title := Label.new()
	title.position = Vector2(42.0, 36.0)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(title)
	var note := Label.new()
	note.position = Vector2(44.0, 80.0)
	note.add_theme_font_size_override("font_size", 21)
	note.add_theme_color_override("font_shadow_color", Color.BLACK)
	note.add_theme_constant_override("shadow_offset_x", 2)
	note.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(note)
	var output_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if output_error != OK:
		push_error("CORIUM_RENDER_FAIL could not create capture folder")
		quit(1)
		return
	for phase in ["seeping", "dormant", "exhausted"]:
		var surface := 160.0 if phase == "seeping" else (80.0 if phase == "dormant" else 0.0)
		seep.update_source({"id": 7, "kind": "corium", "materials": {"corium": surface}, "initial": 1100.0, "reserve_corium": 940.0 if phase != "exhausted" else 0.0, "surface_capacity": 160.0, "seep_phase": phase})
		title.text = "CORIUM / %s" % phase.to_upper()
		note.text = {"seeping": "A toxic surface seep. The harvester collects the exposed material.", "dormant": "The seep is quiet. Exposed residue remains collectable.", "exhausted": "The underground reserve and exposed material are spent."}[phase]
		arm.suction = phase != "exhausted"
		for frame in range(16):
			await process_frame
		await RenderingServer.frame_post_draw
		var output := OUTPUT_DIR.path_join("corium_%s.png" % phase)
		var error := root.get_texture().get_image().save_png(output)
		if error != OK:
			push_error("CORIUM_RENDER_FAIL screenshot=%s error=%s" % [output, error_string(error)])
			quit(1)
			return
		print("CORIUM_RENDER_CAPTURE %s" % ProjectSettings.globalize_path(output))
	var before: float = seep.get("_elapsed")
	paused = true
	for frame in range(4):
		await process_frame
	if not is_equal_approx(before, float(seep.get("_elapsed"))):
		push_error("CORIUM_RENDER_FAIL seep animation advanced while paused")
		quit(1)
		return
	paused = false
	print("CORIUM_RENDER_PASS active / dormant / exhausted captured; pause verified")
	quit(0)
