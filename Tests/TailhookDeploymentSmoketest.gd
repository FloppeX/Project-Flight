extends SceneTree

var failures: Array[String] = []

func strip_scripts(node: Node) -> void:
	for child in node.get_children():
		strip_scripts(child)
	if node.name != "TailHook":
		node.set_script(null)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var aircraft := load("res://Aircraft/Aircraft_1.tscn").instantiate() as RigidBody3D
	strip_scripts(aircraft)
	aircraft.freeze = true
	scene.add_child(aircraft)
	var hook := aircraft.get_node("TailHook")
	hook.set_technical_index_preview_fraction(1.0)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(9, -3, -5)
	camera.look_at(Vector3(0, -1, 0))
	camera.make_current()
	var light := DirectionalLight3D.new()
	scene.add_child(light)
	light.rotation_degrees = Vector3(30, -50, 0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.2, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7
	scene.add_child(env)
	await process_frame
	var authored_tip: Transform3D = hook.transform
	for fraction in [0.0, 0.5, 1.0]:
		hook.set_technical_index_preview_fraction(fraction)
		var visual: Node3D = hook.get_node("Tailhook")
		var visual_in_aircraft: Transform3D = hook.transform * visual.transform
		_check(visual_in_aircraft.origin.is_equal_approx(hook.stowed_mount_position.lerp(hook.position, fraction)), "tip extends from belly mount")
		if fraction > 0.0:
			_check((visual_in_aircraft * Vector3(0, hook._shaft_length, 0)).is_equal_approx(hook.stowed_mount_position), "shaft remains anchored at mount")
		_check(hook.transform == authored_tip, "wire capture point unchanged")
		if "--rendered" in OS.get_cmdline_user_args():
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://logs/tailhook_%d.png" % int(fraction * 100))
	hook.set_technical_index_preview_fraction(0.0)
	hook.deploy()
	await create_timer(hook.deployment_duration_s * 0.5).timeout
	_check(hook._visual_fraction > 0.1 and hook._visual_fraction < 0.95, "deployment animates rather than popping")
	var mid_fraction: float = hook._visual_fraction
	hook.stow()
	_check(is_equal_approx(hook._visual_fraction, mid_fraction), "reversal does not snap")
	await create_timer(hook.deployment_duration_s + 0.1).timeout
	_check(is_zero_approx(hook._visual_fraction) and not hook.get_node("Tailhook").visible, "stow finishes hidden")
	hook.deploy()
	await create_timer(hook.deployment_duration_s + 0.1).timeout
	_check(is_equal_approx(hook._visual_fraction, 1.0) and hook._is_deployed, "deployment completes")
	for model in ["Aircraft_2", "Aircraft_5", "Aircraft_7", "Aircraft_8", "Aircraft_14", "CompleteFighterJet"]:
		var other := load("res://Aircraft/%s.tscn" % model).instantiate() as RigidBody3D
		strip_scripts(other)
		var other_hook := other.get_node("TailHook")
		var original: Transform3D = other_hook.transform
		other_hook.set_technical_index_preview_fraction(1.0)
		var visual: Transform3D = other_hook.transform * other_hook.get_node("Tailhook").transform
		_check(visual.origin.is_equal_approx(original.origin), model + " retains deployed tip")
		_check((visual * Vector3(0, other_hook._shaft_length, 0)).is_equal_approx(other_hook.stowed_mount_position), model + " uses belly mount")
		other.free()
	for failure in failures:
		push_error(failure)
	print("TAILHOOK_DEPLOYMENT ", "PASS" if failures.is_empty() else "FAIL", " mount+extension+capture_point+animation+reversal")
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
