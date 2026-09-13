extends SceneTree
## Real Main_Scene, stock hangar/catapult, no flight or physics overrides.
## Run with -- --test-scenario=0. Autosaving disabled in this process only.
class Observer extends Node:
	var launched := false
	var craft: WeakRef
	func notify_aircraft_launched(pilot: Node) -> void:
		launched = true
		craft = weakref(pilot.get("aircraft"))

func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	if not "--test-scenario=0" in OS.get_cmdline_user_args():
		fail("requires --test-scenario=0")
		return
	create_timer(300.0, true, false, true).timeout.connect(func(): fail("watchdog"))
	root.get_node("SaveGameManager").set("autosave_enabled", false)
	root.get_node("AirOpsManager").set("mission_tasking_enabled", false)
	root.get_node("GameSession").call("configure_new_game", "Recording Launch Test", Color.WHITE, Color.BLACK, 0, 0, "open_canyons")
	var loading := root.get_node("LoadingScreen")
	loading.call("begin_scenario_load")
	var scene: Node3D = load("res://Main_Scene.tscn").instantiate()
	scene.set("randomize_play_area_each_run", false)
	scene.get_node("LandCarrier").set("startup_placement_seed", 20260911)
	root.add_child(scene)
	current_scene = scene
	while bool(loading.get("_active")): await process_frame
	print("[RecordingScenarioLaunch] loaded")
	var carrier: Node3D = scene.get_node("LandCarrier")
	if "--baseline-cleanup" in OS.get_cmdline_user_args():
		# Control run: no recorder, replay copies, or capture resources.
		await create_timer(2.0).timeout
		paused = true
		current_scene = null
		scene.queue_free()
		for frame in range(4): await process_frame
		print("[RecordingScenarioLaunch] baseline cleanup PASS drained")
		quit(0)
		return
	if "--cleanup-only" in OS.get_cmdline_user_args():
		var probe_mode := root.get_node("RecordingMode")
		probe_mode.enter()
		var probe_actors: Array[Node3D] = [carrier]
		if not probe_mode.start_recording(probe_actors):
			fail("cleanup probe could not record")
			return
		await create_timer(2.0).timeout
		probe_mode.stop_recording()
		probe_mode.enter_replay()
		await process_frame
		probe_mode.leave_replay()
		print("[RecordingScenarioLaunch] cleanup live restored")
		probe_mode.exit()
		probe_mode.clear_take()
		print("[RecordingScenarioLaunch] cleanup take cleared")
		current_scene = null
		scene.queue_free()
		for frame in range(4): await process_frame
		print("[RecordingScenarioLaunch] cleanup PASS drained")
		quit(0)
		return
	carrier.call("hold_position")
	var deck: Node = carrier.find_child("FlightDeckManager", true, false)
	# A normal placement may face a cliff. Give navigation authority through
	# the normal player route API, never bypass catapult clearance checks.
	if not bool(deck.call("_launch_path_clear_of_terrain")):
		var terrain: Node = scene.get_node("LowPolyTerrainPrototype")
		var ordered := false
		for bearing in [0, 30, -30, 60, -60, 90, -90, 150, -150, 180]:
			var point: Vector3 = carrier.global_position + carrier.global_basis.z.rotated(Vector3.UP, deg_to_rad(float(bearing))) * 1000.0
			point.y = terrain.call("get_height", point)
			if not carrier.call("get_player_route_point_error", point).is_empty(): continue
			var points: Array[Vector3] = [point]
			if carrier.call("set_player_patrol_waypoints", points):
				ordered = true
				break
		print("[RecordingScenarioLaunch] launch terrain blocked; route ordered=%s" % ordered)
	var observer := Observer.new()
	scene.add_child(observer)
	if "--baseline-launch" in OS.get_cmdline_user_args():
		if int(deck.call("queue_ai_flight", 1, observer, "", "Aircraft_5")) != 1:
			fail("baseline launch rejected")
			return
		while not observer.launched: await physics_frame
		await create_timer(5.0).timeout
		print("[RecordingScenarioLaunch] baseline launch complete; no recording was used")
		paused = true
		current_scene = null
		scene.queue_free()
		for frame in range(4): await process_frame
		print("[RecordingScenarioLaunch] baseline launch cleanup PASS drained")
		quit(0)
		return
	var mode := root.get_node("RecordingMode")
	mode.enter()
	mode.camera.global_position = carrier.global_position + Vector3(160, 110, 150)
	mode.camera.look_at(carrier.global_position)
	mode.camera.attach(carrier, 2)
	var actors: Array[Node3D] = [carrier]
	var build_start := Time.get_ticks_usec()
	if not mode.start_recording(actors):
		fail("capture start: " + mode._message)
		return
	print("[RecordingScenarioLaunch] build_ms=%.1f tracks=%d" % [(Time.get_ticks_usec() - build_start) / 1000.0, mode.take.copies.size()])
	if int(deck.call("queue_ai_flight", 1, observer, "", "Aircraft_5")) != 1:
		fail("launch order rejected")
		return
	var launch_time := -1.0
	var last_report := -10.0
	while mode.recording and mode.elapsed < 100.0:
		if mode.elapsed - last_report >= 10.0:
			last_report = mode.elapsed
			print("[RecordingScenarioLaunch] t=%.1f subjects=%d tracks=%d deck=%s corridor=%s turning=%s" % [mode.elapsed, mode.take.subjects.size(), mode.take.copies.size(), deck.get("current_state"), deck.call("_launch_path_clear_of_terrain"), deck.call("_is_carrier_turning_for_launch")])
		if observer.launched and launch_time < 0.0:
			launch_time = mode.elapsed
			print("[RecordingScenarioLaunch] launched t=%.2f subjects=%d" % [launch_time, mode.take.subjects.size()])
		if launch_time >= 0.0 and mode.elapsed > launch_time + 5.0: break
		await physics_frame
	mode.stop_recording()
	if not observer.launched:
		fail("no launch within capture window; deck state=%s" % deck.get("current_state"))
		return
	var craft: Variant = observer.craft.get_ref()
	if not is_instance_valid(craft) or not mode.take.has_actor(craft):
		fail("launched aircraft not captured")
		return
	var take: RefCounted = mode.take
	var actor_index := -1
	for index in range(take._roots.size()):
		if take._roots[index].get_ref() == craft: actor_index = index
	var track: int = take.copies.find(take.subjects[actor_index])
	var birth := 0.0
	for index in range(take.frames.size()):
		if track < take.frames[index].poses.size():
			birth = take.times[index]
			break
	var end_position: Vector3 = craft.global_position
	print("[RecordingScenarioLaunch] end source=%s scene=%s position=%s offset=%s recorded=%s" % [craft.name, craft.scene_file_path, end_position, take.origin_offset, take.frames.back().poses[track].origin])
	mode.enter_replay()
	mode.seek(0.0)
	if take.subjects[actor_index].visible:
		fail("aircraft visible before retrieval")
		return
	mode.seek(take.duration())
	if take.subjects[actor_index].global_position.distance_to(end_position + take.origin_offset) > 0.5:
		fail("replay aircraft end position mismatch actual=%s expected=%s" % [take.subjects[actor_index].global_position, end_position + take.origin_offset])
		return
	mode.selected_shot = 0
	mode._selected_subject = actor_index
	mode.camera.global_position = take.subjects[actor_index].global_position + Vector3(22, 8, 33)
	mode.camera.look_at(take.subjects[actor_index].global_position)
	mode.camera.attach(take.subjects[actor_index], 1)
	mode.add_key()
	mode.selected_shot = 1
	mode._selected_subject = 0
	mode.camera.global_position = take.subjects[0].global_position + Vector3(160, 110, 150)
	mode.camera.look_at(take.subjects[0].global_position)
	mode.camera.attach(take.subjects[0], 2)
	mode.add_key()
	var directory: String = mode.save_take()
	if directory.is_empty():
		fail("save failed")
		return
	DirAccess.make_dir_recursive_absolute("res://captures/recording")
	FileAccess.open("res://captures/recording/scenario_take_path.txt", FileAccess.WRITE).store_string(directory)
	if DisplayServer.get_name() != "headless":
		mode._panel.hide()
		for shot in range(2):
			mode.camera.apply_keys(take.shots[shot], mode.playhead, take.subjects)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/recording/scenario_shot_%d.png" % shot)
	mode.leave_replay()
	if craft.global_position != end_position:
		fail("live aircraft changed during replay")
		return
	print("[RecordingScenarioLaunch] PASS subjects=%d tracks=%d birth=%.2f launch=%.2f duration=%.2f saved=%s" % [take.subjects.size(), take.copies.size(), birth, launch_time, take.duration(), directory])
	mode.exit()
	mode.clear_take()
	# Allow deferred scene/resource cleanup and rendering commands to drain
	# before stopping the engine (especially while the live tree is paused).
	current_scene = null
	scene.queue_free()
	for frame in range(4): await process_frame
	quit(0)

func fail(message: String) -> void:
	push_error("[RecordingScenarioLaunch] FAIL " + message)
	var mode := root.get_node_or_null("RecordingMode")
	if mode != null and mode.active:
		mode.exit()
		mode.clear_take()
	quit(1)
