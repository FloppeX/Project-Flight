extends SceneTree
const Hooks = preload("res://Recording/CaptureHooks.gd")
const Take = preload("res://Recording/SceneTake.gd")
var failures: Array[String] = []
class Target:
	extends StaticBody3D
	var hits := 0
	func take_damage(_amount: float) -> void: hits += 1

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	await process_frame
	var bullet_scene: PackedScene = load("res://Projectiles/Bullet/bullet.tscn")
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var mode := root.get_node("RecordingMode")
	mode.process_mode = Node.PROCESS_MODE_ALWAYS
	var particles := root.get_node("ParticleManager")
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(15, 10, 28)
	camera.look_at(Vector3(0, 1, 0))
	camera.make_current()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.12, 0.17)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7
	env.environment.glow_enabled = true
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	scene.add_child(sun)
	var target := Target.new()
	target.add_to_group("ground_vehicles")
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(7, 4, 0.5)
	target.add_child(collision)
	var target_mesh := _mesh(Vector3(7, 4, 0.5), Color(0.25, 0.38, 0.28))
	target.add_child(target_mesh)
	scene.add_child(target)
	var craft := RigidBody3D.new()
	craft.freeze = true
	craft.position = Vector3(8, 3, 0)
	var wing := _mesh(Vector3(4, 0.2, 1.5), Color(0.65, 0.65, 0.68))
	wing.name = "Wing"
	craft.add_child(wing)
	for collider_name in ["LeftWingDamageCollider", "RightWingDamageCollider", "FuselageDamageCollider", "CockpitDamageCollider", "HorizontalStabilizerDamageCollider", "VerticalStabilizerDamageCollider"]:
		var part_collider := CollisionShape3D.new()
		part_collider.name = collider_name
		part_collider.shape = BoxShape3D.new()
		craft.add_child(part_collider)
	var damage := preload("res://Aircraft/AircraftPartDamageModel.gd").new()
	damage.left_wing_visual_paths = [NodePath("../Wing")]
	craft.add_child(damage)
	scene.add_child(craft)
	await physics_frame
	await physics_frame
	mode.enter()
	var actors: Array[Node3D] = [target, craft]
	check(mode.start_recording(actors), "capture starts")
	paused = true
	var bullet: Variant = null
	var first_bullet_id := 0
	var reused := false
	var sample_us := 0
	var sample_peak_us := 0
	for frame in range(1, 121):
		mode.elapsed = frame / 60.0
		if frame in [6, 42]:
			bullet = root.get_node("BulletPool").acquire(bullet_scene, scene, Transform3D(Basis.IDENTITY, Vector3(0, 0, 15)))
			if first_bullet_id == 0: first_bullet_id = bullet.get_instance_id()
			else: reused = bullet.get_instance_id() == first_bullet_id
			bullet.set_physics_process(false)
			bullet.gravity_scale = 0.0
			bullet.hit_debris_count = 0
			bullet.ground_particle_count = 0
			bullet.fire(Vector3(0, 0, -60), null)
		if is_instance_valid(bullet) and not bullet.has_impacted: bullet._physics_process(1.0 / 60.0)
		if frame == 60:
			var explosion: Node3D = load("res://Projectiles/Explosion/explosion.tscn").instantiate()
			scene.add_child(explosion)
			explosion.position = Vector3(-6, 1, 0)
			explosion.blast_radius = 5.0
			explosion.visual_preset = 2 # STANDARD includes a blast wave.
			explosion.visual_spread_duration_s = 0.0
			explosion.play_explosion_audio = false
			explosion.max_damage = 0.0
			explosion.min_damage = 0.0
			explosion.trigger_explosion()
			damage._detach_zone_visuals(&"left_wing")
		for debris in get_nodes_in_group("recording_transient"):
			if debris.get_meta("recording_kind", "") == "detached_part":
				debris.position += Vector3(0.02, -0.02, 0.03)
		particles._process(1.0 / 60.0)
		if frame % 2 == 0:
			var started := Time.get_ticks_usec()
			mode.take.sample(mode.elapsed)
			var cost := Time.get_ticks_usec() - started
			sample_us += cost
			sample_peak_us = maxi(sample_peak_us, cost)
		# Flush real deferred pool returns between simulated ticks.
		await process_frame
	check(target.hits == 2, "two live shots apply damage exactly twice")
	check(reused, "actual bullet object reused by pool")
	check(not wing.visible, "production detach hides original wing")
	mode.stop_recording()
	var kinds: Dictionary = {}
	for track in mode.take.combat.tracks: kinds[track.kind] = int(kinds.get(track.kind, 0)) + 1
	for kind in ["bullet", "spark", "explosion_flash", "blast_wave", "detached_part"]:
		check(kinds.has(kind), "production capture includes " + kind)
	check(kinds.get("bullet", 0) == 4, "two meshes per activation have independent lifetime tracks")
	var bullet_visible := false
	mode.take.combat.seek(0.2)
	for index in mode.take.combat.tracks.size():
		if mode.take.combat.tracks[index].kind == "bullet" and mode.take.combat.copies[index].visible: bullet_visible = true
	check(bullet_visible, "actual tracer visible between launch and hit")
	mode.enter_replay()
	for t in [0.0, 0.2, 0.4, 0.8, 1.1, 2.0, 0.4, 0.0]:
		mode.seek(t)
		for index in mode.take.combat.tracks.size():
			var track: Dictionary = mode.take.combat.tracks[index]
			if t < track.birth or t >= track.death: check(not mode.take.combat.copies[index].visible, "outside lifetime is hidden")
	check(target.hits == 2, "scrubbing never reruns damage")
	mode.seek(0.0)
	mode.camera.attach(null, 0)
	mode.camera.global_position = camera.global_position
	mode.camera.look_at(Vector3.ZERO)
	mode.camera.attach(null, 0)
	mode.add_key()
	mode.selected_shot = 1
	mode.camera.global_position = Vector3(-12, 5, 22)
	mode.camera.look_at(Vector3(0, 1, 0))
	mode.camera.attach(null, 0)
	mode.add_key()
	var directory: String = mode.save_take()
	var loaded := Take.new()
	check(loaded.load_from(directory), "v4 combat take reloads")
	root.add_child(loaded.world)
	for t in [0.2, 0.4, 1.15, 0.0, 1.6]:
		mode.seek(t)
		loaded.seek(t)
		for index in loaded.combat.copies.size():
			check(loaded.combat.copies[index].transform.is_equal_approx(mode.take.combat.copies[index].transform), "reloaded combat pose matches")
			check(loaded.combat.copies[index].visible == mode.take.combat.copies[index].visible, "reloaded combat visibility matches")
			if loaded.combat.copies[index].material_override is BaseMaterial3D:
				check(loaded.combat.copies[index].material_override.albedo_color.is_equal_approx(mode.take.combat.copies[index].material_override.albedo_color), "reloaded fade matches")
	loaded.dispose()
	mode._panel.hide()
	mode.play_shot = true
	for shot in range(2):
		mode.selected_shot = shot
		mode.seek(1.15)
		for frame in range(3): await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/recording/combat_%d.png" % shot)
	FileAccess.open("res://captures/recording/combat_take_path.txt", FileAccess.WRITE).store_string(directory)
	print("[RecordingCombatSmoketest] %s failures=%s kinds=%s mib=%.3f take=%s" % ["PASS" if failures.is_empty() else "FAIL", failures, kinds, mode.take.estimated_bytes / 1048576.0, directory])
	mode.exit()
	mode.clear_take()
	_edge_cases(scene)
	# Exercise the real late-physics recording clock and a take that begins
	# while older managed effects / detached parts are already alive.
	mode.enter()
	check(mode.start_recording(actors), "live follow-up starts")
	check(mode.take.combat.tracks.size() > 0, "already-live effects discovered at capture start")
	particles.process_mode = Node.PROCESS_MODE_PAUSABLE
	var live_bullet: Variant = root.get_node("BulletPool").acquire(bullet_scene, scene, Transform3D(Basis.IDENTITY, Vector3(0, 0, 15)))
	live_bullet.gravity_scale = 0.0
	live_bullet.fire(Vector3(0, 0, -60), null)
	for tick in 60: await physics_frame
	mode.stop_recording()
	check(target.hits == 3, "live physics adds exactly one further hit")
	check(mode.take.frames.size() > 20, "real capture clock produces samples")
	for track in mode.take.combat.tracks:
		for index in range(1, track.times.size()): check(track.times[index] > track.times[index - 1], "event clock stays strictly ordered")
	print("[RecordingCombatLive] frames=%d combat_meshes=%d sample_mean_ms=%.3f sample_peak_ms=%.3f" % [mode.take.frames.size(), mode.take.combat.tracks.size(), mode._sampling_usec_total / float(maxi(mode._sampling_count, 1)) / 1000.0, mode._sampling_usec_max / 1000.0])
	mode.exit()
	mode.clear_take()
	print("[RecordingCombatSmoketest] final %s sample_mean_ms=%.3f sample_peak_ms=%.3f" % ["PASS" if failures.is_empty() else "FAIL", sample_us / 60000.0, sample_peak_us / 1000.0])
	await process_frame
	scene.free()
	quit(0 if failures.is_empty() else 1)

