extends Node

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
		var pilot := AIPilot.new()
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
	pilot.change_state(AIPilot.State.DOGFIGHT)
	check(pilot.formation_speed_cap_mps < 0.0 and pilot.formation_peer_ids.is_empty(), "leader immediately releases formation waiting speed")
	flight._update_formation()
	check(not breaking.formation_anchor_active and not pilot.formation_anchor_active, "flight updates cannot reapply formation during combat")
	breaking.change_state(AIPilot.State.SEARCH)
	check(not breaking.formation_anchor_active, "combat exit does not restore stale formation commands")
	flight._update_formation()
	check(breaking.formation_peer_ids.size() > 1, "formation resumes after return to patrol")
	print("FORMATION_GUIDANCE_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	for craft in craft_list: craft.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
