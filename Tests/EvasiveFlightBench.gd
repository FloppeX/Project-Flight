extends "res://Scenario/GunsOnlyDuel.gd"
var evasion_off := false
var side_entry := false
var occlusion := false
var cone_time_s := 0.0
var defense_min_speed := INF
var defense_min_altitude := INF
var defense_start_energy := NAN
var defense_min_energy := INF
var defense_first_break := -1.0
var defense_first_hit := -1.0
var occluded_samples := 0
var occluded_visible_samples := 0
var _screen: StaticBody3D
var _bench_written := false
var _defense_trace := []
var _trace_tick := 0
func _ready() -> void:
	_duel_tail_entry = true
	super._ready()
	merge_aircraft_scene = preload("res://Aircraft/Aircraft_3.tscn")
	merge_aircraft_scene_b = preload("res://Tests/Fixtures/EvasiveDefender.tscn")
	round_max_duration_s = 90.0
	for arg in OS.get_cmdline_user_args():
		evasion_off = evasion_off or arg == "--evasion-off"
		side_entry = side_entry or arg == "--evasion-side"
		occlusion = occlusion or arg == "--evasion-occlusion"
	for path in ["res://Tests/EvasiveFlightBench.gd", "res://Tests/Fixtures/EvasiveDefender.tscn",
		"res://Tests/Fixtures/EvasiveDefender.gd", "res://Tests/Fixtures/EvasiveDefenderPilot.gd"]:
		_input_hashes[path] = FileAccess.get_sha256(path)
	_screen = StaticBody3D.new()
	_screen.collision_layer = 2 # Sensor occluder, not an aircraft/ground obstacle.
	_screen.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 300, 5)
	collider.shape = box
	_screen.add_child(collider)
	_screen.position = Vector3(100000, 10000, 0)
	add_child(_screen)
func _spawn_merge_test() -> void:
	await super._spawn_merge_test()
	_verify_loadouts() # Attach hit/shot accounting before the first burst.
func _spawn_ai_fighter(scene: PackedScene, fighter_name: String, team: int, pos: Vector3,
	heading: float, speed_mps: float, skill_override: int = -1) -> RigidBody3D:
	var craft := super._spawn_ai_fighter(scene, fighter_name, team, pos, heading, 85.0 if team == 2 else speed_mps, skill_override)
	var pilot: AIPilot = craft.get_node("AIPilot")
	if team == 2:
		pilot.dogfight_evasion_enabled = not evasion_off
	else:
		pilot.dogfight_evasion_enabled = false
		if side_entry:
			craft.position = Vector3(-350, 1000, -300)
			craft.rotation.y = deg_to_rad(40)
			craft.linear_velocity = craft.global_basis.z * 100.0
	# This bench deliberately toggles evasion after the production spawn. Declare
	# that one override so the parent still detects unintended skill/gain drift.
	_expected_pilot_settings[fighter_name]["dogfight_evasion_enabled"] = pilot.dogfight_evasion_enabled
	return craft
func _physics_process(delta: float) -> void:
	if _summary_written:
		return
	if _combatants.size() == 2:
		var attacker: Variant = _combatants[0].node
		var defender: Variant = _combatants[1].node
		if is_instance_valid(attacker) and is_instance_valid(defender):
			var pilot: AIPilot = defender.get_node("AIPilot")
			_trace_tick += 1
			if _trace_tick % 6 == 0:
				_defense_trace.append({"t": _elapsed_s, "speed": defender.linear_velocity.length(),
					"bank": rad_to_deg(atan2(defender.global_basis.x.y, defender.global_basis.y.y)),
					"altitude": defender.global_position.y, "phase": pilot._evasive_flight.phase,
					"inputs": [pilot.roll_input, pilot.pitch_input, pilot.yaw_input, pilot.throttle_input]})
			var rel: Vector3 = defender.global_position - attacker.global_position
			if rel.length() < 900 and rel.normalized().dot(attacker.global_basis.z) > cos(deg_to_rad(2.0)):
				cone_time_s += delta
			defense_min_speed = minf(defense_min_speed, defender.linear_velocity.length())
			defense_min_altitude = minf(defense_min_altitude, defender.global_position.y)
			var energy: float = defender.global_position.y + defender.linear_velocity.length_squared() / 19.6
			if is_nan(defense_start_energy):
				defense_start_energy = energy
			defense_min_energy = minf(defense_min_energy, energy)
			if defender.received_projectile_hits > 0 and defense_first_hit < 0:
				defense_first_hit = _elapsed_s
			if pilot._evasive_flight.phase != "idle" and defense_first_break < 0:
				defense_first_break = _elapsed_s
			var screened := occlusion and _elapsed_s >= 15.0 and _elapsed_s < 20.0
			if screened:
				_screen.global_position = attacker.global_position.lerp(defender.global_position, 0.5)
				_screen.look_at(defender.global_position)
				occluded_samples += 1
				var observed: Dictionary = attacker.get_node("AIPilot")._dogfight_target_observation(defender)
				occluded_visible_samples += int(not observed.is_empty() and bool(observed.visible))
			else:
				_screen.position = Vector3(100000, 10000, 0)
	super._physics_process(delta)
	if _summary_written and not _bench_written:
		_bench_written = true
		var defender: Variant = _combatants[1].node
		var pilot: AIPilot = defender.get_node("AIPilot") if is_instance_valid(defender) else null
		var result := {"status": "COMPLETE", "evasion_enabled": not evasion_off, "side": side_entry,
			"duration_s": _elapsed_s, "in_attacker_cone_s": cone_time_s, "min_speed_mps": defense_min_speed,
			"min_altitude_m": defense_min_altitude, "energy_loss_m": defense_start_energy - defense_min_energy,
			"first_hit_s": defense_first_hit, "first_break_s": defense_first_break,
			"occluded_samples": occluded_samples, "occluded_visible_samples": occluded_visible_samples,
			"episodes": pilot._evasive_flight.episodes if pilot != null else -1,
			"defending_s": pilot._evasive_flight.active_time_s if pilot != null else -1,
			"projectile_hits_received": defender.received_projectile_hits if is_instance_valid(defender) else -1,
			"defender_alive": is_instance_valid(defender) and defender.current_health > 0,
			"min_separation_m": _shot_stats.Merge_A.min_separation_m, "trace": _defense_trace}
		var file := FileAccess.open(duel_log_path + ".defense.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t"))
