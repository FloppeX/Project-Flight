extends SceneTree

const GUNS := preload("res://Weapons/Turrets/TurretGunCatalog.gd")
var failures: Array[String] = []
var cases := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	for caliber in [10, 15, 20, 25, 40]:
		var controller = load("res://LandCarrier/CarrierDefenseTurretAssembly.tscn").instantiate()
		controller.process_mode = Node.PROCESS_MODE_DISABLED
		controller.gun_profile_override = GUNS.get_profile(caliber)
		world.add_child(controller)
		var turret = controller.turret
		var weapon = controller.weapon_instance
		controller.transform = Transform3D(Basis.from_euler(Vector3(0.3, 1.2, -0.2)).scaled(Vector3.ONE * 1.3), Vector3(10, 100, 20))
		var mount_rest: Transform3D = turret.barrel_mount.transform
		var barrel_rest: Vector3 = turret.mounted_barrel.global_position
		var forward: Vector3 = turret.barrel_mount.global_basis.z.normalized()
		_expect(weapon.fire(), "turret %d fires" % caliber)
		_expect(turret.mounted_barrel.global_position.distance_to(barrel_rest - forward * caliber * 0.01) < 0.0001, "turret %d calibrated travel" % caliber)
		_expect(turret.barrel_mount.transform.is_equal_approx(mount_rest), "turret aiming mount stays fixed")
		_check_cycle(turret._barrel_recoil, caliber, "turret %d" % caliber)
		# Changing the mounted caliber mid-recoil must restore/remove the old rig.
		turret.kick_barrel_recoil(caliber, 0.1)
		turret.configure_weapon_barrel(weapon)
		_expect(turret._barrel_recoil == null, "weapon swap clears old recoil")
		controller.free()
		var path := "res://Weapons/Guns/Hardpoint/%dmm_%s_hardpoint.tscn" % [caliber, "machine_gun" if caliber < 20 else "autocannon"]
		# The nominal 40mm hardpoint scene currently contains a rocket pod.
		# Exercise the actual 40mm gun without changing that authored loadout.
		if caliber == 40:
			path = "res://Weapons/Turrets/40mm_autocannon_weapon.tscn"
		var gun = load(path).instantiate()
		gun.process_mode = Node.PROCESS_MODE_DISABLED
		world.add_child(gun)
		gun.transform = Transform3D(Basis.from_euler(Vector3(-0.4, 1.0, 0.2)), Vector3(-10, 100, 20))
		var attachment: Node3D = gun.get_node("AttachmentPoint")
		var attachment_rest := attachment.transform
		_expect(gun._barrel_recoil != null, "hardpoint %d has barrel" % caliber)
		_expect(gun.fire(), "hardpoint %d fires" % caliber)
		_check_cycle(gun._barrel_recoil, caliber, "hardpoint %d" % caliber)
		_expect(attachment.transform.is_equal_approx(attachment_rest), "hardpoint attachment stays fixed")
		if gun is Autocannon:
			gun.fire_timer = 1.0
			_expect(not gun.fire() and not gun._barrel_recoil.is_processing(), "cooldown does not kick barrel")
		gun.free()
	# Legacy exposed guns and helicopter side guns use the same helper.
	for scene in ["vehicle_lmg_turret", "vehicle_heavy_gun_turret", "helicopter_side_gun_turret"]:
		var turret = load("res://Weapons/Turrets/%s.tscn" % scene).instantiate()
		turret.process_mode = Node.PROCESS_MODE_DISABLED
		world.add_child(turret)
		var mount_rest: Transform3D = turret.barrel_mount.transform
		turret.kick_barrel_recoil(15, 0.1)
		_expect(turret._barrel_recoil.targets.size() >= 2, scene + ": visual and muzzle targets")
		_check_cycle(turret._barrel_recoil, 15, scene)
		_expect(turret.barrel_mount.transform.is_equal_approx(mount_rest), scene + ": fixed mount")
		turret.free()
	if "--render" in OS.get_cmdline_user_args():
		await _render(world)
	print("BARREL_RECOIL_SMOKETEST " + JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "cases": cases, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _check_cycle(recoil: Node, caliber: int, label: String) -> void:
	if recoil == null:
		_expect(false, label + ": missing recoil")
		return
	cases += 1
	var forward: Vector3 = recoil.frame.global_basis.z.normalized()
	for target in recoil.targets:
		var rest_world: Vector3 = target.node.get_parent_node_3d().to_global(target.rest)
		_expect(target.node.global_position.distance_to(rest_world - forward * caliber * 0.01) < 0.0001, label + ": mesh/muzzle displacement")
	# Many overlapping impulses remain bounded instead of accumulating drift.
	for shot in 20:
		recoil._process(0.015)
		recoil.kick(caliber, 0.1)
		for target in recoil.targets:
			var rest_world: Vector3 = target.node.get_parent_node_3d().to_global(target.rest)
			_expect(target.node.global_position.distance_to(rest_world - forward * caliber * 0.01) < 0.0001, label + ": no accumulated offset")
	_expect(is_equal_approx(recoil.distance_m, caliber * 0.01), label + ": bounded burst")
	recoil._process(1.0)
	for target in recoil.targets:
		_expect(target.node.position.is_equal_approx(target.rest), label + ": exact recovery")
	_expect(not recoil.is_processing(), label + ": idle processing off")

func _render(world: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("26323e")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	var controller = load("res://LandCarrier/CarrierDefenseTurretAssembly.tscn").instantiate()
	controller.process_mode = Node.PROCESS_MODE_DISABLED
	controller.gun_profile_override = GUNS.get_profile(25)
	world.add_child(controller)
	var gun = load("res://Weapons/Guns/Hardpoint/25mm_autocannon_hardpoint.tscn").instantiate()
	gun.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(gun)
	for subject in ["turret", "hardpoint"]:
		controller.visible = subject == "turret"
		gun.visible = subject == "hardpoint"
		if subject == "turret":
			camera.position = Vector3(5, 3.2, 3.5)
			camera.look_at(Vector3(0, 1.0, 0.8))
		else:
			camera.position = Vector3(1.5, 0.65, 1.4)
			camera.look_at(Vector3(0, 0, 0.5))
		for phase in ["rest", "recoil", "returned"]:
			if phase == "recoil":
				if subject == "turret": controller.turret.kick_barrel_recoil(25, 0.2)
				else: gun._kick_barrel_recoil()
			if phase == "returned":
				if subject == "turret": controller.turret._barrel_recoil._process(1.0)
				else: gun._barrel_recoil._process(1.0)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://barrel_%s_%s.png" % [subject, phase])

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
