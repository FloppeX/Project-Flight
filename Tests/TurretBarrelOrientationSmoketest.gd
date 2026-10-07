extends SceneTree

var failures: Array[String] = []
var cases := 0
var worst_error := 0.0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	root.get_node("SaveGameManager").set("autosave_enabled", false)
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	create_timer(90.0).timeout.connect(func(): quit(2))
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	for model in ["vehicle_enemy_buggy", "vehicle_enemy_pickup", "vehicle_enemy_battle_bus", "vehicle_friendly_light", "vehicle_friendly_2"]:
		_check_vehicle(world, "res://GroundVehicle/%s.tscn" % model)
	_check_vehicle(world, "res://Aircraft/Aircraft_4.tscn")
	_check_vehicle(world, "res://Aircraft/Aircraft_9.tscn")
	# Every modular caliber shares the carrier/APC rig, but has a different muzzle.
	var controller = load("res://LandCarrier/CarrierDefenseTurretAssembly.tscn").instantiate()
	controller.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(controller)
	for caliber in [10, 15, 20, 25, 40]:
		var name_ := "heavy_gun_weapon" if caliber == 25 else ("bullet_weapon" if caliber == 10 else ("40mm_autocannon_weapon" if caliber == 40 else "bullet_weapon_%dmm" % caliber))
		controller.mount_weapon(load("res://Weapons/Turrets/%s.tscn" % name_))
		_check_controller(controller, "carrier_%d" % caliber)
	controller.free()
	var standalone = load("res://Weapons/Turrets/bullet_weapon.tscn").instantiate()
	world.add_child(standalone)
	var locator := Marker3D.new()
	locator.name = "BulletSpawnPoint"
	locator.position = Vector3(0, 0, 4)
	standalone.add_child(locator)
	check(standalone._get_bullet_spawn_transform(Transform3D.IDENTITY).is_equal_approx(locator.global_transform), "non-turret weapon lost its muzzle locator")
	standalone.free()
	await process_frame
	print("BARREL_ORIENTATION_RESULT cases=%d max_error_deg=%.4f failures=%s" % [cases, worst_error, failures])
	if "--render" in OS.get_cmdline_user_args(): await _render(world)
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("TURRET_BARREL_ORIENTATION_SMOKETEST_OK")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check_vehicle(world: Node3D, path: String) -> void:
	# Keep actual controller/rig transforms without running vehicle navigation,
	# flight or campaign setup. No authored scene is changed by this extraction.
	var source = load(path).instantiate()
	var controllers: Array[Node] = []
	for node in source.find_children("*", "Node3D", true, false):
		if node.has_method("mount_weapon"): controllers.append(node)
	check(not controllers.is_empty(), path + ": no controllers")
	for controller in controllers:
		var authored: Transform3D = controller.transform
		var parent: Node = controller.get_parent()
		while parent != source:
			if parent is Node3D: authored = parent.transform * authored
			parent = parent.get_parent()
		controller.owner = null
		controller.get_parent().remove_child(controller)
		controller.transform = authored
		controller.process_mode = Node.PROCESS_MODE_DISABLED
		world.add_child(controller)
		_check_controller(controller, path.get_file() + "/" + str(controller.name))
		controller.free()
	source.free()

