extends Node

# Keeps inactive bullets out of the physics/render update loops and reuses them
# across bursts. Pools are keyed by PackedScene so alternate ammunition scenes
# cannot accidentally exchange instances.
@export var max_inactive_per_scene: int = 256
@export var max_inactive_total: int = 384

var _inactive_by_scene: Dictionary = {}
var _inactive_total: int = 0
var acquired_count: int = 0
var reused_count: int = 0
var released_count: int = 0

func acquire(scene: PackedScene, active_parent: Node, local_transform: Transform3D) -> Node:
	if scene == null or active_parent == null or not is_instance_valid(active_parent):
		return null
	var key: String = _scene_key(scene)
	var projectile: Node = _take_inactive(key)
	if projectile == null:
		projectile = scene.instantiate()
		if projectile == null:
			return null
		projectile.set_meta(&"_bullet_pool_key", key)
		if projectile is Node3D:
			(projectile as Node3D).transform = local_transform
		active_parent.add_child(projectile)
	else:
		projectile.reparent(active_parent, false)
		if projectile is Node3D:
			(projectile as Node3D).transform = local_transform
		reused_count += 1
	acquired_count += 1
	if projectile.has_method("prepare_for_reuse"):
		projectile.call("prepare_for_reuse")
	return projectile

func release(projectile: Node) -> void:
	if projectile == null or not is_instance_valid(projectile):
		return
	if projectile.get_meta(&"_bullet_pool_release_pending", false):
		return
	projectile.set_meta(&"_bullet_pool_release_pending", true)
	if projectile.has_method("prepare_for_pool"):
		projectile.call("prepare_for_pool")
	call_deferred("_release_deferred", projectile)

func _release_deferred(projectile: Node) -> void:
	if projectile == null or not is_instance_valid(projectile):
		return
	projectile.remove_meta(&"_bullet_pool_release_pending")
	var key: String = str(projectile.get_meta(&"_bullet_pool_key", ""))
	if key.is_empty() or _inactive_total >= max(max_inactive_total, 0):
		projectile.queue_free()
		return
	var pool_variant: Variant = _inactive_by_scene.get(key, [])
	var pool: Array = pool_variant if pool_variant is Array else []
	if pool.size() >= max(max_inactive_per_scene, 0):
		projectile.queue_free()
		return
	projectile.reparent(self, false)
	pool.append(projectile)
	_inactive_by_scene[key] = pool
	_inactive_total += 1
	released_count += 1

func _take_inactive(key: String) -> Node:
	var pool_variant: Variant = _inactive_by_scene.get(key, [])
	if not (pool_variant is Array):
		return null
	var pool: Array = pool_variant
	while not pool.is_empty():
		var candidate_variant: Variant = pool.pop_back()
		_inactive_total = maxi(_inactive_total - 1, 0)
		if typeof(candidate_variant) == TYPE_OBJECT and candidate_variant is Node and is_instance_valid(candidate_variant):
			_inactive_by_scene[key] = pool
			return candidate_variant as Node
	_inactive_by_scene[key] = pool
	return null

func _scene_key(scene: PackedScene) -> String:
	if not scene.resource_path.is_empty():
		return scene.resource_path
	return "packed_scene:%d" % scene.get_instance_id()

func get_stats() -> Dictionary:
	return {
		"inactive": _inactive_total,
		"acquired": acquired_count,
		"reused": reused_count,
		"released": released_count,
	}

func clear_inactive() -> void:
	for pool_variant in _inactive_by_scene.values():
		if not (pool_variant is Array):
			continue
		for projectile_variant in pool_variant as Array:
			if typeof(projectile_variant) == TYPE_OBJECT and projectile_variant is Node and is_instance_valid(projectile_variant):
				(projectile_variant as Node).queue_free()
	_inactive_by_scene.clear()
	_inactive_total = 0
