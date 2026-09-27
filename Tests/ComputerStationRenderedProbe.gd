extends SceneTree

const OUTPUT_DIR := "res://captures/computer_station_probe"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "ComputerStationRenderedProbe"
	root.add_child(scene)
	current_scene = scene

	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color("090d10")
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color("a9c4cf")
	environment_resource.ambient_light_energy = 1.15
	environment.environment = environment_resource
	scene.add_child(environment)

	var carrier_model_scene := load("res://Models/LandCarrier/Land carrier 4.glb") as PackedScene
	var station_scene := load("res://LandCarrier/ComputerStation.tscn") as PackedScene
	var commander_scene := load("res://LandCarrier/Commander.tscn") as PackedScene
	if carrier_model_scene == null or station_scene == null or commander_scene == null:
		push_error("[ComputerStationRenderedProbe] required scene unavailable")
		quit(1)
		return

	var carrier_model := carrier_model_scene.instantiate() as Node3D
	carrier_model.rotation.y = PI
	scene.add_child(carrier_model)

	var station := station_scene.instantiate() as Node3D
	station.position = Vector3(-19.2, 8.863214, 2.5)
	station.rotation.y = -PI * 0.5
	scene.add_child(station)

	var commander := commander_scene.instantiate() as CharacterBody3D
	commander.transform = Transform3D(
		Vector3(0.9957665, 0, -0.09191874),
		Vector3(0, 1, 0),
		Vector3(0.09191874, 0, 0.9957665),
		Vector3(-21.891285, 8.863214, 2.5103567)
	)
	scene.add_child(commander)

	var key_light := OmniLight3D.new()
	key_light.position = Vector3(-21.5, 14.2, 2.5)
	key_light.light_color = Color("d7eef5")
	key_light.light_energy = 9.0
	key_light.omni_range = 9.0
	scene.add_child(key_light)

	await process_frame
	await process_frame
	commander.set_physics_process(false)
	commander.set_process(false)
	var camera := commander.get_node("Camera3D") as Camera3D
	camera.current = true
	var interaction_target := station.get_node("InteractionTarget") as Marker3D
	var to_screen := interaction_target.global_position - camera.global_position
	camera.global_position += to_screen.normalized() * 0.4
	camera.look_at(interaction_target.global_position, Vector3.UP)
	if float(station.call("get_interaction_score", camera)) == -INF:
		push_error("[ComputerStationRenderedProbe] approach camera does not hit the screen interaction area")
		quit(1)
		return
	station.call("set_interaction_available", true)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	_save_frame("approach.png")

	station.call("set_interaction_available", false)
	var seated_global: Transform3D = station.call("get_camera_anchor_transform") as Transform3D
	camera.transform = commander.global_transform.affine_inverse() * seated_global
	camera.fov = float(station.call("get_seated_camera_fov"))
	await create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	_save_frame("seated_screen.png")

	var viewport_size := root.get_viewport().get_visible_rect().size
	var viewport_aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var focused_global: Transform3D = station.call(
		"get_screen_focus_camera_transform"
	) as Transform3D
	camera.transform = commander.global_transform.affine_inverse() * focused_global
	camera.fov = float(station.call("get_screen_focus_fov", viewport_aspect))
	await create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	_save_frame("focused_screen.png")

	var console := root.get_node_or_null("CarrierConsole")
	if console != null:
		console.call("show_page", "tactical", true)
		await create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		_save_frame("tactical_view.png")
		console.call("set_open", false)

	camera.global_position = station.global_position + Vector3(2.7, 2.2, -2.7)
	camera.look_at(station.global_position + Vector3(0.0, 0.8, 0.0), Vector3.UP)
	camera.fov = 52.0
	await create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	_save_frame("station_three_quarter.png")

	print(
		"[ComputerStationRenderedProbe] PASS output=%s"
		% ProjectSettings.globalize_path(OUTPUT_DIR)
	)
	quit(0)


func _save_frame(file_name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUTPUT_DIR, file_name]
	var save_error := image.save_png(path)
	if save_error != OK:
		push_error("[ComputerStationRenderedProbe] could not save %s" % file_name)
