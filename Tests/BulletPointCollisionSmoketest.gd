extends Node3D

class Target:
	extends StaticBody3D
	var hits := 0
	var damage_total := 0.0
	var hit_position := Vector3.INF
	var hit_shape := -1
	func take_damage(amount: float) -> void:
		hits += 1
		damage_total += amount
	func take_projectile_damage_at(amount: float, pos: Vector3, shape_index: int) -> void:
		take_damage(amount)
		hit_position = pos
		hit_shape = shape_index

const PROFILE_NAMES := ["10mm_machine_gun", "15mm_machine_gun", "20mm_autocannon", "25mm_autocannon", "40mm_autocannon", "legacy_heavy_round"]
var checks := 0
var failures := 0
var arena: Node3D

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _box(body: Node3D, offset: Vector3, size: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = offset
	body.add_child(collision)

func _target(pos: Vector3, size: Vector3) -> Target:
	var target := Target.new()
	target.position = pos
	target.add_to_group("ground_vehicles")
	_box(target, Vector3.ZERO, size)
	arena.add_child(target)
	return target

func _bullet(scene: PackedScene, pos: Vector3 = Vector3.ZERO) -> Bullet:
	var bullet: Bullet = get_node("/root/BulletPool").acquire(scene, arena, Transform3D(Basis.IDENTITY, pos)) as Bullet
	bullet.set_physics_process(false)
	bullet.gravity_scale = 0.0
	bullet.lifetime = 2.0
	bullet.damage = 5.0
	bullet.damage_amount = 5.0
	bullet.ground_particle_count = 0
	bullet.hit_debris_count = 0
	bullet.virtual_impact_count = 0
	bullet.explosion_scene = null # Isolate contact damage, not a heavy round's splash.
	return bullet

func _fresh_arena() -> void:
	if is_instance_valid(arena):
		arena.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
	arena = Node3D.new()
	add_child(arena)

func _sync() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

func _run() -> void:
	for profile_name in PROFILE_NAMES:
		var scene: PackedScene
		if profile_name == "legacy_heavy_round":
			scene = preload("res://Projectiles/HeavyRound/heavy_round.tscn")
		else:
			var profile: Resource = load("res://Weapons/Guns/Profiles/" + profile_name + ".tres")
			scene = profile.projectile_scene
		await _fresh_arena()
		var target := _target(Vector3(0, 0, 4), Vector3(1, 1, 0.02))
		await _sync()
		var bullet := _bullet(scene)
		_check(bullet.uses_swept_point_collision() and not bullet.hit_assist_enabled, profile_name + " uses unassisted point collision")
		_check(bullet.get_child_collision_shape() == null and bullet.get_shape_owners().is_empty(), profile_name + " has no physical projectile shape")
		_check(bullet.freeze and bullet.collision_layer == 0 and bullet.collision_mask == 0
			and not bullet.contact_monitor and not bullet.body_entered.is_connected(bullet._on_body_entered),
			profile_name + " has no physics contact path")
		bullet.fire(Vector3(0, 0, 2000), null)
		bullet._physics_process(1.0 / 60.0)
		_check(target.hits == 1 and is_equal_approx(target.damage_total, 5.0), profile_name + " hits a 2 cm plate within the first 33 m sweep from origin")
		_check(absf(target.hit_position.z - 3.99) < 0.002 and target.hit_shape == 0, profile_name + " preserves exact surface and shape attribution")
		bullet._physics_process(1.0 / 60.0)
		_check(target.hits == 1, profile_name + " damages once, not once per collision layer")
		await _sync()
		var reused := _bullet(scene)
		_check(reused == bullet, profile_name + " reuses its pooled projectile")
		# Actual surface begins at x=0.05: the point ray passes 5 cm clear. Even
		# a legacy assist flag or max-radius setting must not change this path.
		target.position.x = 0.55
		reused.hit_assist_enabled = true
		var prior_radius := ProjectileNew.get_hit_assist_radius_m()
		ProjectileNew.set_hit_assist_radius_m(6.0)
		await _sync()
		reused.fire(Vector3(0, 0, 2000), null)
		reused._physics_process(1.0 / 60.0)
		_check(target.hits == 1 and not reused.has_impacted, profile_name + " misses a surface 5 cm clear despite legacy assist settings")
		ProjectileNew.set_hit_assist_radius_m(prior_radius)
		reused.hit_assist_enabled = false
		# A source lifetime expires normally without running a second collision path.
		reused.lifetime = 0.02
		reused._physics_process(1.0 / 60.0)
		_check(reused.has_impacted, profile_name + " retains pool-aware lifetime expiry")

	await _fresh_arena()
	var wall := _target(Vector3(0, 0, 2), Vector3(1, 1, 0.02))
	var behind := _target(Vector3(0, 0, 4), Vector3(1, 1, 0.02))
	await _sync()
	var scene := preload("res://Projectiles/Bullet/bullet.tscn")
	var bullet := _bullet(scene)
	bullet.fire(Vector3(0, 0, 2000), null)
	bullet._physics_process(1.0 / 60.0)
	_check(wall.hits == 1 and behind.hits == 0, "Nearest real surface occludes targets farther along the sweep")

	await _fresh_arena()
	var shooter := Node3D.new()
	arena.add_child(shooter)
	var child_body := StaticBody3D.new()
	child_body.position.z = 1
	_box(child_body, Vector3.ZERO, Vector3.ONE)
	shooter.add_child(child_body)
	var component_target := Target.new()
	component_target.position.z = 4
	_box(component_target, Vector3(4, 0, 0), Vector3.ONE)
	_box(component_target, Vector3.ZERO, Vector3(1, 1, 0.02))
	arena.add_child(component_target)
	await _sync()
	bullet = _bullet(scene)
	bullet.fire(Vector3(0, 0, 2000), shooter)
	bullet._physics_process(1.0 / 60.0)
	_check(component_target.hits == 1 and component_target.hit_shape == 1,
		"Sweep skips firing-platform child bodies and preserves the victim's actual component index")

	await _fresh_arena()
	var enclosing := _target(Vector3.ZERO, Vector3.ONE)
	await _sync()
	bullet = _bullet(scene)
	bullet.fire(Vector3(0, 0, 2000), null)
	bullet._physics_process(1.0 / 60.0)
	_check(enclosing.hits == 1, "A bullet starting inside real geometry cannot escape through it")
	await _fresh_arena()
	var shifted_target := _target(Vector3(4000, 0, 4), Vector3(1, 1, 0.02))
	await _sync()
	bullet = _bullet(scene, Vector3(4000, 0, 0))
	bullet.fire(Vector3(0, 0, 2000), null)
	bullet._physics_process(0.001)
	get_node("/root/FloatingOrigin").shift_origin(Vector3(4000, 0, 0))
	_check(bullet.last_position.is_equal_approx(bullet.global_position), "Origin shift rebases the live sweep start exactly once")
	await _sync()
	bullet._physics_process(1.0 / 60.0)
	_check(shifted_target.hits == 1, "A shot after origin rebasing still hits the nearby real target")
	await _fresh_arena()
	var terrain := Target.new()
	var terrain_shape := CollisionShape3D.new()
	var mesh_shape := ConcavePolygonShape3D.new()
	mesh_shape.set_faces(PackedVector3Array([Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(0, 0, 10)]))
	terrain_shape.shape = mesh_shape
	terrain.add_child(terrain_shape)
	arena.add_child(terrain)
	await _sync()
	bullet = _bullet(scene, Vector3(0, 4, 0))
	bullet.fire(Vector3(0, -2000, 0), null)
	bullet._physics_process(1.0 / 60.0)
	_check(terrain.hits == 1 and absf(terrain.hit_position.y) < 0.002,
		"Swept point hits a zero-thickness terrain triangle without a height-map collision fallback")
	var rocket := preload("res://Projectiles/Rocket/rocket.tscn").instantiate()
	arena.add_child(rocket)
	_check(not rocket.uses_swept_point_collision() and rocket.contact_monitor
		and rocket.get_child_collision_shape() != null, "Rockets retain their independent physical collision path")
	print("BULLET_POINT_COLLISION_SMOKETEST checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
