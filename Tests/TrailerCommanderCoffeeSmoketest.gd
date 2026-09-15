extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	create_timer(45).timeout.connect(func(): quit(1))
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_node("GameSession").set("is_trailer_scenario", true)
	root.get_node("PauseMenu").visible = false
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	stage.add_to_group("carrier")
	var commander: Node3D = load("res://LandCarrier/Commander.tscn").instantiate()
	stage.add_child(commander)
	commander.set_physics_process(false)
	await process_frame
	var coffee := commander.get_node("BodyVisualCoffee")
	var player := coffee.get_node("AnimationPlayer") as AnimationPlayer
	check(player.current_animation == "Coffee_Hold", "trailer starts holding coffee")
	var controller: Node = load("res://Scenario/Trailer/TrailerAircraftCameras.gd").new()
	stage.add_child(controller)
	controller.set_process(false)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	paused = true
	for slot in 5:
		controller.select_slot(slot, stage)
		player.play("Coffee_Hold")
		controller._input(key)
		check(player.current_animation == "Coffee_Sip", "B from filming slot %d" % slot)
		check(paused, "B preserves pause")
		player.advance(0.7)
		var before := player.current_animation_position
		controller._input(key)
		check(is_equal_approx(before, player.current_animation_position), "repeat does not restart sip")
		await process_frame
		check(is_equal_approx(before, player.current_animation_position), "sip frozen while paused")
		player.advance(4.2)
		check(player.current_animation == "Coffee_Hold", "sip returns to hold")
	controller.active = false
	controller.piloting = true
	controller._input(key)
	check(player.current_animation == "Coffee_Hold", "cockpit B not intercepted")
	controller.piloting = false
	controller.active = true
	key.echo = true
	controller._input(key)
	check(player.current_animation == "Coffee_Hold", "key echo ignored")
	key.echo = false
	key.ctrl_pressed = true
	controller._input(key)
	check(player.current_animation == "Coffee_Hold", "modified B ignored")
	key.ctrl_pressed = false
	controller._input(key)
	paused = false
	await create_timer(0.25).timeout
	check(player.current_animation_position > 0.1, "queued sip advances on unpause")
	paused = true
	commander._update_body_visibility(false)
	check(coffee.visible and not commander.get_node("BodyVisual").visible, "only coffee officer visible")
	if DisplayServer.get_name() != "headless":
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.09, 0.115, 0.15)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_energy = 0.7
		stage.add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-40, -35, 0)
		stage.add_child(light)
		var camera := Camera3D.new()
		stage.add_child(camera)
		camera.position = Vector3(-2.4, 2.1, 4)
		camera.look_at(Vector3(0, 0.95, 0))
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.15
		camera.make_current()
		for pose in ["Coffee_Hold", "Coffee_Sip"]:
			player.play(pose)
			player.advance(0 if pose == "Coffee_Hold" else 1.8)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/trailer_commander_%s.png" % pose)
	paused = false
	stage.queue_free()
	await process_frame
	print("TRAILER_COMMANDER_COFFEE_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
