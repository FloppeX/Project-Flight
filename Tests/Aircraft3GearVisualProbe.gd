extends SceneTree

const AIRCRAFT := preload("res://Aircraft/Aircraft_3.tscn")
const MODEL_GEAR := ["landing gear struts", "Cylinder", "Cylinder_002", "Cylinder_004", "Object_003"]
const GODOT_GEAR := ["CenterGearCollider/nose gear pivot point", "RightGearCollider/right gear pivot point", "LeftGearCollider/left gear pivot point"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	var aircraft := AIRCRAFT.instantiate() as RigidBody3D
	aircraft.freeze = true
	root.add_child(aircraft)
	await process_frame
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("273340")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	root.add_child(environment)
	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-40, -35, 0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/aircraft3_gear"))
	for style in ["blender", "godot"]:
		for name in MODEL_GEAR:
			aircraft.get_node("Aircraft 3/" + name).visible = style == "blender"
		for path in GODOT_GEAR:
			aircraft.get_node(path).visible = style == "godot"
		for view in ["side", "below"]:
			camera.position = Vector3(11, -0.5, 0) if view == "side" else Vector3(7, -9, -9)
			camera.look_at(Vector3(0, -0.5, -0.5))
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/aircraft3_gear/%s_%s.png" % [style, view])
	print("AIRCRAFT3_GEAR_VISUAL_PROBE_OK")
	quit()
