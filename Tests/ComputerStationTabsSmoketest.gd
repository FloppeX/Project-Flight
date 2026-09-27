extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var packed := load("res://LandCarrier/ComputerStation.tscn") as PackedScene
	var a := packed.instantiate()
	var b := packed.instantiate()
	scene.add_child(a)
	scene.add_child(b)
	await process_frame
	await process_frame
	var console := root.get_node("CarrierConsole")
	a.set_in_use(true)
	a.activate_station()
	console.show_page("air_wing")
	a.set_in_use(false)
	console.set_open(false)
	check(a.last_console_page == "air_wing" and b.last_console_page == "tactical", "tab selection is per station")
	b.set_in_use(true)
	b.activate_station()
	check(console.get_current_page() == "tactical", "new station retains its own default")
	console.show_page("personnel")
	b.set_in_use(false)
	console.set_open(false)
	a.set_in_use(true)
	a.activate_station()
	check(console.get_current_page() == "air_wing", "re-enter restores station tab")
	a.set_in_use(false)
	console.set_open(false)
	var display: Node = a._tactical_screen_display
	for page_id in ["air_wing", "ground_bay", "personnel", "carrier", "replicator"]:
		a.set_remembered_page(page_id)
		b.set_remembered_page(page_id)
		await process_frame
		var material_a: ShaderMaterial = a._screen_mesh.material_override
		var material_b: ShaderMaterial = b._screen_mesh.material_override
		check(material_a.get_shader_parameter("tactical_texture") == material_b.get_shader_parameter("tactical_texture"), "matching tabs share feed " + page_id)
		var feed: Dictionary = display._page_feeds[page_id]
		if page_id == "carrier":
			var wireframe: Node = feed.page.get("_wireframe_view")
			var deadline := Time.get_ticks_msec() + 30000
			while not bool(wireframe.get("_model_loaded")) and Time.get_ticks_msec() < deadline:
				await process_frame
			check(bool(wireframe.get("_model_loaded")), "carrier schematic finishes loading")
		check(feed.viewport.gui_disable_input, "preview cannot accept input " + page_id)
		check(feed.page.is_processing() or page_id == "replicator", "live preview processing " + page_id)
		if "--rendered" in OS.get_cmdline_user_args():
			await create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			feed.viewport.get_texture().get_image().save_png("res://logs/computer_tab_%s.png" % page_id)
	check(display._page_feeds.size() == 5, "one feed per non-map tab")
	console.show_page("carrier", false)
	check(a.last_console_page == "replicator" and b.last_console_page == "replicator", "global console does not change unattended stations")
	a.set_remembered_page("unknown")
	check(a.last_console_page == "replicator", "invalid page ignored")
	a.queue_free()
	b.queue_free()
	await process_frame
	display._refresh_page_feeds()
	for feed: Dictionary in display._page_feeds.values():
		check(feed.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "unused feed stops rendering")
	for failure in failures:
		push_error(failure)
	print("COMPUTER_STATION_TABS ", "PASS" if failures.is_empty() else "FAIL", " per_station+restore+all_tabs+shared_feeds+read_only+cleanup")
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
