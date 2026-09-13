extends Node3D
const Track = preload("res://AI/VisualContactTrack.gd")
var checks := 0
var failures := 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var track = Track.new()
	check(track.sample(0, 5).is_empty(), "Unknown target has no invented position")
	track.observe(Vector3(0, 1000, 400), Vector3(0, 0, 80), 0)
	track.visible = false
	var remembered: Dictionary = track.sample(1, 5)
	check(remembered.position == Vector3(0, 1000, 480), "Hidden contact extrapolates last observation")
	check(not remembered.visible, "Memory cannot authorize gunfire")
	check(track.sample(4, 5).uncertainty_m > remembered.uncertainty_m, "Uncertainty grows while hidden")
	check(track.sample(6, 5).expired, "Contact memory expires")
	track.shift_origin(Vector3(4000, 0, 0))
	check(track.sample(1, 5).position == remembered.position - Vector3(4000, 0, 0), "Memory rebases once")
	check(Track.in_visual_sector(Vector3.BACK), "Forward target visible")
	check(not Track.in_visual_sector(Vector3.FORWARD), "Rear target not magically visible")
	check(not Track.in_visual_sector(Vector3.DOWN), "Belly target occluded")
	check(Track.in_search_sector(Vector3.FORWARD, Vector3.FORWARD), "A deliberate remembered shoulder check can see behind")
	check(not Track.in_search_sector(Vector3.FORWARD, Vector3.BACK), "Front memory cannot reveal an unseen rear contact")
	check(not Track.in_search_sector(Vector3.DOWN, Vector3.FORWARD), "Shoulder check retains belly blind sector")
	var craft := preload("res://Aircraft/Aircraft_5.tscn").instantiate() as RigidBody3D
	craft.team = 1
	craft.position = Vector3(0, 1000, 0)
	craft.freeze = true
	add_child(craft)
	var enemy := preload("res://Aircraft/Aircraft_3.tscn").instantiate() as RigidBody3D
	enemy.position = Vector3(0, 1000, 500)
	enemy.freeze = true
	enemy.team = 2
	add_child(enemy)
	# Aircraft health/module initialization awaits a process frame, not a physics tick.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pilot: AIPilot = craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	enemy.get_node("AIPilot").set_physics_process(false)
	pilot.combat_target = enemy
	pilot._update_visual_contacts([enemy])
	check(pilot._dogfight_target_observation(enemy).is_empty(), "First glimpse is not immediate recognition")
	pilot.current_state = AIPilot.State.DOGFIGHT
	craft.linear_velocity = Vector3(0, 0, 85)
	pilot._state_dogfight(1.0 / 60.0)
	check(pilot.current_state == AIPilot.State.DOGFIGHT and pilot._dogfight_fire_block_reason == "recognizing_contact",
		"Pending recognition holds own course instead of dropping the assigned contact")
	check(absf(pilot.nav_waypoint.x - craft.position.x) < 0.01 and not pilot._dogfight_burst_active,
		"Recognition grace uses own course and never authorizes firing")
	for step in 6:
		pilot._visual_clock_s += 0.1
		pilot._update_visual_contacts([enemy])
	var visible: Dictionary = pilot._dogfight_target_observation(enemy)
	check(not visible.is_empty() and visible.visible, "Real pilot observes a clear forward contact")
	if visible.is_empty():
		print("CONTACT_DIAGNOSTIC own=%s enemy=%s teams=%s/%s basis=%s valid=%s" % [craft.global_position, enemy.global_position, craft.get_team(), enemy.get_team(), craft.global_basis, pilot._is_enemy_aircraft_target(enemy)])
		get_tree().quit(1)
		return
	enemy.position = Vector3(0, 1000, -500)
	pilot._visual_clock_s += 0.1
	pilot._update_visual_contacts([enemy])
	var lost: Dictionary = pilot._dogfight_target_observation(enemy)
	check(not lost.visible, "Real pilot loses rear contact at close range")
	check(lost.position.z > 400, "Hidden position jump does not leak into remembered track")
	pilot.known_enemies = [enemy]
	check(pilot._find_best_air_target() == null, "No proximity reacquisition of hidden target")
	enemy.position = Vector3(0, 1000, 500)
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 1000, 250)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 100, 10)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	await get_tree().physics_frame
	pilot._update_visual_contacts([enemy])
	check(not pilot._dogfight_target_observation(enemy).visible, "World collision blocks visual observation")
	pilot.current_state = AIPilot.State.DOGFIGHT
	craft.linear_velocity = Vector3(0, 0, 85)
	pilot._dogfight_burst_active = true
	pilot._state_dogfight(1.0 / 60.0)
	check(not pilot._dogfight_burst_active and pilot._dogfight_fire_block_reason == "lost_visual_contact", "Occlusion cancels an active gun burst")
	wall.queue_free()
	await get_tree().physics_frame
	pilot._visual_clock_s += 0.1
	pilot._update_visual_contacts([enemy])
	check(pilot._dogfight_target_observation(enemy).visible, "Target can be reacquired after occlusion")
	pilot._visual_clock_s += 20
	pilot._state_dogfight(0.1)
	check(pilot.combat_target == null and pilot.current_state == AIPilot.State.SEARCH, "Expired contact is actually dropped")
	pilot.current_state = AIPilot.State.DOGFIGHT
	pilot._dogfight_assertive_turn_active = true
	pilot._dogfight_track_rate_initialized = true
	pilot._dogfight_energy_recovering = false
	pilot._coordinated_turn_nonwing_vertical_accel_mps2 = 0.0
	craft.global_basis = Basis(Vector3.BACK, deg_to_rad(20.0))
	craft.linear_velocity = Vector3(0, 15, 85)
	pilot._coordinated_turn_last_frame = -100
	var climb_arrest := pilot._compute_coordinated_turn_controls(1.0 / 60.0, deg_to_rad(70), -10, 3.4, true, false)
	check(float(climb_arrest.target_g) < 1.0, "Steep-turn demand must not override climb arrest during roll-in")
	pilot._dogfight_contact_visible = false
	pilot._dogfight_contact_age_s = 3.0
	pilot.altitude_agl = 1000
	var reset_point := pilot._update_dogfight_tactical_reset(0.1, craft.position + Vector3(0, 0, -500))
	check(pilot._dogfight_reset_timer_s > 0, "Lost contact begins committed reset")
	var direction := (reset_point - craft.position).normalized()
	var second_point := pilot._update_dogfight_tactical_reset(0.1, craft.position + Vector3(500, 300, -200))
	check(direction.distance_to((second_point - craft.position).normalized()) < 0.001, "Reset direction does not reroll with target movement")
	pilot._visual_contacts.clear()
	pilot.current_air_task = AirTask.intercept_target(enemy)
	pilot.receive_intercept_contact_report(enemy, Vector3(41, 1000, 2460), Vector3(1, 0, 78))
	var report: Dictionary = pilot._dogfight_target_observation(enemy)
	check(not report.visible and report.position == Vector3(0, 1000, 2500), "Controller report is coarse and not visual")
	enemy.position = Vector3(9000, 9000, 9000)
	enemy.linear_velocity = Vector3(300, 400, 500)
	pilot._visual_clock_s += 1.0
	var stale_report: Dictionary = pilot._dogfight_target_observation(enemy)
	check(stale_report.position == Vector3(0, 1000, 2580), "Report prediction cannot read hidden target movement")
	pilot._visual_clock_s += 60.0
	check(pilot._dogfight_target_observation(enemy).expired, "Controller reports expire without fresh events")
	print("VISUAL_CONTACT_SMOKETEST checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
