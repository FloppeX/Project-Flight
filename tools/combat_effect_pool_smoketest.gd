extends Node3D

const EXPLOSION_SCENE: PackedScene = preload("res://Projectiles/Explosion/explosion.tscn")
const SMALL_EXPLOSIVE_ROUND_SCENE: PackedScene = preload("res://Projectiles/SmallExplosiveRound/small_explosive_round.tscn")
const BURST_SIZE: int = 48

var _failures: Array[String] = []

func _ready() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = Vector3(0.0, 18.0, 45.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true

	await get_tree().process_frame
	await _verify_small_round_reuse()
	var cold_us: int = _spawn_burst()
	await get_tree().create_timer(1.8).timeout
	var after_cold: Dictionary = ParticleManager.get_managed_effect_stats()
	_assert(int(after_cold.get("active", -1)) == 0, "cold burst effects did not return to the pool")
	_assert(int(after_cold.get("pooled", 0)) > 0, "cold burst did not populate the managed pool")
	_assert(_count_explosion_nodes(self) == 0, "explosion coordinator nodes leaked after cold burst")

	var warm_us: int = _spawn_burst()
	var during_warm: Dictionary = ParticleManager.get_managed_effect_stats()
	_assert(int(during_warm.get("active", 0)) > 0, "warm burst produced no managed effects")
	await get_tree().create_timer(1.8).timeout
	var after_warm: Dictionary = ParticleManager.get_managed_effect_stats()
	_assert(int(after_warm.get("active", -1)) == 0, "warm burst effects did not return to the pool")
	_assert(_count_explosion_nodes(self) == 0, "explosion coordinator nodes leaked after warm burst")

	var smoke_spawned: int = 0
	for i in range(64):
		if ParticleManager.spawn_managed_smoke(
			Vector3(float(i % 8) - 3.5, 0.0, float(i / 8) - 3.5),
			Vector3.ONE,
			Color(0.9, 0.9, 0.9, 0.8),
			0.35,
			0.0,
			0.0,
			false,
			"box"
		):
			smoke_spawned += 1
	_assert(smoke_spawned > 0, "managed smoke pool rejected every nearby puff")
	await get_tree().create_timer(0.8).timeout
	var after_smoke: Dictionary = ParticleManager.get_managed_effect_stats()
	_assert(int(after_smoke.get("active", -1)) == 0, "managed smoke did not return to the pool")

	print("COMBAT_EFFECT_POOL_SMOKETEST ", JSON.stringify({
		"burst_size": BURST_SIZE,
		"cold_spawn_us": cold_us,
		"warm_spawn_us": warm_us,
		"warm_to_cold_ratio": float(warm_us) / maxf(float(cold_us), 1.0),
		"pooled_after_warm": int(after_smoke.get("pooled", 0)),
		"managed_smoke_spawned": smoke_spawned,
		"managed_meshes_created": int(after_smoke.get("meshes_created", 0)),
		"managed_meshes_reused": int(after_smoke.get("meshes_reused", 0)),
		"managed_spawns_rejected": int(after_smoke.get("spawn_rejected", 0)),
		"failures": _failures,
	}))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _verify_small_round_reuse() -> void:
	var first_round: Node = BulletPool.acquire(SMALL_EXPLOSIVE_ROUND_SCENE, self, Transform3D.IDENTITY)
	_assert(first_round != null, "could not acquire small explosive round")
	if first_round == null:
		return
	var first_id: int = first_round.get_instance_id()
	first_round.call("_retire_projectile")
	await get_tree().process_frame
	await get_tree().process_frame
	var second_round: Node = BulletPool.acquire(SMALL_EXPLOSIVE_ROUND_SCENE, self, Transform3D.IDENTITY)
	_assert(second_round != null, "could not reacquire small explosive round")
	if second_round == null:
		return
	_assert(second_round.get_instance_id() == first_id, "small explosive round bypassed BulletPool reuse")
	BulletPool.release(second_round)
	await get_tree().process_frame

func _spawn_burst() -> int:
	var start_us: int = Time.get_ticks_usec()
	for i in range(BURST_SIZE):
		var explosion := EXPLOSION_SCENE.instantiate() as Explosion
		add_child(explosion)
		explosion.global_position = Vector3(
			(float(i % 12) - 5.5) * 1.2,
			0.0,
			(float(i / 12) - 1.5) * 1.2
		)
		explosion.blast_radius = 4.0
		explosion.flash_duration = 0.12
		explosion.effect_duration = 0.45
		explosion.debris_count = 3
		explosion.max_damage = 0.0
		explosion.min_damage = 0.0
		explosion.knockback_impulse_at_center = 0.0
		explosion.knockback_impulse_at_edge = 0.0
		explosion.use_line_of_sight = false
		explosion.visual_preset = Explosion.VisualPreset.LIGHT
		explosion.play_explosion_audio = false
		# Trigger synchronously so the timing includes presentation acquisition and
		# cold resource construction. The deferred _ready callback is idempotent.
		explosion.trigger_explosion()
	return Time.get_ticks_usec() - start_us

func _count_explosion_nodes(root: Node) -> int:
	var count: int = 1 if root is Explosion else 0
	for child in root.get_children():
		count += _count_explosion_nodes(child)
	return count

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
