extends Node3D

class DamageTarget:
	extends StaticBody3D
	var damage_taken: float = 0.0
	func take_damage(amount: float) -> void:
		damage_taken += amount

const BULLET_SCENE := preload("res://Projectiles/Bullet/bullet.tscn")
var _world: Node3D
var _failures: Array[String] = []

func _ready() -> void:
	print("[BulletOptimizationSmoketest] starting")
	call_deferred("_run")

func _run() -> void:
	print("[BulletOptimizationSmoketest] installing services")
	_ensure_service("ParticleManager", "res://Effects/ParticleManager.gd")
	_ensure_service("BulletImpactBudget", "res://Effects/BulletImpactBudget.gd")
	_ensure_service("BulletPool", "res://Projectiles/Bullet/BulletPool.gd")
	var impact_budget: Node = get_tree().root.get_node("BulletImpactBudget")
	_world = Node3D.new()
	_world.name = "BulletOptimizationSmoketestWorld"
	get_tree().root.add_child(_world)
	var camera := Camera3D.new()
	_world.add_child(camera)
	camera.global_position = Vector3(0.0, 8.0, 20.0)
	camera.look_at(Vector3(0.0, 0.0, 50.0))
	camera.current = true

	var target := DamageTarget.new()
	target.name = "DamageTarget"
	target.add_to_group("ground_vehicles")
	target.position = Vector3(0.0, 0.0, 50.0)
	var target_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 8.0, 2.0)
	target_shape.shape = box
	target.add_child(target_shape)
	_world.add_child(target)

	await get_tree().physics_frame
	print("[BulletOptimizationSmoketest] firing first round")
	var first := _acquire_test_bullet(1)
	var first_id: int = first.get_instance_id()
	first.fire(Vector3(0.0, 0.0, 500.0), null)
	_expect(_is_aligned_to_velocity(first), "new bullet tracer was not aligned on its first rendered frame")
	_expect(first.distant_tracer_stride == 1, "default distant tracer sampling still hides some rounds")
	await _wait_physics_frames(20)
	print("[BulletOptimizationSmoketest] first round complete damage=%.1f pool=%s" % [target.damage_taken, get_tree().root.get_node("BulletPool").call("get_stats")])
	_expect(is_equal_approx(target.damage_taken, 5.0), "cosmetic virtual vehicle impact changed physical bullet damage")
	_expect(first.virtual_impact_visuals_spawned == 1, "virtual vehicle impact did not create one nearby decal")
	_expect(first.get_parent() == get_tree().root.get_node("BulletPool"), "retired bullet was not returned to BulletPool")

	var second := _acquire_test_bullet()
	_expect(second.get_instance_id() == first_id, "second shot did not reuse the retired bullet")
	second.fire(Vector3(0.0, 0.0, 500.0), null)
	_expect(_is_aligned_to_velocity(second), "reused bullet tracer retained its previous orientation")
	print("[BulletOptimizationSmoketest] reused fired processing=%s impacted=%s pos=%s vel=%s" % [second.is_physics_processing(), second.has_impacted, second.global_position, second.linear_velocity])
	await _wait_physics_frames(20)
	print("[BulletOptimizationSmoketest] reused round complete damage=%.1f parent=%s pos=%s impacted=%s" % [target.damage_taken, second.get_parent().name if second.get_parent() else "none", second.global_position, second.has_impacted])
	_expect(target.damage_taken >= 10.0, "reused bullet did not damage the target")

	# A machine-gun ground hit gets one adjacent cosmetic mark and a second dirt
	# burst, but still uses the single physical projectile collision.
	target.position.x = 20.0
	var ground_target := StaticBody3D.new()
	ground_target.name = "GroundImpactTarget"
	ground_target.add_to_group("ground")
	ground_target.position = Vector3(0.0, 0.0, 50.0)
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(8.0, 8.0, 2.0)
	ground_shape.shape = ground_box
	ground_target.add_child(ground_shape)
	_world.add_child(ground_target)
	await get_tree().physics_frame
	var debris_before_ground := int((impact_budget.call("get_stats") as Dictionary).get("active_debris", 0))
	var ground_bullet := _acquire_test_bullet(1, 1)
	ground_bullet.fire(Vector3(0.0, 0.0, 500.0), null)
	await _wait_physics_frames(20)
	var ground_impact_stats := impact_budget.call("get_stats") as Dictionary
	_expect(ground_bullet.virtual_impact_visuals_spawned == 1, "virtual ground impact did not create one nearby marker")
	_expect(
		int(ground_impact_stats.get("active_debris", 0)) - debris_before_ground >= 2,
		"virtual ground impact did not add a second dirt burst"
	)
	ground_target.queue_free()
	await get_tree().physics_frame

	# Exercise the assist-only path: this box does not intersect the x=0 shot,
	# but its target envelope is within the configured forgiveness radius.
	var assist_target := DamageTarget.new()
	assist_target.name = "AssistTarget"
	assist_target.add_to_group("ground_vehicles")
	assist_target.position = Vector3(2.4, 0.0, 50.0)
	var assist_shape := CollisionShape3D.new()
	var assist_box := BoxShape3D.new()
	assist_box.size = Vector3(2.0, 2.0, 2.0)
	assist_shape.shape = assist_box
	assist_target.add_child(assist_shape)
	_world.add_child(assist_target)
	# Push the candidate population above the adaptive direct-list threshold so
	# this shot exercises the staggered physics broadphase branch as well.
	for i in range(25):
		var decoy := DamageTarget.new()
		decoy.name = "AssistBroadphaseDecoy%d" % i
		decoy.add_to_group("ground_vehicles")
		decoy.position = Vector3(100.0 + float(i) * 4.0, 0.0, 50.0)
		var decoy_shape := CollisionShape3D.new()
		var decoy_box := BoxShape3D.new()
		decoy_box.size = Vector3(2.0, 2.0, 2.0)
		decoy_shape.shape = decoy_box
		decoy.add_child(decoy_shape)
		_world.add_child(decoy)
	ProjectileNew.clear_hit_assist_candidate_cache()
	await get_tree().physics_frame
	var assist_bullet := _acquire_test_bullet()
	assist_bullet.fire(Vector3(0.0, 0.0, 500.0), null)
	await _wait_physics_frames(20)
	_expect(assist_target.damage_taken > 0.0, "staggered hit-assist path did not register the near miss")

	for i in range(220):
		var decal := Decal.new()
		_world.add_child(decal)
		get_tree().root.get_node("BulletImpactBudget").call("register_decal", decal, 0.0)
	await get_tree().process_frame
	print("[BulletOptimizationSmoketest] decal cap complete")
	var impact_stats: Dictionary = impact_budget.call("get_stats")
	_expect(int(impact_stats.active_decals) <= int(impact_budget.get("max_active_decals")), "global decal cap was exceeded")

	for i in range(140):
		impact_budget.call("spawn_debris",
			Vector3(float(i % 10) - 4.5, 0.0, 30.0 + float(i / 10)),
			Vector3.ONE * 0.1,
			Color.WHITE,
			0.0,
			1.0,
			Vector3.UP,
			0.2)
	impact_stats = impact_budget.call("get_stats")
	_expect(int(impact_stats.active_debris) > 0, "visible impact debris was not spawned")
	_expect(int(impact_stats.active_debris) <= int(impact_budget.get("max_active_debris")), "active debris cap was exceeded")
	await get_tree().create_timer(0.4).timeout
	print("[BulletOptimizationSmoketest] debris expiry complete")
	impact_stats = impact_budget.call("get_stats")
	_expect(int(impact_stats.active_debris) == 0, "expired debris did not return to its pool")
	_expect(int(impact_stats.pooled_debris) > 0, "expired debris was not retained for reuse")
	for i in range(12):
		var pooled_decal: Decal = impact_budget.call("acquire_decal", _world) as Decal
		impact_budget.call("register_decal", pooled_decal, 0.05)
	await get_tree().create_timer(0.35).timeout
	impact_stats = impact_budget.call("get_stats")
	_expect(int(impact_stats.pooled_decals) > 0, "expired decals were not retained for reuse")

	if _failures.is_empty():
		print("[BulletOptimizationSmoketest] PASS pool=%s impact=%s" % [get_tree().root.get_node("BulletPool").call("get_stats"), impact_stats])
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("[BulletOptimizationSmoketest] " + failure)
		get_tree().quit(1)

