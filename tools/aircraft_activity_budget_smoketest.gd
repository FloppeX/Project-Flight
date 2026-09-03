extends Node3D

const AIRCRAFT_SCENE := preload("res://Aircraft/Aircraft_5.tscn")


class TargetFocusPanel:
	extends Node
	var focused_node: Node3D = null

	func is_target_camera_focusing_node(candidate: Node3D) -> bool:
		return candidate == focused_node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	_require(aircraft != null, "Aircraft_5 did not instantiate")
	var ai_toggle := aircraft.get_node_or_null("AIToggle")
	if ai_toggle != null:
		ai_toggle.set("ai_enabled_at_start", false)
	add_child(aircraft)
	await get_tree().process_frame
	await get_tree().process_frame

	var hud := aircraft.find_child("HeadsUpDisplay", true, false)
	var panel := aircraft.find_child("InstrumentPanel", true, false)
	_require(hud != null and panel != null, "cockpit UI missing")
	hud.call("set_view_updates_active", false)
	panel.call("set_view_updates_active", false)
	var viewports := _collect_subviewports(aircraft)
	_require(viewports.size() >= 3, "expected HUD, panel, and target viewports")
	for viewport in viewports:
		_require(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden viewport still active")
	var radar := panel.find_child("RadarCanvas", true, false)
	_require(radar != null and not radar.is_processing(), "hidden radar still processing")
	hud.call("set_view_updates_active", true)
	panel.call("set_view_updates_active", true)
	for viewport in viewports:
		_require(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "viewed viewport did not restore")
	_require(radar.is_processing(), "viewed radar did not restore")

	var tailhook := aircraft.find_child("TailHook", true, false)
	_require(tailhook != null and not tailhook.is_physics_processing(), "stowed tailhook is active")
	tailhook.call("deploy")
	_require(tailhook.is_physics_processing(), "deployed tailhook did not wake")
	tailhook.call("stow")
	_require(not tailhook.is_physics_processing(), "stowed tailhook did not sleep")

	var ejection := aircraft.find_child("EjectionSequence", true, false)
	var damage := aircraft.find_child("DamageEffects", true, false)
	_require(ejection != null and not ejection.is_physics_processing(), "dormant ejection sequence is active")
	_require(damage != null and not damage.is_processing(), "pristine damage effects are active")
	for weapon_name in ["Autocannon", "RocketPod"]:
		var weapon := aircraft.find_child(weapon_name, true, false)
		if weapon != null:
			_require(not weapon.is_processing(), "%s idle timer is active" % weapon_name)

	var landing_gear := aircraft.find_child("LandingGear", true, false)
	_require(landing_gear != null, "landing gear module missing")
	aircraft.set("local_altitude", 100.0)
	_require(bool(landing_gear.call("_can_skip_airborne_suspension_probes")), "airborne suspension did not budget")
	aircraft.set_meta("controls_disabled", true)
	_require(not bool(landing_gear.call("_can_skip_airborne_suspension_probes")), "deck handling incorrectly budgeted suspension")
	aircraft.remove_meta("controls_disabled")

	var pilot := aircraft.find_child("AIPilot", true, false)
	var targeting := aircraft.find_child("ControlTargeting", true, false)
	_require(pilot != null and targeting != null, "AI targeting nodes missing")
	var flight_director := get_node_or_null("/root/FlightDirector")
	_require(flight_director != null, "flight director autoload missing")
	pilot.call("initialize", aircraft)
	_require(bool(targeting.get("external_target_authority")), "AI did not claim targeting authority")
	pilot.call("deinitialize")
	_require(not bool(targeting.get("external_target_authority")), "player targeting authority did not restore")
	_require(not bool(targeting.get("auto_target_when_none")), "AI handoff re-enabled automatic player target acquisition")
	_require(not bool(targeting.get("auto_replace_target")), "AI handoff re-enabled automatic player target replacement")
	var disposable_target := Node3D.new()
	var disposable_target_id := disposable_target.get_instance_id()
	disposable_target.free()
	pilot.set("_attack_geometry_job", {"target_instance_id": disposable_target_id})
	pilot.call("_advance_attack_geometry_job")
	_require((pilot.get("_attack_geometry_job") as Dictionary).is_empty(), "freed attack-geometry target did not cancel safely")
	var freed_combat_target := Node3D.new()
	pilot.set("combat_target", freed_combat_target)
	freed_combat_target.free()
	pilot.call("_sync_ai_combat_selection_to_aircraft")
	_require(targeting.get("current_target") == null, "freed combat target was forwarded to aircraft targeting")
	pilot.set("combat_target", null)

	var saved_viewed_aircraft: Variant = flight_director.get("current_viewed_aircraft")
	var saved_player_aircraft: Variant = flight_director.get("player_controlled_plane")
	flight_director.set("current_viewed_aircraft", null)
	flight_director.set("player_controlled_plane", null)
	aircraft.set_meta("visual_budget_band", "far")
	aircraft.set_meta("visual_budget_distance_m", 3000.0)
	pilot.set("current_state", AIPilot.State.SEARCH)
	var far_guidance_interval_s: float = float(pilot.call("_get_guidance_update_interval_s"))
	_require(far_guidance_interval_s > 0.0, "distant search guidance did not use adaptive cadence")
	pilot.set("_force_guidance_update", false)
	pilot.set("_guidance_update_timer_s", far_guidance_interval_s)
	pilot.set("_guidance_elapsed_s", 0.0)
	_require(is_zero_approx(float(pilot.call("_consume_guidance_update_delta", 0.01))), "guidance scheduler did not reuse controls between updates")
	_require(float(pilot.call("_consume_guidance_update_delta", far_guidance_interval_s)) > far_guidance_interval_s, "guidance scheduler did not return accumulated delta")
	pilot.set("current_state", AIPilot.State.LANDING)
	var landing_guidance_interval_s: float = float(pilot.call("_get_guidance_update_interval_s"))
	_require(landing_guidance_interval_s > 0.0 and landing_guidance_interval_s <= 0.04, "landing guidance did not use precision cadence")
	pilot.set("current_state", AIPilot.State.SEARCH)
	aircraft.set_meta("visual_budget_band", "human")
	var focused_guidance_interval_s: float = float(pilot.call("_get_guidance_update_interval_s"))
	_require(focused_guidance_interval_s > 0.0 and focused_guidance_interval_s <= 0.04, "focused guidance did not use precision cadence")
	var saved_adaptive_guidance: bool = bool(pilot.get("adaptive_guidance_cadence_enabled"))
	pilot.set("adaptive_guidance_cadence_enabled", false)
	_require(is_zero_approx(float(pilot.call("_get_guidance_update_interval_s"))), "fixed-wing guidance rollback switch did not restore full rate")
	pilot.set("adaptive_guidance_cadence_enabled", saved_adaptive_guidance)
	flight_director.set("current_viewed_aircraft", saved_viewed_aircraft)
	flight_director.set("player_controlled_plane", saved_player_aircraft)
	aircraft.remove_meta("visual_budget_band")
	aircraft.remove_meta("visual_budget_distance_m")

	var budget := get_node_or_null("/root/EnemyVisualBudget")
	_require(budget != null, "visual budget autoload missing")
	var pilot_pool := get_node_or_null("/root/CockpitPilotPool")
	_require(pilot_pool != null and pilot_pool.has_method("get_pool_stats"), "cockpit pilot pool missing")
	var pre_tree_aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	_require(pre_tree_aircraft != null, "pre-tree Aircraft_5 did not instantiate")
	pre_tree_aircraft.freeze = true
	pre_tree_aircraft.position = Vector3(300.0, 1000.0, 300.0)
	var pre_tree_ai_toggle := pre_tree_aircraft.get_node_or_null("AIToggle")
	if pre_tree_ai_toggle != null:
		pre_tree_ai_toggle.set("ai_enabled_at_start", false)
	var pre_tree_hud := pre_tree_aircraft.get_node_or_null("HeadsUpDisplay")
	var pre_tree_pilot_mount := pre_tree_aircraft.get_node_or_null("CockpitPilot")
	var pool_before_pre_tree: Dictionary = pilot_pool.call("get_pool_stats")
	var prepare_result: Dictionary = budget.call("prepare_aircraft_presentation_for_staged_tree_entry", pre_tree_aircraft)
	_require(bool(prepare_result.get("prepared", false)), "off-tree AI presentation was not prepared")
	_require(int(prepare_result.get("detached_nodes", 0)) > 0, "off-tree AI presentation detached no nodes")
	_require(int(prepare_result.get("detached_roots", 0)) > 1, "staged preparation did not retain multiple roots")
	_require(pre_tree_aircraft.get_node_or_null("HeadsUpDisplay") == null, "off-tree HUD remained attached")
	_require(pre_tree_aircraft.get_node_or_null("CockpitPilot") == null, "off-tree pilot mount remained attached")
	add_child(pre_tree_aircraft)
	await get_tree().process_frame
	await get_tree().process_frame
	_require(pre_tree_aircraft.get_node_or_null("HeadsUpDisplay") == null, "dormant HUD entered the SceneTree")
	_require(pre_tree_aircraft.get_node_or_null("CockpitPilot") == null, "dormant pilot mount entered the SceneTree")
	var pool_after_pre_tree: Dictionary = pilot_pool.call("get_pool_stats")
	_require(
		int(pool_after_pre_tree.get("created", -1)) == int(pool_before_pre_tree.get("created", -2)) \
			and int(pool_after_pre_tree.get("checked_out", -1)) == int(pool_before_pre_tree.get("checked_out", -2)) \
			and int(pool_after_pre_tree.get("acquire_count", -1)) == int(pool_before_pre_tree.get("acquire_count", -2)),
		"off-tree AI preparation checked out or created a pilot rig"
	)
	var pre_tree_cache: Dictionary = budget.call("_get_cache_for_root", pre_tree_aircraft)
	var pre_tree_session = pre_tree_cache.get("presentation_session")
	_require(pre_tree_session != null, "prepared AI presentation session was not retained")
	var restored_root_names: Array[String] = []
	var staged_node_total := 0
	while bool(pre_tree_aircraft.get_meta("visual_budget_presentation_staging", false)):
		var staged_result: Dictionary = budget.call(
			"restore_next_staged_aircraft_presentation_root",
			pre_tree_aircraft
		)
		var staged_root_name := str(staged_result.get("root_name", ""))
		_require(not staged_root_name.is_empty(), "staged restoration returned no root")
		restored_root_names.append(staged_root_name)
		staged_node_total += int(staged_result.get("node_count", 0))
		await get_tree().process_frame
	_require(restored_root_names.size() == int(prepare_result.get("detached_roots", 0)), "staged restoration skipped a root")
	_require(restored_root_names[-1] == "AudioManager3D", "audio manager was not restored after its camera dependency")
	_require(restored_root_names.find("CameraController") < restored_root_names.find("AudioManager3D"), "camera controller was not restored before audio")
	_require(staged_node_total == int(prepare_result.get("detached_nodes", 0)), "staged node accounting changed during restoration")
	_require(bool(pre_tree_aircraft.get_meta("visual_budget_presentation_keep_attached", false)), "completed staging lost its keep-attached lock")
	budget.call("release_aircraft_presentation_keep_attached", pre_tree_aircraft)
	_require(pre_tree_aircraft.get_node_or_null("HeadsUpDisplay") == pre_tree_hud, "prepared HUD identity did not restore")
	_require(pre_tree_aircraft.get_node_or_null("CockpitPilot") == pre_tree_pilot_mount, "prepared pilot mount identity did not restore")
	var pool_after_restore: Dictionary = pilot_pool.call("get_pool_stats")
	_require(
		int(pool_after_restore.get("acquire_count", -1)) == int(pool_before_pre_tree.get("acquire_count", -2)),
		"non-presented restoration checked out a pilot rig"
	)
	budget.call("release_aircraft_cache", pre_tree_aircraft, true)
	pre_tree_aircraft.queue_free()
	await get_tree().process_frame
	var materialize_flight := preload("res://Enemies/EnemyVirtualFlight.gd").new()
	materialize_flight.flight_name = "SMOKE-01"
	var materialize_scenes: Array[PackedScene] = [AIRCRAFT_SCENE]
	var materialize_loadouts: Array[String] = ["guns"]
	materialize_flight.setup(Vector3(1200.0, 1000.0, 1200.0), materialize_scenes, materialize_loadouts)
	add_child(materialize_flight)
	var pool_before_materialize: Dictionary = pilot_pool.call("get_pool_stats")
	materialize_flight.call("_begin_materialize")
	materialize_flight.call("_tick_materialize_step")
	var materialized_aircraft_list: Array = materialize_flight.get("active_aircraft") as Array
	_require(materialized_aircraft_list.size() == 1, "virtual flight did not materialize one aircraft")
	var materialized_aircraft := materialized_aircraft_list[0] as RigidBody3D
	_require(materialized_aircraft != null and is_instance_valid(materialized_aircraft), "materialized aircraft is invalid")
	materialized_aircraft.freeze = true
	_require(materialized_aircraft.get_node_or_null("HeadsUpDisplay") == null, "virtual-flight HUD entered the SceneTree")
	_require(materialized_aircraft.get_node_or_null("CockpitPilot") == null, "virtual-flight pilot mount entered the SceneTree")
	_require(bool(materialized_aircraft.get_meta("visual_budget_pre_tree_presentation_prepared", false)), "virtual-flight presentation was not prepared off-tree")
	var pool_after_materialize: Dictionary = pilot_pool.call("get_pool_stats")
	_require(
		int(pool_after_materialize.get("created", -1)) == int(pool_before_materialize.get("created", -2)) \
			and int(pool_after_materialize.get("acquire_count", -1)) == int(pool_before_materialize.get("acquire_count", -2)),
		"virtual-flight materialization checked out or created a pilot rig"
	)
	var budget_report: Dictionary = budget.call("get_report_stats")
	_require(int(budget_report.get("pre_tree_prepared_total", 0)) >= 2, "pre-tree preparation telemetry did not advance")
	materialize_flight.dematerialize()
	await get_tree().process_frame
	materialize_flight.queue_free()
	await get_tree().process_frame
	var direct_spawner := preload("res://Enemies/EnemyAircraftSpawner.gd").new()
	add_child(direct_spawner)
	await get_tree().process_frame
	var direct_spawned_variant: Variant = await direct_spawner.call(
		"_spawn_ai_fighter",
		AIRCRAFT_SCENE,
		"PresentationPreparedDirectSpawn",
		2,
		"enemies",
		Vector3(1800.0, 1000.0, 1800.0),
		Vector3.FORWARD,
		80.0
	)
	var direct_spawned := direct_spawned_variant as RigidBody3D
	_require(direct_spawned != null and is_instance_valid(direct_spawned), "direct AI spawner did not create an aircraft")
	_require(bool(direct_spawned.get_meta("visual_budget_pre_tree_presentation_prepared", false)), "direct AI spawn presentation was not prepared off-tree")
	_require(int(direct_spawned.get_meta("visual_budget_pre_tree_detached_nodes", 0)) > 0, "direct AI spawn detached no presentation nodes")
	_require(direct_spawned.get_node_or_null("HeadsUpDisplay") == null, "direct AI spawn HUD entered the SceneTree")
	_require(direct_spawned.get_node_or_null("CockpitPilot") == null, "direct AI spawn pilot mount entered the SceneTree")
	var active_planes: Array = direct_spawner.get("_active_ai_planes") as Array
	var active_count_before_stale_cleanup := active_planes.size()
	var stale_respawn_aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	_require(stale_respawn_aircraft != null, "stale respawn aircraft did not instantiate")
	if stale_respawn_aircraft != null:
		active_planes.append(stale_respawn_aircraft)
		direct_spawner.set("respawn_delay", 0.01)
		direct_spawner.call("_schedule_respawn", stale_respawn_aircraft)
		stale_respawn_aircraft.free()
		await get_tree().create_timer(0.05).timeout
		_require(active_planes.size() == active_count_before_stale_cleanup, "freed enemy remained in the typed active-aircraft array")
	budget.call("release_aircraft_cache", direct_spawned, true)
	direct_spawned.queue_free()
	direct_spawner.queue_free()
	await get_tree().process_frame

	var detached_audio := AudioStreamPlayer.new()
	detached_audio.stream = AudioStreamGenerator.new()
	add_child(detached_audio)
	await get_tree().process_frame
	detached_audio.play()
	detached_audio.set_meta("visual_budget_audio_was_playing", true)
	remove_child(detached_audio)
	budget.call("_apply_aircraft_audio_budget", [detached_audio], true)
	_require(not detached_audio.playing, "detached AI audio attempted to resume playback")
	detached_audio.free()
	var cache: Dictionary = budget.call("_get_cache_for_root", aircraft)
	var detail_nodes: Array = budget.call("_resolve_ref_array", cache.get("ai_detail_refs", []))
	var original_hud := aircraft.get_node_or_null("HeadsUpDisplay")
	var original_audio_manager := aircraft.get_node_or_null("AudioManager3D")
	budget.call("_apply_ai_aircraft_player_only_budget", aircraft, false, cache)
	_require(aircraft.get_node_or_null("HeadsUpDisplay") == null, "dormant AI presentation remained attached")
	var target_focus_panel := TargetFocusPanel.new()
	target_focus_panel.add_to_group("instrument_panel")
	add_child(target_focus_panel)
	var target_focus_aircraft: Array[Node3D] = [aircraft]
	for target_index in range(2):
		var additional_target := AIRCRAFT_SCENE.instantiate() as RigidBody3D
		_require(additional_target != null, "additional target aircraft did not instantiate")
		additional_target.freeze = true
		additional_target.position = Vector3(350.0 + target_index * 80.0, 1000.0, 350.0)
		var additional_toggle := additional_target.get_node_or_null("AIToggle")
		if additional_toggle != null:
			additional_toggle.set("ai_enabled_at_start", false)
		budget.call("prepare_ai_aircraft_for_tree_entry", additional_target)
		add_child(additional_target)
		target_focus_aircraft.append(additional_target)
	await get_tree().process_frame
	await get_tree().process_frame
	var target_pool_before: Dictionary = pilot_pool.call("get_pool_stats")
	var target_saved_viewed: Variant = flight_director.get("current_viewed_aircraft")
	var target_saved_player: Variant = flight_director.get("player_controlled_plane")
	flight_director.set("current_viewed_aircraft", null)
	flight_director.set("player_controlled_plane", null)
	var target_budget_elapsed_ms := 0.0
	for target_aircraft in target_focus_aircraft:
		target_focus_panel.focused_node = target_aircraft
		var target_budget_start_usec := Time.get_ticks_usec()
		budget.call("_apply_budget_to_unit", target_aircraft, null)
		target_budget_elapsed_ms = maxf(
			target_budget_elapsed_ms,
			float(Time.get_ticks_usec() - target_budget_start_usec) * 0.001
		)
		_require(target_aircraft.get_node_or_null("HeadsUpDisplay") == null, "target feed restored the target aircraft HUD")
		_require(target_aircraft.get_node_or_null("CockpitPilot") == null, "target feed restored the target aircraft pilot")
		_require(str(target_aircraft.get_meta("visual_budget_band", "")) != "human", "target feed promoted target AI to player cadence")
		_require(bool(target_aircraft.get_meta("visual_budget_ai_detail_enabled", false)), "target feed did not retain exterior detail")
		_require(bool(target_aircraft.get_meta("visual_budget_shadows_enabled", false)), "target feed did not retain exterior shadows")
		_require(not bool(target_aircraft.get_meta("visual_budget_ai_audio_enabled", true)), "target feed enabled distant target audio")
	flight_director.set("current_viewed_aircraft", target_saved_viewed)
	flight_director.set("player_controlled_plane", target_saved_player)
	var target_pool_after: Dictionary = pilot_pool.call("get_pool_stats")
	_require(
		int(target_pool_after.get("acquire_count", -1)) == int(target_pool_before.get("acquire_count", -2)),
		"target-feed switch checked out a pooled pilot"
	)
	print("[AircraftActivityBudgetSmoketest] target_focus_ok switches=%d max_budget_ms=%.3f pilot_acquire_delta=%d exterior_detail=%s" % [
		target_focus_aircraft.size(),
		target_budget_elapsed_ms,
		int(target_pool_after.get("acquire_count", 0)) - int(target_pool_before.get("acquire_count", 0)),
		str(bool(aircraft.get_meta("visual_budget_ai_detail_enabled", false))),
	])
	target_focus_panel.queue_free()
	for target_index in range(1, target_focus_aircraft.size()):
		var cleanup_target := target_focus_aircraft[target_index]
		budget.call("release_aircraft_cache", cleanup_target, true)
		cleanup_target.queue_free()
	await get_tree().process_frame
	_require(flight_director != null and bool(flight_director.call("_node_has_cameras", aircraft)), "detached AI aircraft disappeared from camera cycling")
	flight_director.call("_set_aircraft_view_ui_enabled", aircraft, true)
	_require(aircraft.get_node_or_null("HeadsUpDisplay") == original_hud, "AI presentation did not restore the original nodes")
	_require(aircraft.get_node_or_null("AudioManager3D") == original_audio_manager, "AI audio manager did not restore with the viewed aircraft")
	_require(original_audio_manager != null and original_audio_manager.is_processing(), "viewed AI aircraft audio manager remained dormant")
	var gear_visibility_before: Dictionary = {}
	for gear_name in ["NoseGearRig", "LeftGearRig", "RightGearRig"]:
		var gear_rig := aircraft.find_child(gear_name, true, false) as Node3D
		_require(gear_rig != null, "%s visual missing" % gear_name)
		gear_visibility_before[gear_name] = gear_rig.visible
	budget.call("_apply_ai_aircraft_detail_budget", detail_nodes, false)
	for gear_name in ["NoseGearRig", "LeftGearRig", "RightGearRig"]:
		var gear_rig := aircraft.find_child(gear_name, true, false) as Node3D
		_require(gear_rig.visible == bool(gear_visibility_before[gear_name]), "%s visibility was overridden" % gear_name)
	aircraft.set_meta("visual_budget_ai_detail_enabled", false)
	var nose_gear_rig := aircraft.find_child("NoseGearRig", true, false)
	_require(not bool(nose_gear_rig.call("_visual_budget_allows_update")), "gear visual budget early-out missing")
	budget.call("_apply_ai_aircraft_detail_budget", detail_nodes, true)

	var original_contact_monitor: bool = aircraft.contact_monitor
	var saved_contact_budget: bool = bool(budget.get("budget_distant_aircraft_contact_monitoring"))
	aircraft.set("local_altitude", 700.0)
	pilot.set("current_state", AIPilot.State.SEARCH)
	budget.call("_apply_aircraft_contact_monitor_budget", aircraft, false, 3000.0)
	_require(not aircraft.contact_monitor, "safe distant aircraft contact monitor remained active")
	budget.call("_apply_aircraft_contact_monitor_budget", aircraft, true, 3000.0)
	_require(aircraft.contact_monitor == original_contact_monitor, "focused aircraft contact monitor did not restore")
	pilot.set("current_state", AIPilot.State.LANDING)
	budget.call("_apply_aircraft_contact_monitor_budget", aircraft, false, 3000.0)
	_require(aircraft.contact_monitor == original_contact_monitor, "landing contact monitor was incorrectly budgeted")
	budget.set("budget_distant_aircraft_contact_monitoring", false)
	pilot.set("current_state", AIPilot.State.SEARCH)
	budget.call("_apply_aircraft_contact_monitor_budget", aircraft, false, 3000.0)
	_require(aircraft.contact_monitor == original_contact_monitor, "contact-monitor rollback switch did not restore")
	budget.set("budget_distant_aircraft_contact_monitoring", saved_contact_budget)

	var virtual_flight := preload("res://Enemies/EnemyVirtualFlight.gd").new()
	pilot.set("engagement_radius_from_carrier_m", 1234.0)
	pilot.set("disengage_radius_from_carrier_m", 2345.0)
	virtual_flight.call("_configure_materialized_enemy_aircraft", aircraft, "guns")
	_require(
		is_zero_approx(float(pilot.get("engagement_radius_from_carrier_m"))) \
			and is_zero_approx(float(pilot.get("disengage_radius_from_carrier_m"))),
		"virtual patrol retained an asymmetric combat leash"
	)
	virtual_flight.free()

	for aircraft_scene_path in ["res://Aircraft/Aircraft_3.tscn", "res://Aircraft/Aircraft_5.tscn"]:
		for dependency in ResourceLoader.get_dependencies(aircraft_scene_path):
			_require(
				not String(dependency).to_lower().contains("_exploded.glb"),
				"%s still loads a legacy exploded-model GLB" % aircraft_scene_path
			)
	_require(not bool(aircraft.get("legacy_exploded_model_breakup_enabled")), "legacy exploded-model breakup is enabled by default")
	aircraft.set("critical_debris_chunk_min_count", 3)
	aircraft.set("critical_debris_chunk_max_count", 3)
	aircraft.call("explode")
	var destruction_chunk_count := 0
	for child in get_children():
		if String(child.name).begins_with("AircraftDebrisChunk_"):
			destruction_chunk_count += 1
	_require(destruction_chunk_count == 0, "aircraft debris was allocated in the destruction frame")
	# The debris burst is deliberately spread over 0.28 seconds. A fixed frame
	# count can expire too early in an uncapped Forward+ validation run.
	var destruction_deadline_msec := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < destruction_deadline_msec:
		await get_tree().process_frame
		destruction_chunk_count = 0
		for child in get_children():
			if String(child.name).begins_with("AircraftDebrisChunk_"):
				destruction_chunk_count += 1
		if destruction_chunk_count == 3:
			break
	_require(destruction_chunk_count == 3, "aircraft destruction did not use the configured procedural chunks")
	_require(not is_instance_valid(aircraft), "destroyed aircraft was not released")
	for child in get_children():
		if String(child.name).begins_with("AircraftDebrisChunk_") or String(child.name) == "Explosion":
			child.queue_free()
	await get_tree().process_frame

	print("[AircraftActivityBudgetSmoketest] PASS viewports=%d detail_nodes=%d target_budget_ms=%.3f target_pool_acquire_delta=%d" % [
		viewports.size(),
		detail_nodes.size(),
		target_budget_elapsed_ms,
		int(target_pool_after.get("acquire_count", 0)) - int(target_pool_before.get("acquire_count", 0)),
	])
	get_tree().quit(0)


func _collect_subviewports(root_node: Node) -> Array[SubViewport]:
	var result: Array[SubViewport] = []
	_collect_subviewports_recursive(root_node, result)
	return result


func _collect_subviewports_recursive(node: Node, result: Array[SubViewport]) -> void:
	if node is SubViewport:
		result.append(node as SubViewport)
	for child in node.get_children():
		_collect_subviewports_recursive(child, result)


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("[AircraftActivityBudgetSmoketest] FAIL %s" % message)
	get_tree().quit(1)
	assert(condition, message)