func _edge_cases(scene: Node3D) -> void:
	var take := Take.new()
	take.world = Node3D.new()
	root.add_child(take.world)
	var mesh := _mesh(Vector3.ONE, Color.RED)
	scene.add_child(mesh)
	mesh.position.x = 10.0
	take.combat.begin(take, mesh, 0.1, "short_effect")
	take.combat.end(take, mesh.get_instance_id(), 0.11)
	take.combat.seek(0.105)
	check(take.combat.copies[0].visible, "effect shorter than sample interval retained")
	take.combat.seek(0.11)
	check(not take.combat.copies[0].visible, "death boundary is exclusive")
	mesh.material_override.albedo_color = Color.BLUE
	take.origin_offset = Vector3(100, 0, 0)
	take.combat.begin(take, mesh, 0.2, "reused_effect")
	mesh.position.x -= 1000.0
	take.origin_offset.x += 1000.0
	take.combat.sample(take, 0.3)
	take.combat.seek(0.25)
	check(is_equal_approx(take.combat.copies[1].position.x, 110.0), "origin shift preserves transient trajectory")
	check(take.combat.copies[1].material_override.albedo_color == Color.BLUE, "new pooled material captured")
	take.combat.seek(0.105)
	check(take.combat.copies[0].material_override.albedo_color == Color.RED, "pool reuse cannot recolor earlier event")
	mesh.free()
	take.combat.sample(take, 0.4)
	take.combat.seek(0.4)
	check(not take.combat.copies[1].visible, "freed source closes without dereferencing it")
	var too_large := Node3D.new()
	scene.add_child(too_large)
	for i in 257: too_large.add_child(_mesh(Vector3.ONE, Color.WHITE))
	take.combat.begin(take, too_large, 0.5, "over_limit")
	check(take.combat.tracks.size() == 2 and not take.warning.is_empty(), "active cap rejects entire effect atomically")
	too_large.free()
	take.dispose()
	# Exercise the supported worst-case active-mesh count, not a full battle.
	var stress := Take.new()
	stress.world = Node3D.new()
	root.add_child(stress.world)
	var batch := Node3D.new()
	scene.add_child(batch)
	for i in 256: batch.add_child(_mesh(Vector3.ONE, Color.WHITE))
	var start := Time.get_ticks_usec()
	stress.combat.begin(stress, batch, 0.0, "budget_fixture")
	var spawn_ms := (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	for tick in 60: stress.combat.sample(stress, (tick + 1) / 30.0)
	var sample_ms := (Time.get_ticks_usec() - start) / 60000.0
	start = Time.get_ticks_usec()
	for tick in 60: stress.combat.seek((59 - tick) / 30.0)
	var seek_ms := (Time.get_ticks_usec() - start) / 60000.0
	check(stress.combat.tracks.size() == 256, "active limit can be fully used")
	print("[RecordingCombatBudget] meshes=256 spawn_ms=%.3f sample_mean_ms=%.3f seek_mean_ms=%.3f estimated_mib=%.3f" % [spawn_ms, sample_ms, seek_ms, stress.estimated_bytes / 1048576.0])
	stress.estimated_bytes = Take.MAX_ESTIMATED_BYTES
	var old_count: int = stress.combat.tracks[0].times.size()
	stress.combat.sample(stress, 3.0)
	check(stress.combat.tracks[0].times.size() == old_count and not stress.warning.is_empty(), "shared memory cap bounds event samples")
	stress.dispose()
	batch.free()

func _mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.material_override = StandardMaterial3D.new()
	mesh.material_override.albedo_color = color
	return mesh

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
