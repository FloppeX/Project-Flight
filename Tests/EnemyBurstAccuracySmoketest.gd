extends SceneTree

var probe: Script
var failures: Array[String] = []
var checks := 0
var gunner: Node3D
var host: Node3D
var rig: Turret
var target: Node3D
var test_team := 2

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func tick(seconds: float) -> void:
	for frame in ceili(seconds * 60.0): gunner._physics_process(1.0 / 60.0)

func restart() -> void:
	gunner._set_current_target(null)
	gunner._set_current_target(target)
	gunner._reaction_remaining_s = 0.0

func run() -> void:
	test_team = 1 if "--friendly" in OS.get_cmdline_user_args() else 2
	probe = load("res://Tests/Fixtures/VehicleGunnerProbe.gd")
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	host = probe.Host.new()
	host.team = test_team
	world.add_child(host)
	rig = probe.AlignedTurret.new()
	host.add_child(rig)
	gunner = probe.new()
	gunner.turret = rig
	gunner.performance_lod_enabled = false
	gunner.max_range = 2000.0
	host.add_child(gunner)
	gunner.set_physics_process(false)
	gunner.weapon_instance = Weapon.new()
	gunner.weapon_instance.ammo_count = 100000
	rig.add_child(gunner.weapon_instance)
	target = Node3D.new()
	world.add_child(target)
	target.position = Vector3(0, 0, 500)
	restart()
	var burst_errors: Array[float] = []
	var burst_offset := Vector3.ZERO
	var prior_state: int = gunner.fire_state
	for frame in 1800:
		gunner._physics_process(1.0 / 60.0)
		if gunner.fire_state == gunner.FireState.BURSTING:
			if prior_state != gunner.FireState.BURSTING:
				burst_offset = gunner._noise_offset
				burst_errors.append(burst_offset.length())
			else:
				check(gunner._noise_offset.is_equal_approx(burst_offset), "aim error changed inside a burst")
		prior_state = gunner.fire_state
	check(burst_errors.size() >= 6, "successive bursts were fired")
	for index in range(1, burst_errors.size()):
		check(burst_errors[index] <= burst_errors[index - 1] + 0.001, "later burst became less accurate")
	check(burst_errors[-1] < burst_errors[0] * 0.5, "sustained opportunity did not improve aim")
	check(burst_errors[-1] > 0.0 and is_equal_approx(burst_errors[-1], burst_errors[-2]), "skill floor not retained")
	print("ENEMY_BURST_ERRORS_500M ", burst_errors)

	# Losing a shot during either firing OR the ordinary burst pause must reset.
	for phase in [gunner.FireState.BURSTING, gunner.FireState.DELAYING]:
		for reason in ["sight", "range", "arc", "alignment", "host_plane", "ammo", "disabled"]:
			restart()
			tick(12.0)
			for frame in 400:
				if gunner.fire_state == phase: break
				tick(1.0 / 60.0)
			check(gunner._burst_aim_time_s > 5.0, "reset fixture never acquired aim")
			match reason:
				"sight": gunner.sight_clear = false
				"range": target.position.z = 3000.0
				"arc": rig.arc_available = false
				"alignment": rig.aim_angle = 90.0
				"host_plane": gunner.above_plane = false
				"ammo": gunner.weapon_instance.ammo_count = 0
				"disabled": host.defense_capability = 0.0
			tick(0.02)
			check(gunner._burst_aim_time_s == 0.0 and gunner.fire_state == gunner.FireState.IDLE, "%s did not reset phase %d" % [reason, phase])
			gunner.sight_clear = true
			target.position.z = 500.0
			rig.arc_available = true
			rig.aim_angle = 0.0
			gunner.above_plane = true
			gunner.weapon_instance.ammo_count = 100000
			host.defense_capability = 1.0
			tick(1.0 / 60.0)
			check(gunner.fire_state == gunner.FireState.BURSTING and is_equal_approx(gunner._burst_error_scale, gunner.burst_initial_error_multiplier), "%s reacquired with stale precision" % reason)

	tick(12.0)
	gunner._set_current_target(target)
	check(gunner._burst_aim_time_s > 5.0, "same target assignment lost precision")
	var other := Node3D.new()
	world.add_child(other)
	other.position.z = 500.0
	gunner._set_current_target(other)
	check(gunner._burst_aim_time_s == 0.0 and gunner.fire_state == gunner.FireState.IDLE, "target switch retained precision")
	other.free()
	tick(0.1)
	check(gunner.current_target == null and gunner._burst_aim_time_s == 0.0, "freed target retained aim")

	var floors: Array[float] = []
	for skill in [0.0, 0.35, 1.0]:
		gunner.aim_skill = skill
		restart()
		# Same miss bearing isolates skill from the random choice of miss side.
		gunner._burst_error_direction = Vector2.RIGHT
		gunner._burst_error_scale = gunner.burst_initial_error_multiplier
		tick(20.0)
		floors.append(gunner._noise_offset.length())
	check(floors[0] > floors[1] and floors[1] > floors[2] and floors[2] > 0, "crew skill does not control final accuracy")
	print("ENEMY_BURST_SKILL_FLOORS_500M ", floors)

	# Angular bias scales with distance and rotates with target bearing.
	restart()
	tick(0.1)
	var near_error: float = gunner._noise_offset.length()
	target.position.z = 1000.0
	tick(0.1)
	check(absf(gunner._noise_offset.length() / near_error - 2.0) < 0.001, "burst error does not scale with range")
	target.position = Vector3(1000, 0, 0)
	tick(0.1)
	var sight_direction: Vector3 = (gunner._get_target_aim_point(target) - gunner._get_aim_origin()).normalized()
	check(absf(gunner._noise_offset.dot(sight_direction)) < 0.001, "burst bias was not perpendicular to target bearing")
	var held_error: Vector3 = gunner._noise_offset
	gunner.aim_skill = 0.0
	tick(0.1)
	check(gunner._noise_offset.is_equal_approx(held_error), "skill/conditions changed the estimate mid-burst")
	host.team = 1
	check(gunner._uses_burst_aim(), "friendly turret did not receive shared accuracy model")
	host.team = test_team
	gunner.gunnery_error_enabled = false
	check(not gunner._uses_burst_aim(), "accuracy opt-out ignored")
	gunner.gunnery_error_enabled = true
	_check_faction_skill()
	_check_production_scenes()
	_check_projectiles(world)
	await _check_real_cover(world)
	print("SHARED_BURST_ACCURACY_%s team=%d checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", test_team, checks, failures])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_faction_skill() -> void:
	var faction_errors: Array[float] = []
	var settle_times: Array[float] = []
	target.position = Vector3(0, 0, 500)
	for faction in [1, 2]:
		host.team = faction
		gunner.aim_skill = -1.0
		restart()
		gunner._burst_error_direction = Vector2.RIGHT
		tick(0.1)
		faction_errors.append(gunner._noise_offset.length())
		settle_times.append(gunner._get_burst_settle_time_s())
		tick(20.0)
		faction_errors.append(gunner._noise_offset.length())
	check(faction_errors[0] < faction_errors[2] and faction_errors[1] < faction_errors[3], "friendly default skill did not improve initial and settled accuracy")
	check(settle_times[0] < settle_times[1], "friendly default skill did not correct faster")
	# Matching skill must produce matching behavior, regardless of allegiance.
	var equal_skill_errors: Array[float] = []
	for faction in [1, 2]:
		host.team = faction
		gunner.aim_skill = 0.5
		restart()
		gunner._burst_error_direction = Vector2.RIGHT
		tick(8.0)
		equal_skill_errors.append(gunner._noise_offset.length())
	check(is_equal_approx(equal_skill_errors[0], equal_skill_errors[1]), "same skill used different faction aiming paths")
	host.team = test_team
	gunner.aim_skill = -1.0
	print("FACTION_BURST_ERRORS friendly_initial/floor enemy_initial/floor=", faction_errors, " settle_times=", settle_times)

