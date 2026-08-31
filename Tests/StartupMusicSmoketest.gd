extends Node

const MAIN_MENU_SCENE := preload("res://UI/MainMenu.tscn")
const EXPECTED_TRACK_PATH := "res://Audio/Music/Static Horizon.wav"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_menu := MAIN_MENU_SCENE.instantiate()
	var music := main_menu.get_node_or_null("StartupMusic") as AudioStreamPlayer
	if music == null:
		_fail("main menu was missing its startup music player")
		main_menu.free()
		return
	if music.stream == null or music.stream.resource_path != EXPECTED_TRACK_PATH:
		_fail("startup music player did not use Static Horizon")
		main_menu.free()
		return
	if music.autoplay:
		_fail("startup music still used scene autoplay")
		main_menu.free()
		return
	if music.stream is AudioStreamWAV \
			and (music.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		_fail("startup music was not configured to loop")
		main_menu.free()
		return
	var main_menu_source := FileAccess.get_file_as_string("res://UI/MainMenu.gd")
	if main_menu_source.count("_start_game_with_scenario(NORMAL_TEST_SCENARIO, true)") != 2:
		_fail("new and continued campaigns were not the two music-carrying launch paths")
		main_menu.free()
		return

	var loading_screen := get_node_or_null("/root/LoadingScreen") as CanvasLayer
	if loading_screen == null:
		_fail("LoadingScreen autoload was unavailable")
		main_menu.free()
		return
	loading_screen.visible = true
	get_tree().root.add_child(main_menu)
	if music.playing:
		_fail("startup music began before the carrier was rendered")
		return

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if music.playing:
		_fail("startup music played while the loading screen was visible")
		return

	loading_screen.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	if not music.playing:
		_fail("startup music did not begin after the carrier became visible")
		return
	if not bool(main_menu.call("_handoff_startup_music_to_loading_screen", loading_screen)):
		_fail("campaign launch could not hand music to the loading screen")
		return
	if music.get_parent() != loading_screen or not music.playing:
		_fail("loading screen did not preserve the playing menu track")
		return
	loading_screen.call("begin_scenario_load")
	main_menu.queue_free()
	await get_tree().process_frame
	if not is_instance_valid(music) \
			or music.get_parent() != loading_screen \
			or not loading_screen.visible \
			or not music.playing:
		_fail("campaign music did not survive the menu scene leaving during loading")
		return
	loading_screen.call("_hide_immediately")
	if music.playing:
		_fail("carried campaign music did not stop when loading finished")
		return

	print("[StartupMusicSmoketest] PASS track=Static Horizon carrier_start=true campaign_load_handoff=true loop=true volume_db=%.1f" % music.volume_db)
	await get_tree().process_frame
	get_tree().quit()


func _fail(reason: String) -> void:
	push_error("[StartupMusicSmoketest] FAIL %s" % reason)
	get_tree().quit(1)
