extends Node3D

class Target:
	extends StaticBody3D
	var hits := 0
	func take_damage(_amount: float) -> void:
		hits += 1

var checks := 0
var failures := 0

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var night := "--night" in OS.get_cmdline_user_args()
	var render := "--render" in OS.get_cmdline_user_args()
	var camera := Camera3D.new()
	camera.position = Vector3(5, 2.5, -11)
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.015, 0.022, 0.04) if night else Color(0.42, 0.53, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.06 if night else 0.7
	env.environment.glow_enabled = true
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	sun.light_energy = 0.08 if night else 1.5
	add_child(sun)
	var target := Target.new()
	target.add_to_group("ground_vehicles")
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(7, 4, 0.5)
	collider.shape = box
	target.add_child(collider)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = box.size
	mesh.mesh = cube
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.32, 0.29)
	material.metallic = 0.65
	material.roughness = 0.6
	mesh.material_override = material
	target.add_child(mesh)
	add_child(target)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var budget := get_node("/root/BulletImpactBudget")
	var particles := get_node("/root/ParticleManager")
	var bullet := preload("res://Projectiles/Bullet/bullet.tscn").instantiate()
	bullet.position = Vector3(0, 0, -5)
	add_child(bullet)
	bullet.set_physics_process(false)
	bullet.gravity_scale = 0.0
	bullet.hit_debris_count = 0
	bullet.ground_particle_count = 0
	bullet.fire(Vector3(0, 0, 2000), null)
	bullet._physics_process(1.0 / 60.0)
	_check(target.hits == 1, "Spark presentation does not add damage events")
	_check(budget._active_debris.size() == 6, "One actual target hit creates six sparks")
	for spark in budget._active_debris.values():
		var spark_material: StandardMaterial3D = spark.material_override
		_check(spark_material.emission_enabled and spark_material.emission_energy_multiplier >= 7.0
			and spark_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
			"Sparks remain bright regardless of scene lighting")
		_check(spark.global_position.z < -0.25, "Sparks originate just outside the actual struck surface")
	if render:
		await get_tree().create_timer(0.075).timeout
		particles.set_process(false)
		await RenderingServer.frame_post_draw
		var path := "user://bullet_hit_sparks_" + ("night" if night else "day") + ".png"
		get_viewport().get_texture().get_image().save_png(path)
		print("BULLET_HIT_SPARK_RENDER " + ProjectSettings.globalize_path(path))
		particles.set_process(true)
	await get_tree().create_timer(0.5).timeout
	_check(budget._active_debris.is_empty(), "Short-lived sparks return to the bounded pool")
	_check(budget._debris_pool.size() >= 6, "Spark meshes are retained for reuse")
	budget.spawn_debris(Vector3.ZERO, Vector3.ONE * 0.1, Color(0.2, 0.15, 0.1), 0.0, 1.0, Vector3.ZERO, 0.1)
	var dirt: MeshInstance3D = budget._active_debris.values()[0]
	var dirt_material: StandardMaterial3D = dirt.material_override
	_check(not dirt_material.emission_enabled and dirt_material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL
		and dirt_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Reusing a spark as dirt resets glow and transparency")
	await get_tree().create_timer(0.25).timeout
	budget.max_active_debris = 3
	_check(budget.spawn_hit_sparks(Vector3.ZERO, Vector3.FORWARD) == 3, "Spark bursts obey the shared effect cap")
	await get_tree().create_timer(0.4).timeout
	budget.max_active_debris = 96
	var heavy := preload("res://Projectiles/HeavyRound/heavy_round.tscn").instantiate()
	heavy.position = Vector3(0, 0, -5)
	add_child(heavy)
	heavy.set_physics_process(false)
	heavy.gravity_scale = 0.0
	heavy.explosion_scene = null
	heavy.fire(Vector3(0, 0, 2000), null)
	heavy._physics_process(1.0 / 60.0)
	_check(target.hits == 2 and budget._active_debris.size() == 6, "Heavy rounds use the same real-hit spark hook without duplicate damage")
	await get_tree().create_timer(0.4).timeout
	var miss := preload("res://Projectiles/Bullet/bullet.tscn").instantiate()
	miss.position = Vector3(5, 0, -5)
	add_child(miss)
	miss.set_physics_process(false)
	miss.gravity_scale = 0.0
	miss.fire(Vector3(0, 0, 2000), null)
	miss._physics_process(1.0 / 60.0)
	_check(budget._active_debris.is_empty() and target.hits == 2, "A close miss creates no hit sparks")
	miss.queue_free()
	var ground := StaticBody3D.new()
	ground.add_to_group("ground")
	add_child(ground)
	var probe := preload("res://Projectiles/Bullet/bullet.tscn").instantiate()
	add_child(probe)
	probe.set_physics_process(false)
	probe._spawn_target_hit_sparks(ground)
	_check(budget._active_debris.is_empty(), "Ordinary ground contacts retain dirt rather than metal sparks")
	print("BULLET_HIT_SPARK_SMOKETEST checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
