extends Node

const CARRIER_SCENE := preload("res://LandCarrier/LandCarrier2.tscn")

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var staged_roots := 0
	var staged_nodes := 0
	var staged_frames := 0
	var carrier := CARRIER_SCENE.instantiate() as Node3D
	_expect(carrier != null, "LandCarrier2 did not instantiate")
	add_child(carrier)
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
		var occupant_mount_count := 0
		for child in aircraft.get_children():
			if child.has_method("is_pooled_aircraft_occupant_mount") \
					and bool(child.call("is_pooled_aircraft_occupant_mount")):
				occupant_mount_count += 1
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

	carrier.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("HANGAR_PRESENTATION_STAGING_SMOKETEST_OK roots=%d nodes=%d frames=%d" % [
			staged_roots,
			staged_nodes,
			staged_frames,
		])
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[HangarPresentationStagingSmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
