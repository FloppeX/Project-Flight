extends Node3D

## Real fixed-wing physics and finite ammunition against a durable helicopter
## proxy. The proxy isolates pass geometry from the helicopter's defensive AI.
class Target:
	extends RigidBody3D
	var current_health := 1000.0
	var damage_total := 0.0
	var hits := 0
	func get_team() -> int: return 2
	func take_damage(amount: float) -> void:
		damage_total += amount
		hits += 1

var elapsed := 0.0
var shots := 0
var speed := 0.0
var target_altitude := 300.0
var commanded := false
var output := "res://logs/helicopter_attack_pass.json"
var craft: RigidBody3D
var pilot: AIPilot
var target: Target
var result := {"transitions": [], "trace": [], "min_speed": INF, "min_altitude": INF}

func _ready() -> void:
	get_node("/root/FloatingOrigin").set("enabled", false)
	for manager_name in ["FlightDirector", "AirOpsManager", "EnemyOpsManager", "GroundOpsManager", "OperationsCoordinator"]:
		var manager := get_node_or_null("/root/" + manager_name)
		if manager: manager.process_mode = Node.PROCESS_MODE_DISABLED
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--target-speed="): speed = float(arg.get_slice("=", 1))
		elif arg.begins_with("--target-altitude="): target_altitude = float(arg.get_slice("=", 1))
		elif arg.begins_with("--output="): output = arg.get_slice("=", 1)
		elif arg == "--commanded": commanded = true
	seed(20260929)
	call_deferred("run")

func run() -> void:
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40000, 50, 40000)
	ground_shape.shape = box
	ground.add_child(ground_shape)
	ground.position.y = -25
	add_child(ground)
	target = Target.new()
	target.gravity_scale = 0.0
	target.linear_damp = 0.0
	target.mass = 3000.0
	target.lock_rotation = true
	target.can_sleep = false
	target.position = Vector3(0, target_altitude, 0)
	target.set_meta("is_helicopter", true)
	var collider := CollisionShape3D.new()
	var target_box := BoxShape3D.new()
	target_box.size = Vector3(12, 4, 12)
	collider.shape = target_box
	target.add_child(collider)
	add_child(target)
	target.add_to_group("aircraft")
	target.add_to_group("enemies")
	target.linear_velocity = Vector3(speed, 0, 0)
	craft = preload("res://Aircraft/Aircraft_5.tscn").instantiate()
	craft.position = Vector3(0, target_altitude + 250, -1800)
	add_child(craft)
	craft.set("team", 1)
	craft.set_meta("carrier_transport_mode", false)
	craft.set_meta("controls_disabled", false)
	craft.linear_velocity = Vector3(0, 0, 110)
	await get_tree().process_frame
	await get_tree().process_frame
	craft.get_node("AIToggle").enable_ai()
	pilot = craft.get_node("AIPilot")
	pilot.skill = 2
	pilot.apply_skill_preset()
	pilot.debug_enabled = false
	pilot.verbose_debug_enabled = false
	pilot.ground_attack_enabled = false
	pilot.dogfight_enabled = true
	pilot.land_after_launch = false
	pilot._land_after_climb = false
	pilot.rtb_fuel_threshold = 0.0
	pilot.rtb_health_threshold = 0.0
	pilot.engagement_radius_from_carrier_m = 0.0
	pilot.disengage_radius_from_carrier_m = 0.0
	pilot._terrain_height_callable = func(_pos: Vector3): return 0.0
	craft.find_child("ControlLandingGear", true, false).stow_gear()
	for node in craft.find_children("*", "Autocannon", true, false):
		node.set_tuning_context(_shot, Callable(), 1, target)
	pilot.known_enemies.assign([target])
	if commanded:
		pilot.assign_air_task(AirTask.intercept_target(target))
	else:
		pilot.set_target(target)
	var previous_phase := -1
	var tick := 0
	while elapsed < 180.0 and is_instance_valid(craft) and craft.current_health > 0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		target.linear_velocity = Vector3(speed, 0, 0)
		if commanded and tick % 300 == 0:
			pilot.receive_intercept_contact_report(target, target.position, target.linear_velocity)
		if not is_instance_valid(craft): break
		var phase: int = pilot._helicopter_attack_phase
		result.min_speed = minf(result.min_speed, craft.linear_velocity.length())
		result.min_altitude = minf(result.min_altitude, craft.position.y)
		var sample := {"t": elapsed, "phase": phase, "state": AIPilot.State.keys()[pilot.current_state],
			"range": craft.position.distance_to(target.position), "speed": craft.linear_velocity.length(),
			"altitude": craft.position.y, "shots": shots, "hits": target.hits,
			"nose_dot": craft.global_basis.z.dot(craft.position.direction_to(target.position)),
			"contact_velocity": str(pilot._dogfight_target_observation(target).get("velocity", Vector3.INF)),
			"fire_block": pilot._dogfight_fire_block_reason,
			"observed_range": pilot._dogfight_fire_range_m, "miss": pilot._dogfight_fire_miss_radius_m,
			"precision": pilot._dogfight_precise_aim_blend, "bank": rad_to_deg(atan2(craft.global_basis.x.y, craft.global_basis.y.y)),
			"ext_traveled": (craft.position - pilot._helicopter_extension_origin).dot(pilot._helicopter_extension_direction)}
		if phase != previous_phase:
			result.transitions.append(sample)
			previous_phase = phase
		if tick % 120 == 0: result.trace.append(sample)
		tick += 1
	result.shots = shots
	result.hits = target.hits
	result.damage = target.damage_total
	result.alive = is_instance_valid(craft) and craft.current_health > 0
	result.target_speed = speed
	result.target_altitude = target_altitude
	result.commanded = commanded
	var pass_count := 0
	var firing_passes := 0
	var shots_before_pass := 0
	for entry in result.transitions:
		if entry.phase == AIPilot.HelicopterAttackPhase.PASS: pass_count += 1
		if entry.phase == AIPilot.HelicopterAttackPhase.EXTEND:
			if entry.shots > shots_before_pass: firing_passes += 1
			shots_before_pass = entry.shots
	result.firing_passes = firing_passes
	var ok: bool = result.alive and shots > 0 and target.hits > 0 and pass_count >= 2 \
		and (not commanded or firing_passes >= 2)
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("HELICOPTER_ATTACK_PASS_", "PASS" if ok else "FAIL", " shots=", shots, " hits=", target.hits, " passes=", pass_count, " firing_passes=", firing_passes, " alive=", result.alive)
	get_tree().quit(0 if ok else 1)

func _shot(_id: int, _projectile: Node = null) -> void:
	shots += 1
