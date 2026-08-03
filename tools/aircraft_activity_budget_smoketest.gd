extends Node3D

const AIRCRAFT_SCENE := preload("res://Aircraft/Aircraft_5.tscn")


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
	budget.call("_apply_ai_aircraft_player_only_budget", aircraft, false, cache)
	_require(aircraft.get_node_or_null("HeadsUpDisplay") == null, "dormant AI presentation remained attached")
	_require(flight_director != null and bool(flight_director.call("_node_has_cameras", aircraft)), "detached AI aircraft disappeared from camera cycling")
	budget.call("ensure_aircraft_presentation_attached", aircraft)
	_require(aircraft.get_node_or_null("HeadsUpDisplay") == original_hud, "AI presentation did not restore the original nodes")
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
	for _frame in range(40):
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

	print("[AircraftActivityBudgetSmoketest] PASS viewports=%d detail_nodes=%d" % [viewports.size(), detail_nodes.size()])
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
