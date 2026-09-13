extends SceneTree
## Full scenario startup, without changing saved scenario/menu settings.
## Run with -- --test-scenario=0; optional --startup-map=layered_badlands.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var profile := "open_canyons"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--startup-map="):
			profile = argument.trim_prefix("--startup-map=")
	var session := root.get_node("GameSession")
	session.call("configure_new_game", "Startup Benchmark", Color.WHITE, Color.BLACK, 0, 0, profile)
	var loading := root.get_node("LoadingScreen")
	loading.call("begin_scenario_load")
	var start := Time.get_ticks_usec()
	var packed := load("res://Main_Scene.tscn") as PackedScene
	var loaded := Time.get_ticks_usec()
	print("SCENARIO_BENCH_RESOURCE_LOAD_MS ", (loaded - start) / 1000.0)
	var scene := packed.instantiate()
	# Deterministic region; all real startup systems and full grid remain enabled.
	scene.set("randomize_play_area_each_run", false)
	var instantiated := Time.get_ticks_usec()
	print("SCENARIO_BENCH_INSTANTIATE_MS ", (instantiated - loaded) / 1000.0)
	root.add_child(scene)
	current_scene = scene
	print("SCENARIO_BENCH_ENTER_READY_MS ", (Time.get_ticks_usec() - instantiated) / 1000.0)
	while bool(loading.get("_active")) and Time.get_ticks_usec() - start < 240000000:
		await process_frame
	var complete := not bool(loading.get("_active"))
	var report: Dictionary = loading.call("get_load_timing_stats")
	report["resource_load_ms"] = (loaded - start) / 1000.0
	report["instantiate_ms"] = (instantiated - loaded) / 1000.0
	report["complete"] = complete
	report["wall_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	var file := FileAccess.open("user://terrain_scenario_startup_%s.json" % profile.validate_filename(), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SCENARIO_LOADING_BENCH ", JSON.stringify(report))
	# Let the real scene release render objects before shutting down the engine.
	current_scene = null
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if complete else 1)
