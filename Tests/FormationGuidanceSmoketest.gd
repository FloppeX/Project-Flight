extends Node

class SearchPilot extends AIPilot:
	var navigated_without_formation := false
	func _navigate_to_waypoint(_delta: float):
		navigated_without_formation = not formation_anchor_active and formation_peer_ids.is_empty() \
			and formation_speed_cap_mps < 0.0 and formation_lead_bank_rad == 0.0

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for child in get_tree().root.get_children():
		if child != self: child.process_mode = Node.PROCESS_MODE_DISABLED
	var flight := Flight.new()
	add_child(flight)
	flight.set_physics_process(false)
	var craft_list: Array[RigidBody3D] = []
	for i in range(4):
		var craft := RigidBody3D.new()
		craft.gravity_scale = 0.0
		craft.position = Vector3(0, 1200, 0) + Flight.FORMATION_OFFSETS[i]
		craft.linear_velocity = Vector3(0, 0, 80)
		add_child(craft)
		craft.add_to_group("ai_aircraft")
		var pilot := SearchPilot.new()
		pilot.name = "AIPilot"
		craft.add_child(pilot)
		pilot.set_physics_process(false)
		pilot.aircraft = craft
		pilot.current_state = AIPilot.State.SEARCH
		flight.register(craft)
		craft_list.append(craft)
	flight._update_formation()
	var lead := craft_list[0]
	var pilot := lead.get_node("AIPilot") as AIPilot
	check(not pilot._check_collision_avoidance(0.1), "parallel formation is not a collision")
	pilot.formation_peer_ids.clear()
	check(pilot._check_collision_avoidance(0.1), "unrelated traffic retains ordinary separation")
	flight._update_formation()
	# Move the other two aircraft clear, then make one peer converge head-on.
	craft_list[2].position.x = 1000
	craft_list[3].position.x = -1000
	craft_list[1].position = lead.position + Vector3(0, 0, 100)
	craft_list[1].linear_velocity = Vector3(0, 0, -80)
	check(pilot._check_collision_avoidance(0.1), "converging formation peer still triggers avoidance")
	var breaking := craft_list[1].get_node("AIPilot") as AIPilot
	breaking.set_formation_speed_guidance(62.0, -12.0)
	breaking.set_formation_handling(1.0, 1.0, 0.3, 4.0)
	breaking.change_state(AIPilot.State.DOGFIGHT)
	# Assert before Flight updates: no frame of formation control may leak into combat.
	check(not breaking.formation_anchor_active and breaking.formation_peer_ids.is_empty(), "dogfight immediately releases slot and peer exemptions")
	check(breaking.formation_speed_cap_mps < 0.0 and breaking.formation_speed_bias_mps == 0.0, "dogfight immediately releases speed guidance")
	check(breaking.formation_slot_quality == 0.0 and breaking.formation_ahead_hold_t == 0.0 and breaking.formation_lead_bank_rad == 0.0 and breaking.formation_lead_vertical_speed_mps == 0.0, "dogfight immediately releases formation handling")
	breaking.target_speed = 120.0
	check(is_equal_approx(breaking._get_effective_target_speed(), 120.0), "combat speed is not limited by formation cruise")
	flight._update_formation()
	check(not breaking.formation_anchor_active and breaking.formation_peer_ids.is_empty(), "combat releases formation guidance")
	check(not pilot.formation_peer_ids.has(craft_list[1].get_instance_id()), "combat aircraft loses reduced separation")
	var wingman := craft_list[2].get_node("AIPilot") as AIPilot
	craft_list[2].position = lead.position + Flight.FORMATION_OFFSETS[2]
	flight._update_formation()
	check(absf(wingman.formation_anchor.x - craft_list[2].position.x) < 0.01, "remaining wingman keeps left slot")
	check(is_equal_approx(wingman._get_effective_target_speed(), 80.0), "station holding matches lead speed")
	check(wingman.formation_anchor.z > craft_list[2].position.z + 100.0, "station holding steers ahead")
	# A remembered enemy overrides patrol without changing the SEARCH state.
	var track = preload("res://AI/VisualContactTrack.gd").new()
	track.observe(Vector3(2600, 742, -3600), Vector3(24, 0, 6), 0.0)
	wingman._visual_contacts[123] = track
	wingman._visual_clock_s = 12.0
	wingman.dogfight_enabled = true
	wingman._terrain_height_callable = func(_position: Vector3) -> float: return 0.0
	check(wingman._dogfight_search_remerge(1.0 / 60.0), "expired contact still owns finite search maneuver")
	check(wingman.navigated_without_formation, "search clears formation before issuing steering")
	flight._update_formation()
	check(not wingman.formation_anchor_active and wingman.formation_peer_ids.is_empty(), "flight update cannot reattach searching wingman")
	check(not pilot.formation_peer_ids.has(craft_list[2].get_instance_id()), "searching aircraft loses formation separation exemptions")
	wingman._visual_clock_s = 19.0
	flight._update_formation()
	check(wingman.formation_anchor_active, "formation resumes after bounded search expires")
	pilot._visual_contacts[124] = track
	pilot._visual_clock_s = 12.0
	pilot.dogfight_enabled = true
	flight._update_formation()
	check(pilot.formation_peer_ids.is_empty() and pilot.formation_speed_cap_mps < 0.0, "searching leader is not slowed by formation")
	pilot._visual_contacts.clear()
	pilot.change_state(AIPilot.State.DOGFIGHT)
	check(pilot.formation_speed_cap_mps < 0.0 and pilot.formation_peer_ids.is_empty(), "leader immediately releases formation waiting speed")
	flight._update_formation()
	check(not breaking.formation_anchor_active and not pilot.formation_anchor_active, "flight updates cannot reapply formation during combat")
	breaking.change_state(AIPilot.State.SEARCH)
	check(not breaking.formation_anchor_active, "combat exit does not restore stale formation commands")
	flight._update_formation()
	check(breaking.formation_peer_ids.size() > 1, "formation resumes after return to patrol")
	# Explicit orders often remain in SEARCH until a distant formation materializes.
	# Cruise formation must not replace their own ingress routes or cap their turns.
	for explicit_mission in [Flight.Mission.ATTACK, Flight.Mission.INTERCEPT]:
		flight.mission = explicit_mission
		flight._intercept_tracks_flight = explicit_mission == Flight.Mission.INTERCEPT
		flight._update_formation()
		for craft in craft_list:
			var member := craft.get_node("AIPilot") as AIPilot
			check(not member.formation_anchor_active and member.formation_peer_ids.is_empty(), "designated mission owns each aircraft's ingress guidance")
			check(member.formation_speed_cap_mps < 0.0, "designated mission releases formation waiting speed")
	flight.mission = Flight.Mission.CAP
	flight._update_formation()
	check(breaking.formation_peer_ids.size() > 1, "CAP formation still resumes after explicit mission")
	print("FORMATION_GUIDANCE_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	for craft in craft_list: craft.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
