extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var saves := root.get_node("SaveGameManager")
	var session := root.get_node("GameSession")
	var save_path := ProjectSettings.globalize_path("user://saves/campaign_01.json")
	var before := FileAccess.get_sha256(save_path)
	var timeline: RefCounted = load("res://Scenario/Trailer/TrailerTimeline.gd").new()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://Scenario/Trailer/timeline.json"))
	expect(timeline.configure(data), "authored timeline must validate")
	expect(timeline.advance(0.0).size() == 2, "startup cue and launch are both time zero")
	timeline.configure({"version":1, "events":[{"id":"a", "time":0, "action":"cue"},{"id":"b", "time":10, "action":"cue"},{"id":"c", "time":20, "action":"cue"},{"id":"d", "time":40, "action":"cue"}]})
	expect(timeline.advance(0.0).size() == 1, "time-zero cue")
	expect(timeline.advance(9.0).is_empty(), "no early event")
	expect(timeline.advance(31.0).size() == 3, "catch-up must emit every due event")
	expect(timeline.advance(0.0).is_empty(), "events must not repeat")
	expect(not timeline.configure({"version": 1, "events": [{"id":"a", "time":-1, "action":"cue"}]}), "negative time rejected")
	expect(not timeline.configure({"version": 1, "events": [{"id":"a", "time":"later", "action":"cue"}]}), "nonnumeric time rejected")
	var result: Dictionary = saves.prepare_trailer_scenario()
	expect(result.ok and session.is_trailer_scenario and session.has_pending_save_state(), "baseline prepared as isolated session")
	var campaign: Dictionary = session.peek_pending_campaign_state()
	expect(campaign.friendly_air_ops.flights.is_empty() and campaign.friendly_ground_ops.platoons.is_empty(), "previous friendly forces excluded")
	expect(campaign.enemy_bases.bases.is_empty() and campaign.enemy_bases.emplacements.is_empty() and campaign.enemy_ops.base_entries.is_empty(), "previous enemies excluded")
	expect(not saves.request_manual_save().ok, "manual campaign save blocked")
	expect(not saves._save_campaign(true).ok, "automatic campaign save blocked")
	expect(not saves._save_campaign(false).ok, "direct campaign save blocked")
	expect(FileAccess.get_sha256(save_path) == before, "campaign bytes unchanged")
	var runner_script: Script = load("res://Scenario/Trailer/TrailerScenario.gd")
	expect(runner_script != null and runner_script.can_instantiate(), "director compiles")
	var scenario_script: Script = load("res://Scenario/ScenarioManager.gd")
	expect(scenario_script != null and scenario_script.can_instantiate(), "scenario integration compiles")
	var menu_script: Script = load("res://UI/MainMenu.gd")
	expect(menu_script != null and menu_script.can_instantiate(), "main menu compiles")
	if "--menu" in OS.get_cmdline_user_args() and failures.is_empty():
		session.reset_to_defaults()
		change_scene_to_file("res://UI/MainMenu.tscn")
		for frame in 30: await process_frame
		var found := false
		for button in current_scene.get("_main_panel").get_children():
			if button is Button and str(button.get_meta("operator_menu_label", "")) == "TRAILER SCENARIO":
				found = true
				expect(button.get_global_rect().end.y < root.size.y, "trailer button fits viewport")
		expect(found, "separate main-menu trailer item exists")
		if "--render" in OS.get_cmdline_user_args():
			await create_timer(5.0).timeout
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png("res://captures/trailer_main_menu.png") == OK, "menu screenshot saved")
	if "--full" in OS.get_cmdline_user_args() and failures.is_empty():
		if "--loading-only" in OS.get_cmdline_user_args(): root.get_node("LoadingScreen").begin_scenario_load()
		change_scene_to_file("res://Main_Scene.tscn")
		var deadline := Time.get_ticks_msec() + 480000
		var director: Node
		while Time.get_ticks_msec() < deadline:
			await process_frame
			director = get_first_node_in_group("trailer_scenario")
			if director != null and bool(director.get("ready_to_run")): break
		expect(director != null and bool(director.get("ready_to_run")), "full baseline restore must arm director")
		if director != null and bool(director.get("ready_to_run")):
			expect(paused, "baseline waits paused for filming")
			if "--loading-only" in OS.get_cmdline_user_args():
				var loading := root.get_node("LoadingScreen")
				var load_deadline := Time.get_ticks_msec() + 15000
				while loading.visible and Time.get_ticks_msec() < load_deadline: await process_frame
				expect(not loading.visible, "loading overlay must finish without starting simulation or choosing a camera")
				expect(paused and director.timeline.elapsed == 0.0 and director.launch_requests.is_empty(), "loading terrain keeps battle and launch machinery paused")
				expect(FileAccess.get_sha256(save_path) == before, "loading leaves Continue save unchanged")
				print("TRAILER_LOADING_%s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(loading.get_load_timing_stats())])
				if "--render" in OS.get_cmdline_user_args():
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("res://captures/trailer_loading_reveal.png")
				quit(0 if failures.is_empty() else 1)
				return
			var battle: RefCounted = director.battle
			expect(battle != null and battle.friendly.get_members().size() == 4 and battle.enemy.get_members().size() == 8, "startup has four friendly and eight enemy vehicles")
			expect(get_nodes_in_group("ground_vehicles").size() == 12, "no unrelated ground vehicles remain")
			expect(get_nodes_in_group("enemy_bases").is_empty(), "no enemy bases remain")
			expect(battle.ground_span <= 8.0 and battle.route_length <= 2800.0, "same plain and usable ground route")
			expect(absf(battle._flat_distance(battle.friendly_start, battle.enemy_start) - 2000.0) < 1.0, "platoons start two kilometres apart")
			expect(battle.friendly.attack_node == battle.enemy and battle.enemy.attack_node == battle.friendly, "platoons ordered to attack each other")
			await create_timer(2.0).timeout
			expect(director.timeline.elapsed == 0.0 and director.launch_requests.is_empty() and director._pending_launch_orders.size() == 1, "paused staging retains launch order without starting deck machinery")
			expect(get_nodes_in_group("ai_aircraft").is_empty(), "no unrelated aircraft or premature launches remain")
			if "--vehicle-cameras" in OS.get_cmdline_user_args():
				var cameras := get_first_node_in_group("trailer_aircraft_cameras")
				expect(cameras.vehicle_list().size() == 13, "all twelve ground vehicles and carrier viewable before launch")
				var seen: Array = []
				var arrow := InputEventKey.new()
				arrow.physical_keycode = KEY_RIGHT
				arrow.pressed = true
				for index in 13:
					root.push_input(arrow)
					expect(cameras.active and not seen.has(cameras.subject), "right arrow selects each real vehicle once")
					seen.append(cameras.subject)
				if "--render" in OS.get_cmdline_user_args():
					var subjects := [battle.friendly.get_members()[0], battle.enemy.get_members()[0], get_first_node_in_group("carrier")]
					for index in subjects.size():
						for camera_slot in 3:
							cameras.select_slot(camera_slot, subjects[index])
							await create_timer(2.0).timeout
							expect(paused and director.timeline.elapsed == 0.0, "camera streaming does not advance paused battle")
							for frame in 10: await process_frame
							await RenderingServer.frame_post_draw
							expect(root.get_texture().get_image().save_png("res://captures/trailer_vehicle_%d_camera_%d.png" % [index, camera_slot]) == OK, "ground/carrier frame saved")
				cameras.release_camera()
			var key := InputEventKey.new()
			key.keycode = KEY_F6
			key.pressed = true
			var initial_anchor: Transform3D = director.anchor
			director.apply_origin_shift(Vector3(5000, 0, -3000))
			expect(director.anchor.origin.is_equal_approx(initial_anchor.origin - Vector3(5000, 0, -3000)), "future spawn frame follows origin shift")
			director.anchor = initial_anchor
			key.physical_keycode = KEY_SPACE
			key.keycode = KEY_SPACE
			root.push_input(key)
			expect(not paused and director.started, "Space starts full scenario through viewport input")
			var duration := 150.0 if "--battle-long" in OS.get_cmdline_user_args() else 42.0
			var sample_at := 10.0
			var cameras_checked := false
			var direct_video_at := -1.0
			var direct_slot := 0
			while float(director.timeline.elapsed) < duration and Time.get_ticks_msec() < deadline:
				await process_frame
				if "--cameras" in OS.get_cmdline_user_args() and not cameras_checked and battle.aircraft_launched == 2:
					cameras_checked = true
					var cameras := get_first_node_in_group("trailer_aircraft_cameras")
					cameras.select_slot(0, battle.strike.get_members()[0])
					var camera_key := InputEventKey.new()
					camera_key.keycode = KEY_F1
					camera_key.physical_keycode = KEY_F1
					camera_key.pressed = true
					root.push_input(camera_key)
					await process_frame
					expect(cameras.active and cameras.slot == 0, "F1 selects trailer camera through actual input routing")
					var deck := get_first_node_in_group("flight_deck_manager")
					expect(not deck._landing_test_active and battle.strike.strength() == 2, "F1 does not start landing debug or despawn strike")
					if "--render" in OS.get_cmdline_user_args():
						paused = true
						for camera_slot in 3:
							cameras.select_slot(camera_slot)
							for frame in 10: await process_frame
							await RenderingServer.frame_post_draw
							expect(root.get_texture().get_image().save_png("res://captures/trailer_aircraft_camera_%d.png" % (camera_slot + 1)) == OK, "rendered aircraft camera saved")
						if "--free-cameras" in OS.get_cmdline_user_args():
							cameras.select_slot(3)
							cameras.camera.move_camera(Vector3.RIGHT, Vector2(0.1, 0.0), 0.2, 0.5)
							for frame in 10: await process_frame
							await RenderingServer.frame_post_draw
							root.get_texture().get_image().save_png("res://captures/trailer_free_camera.png")
							cameras.select_slot(4)
							expect(cameras._focus_node == cameras.subject.get_node("CockpitPilot"), "actual anchored aircraft uses pilot body mount")
							expect(cameras._focus_node.get_pilot_visual() != null and cameras._focus_node.is_visible_in_tree(), "pilot presentation exists while framing a paused aircraft")
							cameras._orbit_offset = cameras.subject.global_basis * Vector3(3, 1.7, 3)
							cameras._orbit_roll = 0.15
							cameras.camera.fov = 50
							for frame in 20: await process_frame
							await RenderingServer.frame_post_draw
							root.get_texture().get_image().save_png("res://captures/trailer_anchored_pilot.png")
							cameras.select_slot(4, get_first_node_in_group("carrier"))
							expect(cameras._focus_node == cameras.subject.get_node("Commander"), "actual carrier anchored view follows commander")
							cameras._orbit_offset = cameras._focus_node.global_basis * Vector3(1, 0.2, 2.5)
							cameras._orbit_roll = -0.1
							for frame in 20: await process_frame
							await RenderingServer.frame_post_draw
							root.get_texture().get_image().save_png("res://captures/trailer_anchored_commander.png")
						if "--pilot-view" in OS.get_cmdline_user_args():
							var plane: Node3D = battle.strike.get_members()[0]
							expect(cameras.select_slot(5, plane), "pilot cockpit view selectable")
							var flight := root.get_node("FlightDirector")
							var toggle := plane.get_node("AIToggle")
							expect(cameras.piloting and not cameras.active and not flight.trailer_camera_active, "film controller releases ownership in pilot mode")
							expect(flight.is_player_controlling and flight.player_controlled_plane == plane and not toggle.ai_active, "normal manual aircraft control acquired")
							for control in toggle.player_controls:
								expect(control.is_physics_processing(), "normal player control module enabled")
							expect(root.get_camera_3d() == plane.get_node("CameraController").cockpit_camera, "actual authored cockpit is current")
							var trigger := InputEventJoypadMotion.new()
							trigger.axis = JOY_AXIS_TRIGGER_LEFT
							trigger.axis_value = 1.0
							cameras._input(trigger)
							expect(cameras._pad_axes.is_empty(), "pilot trigger is not consumed by filming zoom")
							var video := root.get_node("DirectVideoCapture")
							expect(video.start_capture(), "record actual player cockpit")
							Input.action_press("pitch_up", 0.2)
							await create_timer(0.3).timeout
							Input.action_release("pitch_up")
							await create_timer(1.0).timeout
							await RenderingServer.frame_post_draw
							root.get_texture().get_image().save_png("res://captures/trailer_pilot_clean.png")
							expect(not root.get_node("RadioComms")._canvas.visible, "radio dialogue absent during cockpit capture")
							video.stop_capture()
							expect(paused and flight.is_player_controlling, "record-stop pauses while retaining pilot assignment")
							var encode_deadline := Time.get_ticks_msec() + 60000
							while video.finalizing and Time.get_ticks_msec() < encode_deadline: await process_frame
							expect(bool(video.last_result.get("ok", false)), "cockpit MP4 encoded")
							print("TRAILER_PILOT_VIDEO ", JSON.stringify(video.last_result))
							for film_slot in 5:
								cameras.select_slot(5, plane)
								await RenderingServer.frame_post_draw
								var seated: Node3D = plane.get_node("CockpitPilot").get_pilot_visual()
								expect(seated != null and seated._last_head_hidden, "actual cockpit hides its pilot while paused")
								cameras.select_slot(film_slot, plane)
								await RenderingServer.frame_post_draw
								seated = plane.get_node("CockpitPilot").get_pilot_visual()
								expect(seated != null and not seated._last_head_hidden, "film view %d restores pilot while paused" % film_slot)
								if seated != null:
									for mesh in seated._cockpit_hidden_nodes:
										expect(mesh.is_visible_in_tree(), "film view %d pilot mesh visible" % film_slot)
							cameras._orbit_offset = plane.global_basis * Vector3(1.0, 0.2, 2.5)
							for frame in 3: await process_frame
							await RenderingServer.frame_post_draw
							root.get_texture().get_image().save_png("res://captures/trailer_pilot_restored_after_cockpit.png")
							cameras.select_slot(0, plane)
							expect(not flight.is_player_controlling and toggle.ai_active and cameras.active, "leaving cockpit restores AI and film controls")
						paused = false
					cameras.cycle_aircraft()
					expect(cameras.active, "switching actual strike aircraft succeeds")
					if "--direct-video" in OS.get_cmdline_user_args():
						expect(root.get_node("DirectVideoCapture").start_capture(), "direct aircraft video starts")
						direct_video_at = director.timeline.elapsed
					else: cameras.release_camera()
				if direct_video_at >= 0:
					var video_age: float = director.timeline.elapsed - direct_video_at
					var cameras := get_first_node_in_group("trailer_aircraft_cameras")
					var next_slot := mini(2, int(video_age / 2.0))
					if next_slot != direct_slot:
						direct_slot = next_slot
						cameras.select_slot(direct_slot)
					if video_age >= 6.0:
						root.get_node("DirectVideoCapture").stop_capture()
						expect(paused, "video stop pauses full scenario")
						director.toggle_pause() # Continue the battle diagnostics after the filmed segment.
						cameras.release_camera()
						direct_video_at = -1.0
				if float(director.timeline.elapsed) >= sample_at:
					print("TRAILER_BATTLE_SAMPLE t=%.1f separation=%.1f friendly=%d enemy=%d strike=%d" % [director.timeline.elapsed, battle._flat_distance(battle.friendly.get_center_position(), battle.enemy.get_center_position()), battle.friendly.get_members().size(), battle.enemy.get_members().size(), battle.strike.strength()])
					var deck := get_first_node_in_group("flight_deck_manager")
					print("TRAILER_DECK_SAMPLE state=%s queue=%s jobs=%s cleanup=%s" % [deck.current_state, deck._ai_launch_queue, deck._parallel_launch_jobs.size(), deck._tractor_cleanup_in_progress])
					for job in deck._parallel_launch_jobs.values():
						print("TRAILER_LANE_SAMPLE phase=%s elevator_y=%s top=%s" % [job.phase, deck._get_elevator_platform_local_y_for(job.elevator), deck._is_elevator_physically_at_top_for(job.elevator)])
						if is_instance_valid(job.aircraft) and job.phase == "retrieving":
							expect(job.aircraft.global_position.distance_to(deck.get_parent().global_position) < 250.0, "retrieved aircraft stays with carrier through startup origin shift")
					sample_at += 10.0
			expect(director.timeline.cursor == 2, "startup schedule completed")
			if "--direct-video" in OS.get_cmdline_user_args():
				var video := root.get_node("DirectVideoCapture")
				var video_deadline := Time.get_ticks_msec() + 60000
				while video.finalizing and Time.get_ticks_msec() < video_deadline: await process_frame
				expect(bool(video.last_result.get("ok", false)), "direct aircraft MP4 finished")
				print("TRAILER_DIRECT_VIDEO ", JSON.stringify(video.last_result))
			expect(director.launch_requests.size() == 1 and director.launch_requests[0].accepted == 2, "two scripted hangar launches accepted")
			expect(battle.aircraft_launched == 2, "two aircraft actually launched")
			for aircraft in battle.strike.get_members():
				expect(aircraft.scene_file_path == "res://Aircraft/Aircraft_5.tscn", "strike uses Aircraft 5 only")
			expect(battle.strike.mission == 2, "strike flight assigned CAS")
			expect(battle._flat_distance(battle.friendly.get_center_position(), battle.enemy.get_center_position()) < 1900.0, "ground forces close the gap")
			expect(FileAccess.get_sha256(save_path) == before, "full scenario did not overwrite campaign")
			if "--restart" in OS.get_cmdline_user_args():
				var old_id := director.get_instance_id()
				director.restart()
				director = null
				deadline = Time.get_ticks_msec() + 240000
				while Time.get_ticks_msec() < deadline:
					await process_frame
					director = get_first_node_in_group("trailer_scenario")
					if director != null and director.get_instance_id() != old_id and bool(director.get("ready_to_run")): break
				expect(director != null and director.get_instance_id() != old_id and bool(director.get("ready_to_run")), "restart restores and arms a new director")
				if director != null:
					expect(director.timeline.elapsed == 0.0 and director.timeline.cursor == 2 and paused, "restart reissues time-zero orders and waits paused")
					expect(director.battle.friendly.get_members().size() == 4 and director.battle.enemy.get_members().size() == 8, "restart rebuilds exact ground forces")
					expect(director.anchor.origin.distance_to(initial_anchor.origin) < 0.1, "restart restores the original staging frame")
				expect(FileAccess.get_sha256(save_path) == before, "restart leaves campaign untouched")
	paused = false
	# Keep trailer isolation until process exit; clearing it here lets always-on
	# autoloads dispatch campaign missions during the final shutdown frame.
	print("TRAILER_SCENARIO_SMOKETEST_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
