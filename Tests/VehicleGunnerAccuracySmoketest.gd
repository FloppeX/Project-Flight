extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var probe: Script = load("res://Tests/Fixtures/VehicleGunnerProbe.gd")
	var host: Node3D = probe.Host.new()
	world.add_child(host)
	var target := Node3D.new()
	world.add_child(target)
	target.position.z = 500.0
	var rig: Node3D = probe.AlignedTurret.new()
	host.add_child(rig)
	var gunner: Node3D = probe.new()
	gunner.turret = rig
	gunner.performance_lod_enabled = false
	gunner.max_range = 2500.0
	host.add_child(gunner)
	gunner.set_physics_process(false)
	gunner.host_actor = host
	gunner.weapon_instance = Weapon.new()
	gunner.weapon_instance.ammo_count = 10000
	rig.add_child(gunner.weapon_instance)
	var results: Dictionary = {}
	for role in ["ground_vehicles", "carrier", "aircraft", "emplacement"]:
		host.add_to_group(role)
		var errors: Array[float] = []
		for faction in [1, 2]:
			host.team = faction
			gunner.team = 3 - faction # Real host allegiance must win.
			gunner._set_current_target(null)
			gunner._set_current_target(target)
			var expected_skill := 0.8 if faction == 1 else 0.35
			check(is_equal_approx(gunner._get_effective_aim_skill(target), expected_skill), "%s uses host faction default" % role)
			check(is_equal_approx(gunner._reaction_remaining_s, lerpf(1.0, 0.4, expected_skill)), "%s shared reaction formula" % role)
			gunner._physics_process(0.2)
			check(gunner.fire_state == gunner.FireState.IDLE, "%s no instantaneous first shot" % role)
			var offset: Vector3 = gunner._noise_offset
			gunner._physics_process(0.2)
			check(gunner._noise_offset == offset, "%s coherent aim estimate" % role)
			for frame in 30: gunner._physics_process(1.0 / 60.0)
			check(gunner.fire_state == gunner.FireState.BURSTING, "%s fires after reaction" % role)
			gunner._set_current_target(target)
			check(gunner._reaction_remaining_s == 0.0, "same target does not reset delay")
			var fraction := tan(deg_to_rad(lerpf(2.1, 0.35, expected_skill)))
			for distance in [50.0, 500.0, 1000.0, 2000.0]:
				target.position.z = distance
				var actual_range: float = gunner._get_aim_origin().distance_to(gunner._get_target_aim_point(target))
				check(is_equal_approx(gunner._get_aim_error_spread_m(target), actual_range * fraction), "%s error proportional at %.0fm" % [role, distance])
			target.position.z = 500.0
			errors.append(gunner._get_aim_error_spread_m(target))
		check(errors[0] < errors[1], "%s friendly crew more accurate" % role)
		results[role] = errors
		host.remove_from_group(role)
	host.team = 1
	gunner.aim_skill = 0.25
	check(is_equal_approx(gunner._get_effective_aim_skill(target), 0.25), "explicit crew skill override honored")
	gunner.aim_skill = -1.0
	target.add_to_group("aircraft")
	gunner.air_target_extra_spread_m = 10.0
	var near_error: float = gunner._get_aim_error_spread_m(target)
	target.position.z = 1000.0
	check(absf(gunner._get_aim_error_spread_m(target) / near_error - 2.0) < 0.001, "anti-air extra error scales")
	gunner._set_current_target(target)
	target.free()
	gunner._noise_timer = 0.0
	gunner._physics_process(0.1)
	check(gunner.current_target == null and gunner.fire_state == gunner.FireState.IDLE, "destroyed target safe")
	var controllers := 0
	for path in ["GroundVehicle/GroundVehicle.tscn", "GroundVehicle/vehicle_friendly_light.tscn", "GroundVehicle/vehicle_enemy_buggy.tscn", "GroundVehicle/vehicle_enemy_pickup.tscn", "GroundVehicle/vehicle_enemy_battle_bus.tscn", "LandCarrier/CarrierDefenseTurret.tscn", "LandCarrier/CarrierDefenseTurretAssembly.tscn", "Aircraft/Aircraft_4.tscn", "Aircraft/Aircraft_9.tscn", "Enemies/EnemyAircraft.tscn"]:
		var packed: PackedScene = load("res://" + path)
		var state := packed.get_state()
		for node in state.get_node_count():
			var is_controller := false
			var skill := -1.0
			for property in state.get_node_property_count(node):
				var property_name := state.get_node_property_name(node, property)
				var value: Variant = state.get_node_property_value(node, property)
				if property_name == &"script" and value is Script and value.resource_path == "res://Weapons/Turrets/turret_controller.gd": is_controller = true
				if property_name == &"aim_skill": skill = float(value)
			if is_controller:
				controllers += 1
				check(skill < 0.0, "%s turret uses shared faction default" % path)
	check(controllers >= 11, "production turret configurations covered")
	var legacy: Node = load("res://Enemies/EnemyAircraft.gd").new()
	var managed := Node3D.new()
	managed.name = "TurretController"
	legacy.add_child(managed)
	legacy.target_aircraft = host
	legacy._process(0.1)
	check(legacy.fire_timer == 0.0, "legacy turret actor cannot run second gun outside shared model")
	legacy.remove_child(managed)
	managed.free()
	legacy._process(0.1)
	check(is_equal_approx(legacy.fire_timer, 0.1), "turretless legacy fallback retained")
	legacy.free()
	print("SHARED_TURRET_GUNNERY_%s failures=%s errors_500m_friendly_enemy=%s controllers=%d" % ["PASS" if failures.is_empty() else "FAIL", failures, results, controllers])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