func _check_controller(controller: Node3D, label: String) -> void:
	var turret = controller.get("turret")
	var weapon = controller.get("weapon_instance")
	check(is_instance_valid(turret) and is_instance_valid(weapon), label + ": missing rig/weapon")
	if not is_instance_valid(turret) or not is_instance_valid(weapon): return
	check(turret.barrel_forward_axis_local == Vector3.BACK, label + ": forward not +Z")
	check(turret.barrel_pitch_axis_local == Vector3.RIGHT, label + ": pitch not +X")
	for point in turret.firing_points:
		check(point.basis.z.normalized().dot(Vector3.BACK) > 0.9999, label + ": backward muzzle marker")
	var rest := controller.transform
	for tilted in [false, true]:
		controller.transform = Transform3D(Basis.from_euler(Vector3(0.21, 2.0, -0.17)), Vector3(50, 20, -40)) * rest if tilted else rest
		var yaw = turret._get_yaw_mount()
		var parent: Node3D = yaw.get_parent_node_3d()
		for azimuth in [-150, -80, -30, 0, 30, 80, 150, 180]:
			for elevation in [maxf(-8.0, turret.max_pitch_down + 2.0), minf(25.0, turret.max_pitch_up - 2.0)]:
				var angle := deg_to_rad(float(azimuth))
				var target := parent.to_global(yaw.position + Vector3(sin(angle) * 200, tan(deg_to_rad(float(elevation))) * 200, cos(angle) * 200))
				if not turret.is_point_within_yaw_arc(target):
					var clamped: Vector3 = turret.get_point_clamped_to_yaw_arc(target)
					turret.aim_at_point(clamped)
					for i in 360: turret.tick(1.0 / 60.0, clamped)
					check(turret.get_aim_angle_to_target() < 0.3, label + ": arc boundary alignment")
					continue
				turret.aim_at_point(target)
				for i in 360: turret.tick(1.0 / 60.0, target)
				var error: float = turret.get_aim_angle_to_target()
				worst_error = maxf(worst_error, error)
				cases += 1
				check(error >= 0 and error < 0.3, "%s: alignment %.3f yaw=%d pitch=%d tilt=%s" % [label, error, azimuth, elevation, tilted])
				var measured: Transform3D = turret.get_current_muzzle_transform()
				var fired: Transform3D = turret.get_next_firing_transform()
				check(measured.is_equal_approx(fired), label + ": measured/fired disagree")
		for above in [true, false]:
			var outside := parent.to_global(yaw.position + Vector3(0, 1000 if above else -1000, 10))
			turret.aim_at_point(outside)
			for i in 360: turret.tick(1.0 / 60.0, outside)
			var limit_rad := deg_to_rad(float(turret.max_pitch_up if above else turret.max_pitch_down))
			# A nearly vertical target cannot drive a 90-degree mount beyond its stop.
			if above and turret.max_pitch_up >= 90.0:
				check(turret._barrel_current_pitch <= limit_rad and turret._barrel_current_pitch > deg_to_rad(89.0), label + ": vertical aiming")
			else:
				check(absf(turret._barrel_current_pitch - limit_rad) < 0.001, label + ": exceeded/missed pitch stop")
	# Request a large turn WITHOUT ticking: shots must not magically snap to it.
	var before: Transform3D = turret.get_current_muzzle_transform()
	turret.aim_at_point(before.origin + before.basis.x * 200)
	var unslewed: Transform3D = turret.get_next_firing_transform()
	check(unslewed.basis.z.dot(before.basis.z) > 0.99999, label + ": target-directed shot shortcut")
	var yaw = turret._get_yaw_mount()
	var yaw_before: float = yaw.rotation.y
	turret.tick(1.0 / 60.0, turret.current_target_position)
	check(absf(wrapf(yaw.rotation.y - yaw_before, -PI, PI)) <= deg_to_rad(turret.turn_speed) / 60.0 + 0.00001, label + ": exceeded yaw rate")
	# A stray weapon mesh locator cannot override a turret's barrel transform.
	var decoy := Marker3D.new()
	decoy.name = "BulletSpawnPoint"
	decoy.position = Vector3(100, 100, 100)
	weapon.add_child(decoy)
	check(weapon._get_bullet_spawn_transform(unslewed).is_equal_approx(unslewed), label + ": weapon locator overrode turret")
	weapon.spread_angle = 0.0
	weapon.visible_round_multiplier = 1
	weapon.set_meta("next_fire_time_s", 0.0)
	var barrel: Transform3D = turret.get_current_muzzle_transform()
	check(weapon.fire(), label + ": refused test shot")
	var bullet: Variant = weapon.last_fired_projectile
	check(is_instance_valid(bullet), label + ": no projectile")
	if is_instance_valid(bullet):
		check(bullet.linear_velocity.normalized().dot(barrel.basis.z) > 0.9999, label + ": projectile not along barrel")
		bullet.queue_free()
	var saved_points: Array[Node3D] = []
	saved_points.assign(turret.firing_points)
	var extra := Marker3D.new()
	extra.position = Vector3(0.5, 0, 1)
	turret.barrel_mount.add_child(extra)
	turret.firing_points.append(extra)
	turret._current_fire_point_idx = 0
	turret.is_aiming_at_point = false
	turret.current_target = null
	for point in turret.firing_points:
		var measured: Transform3D = turret.get_current_muzzle_transform()
		var shot: Transform3D = turret.get_next_firing_transform()
		check(shot.is_equal_approx(measured) and shot.origin.is_equal_approx(point.global_position), label + ": multiple muzzle sequence")
	turret.firing_points.clear()
	check(turret.get_next_firing_transform().basis.z.dot(turret.barrel_mount.global_basis.z.normalized()) > 0.9999, label + ": no-muzzle fallback direction")
	turret.firing_points.assign(saved_points)
	extra.free()
	print("BARREL_RIG_OK ", label)

func _render(world: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("354452")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(3.5, 5, 9)
	camera.look_at(Vector3(0, 0.5, 0.5))
	camera.make_current()
	for i in 3:
		var names := ["vehicle_lmg_turret", "vehicle_heavy_gun_turret", "helicopter_side_gun_turret"]
		var rig = load("res://Weapons/Turrets/%s.tscn" % names[i]).instantiate()
		rig.position.x = (i - 1) * 3.0
		world.add_child(rig)
		for node in rig.barrel_mount.find_children("*", "MeshInstance3D", true, false):
			if node.is_visible_in_tree():
				var bounds: AABB = (rig.barrel_mount.global_transform.affine_inverse() * node.global_transform) * node.get_aabb()
				print("BARREL_VISUAL_BOUNDS ", names[i], " ", node.name, " ", bounds)
				check(bounds.size.z > bounds.size.x * 2.0, names[i] + ": visual barrel not +Z aligned")
				var mesh_to_barrel: Transform3D = rig.barrel_mount.global_transform.affine_inverse() * node.global_transform
				var front := AABB()
				var front_valid := false
				for surface in node.mesh.get_surface_count():
					for vertex in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
						var point: Vector3 = mesh_to_barrel * vertex
						if point.z < bounds.end.z - 0.03: continue
						front = front.expand(point) if front_valid else AABB(point, Vector3.ZERO)
						front_valid = true
				var tip := Vector3(front.get_center().x, front.get_center().y, front.end.z)
				print("BARREL_VISUAL_TIP ", names[i], " ", tip)
				check(front_valid and rig.firing_points[0].position.distance_to(tip) < 0.015, names[i] + ": muzzle not at visual tip")
		rig.aim_at_point(rig.global_position + Vector3(0, 20, 100))
		for j in 240: rig.tick(1.0 / 60.0, rig.current_target_position)
		var muzzle: Transform3D = rig.get_current_muzzle_transform()
		var line := MeshInstance3D.new()
		var mesh := ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color.YELLOW
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
		mesh.surface_add_vertex(muzzle.origin)
		mesh.surface_add_vertex(muzzle.origin + muzzle.basis.z * 2)
		mesh.surface_end()
		line.mesh = mesh
		world.add_child(line)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://barrel_orientation.png") == OK, "render failed")