func _acquire_test_bullet(virtual_impacts: int = 0, ground_particles: int = 0) -> Bullet:
	var bullet := get_tree().root.get_node("BulletPool").call("acquire", BULLET_SCENE, _world, Transform3D(Basis.IDENTITY, Vector3.ZERO)) as Bullet
	bullet.lifetime = 1.0
	bullet.gravity_scale = 0.0
	bullet.damage = 5.0
	bullet.damage_amount = 5.0
	bullet.virtual_impact_count = virtual_impacts
	bullet.ground_particle_count = ground_particles
	bullet.hit_debris_count = 0
	bullet.tracer_hidden_physics_frames = 0
	return bullet

func _ensure_service(service_name: String, script_path: String) -> void:
	if get_tree().root.get_node_or_null(service_name):
		return
	var service := Node.new()
	service.name = service_name
	service.set_script(load(script_path))
	get_tree().root.add_child(service)

func _wait_physics_frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame

func _is_aligned_to_velocity(bullet: Bullet) -> bool:
	if bullet == null or bullet.linear_velocity.length_squared() <= 0.01:
		return false
	var tracer_forward: Vector3 = -bullet.global_transform.basis.z.normalized()
	return tracer_forward.dot(bullet.linear_velocity.normalized()) > 0.999

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