func _check_production_scenes() -> void:
	for path in ["Buildings/gun_emplacement.tscn", "GroundVehicle/vehicle_enemy_buggy.tscn", "GroundVehicle/vehicle_enemy_pickup.tscn", "GroundVehicle/vehicle_enemy_battle_bus.tscn", "GroundVehicle/vehicle_friendly_light.tscn", "LandCarrier/CarrierDefenseTurret.tscn", "LandCarrier/CarrierDefenseTurretAssembly.tscn", "Aircraft/Aircraft_4.tscn", "Aircraft/Aircraft_9.tscn"]:
		var actor: Node = load("res://" + path).instantiate()
		var count := 0
		var nodes: Array[Node] = [actor]
		nodes.append_array(actor.find_children("*", "Node3D", true, false))
		for node in nodes:
			if node.has_method("_uses_burst_aim"):
				count += 1
				node.host_actor = actor as Node3D
				check(node._uses_burst_aim(), path + " does not use burst accuracy")
		check(count > 0, path + " has no shared turret")
		actor.free()

func _check_projectiles(world: Node3D) -> void:
	var weapon := BulletWeapon.new()
	world.add_child(weapon)
	weapon.spread_angle = 8.0 # Deliberately large to expose accidental per-round scatter.
	weapon.visible_round_multiplier = 2
	weapon.use_controller_burst_error = true
	var transform_value := Transform3D(Basis(Vector3.UP, 0.3), Vector3(0, 100, 0))
	for shot in 8:
		weapon._spawn_bullet(transform_value, weapon)
		var bullet := weapon.last_fired_projectile as RigidBody3D
		check(bullet != null and bullet.linear_velocity.normalized().is_equal_approx(transform_value.basis.z), "physical burst round acquired fresh random spread")
		if bullet != null: bullet.queue_free()
	weapon._queue_virtual_rounds(transform_value, weapon, null, 0.1)
	# A pending filler belongs to its original burst, even after stop_firing.
	weapon.use_controller_burst_error = false
	weapon._process(0.2)
	var manager: Node = world.get_node("MachineGunVirtualTracers")
	var tracers: Array = manager.get("_tracers")
	check(tracers.size() == 1 and (tracers[0].velocity as Vector3).normalized().is_equal_approx(transform_value.basis.z), "virtual filler lost the physical round's burst policy")
	weapon._spawn_bullet(transform_value, weapon)
	var ordinary := weapon.last_fired_projectile as RigidBody3D
	check(ordinary != null and not ordinary.linear_velocity.normalized().is_equal_approx(transform_value.basis.z), "ordinary weapon spread was suppressed")
	if ordinary != null: ordinary.queue_free()
	weapon.queue_free()

