extends SceneTree

const SETTINGS_FIXTURE := "user://fixed_time_smoketest.cfg"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var cycle_script: Script = load("res://Environment/DayNightCycle.gd")
	for node in root.get_children():
		node.process_mode = Node.PROCESS_MODE_DISABLED
	var menu := root.get_node("PauseMenu")
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	var original_enabled: bool = menu.is_time_of_day_fixed()
	var original_minutes: int = menu.get_fixed_time_minutes()
	menu.set_fixed_time_of_day(false, 720, false)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	environment.environment = Environment.new()
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	world.add_child(sun)
	var cycle = cycle_script.new()
	cycle.dust_deck_grid_cells = 8
	world.add_child(cycle)
	cycle.set_process(false)
	cycle._t = 0.0
	cycle._process(1.0)
	check(is_equal_approx(cycle._t, 1.0 / 1200.0), "unlocked clock advances")
	check(not menu._fixed_time_controls.visible, "clock selector hidden when off")
	paused = true
	menu.set_fixed_time_of_day(true, 720, false)
	check(menu._fixed_time_controls.visible, "clock selector appears when on")
	check(is_equal_approx(cycle._t, 0.25) and is_equal_approx(sun.light_energy, 2.2), "noon lighting applies while paused")
	var noon_darkness: float = cycle.get_ai_darkness_factor()
	cycle._process(60.0)
	check(is_equal_approx(cycle._t, 0.25), "locked clock holds over elapsed time")
	check(cycle._sun_break_time > 60.0, "weather animation remains active")
	menu.set_fixed_time_of_day(true, 0, false)
	check(is_equal_approx(cycle._t, 0.75), "00:00 maps to midnight")
	check(cycle.get_ai_darkness_factor() > noon_darkness, "AI darkness follows selected time")
	menu.set_fixed_time_of_day(true, 360, false)
	check(is_equal_approx(cycle._t, 0.0), "06:00 maps to dawn")
	menu.set_fixed_time_of_day(true, 1080, false)
	check(is_equal_approx(cycle._t, 0.5), "18:00 maps to dusk")
	menu.set_fixed_time_of_day(true, 1117, false)
	check(int(menu._fixed_time_hour.value) == 18 and int(menu._fixed_time_minute.value) == 37, "selector shows hours and minutes")
	menu._save_settings(SETTINGS_FIXTURE)
	menu.set_fixed_time_of_day(false, 720, false)
	menu._load_settings(SETTINGS_FIXTURE)
	menu._apply_fixed_time_setting()
	check(menu.is_time_of_day_fixed() and menu.get_fixed_time_minutes() == 1117, "settings round trip")
	var second = cycle_script.new()
	second.dust_deck_grid_cells = 8
	world.add_child(second)
	second.set_process(false)
	check(is_equal_approx(second._t, cycle._t), "new scenario cycle reads saved preference")
	menu.set_fixed_time_of_day(false, 1117, false)
	var previous: float = cycle._t
	cycle._process(1.0)
	check(cycle._t > previous, "disabling resumes from selected time")
	cycle.freeze_daytime = true
	cycle.frozen_daytime_t = 0.3
	menu.set_fixed_time_of_day(true, 720, false)
	check(cycle.freeze_daytime and is_equal_approx(cycle.frozen_daytime_t, 0.3), "authored freeze untouched")
	menu.set_fixed_time_of_day(false, 720, false)
	check(is_equal_approx(cycle._t, 0.3), "authored freeze restored when override disabled")
	menu.set_fixed_time_of_day(true, 1117, false)
	menu.visible = true
	menu._show_screen("gameplay")
	menu._fixed_time_hour.get_line_edit().grab_focus()
	var backspace := InputEventKey.new()
	backspace.keycode = KEY_BACKSPACE
	backspace.physical_keycode = KEY_BACKSPACE
	backspace.pressed = true
	check(not menu._handle_pause_navigation_input(backspace), "clock Backspace edits text instead of leaving settings")
	menu._show_screen("gameplay")
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures/recording")
		root.get_texture().get_image().save_png("res://captures/recording/fixed_time_gameplay.png")
	menu.set_fixed_time_of_day(original_enabled, original_minutes, false)
	DirAccess.remove_absolute(SETTINGS_FIXTURE)
	paused = false
	print("FIXED_TIME_OF_DAY_SMOKETEST_%s failures=%s" % ["OK" if failures.is_empty() else "FAILED", failures])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
