extends Node

const CARRIER_SCENE := preload("res://LandCarrier/LandCarrier2.tscn")

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var staged_roots := 0
	var staged_nodes := 0
	var staged_frames := 0
	var real_retrieval_new_aircraft := 0
	var real_retrieval_occupant_mounts := 0
	var real_retrieval_survived := false
	var carrier := CARRIER_SCENE.instantiate() as Node3D
	_expect(carrier != null, "LandCarrier2 did not instantiate")
	add_child(carrier)
	var validation_sun := DirectionalLight3D.new()
	validation_sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	validation_sun.light_energy = 3.0
	validation_sun.shadow_enabled = true
	add_child(validation_sun)
	await get_tree().process_frame
	await get_tree().process_frame

	var manager := carrier.get_node_or_null("FlightDeckManager") as FlightDeckManager
	_expect(manager != null, "FlightDeckManager missing")
	if manager != null:
		# The elevator can report AT_BOTTOM in the same frame as the deferred
		# already-at-bottom path. Exactly one caller may claim the retrieval.
		manager.set("current_state", FlightDeckManager.DeckState.RETRIEVING_FROM_HANGAR)
		manager.set("_retrieval_spawn_generation", 77)
		manager.set("_retrieval_spawn_started", false)
		manager.set("_retrieval_spawn_armed", true)
		_expect(not bool(manager.call("_claim_hangar_retrieval_spawn", 76)), "stale retrieval generation claimed a spawn")
		_expect(bool(manager.call("_claim_hangar_retrieval_spawn", 77)), "first retrieval callback did not claim its spawn")
		_expect(not bool(manager.call("_claim_hangar_retrieval_spawn", 77)), "duplicate retrieval callback claimed a second spawn")
		manager.set("_retrieval_spawn_started", false)
		manager.set("_retrieval_spawn_armed", false)
		manager.set("current_state", FlightDeckManager.DeckState.IDLE)
	FrameProfiler.set_report_capture_enabled(true, "hangar staging smoke")
	var aircraft := manager.call("_create_aircraft_at_hangar_level") as RigidBody3D
	_expect(aircraft != null and is_instance_valid(aircraft), "hangar aircraft was not created")
	if aircraft != null and is_instance_valid(aircraft):
		var detached_roots := int(aircraft.get_meta("hangar_presentation_detached_roots", 0))
		var detached_nodes := int(aircraft.get_meta("hangar_presentation_detached_nodes", 0))
		staged_roots = detached_roots
		staged_nodes = detached_nodes
		_expect(detached_roots > 1, "hangar entry did not split presentation into roots")
		_expect(detached_nodes > detached_roots, "hangar entry detached no presentation subtrees")
		_expect(bool(aircraft.get_meta("visual_budget_presentation_staging", false)), "hangar entry was not marked as staging")
		_expect(aircraft.get_node_or_null("HeadsUpDisplay") == null, "HUD entered the tree in the shell frame")
		_expect(aircraft.get_node_or_null("CameraController") == null, "camera controller entered the tree in the shell frame")
		var flight_director := get_node_or_null("/root/FlightDirector")
		_expect(
			flight_director != null and bool(flight_director.call("_is_camera_cycle_excluded", aircraft)),
			"partially staged aircraft remained camera-selectable"
		)

		await manager.call("_stage_hangar_aircraft_presentation", aircraft)
		var profiler_rows := FrameProfiler.consume_report_rows(64)
		var staged_scope_count := 0
		for row_variant in profiler_rows:
			var row: Dictionary = row_variant
			if str(row.get("label", "")).begins_with("FlightDeckManager.hangar_stage_") \
					and not str(row.get("label", "")).begins_with("FlightDeckManager.hangar_stage_settle_after_") \
					and str(row.get("label", "")) != "FlightDeckManager.hangar_stage_completion_fallback":
				staged_scope_count += 1
		_expect(staged_scope_count == detached_roots, "per-root staging profiler labels were incomplete")
		FrameProfiler.set_report_capture_enabled(false, "hangar staging smoke complete")
		_expect(bool(aircraft.get_meta("hangar_presentation_stage_complete", false)), "hangar staging did not complete")
		_expect(not bool(aircraft.get_meta("visual_budget_presentation_staging", false)), "staging lock remained after the last root")
		_expect(bool(aircraft.get_meta("visual_budget_presentation_keep_attached", false)), "warm presentation was not retained for deck handling")
		staged_frames = int(aircraft.get_meta("hangar_presentation_stage_frames", 0))
		_expect(staged_frames == detached_roots, "staging did not restore one root per frame")
		_expect(aircraft.get_node_or_null("HeadsUpDisplay") != null, "staged HUD did not restore")
		_expect(aircraft.get_node_or_null("InstrumentPanel") != null, "staged instrument panel did not restore")
		_expect(aircraft.get_node_or_null("CameraController") != null, "staged camera controller did not restore")
		var occupant_mount_count := _count_occupant_mounts(aircraft)
		_expect(occupant_mount_count == 1, "staged aircraft restored %d cockpit occupant mounts" % occupant_mount_count)
		var instrument_panel := aircraft.get_node_or_null("InstrumentPanel")
		if instrument_panel != null:
			var panel_viewport := instrument_panel.get_node_or_null("SubViewport") as SubViewport
			var target_viewport_variant: Variant = instrument_panel.get("target_viewport")
			var target_viewport := target_viewport_variant as SubViewport
			_expect(
				panel_viewport != null and panel_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
				"unviewed staged instrument viewport submitted a hidden render frame"
			)
			_expect(
				target_viewport != null and target_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
				"unviewed staged target viewport submitted a hidden full-world render frame"
			)
		_expect(
			flight_director != null and not bool(flight_director.call("_is_camera_cycle_excluded", aircraft)),
			"fully staged aircraft remained excluded from camera cycling"
		)
		var camera_controller := aircraft.get_node_or_null("CameraController")
		var cockpit_tripod := aircraft.get_node_or_null("CameraCockpit") as Node3D
		var cockpit_camera := aircraft.get_node_or_null("CameraCockpit/Camera3D") as Camera3D
		_expect(camera_controller != null and cockpit_tripod != null and cockpit_camera != null, "retrieved cockpit camera chain is incomplete")
		if camera_controller != null and cockpit_tripod != null and cockpit_camera != null:
			# Simulate stale hidden-camera input accumulated while another aircraft
			# was viewed. Selecting this cockpit must always recenter it.
			cockpit_tripod.set("current_look", Vector3(0.0, PI, 0.0))
			cockpit_tripod.rotation = (cockpit_tripod.get("base_rotation") as Vector3) + Vector3(0.0, PI, 0.0)
			camera_controller.call("switch_to_camera", 0)
			await get_tree().process_frame
			if instrument_panel != null:
				instrument_panel.call("set_view_updates_active", true)
				var active_panel_viewport := instrument_panel.get_node_or_null("SubViewport") as SubViewport
				var active_target_viewport := instrument_panel.get("target_viewport") as SubViewport
				_expect(
					active_panel_viewport != null and active_panel_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
					"selected instrument viewport did not resume"
				)
				_expect(
					active_target_viewport != null and active_target_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
					"selected target viewport did not resume"
				)
			var aircraft_forward := aircraft.global_transform.basis.z.normalized()
			var camera_forward := -cockpit_camera.global_transform.basis.z.normalized()
			_expect((cockpit_tripod.get("current_look") as Vector3).is_zero_approx(), "cockpit selection retained hidden right-stick look")
			_expect(camera_forward.dot(aircraft_forward) > 0.99, "retrieved cockpit camera faced away from aircraft forward dot=%.3f aircraft=%s camera=%s base_rotation=%s rotation=%s" % [
				camera_forward.dot(aircraft_forward),
				str(aircraft_forward),
				str(camera_forward),
				str(cockpit_tripod.get("base_rotation")),
				str(cockpit_tripod.rotation),
			])

		var visual_budget := get_node_or_null("/root/EnemyVisualBudget")
		_expect(visual_budget != null, "EnemyVisualBudget missing")
		if visual_budget != null:
			visual_budget.call("release_aircraft_presentation_keep_attached", aircraft)
			_expect(not bool(aircraft.get_meta("visual_budget_presentation_keep_attached", false)), "launch release retained the attachment lock")
			visual_budget.call("release_aircraft_cache", aircraft, false)
		aircraft.queue_free()
		await get_tree().process_frame

	# Exercise the real retrieval entrypoint twice in the same frame. This is the
	# runtime sequence that previously allowed the deferred already-at-bottom path
	# and the elevator signal to create two aircraft at the same transform.
	for stored_index in range(manager.stored_aircraft.size()):
		var stored_entry: Dictionary = manager.stored_aircraft[stored_index]
		if not bool(manager.call("_stored_aircraft_is_helicopter", stored_entry)):
			manager.stored_aircraft.remove_at(stored_index)
			manager.stored_aircraft.push_front(stored_entry)
			break
	var live_ids_before := _live_aircraft_ids()
	var stored_before := manager.stored_aircraft.size()
	manager.call("start_hangar_retrieval")
	manager.call("start_hangar_retrieval")
	var retrieval_wait_frames := 0
	while not is_instance_valid(manager.deck_aircraft) and retrieval_wait_frames < 240:
		retrieval_wait_frames += 1
		await get_tree().process_frame
	var retrieved_variant: Variant = manager.deck_aircraft
	var retrieved := retrieved_variant as RigidBody3D if is_instance_valid(retrieved_variant) else null
	_expect(retrieved != null, "real hangar retrieval did not spawn an aircraft")
	if retrieved != null:
		var stage_wait_frames := 0
		while bool(retrieved.get_meta("visual_budget_presentation_staging", false)) \
				and stage_wait_frames < 120:
			stage_wait_frames += 1
			await get_tree().process_frame
		_expect(not bool(retrieved.get_meta("visual_budget_presentation_staging", false)), "real retrieval did not finish presentation staging")
		real_retrieval_occupant_mounts = _count_occupant_mounts(retrieved)
		_expect(real_retrieval_occupant_mounts == 1, "real retrieval produced duplicate cockpit occupant mounts")
		_expect(manager.stored_aircraft.size() == stored_before - 1, "double retrieval consumed more than one hangar entry")
		var live_ids_after := _live_aircraft_ids()
		var new_aircraft_count := 0
		for instance_id in live_ids_after:
			if not live_ids_before.has(instance_id):
				new_aircraft_count += 1
		real_retrieval_new_aircraft = new_aircraft_count
		_expect(new_aircraft_count == 1, "double retrieval created %d live aircraft" % new_aircraft_count)
		await get_tree().create_timer(0.75).timeout
		real_retrieval_survived = is_instance_valid(retrieved) and not retrieved.is_queued_for_deletion()
		_expect(real_retrieval_survived, "retrieved aircraft was destroyed during elevator separation check")
		if DisplayServer.get_name() != "headless":
			var retrieved_camera_controller := retrieved.get_node_or_null("CameraController")
			if retrieved_camera_controller != null:
				retrieved_camera_controller.call("switch_to_camera", 1)
				await get_tree().process_frame
				await get_tree().process_frame
			var capture_path := "user://unattended_plane_spawn_validation.png"
			var capture_image := get_viewport().get_texture().get_image()
			var capture_error := capture_image.save_png(capture_path) if capture_image != null else ERR_CANT_CREATE
			_expect(capture_error == OK, "could not save unattended retrieval screenshot")
			print("[HangarPresentationStagingSmoketest] screenshot=%s" % ProjectSettings.globalize_path(capture_path))
			var cockpit_mount := retrieved.get_node_or_null("CockpitPilot") as Node3D
			if cockpit_mount != null and cockpit_mount.has_method("set_presentation_active"):
				cockpit_mount.call("set_presentation_active", true)
				await get_tree().process_frame
				await get_tree().process_frame
				var close_camera := Camera3D.new()
				close_camera.fov = 38.0
				add_child(close_camera)
				var aircraft_basis := retrieved.global_transform.basis.orthonormalized()
				var cockpit_focus := cockpit_mount.global_position + aircraft_basis.y * 0.55
				close_camera.global_position = cockpit_focus + aircraft_basis.x * 2.8 + aircraft_basis.z * 0.2
				close_camera.look_at(cockpit_focus, aircraft_basis.y)
				close_camera.current = true
				await get_tree().process_frame
				await get_tree().process_frame
				var pilot_capture_path := "user://unattended_pilot_seating_validation.png"
				var pilot_capture_image := get_viewport().get_texture().get_image()
				var pilot_capture_error := pilot_capture_image.save_png(pilot_capture_path) \
					if pilot_capture_image != null else ERR_CANT_CREATE
				_expect(pilot_capture_error == OK, "could not save unattended pilot seating screenshot")
				print("[HangarPresentationStagingSmoketest] pilot_screenshot=%s" % ProjectSettings.globalize_path(pilot_capture_path))
				close_camera.queue_free()
		var retrieval_visual_budget := get_node_or_null("/root/EnemyVisualBudget")
		if retrieval_visual_budget != null:
			retrieval_visual_budget.call("release_aircraft_cache", retrieved, false)
		retrieved.queue_free()
		await get_tree().process_frame

	carrier.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("HANGAR_PRESENTATION_STAGING_SMOKETEST_OK roots=%d nodes=%d frames=%d retrieval_new=%d occupant_mounts=%d survived=%s" % [
			staged_roots,
			staged_nodes,
			staged_frames,
			real_retrieval_new_aircraft,
			real_retrieval_occupant_mounts,
			str(real_retrieval_survived),
		])
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[HangarPresentationStagingSmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _count_occupant_mounts(aircraft: Node) -> int:
	if aircraft == null or not is_instance_valid(aircraft):
		return 0
	var result := 0
	for child in aircraft.get_children():
		if child.has_method("is_pooled_aircraft_occupant_mount") \
				and bool(child.call("is_pooled_aircraft_occupant_mount")):
			result += 1
	return result


func _live_aircraft_ids() -> Array[int]:
	var result: Array[int] = []
	var seen: Dictionary = {}
	for group_name in [&"aircraft", &"ai_aircraft"]:
		for node_variant in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node_variant):
				continue
			var node := node_variant as Node
			if node == null or node.is_queued_for_deletion():
				continue
			var instance_id := node.get_instance_id()
			if seen.has(instance_id):
				continue
			seen[instance_id] = true
			result.append(instance_id)
	return result