func _check_real_cover(world: Node3D) -> void:
	var real_gunner: Node3D = load("res://Weapons/Turrets/turret_controller.gd").new()
	real_gunner.turret = rig
	real_gunner.performance_lod_enabled = false
	real_gunner.max_range = 2000.0
	real_gunner.defense_coordinator = world # Retain the assigned test target.
	host.add_child(real_gunner)
	real_gunner.set_physics_process(false)
	real_gunner.weapon_instance = gunner.weapon_instance
	target.position = Vector3(0, 0, 500)
	real_gunner._set_current_target(target)
	real_gunner._reaction_remaining_s = 0.0
	real_gunner._burst_error_direction = Vector2.RIGHT
	real_gunner._physics_process(0.1)
	check(real_gunner.fire_state == real_gunner.FireState.BURSTING, "real LOS never allowed a clear shot")
	var cover := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 20, 2)
	shape.shape = box
	cover.add_child(shape)
	cover.position = Vector3(0, 0, 250)
	world.add_child(cover)
	await physics_frame
	await physics_frame
	# The large sideways miss passes this narrow wall; the real target does not.
	for frame in 60: real_gunner._physics_process(1.0 / 60.0)
	check(real_gunner.fire_state == real_gunner.FireState.IDLE and real_gunner._burst_aim_time_s == 0.0, "biased aim ray bypassed actual target cover")
	cover.free()
	await physics_frame
	await physics_frame
	for frame in 60: real_gunner._physics_process(1.0 / 60.0)
	check(real_gunner.fire_state == real_gunner.FireState.BURSTING and is_equal_approx(real_gunner._burst_error_scale, real_gunner.burst_initial_error_multiplier), "real LOS reacquisition retained stale correction")
	real_gunner.free()
