extends Node3D

class Target:
	extends RigidBody3D
	var current_health := 1000.0
	func get_team() -> int: return 2

var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	for manager_name in ["FlightDirector", "AirOpsManager", "EnemyOpsManager", "GroundOpsManager", "OperationsCoordinator"]:
		var manager := get_node_or_null("/root/" + manager_name)
		if manager: manager.process_mode = Node.PROCESS_MODE_DISABLED
	call_deferred("run")

func run() -> void:
	var craft := preload("res://Aircraft/Aircraft_5.tscn").instantiate() as RigidBody3D
	craft.freeze = true
	craft.position.y = 1000
	add_child(craft)
	await get_tree().process_frame
	await get_tree().process_frame
	var pilot: AIPilot = craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	var target := Target.new()
	target.freeze = true
	target.set_meta("is_helicopter", true)
	add_child(target)
	pilot.combat_target = target
	check(pilot._uses_helicopter_flight(target), "Helicopter classification")
	var origin := craft.position
	var velocity := Vector3(0, 0, 110)
	var contact := origin + Vector3(0, -50, 800)
	var tactic := pilot._compute_helicopter_attack_tactic(origin, velocity, contact, contact, 0.1)
	check(pilot._helicopter_attack_phase == AIPilot.HelicopterAttackPhase.PASS and tactic.gun_commit, "Aligned approach commits to a firing pass")
	tactic = pilot._compute_helicopter_attack_tactic(origin, velocity, contact, contact, 4.0)
	check(pilot._helicopter_attack_phase == AIPilot.HelicopterAttackPhase.PASS, "Old four-second limit cannot cancel approach before firing range")
	contact = origin + Vector3(0, 0, 200)
	tactic = pilot._compute_helicopter_attack_tactic(origin, velocity, contact, contact, 0.1)
	check(pilot._helicopter_attack_phase == AIPilot.HelicopterAttackPhase.EXTEND and not tactic.gun_commit, "Close pass extends instead of tail pursuit")
	check(tactic.aim_point.z > origin.z + 900, "Extension carries velocity forward")
	contact = origin + Vector3(700, 0, -100)
	tactic = pilot._compute_helicopter_attack_tactic(origin, velocity, contact, contact, 20.0)
	check(pilot._helicopter_attack_phase == AIPilot.HelicopterAttackPhase.EXTEND, "Elapsed time alone cannot end extension")
	check(is_zero_approx(tactic.aim_point.x - origin.x), "Moving helicopter cannot bend latched extension")
	var shift := Vector3(4000, 0, -4000)
	pilot.apply_origin_shift(shift)
	check(pilot._helicopter_extension_origin == origin - shift, "World recentering preserves extension origin")
	pilot.apply_origin_shift(-shift)
	var outbound := origin + Vector3(0, 0, pilot._helicopter_extension_distance_m + 10)
	tactic = pilot._compute_helicopter_attack_tactic(outbound, velocity, contact, contact, 0.1)
	check(pilot._helicopter_attack_phase == AIPilot.HelicopterAttackPhase.APPROACH, "Separation and travel release next attack")
	pilot._helicopter_attack_phase = AIPilot.HelicopterAttackPhase.EXTEND
	pilot._dogfight_energy_recovering = true
	tactic = pilot._compute_helicopter_attack_tactic(outbound, velocity * 0.4, contact, contact, 0.1)
	check(pilot._helicopter_attack_phase == AIPilot.HelicopterAttackPhase.EXTEND, "Low energy postpones reversal")
	check(is_equal_approx(tactic.aim_point.y, outbound.y), "Low energy rebuilds speed before climbing")
	pilot._reset_dogfight_pursuit()
	check(pilot._helicopter_attack_phase == AIPilot.HelicopterAttackPhase.APPROACH, "Target reset clears pass phase")
	craft.linear_velocity = velocity
	pilot._update_dogfight_closure_throttle(0.1, origin + Vector3(0, 0, 400), Vector3.ZERO, false)
	check(pilot.target_speed >= pilot.dogfight_rejoin_speed_mps, "Hovering helicopter does not command slow pursuit")
	target.remove_meta("is_helicopter")
	check(not pilot._uses_helicopter_flight(target), "Stationary fixed-wing target is not a helicopter")
	# Exercise production tactic selection and final steering, including the
	# simple-pursuit path that used to bypass helicopter energy tactics entirely.
	target.set_meta("is_helicopter", true)
	pilot._reset_dogfight_pursuit()
	pilot.dogfight_situational_awareness_enabled = false
	pilot.current_state = AIPilot.State.DOGFIGHT
	pilot.altitude_agl = 400
	craft.position.y = 400
	target.position = Vector3(0, 140, 800)
	pilot._terrain_height_callable = func(_pos: Vector3): return 0.0
	pilot._state_dogfight(0.1)
	check(pilot._helicopter_attack_phase == AIPilot.HelicopterAttackPhase.PASS, "Production pursuit enters helicopter pass")
	check(pilot.nav_waypoint.y < 200, "Pass aims at low helicopter instead of cruise clearance")
	pilot._helicopter_attack_phase = AIPilot.HelicopterAttackPhase.EXTEND
	pilot._helicopter_extension_direction = Vector3.BACK
	pilot._helicopter_extension_origin = craft.position
	pilot._helicopter_extension_distance_m = 900
	target.position = craft.position + Vector3(1000, 0, -1000)
	pilot._state_dogfight(0.1)
	check(pilot.nav_waypoint.z > craft.position.z + 900, "Ballistic refinement cannot steal extension steering")
	check(not pilot._dogfight_burst_active, "Extension suppresses gunfire")
	# The 40 mm mount asset currently references a rocket pod, so exercise the
	# actual aircraft gun class with that profile rather than trusting its name.
	var heavy_gun := Autocannon.new()
	heavy_gun.gun_profile = preload("res://Weapons/Guns/Profiles/40mm_autocannon.tres")
	add_child(heavy_gun)
	check(heavy_gun.ammo_count == 60, "40 mm aircraft gun initializes 60 rounds")
	heavy_gun.ammo_count = 7
	heavy_gun._apply_gun_profile()
	check(heavy_gun.ammo_count == 7, "Applying profile preserves restored ammunition")
	print("HELICOPTER_ATTACK_PASS_SMOKETEST checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
