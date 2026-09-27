extends Node3D
var failures: Array[String] = []
class Terrain extends Node3D:
	var ridge := false
	func get_height(point: Vector3) -> float:
		return 400.0 if ridge and point.z > 200 and point.z < 400 else 0.0
class Target extends RigidBody3D:
	var team := 1
	func get_team() -> int: return team
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func _ready() -> void: run.call_deferred()
func run() -> void:
	EnemyBaseManager.disable_for_heli_test()
	EnemyOpsManager.set_physics_process(false)
	FloatingOrigin.enabled = false
	var terrain := Terrain.new()
	add_child(terrain)
	TerrainReference.terrain_node = terrain
	var craft := preload("res://Aircraft/Aircraft_13.tscn").instantiate() as RigidBody3D
	craft.position = Vector3(0, 140, 0)
	craft.freeze = true
	add_child(craft)
	var section = preload("res://Enemies/EnemyOutpostHelicopterFlight.gd").new()
	add_child(section)
	section.heading = Vector3.BACK
	section._patrol_waypoints.assign([Vector3(0, 140, 3000), Vector3(2000, 140, 0)])
	section._configure_materialized_enemy_aircraft(craft, "rockets", 0)
	var pilot: HelicopterPilot = craft.get_node("HelicopterPilot")
	pilot.set_physics_process(false)
	pilot.change_state(HelicopterPilot.State.LOW_LEVEL_TRANSIT)
	var target := Target.new()
	target.freeze = true
	target.position = Vector3(0, 140, 600)
	target.rotation.y = PI
	target.set_meta("is_helicopter", true)
	add_child(target)
	target.add_to_group("ai_aircraft")
	var awareness = pilot._air_awareness
	awareness.update_observations(0.2, craft, pilot._get_ground_height_at_position)
	check(not awareness.observation(target).is_empty(), "visible hostile aircraft is observed")
	check(pilot._get_combat_target_candidates().has(target), "outpost patrol may engage observed helicopter")
	var mixed := [{"kind": pilot.COMBAT_WEAPON_ROCKET}, {"kind": pilot.COMBAT_WEAPON_GUN}]
	check(pilot._select_attack_weapon(target, mixed).kind == pilot.COMBAT_WEAPON_GUN, "guns preferred against helicopters")
	check(pilot._select_attack_weapon(target, [mixed[0]]).kind == pilot.COMBAT_WEAPON_ROCKET, "rocket-only helicopter can fight")
	var route := pilot.destination
	pilot._atk_scan_timer_s = 0
	pilot._atk_select(0.2)
	check(pilot._atk_target == target, "real rocket-equipped pilot begins helicopter attack")
	check(pilot._atk_state != pilot.AtkState.POPUP, "airborne target does not use ground popup")
	var observed_before: Vector3 = awareness.observation(target).position
	awareness.shift_origin(Vector3(100, 0, 0))
	check(awareness.observation(target).position == observed_before - Vector3(100, 0, 0), "origin shifts translate remembered air contacts")
	awareness.shift_origin(Vector3(-100, 0, 0))
	terrain.ridge = true
	awareness.update_observations(0.2, craft, pilot._get_ground_height_at_position)
	check(awareness.observation(target).is_empty(), "terrain conceals air contacts")
	pilot._update_atk(0.2, 30)
	check(pilot._atk_target == null and pilot.destination == route, "lost sight ends chase and restores patrol destination")
	terrain.ridge = false
	awareness.update_observations(0.2, craft, pilot._get_ground_height_at_position)
	var survivor := Node3D.new()
	survivor.position = Vector3(0, 0, 2500)
	add_child(survivor)
	var pod: RocketPod = craft.find_children("*", "RocketPod", true, false)[0]
	pod._burst_remaining = 4
	pilot.command_rescue(survivor)
	check(not pod.is_burst_in_progress(), "rescue cancels unlaunched rounds from previous attack")
	pilot.combat_outbound_only = false
	check(not pilot._can_start_combat_attack() and not pilot._can_engage_helicopter(target), "rescue overrides permissive combat settings")
	var rescue_goal := pilot.destination
	pilot._update_outpost_patrol_route()
	check(pilot.destination == rescue_goal, "outpost route cannot replace rescue destination")
	var dodged := false
	for i in 5:
		awareness.update_observations(0.2, craft, pilot._get_ground_height_at_position)
		dodged = pilot._update_air_defense(0.2, 30) or dodged
	check(dodged and awareness.episodes > 0, "rescue evades observed firing-line threat")
	check(pilot.destination == rescue_goal and pilot._rescue_target == survivor and pilot.mission_phase == pilot.MissionPhase.RESCUE, "defense preserves rescue order and destination")
	check(not pilot._update_combat_attack(0.2, 30) and pilot._atk_target == null, "rescue never starts an attack")
	target.set_meta("is_helicopter", false)
	awareness.break_s = 0
	awareness.cooldown_s = 0
	awareness.evidence_s = 0
	for i in 3:
		awareness.update_observations(0.2, craft, pilot._get_ground_height_at_position)
		pilot._update_air_defense(0.2, 30)
	check(awareness.episodes >= 2 and not pilot._is_valid_combat_target(target), "fixed-wing threats trigger evasion without becoming attack targets")
	target.team = 2
	awareness.update_observations(0.2, craft, pilot._get_ground_height_at_position)
	check(awareness.observation(target).is_empty(), "friendly aircraft are not threats")
	target.team = 1
	target.position.z = -600
	awareness.contacts.clear()
	awareness.update_observations(0.2, craft, pilot._get_ground_height_at_position)
	check(awareness.observation(target).is_empty(), "unknown aircraft behind canopy remain unseen")
	awareness.break_s = 0
	awareness.cooldown_s = 0
	awareness.report_damage(5, &"projectile")
	check(awareness.defensive_waypoint(0.5, craft, rescue_goal, pilot._get_ground_height_at_position, 30) != Vector3.INF, "projectile damage permits defensive break without locating attacker")
	pilot._rescue_target = null
	pilot.mission_phase = pilot.MissionPhase.OUTBOUND
	target.set_meta("is_helicopter", true)
	pilot._commanded_attack_target = survivor
	check(not pilot._mission_allows_helicopter_attack(target), "explicit ground order prevents opportunistic air chase")
	pilot._commanded_attack_target = null
	pilot._passengers = 1
	check(not pilot._mission_allows_helicopter_attack(target), "passenger carriage remains defensive")
	print("HELICOPTER_AIR_BEHAVIOR_", "PASS" if failures.is_empty() else "FAIL", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
