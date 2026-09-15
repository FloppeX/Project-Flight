extends SceneTree

var failures: Array[String] = []
var controller: Node
var scene: Node3D
var aircraft: RigidBody3D
var _expected_visual_end_ms := 0.0
var _actual_detonation := false
var _tail_count := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func make_bomb(owner_plane: Node3D, position: Vector3, velocity: Vector3) -> RigidBody3D:
	var result: RigidBody3D = load("res://Projectiles/BombNew/bomb_new.tscn").instantiate()
	result.position = position
	result.freeze = true
	result.process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(result)
	result.fire(velocity, owner_plane)
	return result

func run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var ground := StaticBody3D.new()
	scene.add_child(ground)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	shape.shape = box
	shape.position.y = -1
	ground.add_child(shape)
	var ground_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	ground_mesh.mesh = mesh
	ground_mesh.position.y = -1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.36, 0.19)
	ground_mesh.material_override = material
	ground.add_child(ground_mesh)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -30, 0)
	scene.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.32, 0.42, 0.55)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	scene.add_child(environment)
	aircraft = RigidBody3D.new()
	aircraft.freeze = true
	aircraft.position = Vector3(0, 250, 0)
	scene.add_child(aircraft)
	aircraft.add_to_group("aircraft")
	controller = load("res://Scenario/Trailer/TrailerAircraftCameras.gd").new()
	scene.add_child(controller)
	controller.set_process(false)
	root.get_node("PauseMenu").visible = false
	for frame in 3: await physics_frame
	if "--live" in OS.get_cmdline_user_args():
		await run_live()
		return
	check(not controller.select_slot(controller.BOMB, ground), "ground vehicle has no bomb view")
	check(controller.select_slot(controller.BOMB, aircraft), "aircraft bomb view selectable")
	var rig: Node = controller.bomb_camera
	rig.set_physics_process(false)
	var other := RigidBody3D.new()
	other.freeze = true
	scene.add_child(other)
	var wrong_bomb := make_bomb(other, Vector3(30, 200, 0), Vector3(60, -20, 0))
	rig._physics_process(0.016)
	check(rig.state == rig.State.WAITING, "ignores other aircraft bombs")
	var bomb := make_bomb(aircraft, Vector3(0, 200, 0), Vector3(60, -20, 0))
	rig._physics_process(0.016)
	check(rig.state == rig.State.FOLLOWING and rig.bomb == bomb, "acquires selected aircraft bomb")
	check(rig.has_prediction and absf(rig.impact.y) < 0.05, "predicts collision on ground")
	var fall_time := (-20.0 + sqrt(400.0 + 2.0 * 9.8 * 200.0)) / 9.8
	check(absf(rig.impact.x - 60.0 * fall_time) < 1.0, "prediction agrees with ballistic impact")
	check(rig.pose.origin.distance_to(bomb.position - bomb.linear_velocity.normalized() * 8.0) < 0.01, "camera eight metres behind bomb")
	controller._process(0.016)
	check((-controller.camera.global_basis.z).dot((rig.impact - controller.camera.global_position).normalized()) > 0.9999, "looks at predicted impact")
	var second := make_bomb(aircraft, Vector3(20, 200, 0), Vector3(60, -20, 0))
	rig._physics_process(0.016)
	check(rig.bomb == bomb, "later salvo does not steal camera")
	if "--render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/trailer_bomb_follow.png")
	bomb.position = Vector3(100, 15, 0)
	bomb.linear_velocity = Vector3(60, -80, 0)
	rig._physics_process(0.3)
	controller._process(0.016)
	check(rig.state == rig.State.HOLDING, "fast descent crosses into hold")
	check(absf(rig.pose.origin.y - 40.0) < 0.02, "stop at forty metres instead of overshooting")
	var held_pose: Transform3D = rig.pose
	var held_impact: Vector3 = rig.impact
	bomb.position = Vector3(150, 1, 0)
	rig._physics_process(1.0)
	check(rig.pose == held_pose and rig.impact == held_impact, "hold position and aim remain fixed")
	var shift := Vector3(5000, 50, -3000)
	for node in [ground, aircraft, bomb, second, wrong_bomb, other]: node.position -= shift
	controller.apply_origin_shift(shift)
	check(rig.pose.origin.distance_to(held_pose.origin - shift) < 0.01 and rig.impact.distance_to(held_impact - shift) < 0.01, "origin shift translates stop pose and locked aim")
	# The real detonation signal (not the tuning/despawn signal) arms aftermath.
	bomb._trigger_explosion(ground)
	check(rig.state == rig.State.AFTERMATH, "real detonation starts aftermath")
	var explosion: Node = rig._explosion
	explosion.visual_effects_enabled = false
	explosion.play_explosion_audio = false
	explosion.max_damage = 0.0
	explosion.min_damage = 0.0
	explosion.knockback_impulse_at_center = 0.0
	explosion.knockback_impulse_at_edge = 0.0
	# Model a late-spawned pooled effect outliving its coordinator.
	explosion.visual_tail_started.emit(2.5)
	explosion.visuals_scheduled.emit()
	explosion.free()
	paused = true
	rig._physics_process(10.0)
	check(is_equal_approx(rig._visual_remaining, 5.5), "pause freezes effects plus three-second hold")
	paused = false
	rig._physics_process(5.4)
	check(controller.slot == controller.BOMB, "hold includes full visual lifetime plus three seconds")
	rig._physics_process(0.2)
	check(controller.slot == 0 and controller.active, "completed shot returns to camera one")
	check(controller.select_slot(controller.BOMB, aircraft), "bomb cam can be rearmed")
	rig.set_physics_process(false)
	second.free()
	wrong_bomb.free()
	for frame in 2: await process_frame
	ground.position = Vector3.ZERO
	ground.rotation.z = 0.08
	aircraft.position = Vector3(100, 200, 0)
	for frame in 3: await physics_frame
	var low_bomb := make_bomb(aircraft, Vector3(100, 20, 0), Vector3(0, -60, 0))
	rig._physics_process(0.016)
	check(rig.state == rig.State.HOLDING and absf(rig.pose.origin.y - rig._ground_height(rig.pose.origin) - 40.0) < 0.02, "late selection over sloping terrain clamps forty metres above local ground")
	low_bomb.free()
	controller.select_slot(controller.BOMB, aircraft)
	rig.set_physics_process(false)
	var dud := make_bomb(aircraft, aircraft.position, Vector3(60, -20, 0))
	rig._physics_process(0.016)
	dud.free()
	rig._physics_process(0.016)
	check(rig.state == rig.State.AFTERMATH and rig._visual_remaining == 3.0, "despawn/dud ends cleanly without fake explosion")
	controller.release_camera()
	check(rig.state == rig.State.OFF, "leaving view cancels tracking")
	scene.queue_free()
	await process_frame
	print("TRAILER_BOMB_CAMERA_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)

func run_live() -> void:
	root.get_node("ParticleManager").process_mode = Node.PROCESS_MODE_PAUSABLE
	root.get_node("BulletImpactBudget").process_mode = Node.PROCESS_MODE_PAUSABLE
	controller.set_process(true)
	check(controller.select_slot(controller.BOMB, aircraft), "live bomb view selected")
	var rig: Node = controller.bomb_camera
	var bomb := make_bomb(aircraft, Vector3(0, 200, 0), Vector3(0, -5, 65))
	bomb.process_mode = Node.PROCESS_MODE_INHERIT
	bomb.freeze = false
	bomb.linear_velocity = Vector3(0, -5, 65)
	bomb.detonated.connect(func(_point: Vector3, explosion: Node):
		check(_point.z > 300.0, "live bomb retained horizontal launch speed")
		_actual_detonation = true
		_expected_visual_end_ms = Time.get_ticks_msec() + 3000.0
		explosion.visual_tail_started.connect(func(duration: float):
			_tail_count += 1
			_expected_visual_end_ms = maxf(_expected_visual_end_ms, Time.get_ticks_msec() + (duration + 3.0) * 1000.0)
		)
	)
	var follow_saved := false
	var hold_seen := false
	var hold_pose := Transform3D.IDENTITY
	var impact_pose := Transform3D.IDENTITY
	var explosion_saved := false
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and controller.slot == controller.BOMB:
		await process_frame
		if is_instance_valid(bomb) and bomb.position.y < 130 and not follow_saved:
			follow_saved = true
			if "--render" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://captures/trailer_bomb_live_follow.png")
		if rig.state == rig.State.HOLDING and not hold_seen:
			hold_seen = true
			hold_pose = rig.pose
			check(absf(hold_pose.origin.y - 40.0) < 0.03, "live bomb camera freezes at forty metres")
		if _actual_detonation and rig.state == rig.State.AFTERMATH:
			impact_pose = rig.pose
			check(impact_pose.is_equal_approx(hold_pose), "explosion does not move held camera")
			if _tail_count >= 4 and not explosion_saved:
				explosion_saved = true
				if "--render" in OS.get_cmdline_user_args():
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("res://captures/trailer_bomb_live_explosion.png")
	check(_actual_detonation and hold_seen, "real physics bomb detonated after camera stop")
	check(_tail_count > 0, "actual pooled effects reported their visual lifetimes")
	check(controller.slot == 0, "live sequence returned to camera one")
	check(Time.get_ticks_msec() >= _expected_visual_end_ms - 100.0, "did not finish before visual effects plus three seconds")
	print("TRAILER_BOMB_LIVE tails=%d end_margin_ms=%.1f hold_y=%.3f" % [_tail_count, Time.get_ticks_msec() - _expected_visual_end_ms, hold_pose.origin.y])
	controller.release_camera()
	scene.queue_free()
	await process_frame
	print("TRAILER_BOMB_CAMERA_LIVE_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
