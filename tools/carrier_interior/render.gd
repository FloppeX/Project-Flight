extends SceneTree
const OUT := "D:/3D printing files/Carrier interior review/"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var model: Node3D = load("res://Models/LandCarrier/CarrierWithInterior.tscn").instantiate()
	scene.add_child(model)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.22, 0.28)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.86, 1.0)
	env.environment.ambient_light_energy = 0.75
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	scene.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 75
	camera.near = 0.05
	scene.add_child(camera)
	camera.current = true
	await create_timer(2).timeout
	root.size = Vector2i(1280, 720)
	camera.position = Vector3(16.5, 1.65, -3.945)
	camera.look_at(Vector3(18.6, 1.1, -3.945))
	await capture("godot_door_closed.png")
	for door in model.get_children():
		if door.get_script() == load("res://LandCarrier/CarrierSlidingDoor.gd"):
			door.set_physics_process(false)
			door.openness = 1.0
			door._apply_pose()
	await capture("godot_door_open.png")
	camera.position = Vector3(20.42, 1.7, 3.0)
	camera.look_at(Vector3(20.42, 2.5, 6.3))
	await capture("godot_stairwell.png")
	print("INTERIOR_RENDER_OK")
	quit()

func capture(filename: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + filename)
