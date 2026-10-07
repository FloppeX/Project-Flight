extends SceneTree

var _settings: Node
var _caption: Label
var _dim_capture: Image


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_settings = root.get_node("PauseMenu")
	_settings.set("_display_mode_index", 0)
	_settings.set("_resolution_index", 1)
	await process_frame
	for autoload in root.get_children():
		autoload.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_node("FloatingOrigin").set("enabled", false)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera3D.new()
	camera.position.y = 150.0
	world.add_child(camera)
	camera.current = true
	camera.fov = 75.0
	camera.far = 1000.0
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.58, 0.66, 0.73)
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	environment.glow_strength = 0.85
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.5
	var environment_node := WorldEnvironment.new()
	environment_node.environment = environment
	world.add_child(environment_node)
	var aircraft := RigidBody3D.new()
	aircraft.freeze = true
	aircraft.position.y = 150.0
	aircraft.rotation.y = PI
	world.add_child(aircraft)
	aircraft.linear_velocity = Vector3(0, 0, -85)
	var hud: Node3D = load("res://HUD/HeadsUpDisplay.tscn").instantiate()
	hud.scale = Vector3.ONE
	hud.position = Vector3(0, 150, -0.85)
	hud.set("hud_glass_size", Vector2.ONE)
	world.add_child(hud)
	hud.set("aircraft", aircraft)
	hud.set("cam", camera)
	await process_frame
	await process_frame
	hud.set_process(false)
	(hud.get("ccip_update_timer") as Timer).stop()
	var target := Node3D.new()
	target.position = Vector3(45, 150, -300)
	world.add_child(target)
	hud.call("_update_target_cues_for_target", target)
	_caption = Label.new()
	_caption.position = Vector2(40, 30)
	_caption.add_theme_font_size_override("font_size", 28)
	_caption.add_theme_color_override("font_color", Color.BLACK)
	world.add_child(_caption)
	var colors := ["green", "amber", "blue", "pink", "white"]
	for index in range(colors.size()):
		_settings.set_hud_appearance(index, 2, false)
		_caption.text = "HUD COLOR: %s / BRIGHTNESS: 100%%" % colors[index].to_upper()
		await _capture("hud_" + colors[index])
	for brightness in [0, 4]:
		_settings.set_hud_appearance(0, brightness, false)
		_caption.text = "HUD COLOR: GREEN / BRIGHTNESS: %s" % ("50%" if brightness == 0 else "200%")
		await _capture("hud_brightness_" + str(brightness))
	_caption.visible = false
	_settings.set_hud_appearance(1, 3, false)
	_settings.set("_opentrack_enabled", true)
	_settings.call("_refresh_gameplay_button_labels")
	_settings.set("visible", true)
	_settings.call("_show_screen", "gameplay")
	await _capture("hud_gameplay_options")
	_settings.set("visible", false)
	current_scene = null
	world.queue_free()
	await process_frame
	print("[HudAppearanceRenderedProbe] PASS captures=8 renderer=Forward+")
	quit(0)


func _capture(name: String) -> void:
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	if name == "hud_brightness_0":
		_dim_capture = screenshot
	elif name == "hud_brightness_4":
		var brighter_pixels := 0
		# Exclude the caption: require a visible change on the actual 3D HUD.
		for y in range(110, 760):
			for x in range(460, 1140):
				if screenshot.get_pixel(x, y).g > _dim_capture.get_pixel(x, y).g + 0.05:
					brighter_pixels += 1
		if brighter_pixels < 500:
			push_error("HUD brightness did not visibly change: %d brighter pixels" % brighter_pixels)
			quit(1)
			return
		print("[HudAppearanceRenderedProbe] brightness_changed_pixels=%d" % brighter_pixels)
	var path := "res://logs/" + name + ".png"
	var result := screenshot.save_png(path)
	if result != OK:
		push_error("Screenshot failed: " + path)
		quit(1)
	print("[HudAppearanceRenderedProbe] saved " + path)
