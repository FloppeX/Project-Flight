extends SceneTree

const Logo = preload("res://UI/MenuLogo3D.gd")
var failures: Array[String] = []
var _render := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_render = "--render" in OS.get_cmdline_user_args()
	var full_menu := "--full-menu" in OS.get_cmdline_user_args()
	var host: Node
	var logo: SubViewportContainer
	var exterior: Camera3D
	if full_menu:
		host = (load("res://UI/MainMenu.tscn") as PackedScene).instantiate()
		root.add_child(host)
		current_scene = host
		logo = host.get("_brand_logo") as SubViewportContainer
		exterior = host.get("_camera") as Camera3D
		var loading := root.get_node_or_null("LoadingScreen") as CanvasLayer
		if loading != null:
			loading.visible = false
	else:
		host = Node3D.new()
		root.add_child(host)
		current_scene = host
		exterior = Camera3D.new()
		host.add_child(exterior)
		exterior.current = true
		var backdrop := ColorRect.new()
		backdrop.color = Color(0.04, 0.05, 0.06)
		backdrop.size = Vector2(1920, 1080)
		host.add_child(backdrop)
		logo = Logo.new()
		logo.position = Vector2(240, 160)
		logo.size = Vector2(1440, 480)
		host.add_child(logo)
	await process_frame
	await process_frame
	_expect(root.get_camera_3d() == exterior, "logo stole the menu exterior camera")
	_expect(logo.mouse_filter == Control.MOUSE_FILTER_IGNORE, "logo intercepts menu clicks")
	_expect(logo.focus_mode == Control.FOCUS_NONE, "logo entered keyboard/controller focus")
	var viewport := logo.get("_viewport") as SubViewport
	_expect(viewport.own_world_3d and viewport.transparent_bg, "logo is not an isolated transparent world")
	var model := logo.get("_logo") as Node3D
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	_expect(meshes.size() == (11 if Logo.SPIN_EXPERIMENT else 6), "unexpected logo mesh count")
	for child in meshes:
		_expect((child as MeshInstance3D).material_override is ShaderMaterial, "flat palette missing")
	var pivot := logo.get("_pivot") as Node3D
	var camera := logo.get("_camera") as Camera3D
	var saved_time := float(logo.get("_elapsed"))
	logo.set_process(false)
	var previous_pose := pivot.transform
	var changed := false
	for tick in 120:
		logo.set("_elapsed", float(tick) * 0.5)
		logo.call("_apply_pose")
		changed = changed or not pivot.transform.is_equal_approx(previous_pose)
		if not Logo.SPIN_EXPERIMENT:
			_expect(absf(pivot.rotation_degrees.y) <= 7.01, "yaw exceeds readable tilt limit")
		_expect(absf(pivot.rotation_degrees.x) <= 4.21, "pitch exceeds readable tilt limit")
		for child in meshes:
			var mesh := child as MeshInstance3D
			for corner in 8:
				var point := camera.unproject_position(mesh.to_global(mesh.get_aabb().get_endpoint(corner)))
				_expect(Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(point), "animated logo clips viewport")
	_expect(changed, "logo never changes its 3D pose")
	logo.set("_elapsed", saved_time)
	logo.call("_apply_pose")
	logo.set_process(true)

	if _render:
		await create_timer(6.0 if full_menu else 0.5).timeout
		logo.set_process(false)
		logo.set("_elapsed", 0.0)
		logo.call("_apply_pose")
		await _capture("main_front" if full_menu else "isolated_front")
		logo.set("_elapsed", 4.0)
		logo.call("_apply_pose")
		await _capture("main_sway" if full_menu else "isolated_sway")
		if Logo.SPIN_EXPERIMENT:
			for pose in [{"time": 4.4, "name": "spin_edge"}, {"time": 7.0, "name": "spin_rear"}, {"time": 14.0, "name": "spin_return"}]:
				logo.set("_elapsed", pose.time)
				logo.call("_apply_pose")
				await _capture(pose.name)

	if full_menu:
		host.call("_show_setup_menu")
		_expect(not logo.visible and not logo.is_processing(), "logo still animates in campaign setup")
		_expect(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden logo keeps rendering")
		_expect((host.get("_brand_title_label") as Label).visible, "setup title disappeared")
		_expect(is_equal_approx((host.get("_system_id_label") as Label).position.y, 140.0), "setup caption overlaps title")
		_expect(root.get_camera_3d() == exterior, "setup switched to logo camera")
		if _render:
			await _capture("setup")
		host.call("_show_technical_index")
		_expect(not logo.visible, "logo overlaps Technical Index")
		_expect((host.get("_brand_title_label") as Label).text == "TECHNICAL INDEX", "reference title changed")
		host.call("_show_developer_menu")
		_expect(not logo.visible, "logo overlaps scenario title")
		host.call("_show_main_menu")
		_expect(logo.visible and logo.is_processing(), "logo did not resume on main menu")
		_expect(not (host.get("_brand_title_label") as Label).visible, "duplicate text title behind logo")
		_expect(root.get_camera_3d() == exterior, "main menu failed to retain exterior camera")
		var scale_before := (host.get("_ui_root") as Control).scale
		root.size = Vector2i(1280, 720)
		await process_frame
		host.call("_layout_ui_root")
		_expect((host.get("_ui_root") as Control).scale.x <= scale_before.x, "logo UI did not scale down")
		if _render:
			await _capture("main_720p")
	else:
		logo.hide()
		_expect(not logo.is_processing(), "hidden logo animation did not pause")
		_expect(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden viewport is active")
		logo.show()
		_expect(logo.is_processing(), "logo did not resume after showing")

	print("MAIN_MENU_LOGO_SMOKETEST ", JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL", "full_menu":full_menu, "failures":failures}))
	host.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _capture(label: String) -> void:
	# Let the SubViewport texture and its parent canvas both settle after a pose change.
	for frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://logs/menu_logo_%s.png" % label
	_expect(image.save_png(path) == OK, "could not save " + path)


func _expect(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
		push_error("MAIN_MENU_LOGO_SMOKETEST_FAIL: " + message)
