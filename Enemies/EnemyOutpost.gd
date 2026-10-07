class_name EnemyOutpost
extends Building
## A persistent observation station with a ground patrol and helicopter section.
## Destroyed stations remain as inert scenery so their loss survives checkpoints.

@export var outpost_id: String = "OP-01"
@export var faction_id: int = 0
@export var observation_radius_m: float = 4000.0
@export var report_delay_s: float = 15.0
@export var scan_interval_s: float = 3.0
@export var patrol_radius_m: float = 1200.0
@export var patrol_replacement_delay_s: float = 120.0
@export var helicopter_replacement_delay_s: float = 240.0
@export var radar_degrees_per_second: float = 30.0

var patrol_cooldown_s: float = 0.0
var helicopter_cooldown_s: float = 0.0
var _scan_timer: float = 0.0
var _pending_reports: Array[Dictionary] = []
var _radar: Node3D
var _radar_collision: CollisionShape3D
var _intact_collision_shapes: Array[CollisionShape3D] = []
var _destroyed_model: Node3D
const DESTROYED_SCENE := preload("res://Buildings/building_enemy_outpost_destroyed.tscn")
const VEHICLE_BAY_SCENE := preload("res://Buildings/building_enemy_vehicle_bay.tscn")

func add_vehicle_bay(local_position: Vector3) -> Building:
	var bay := VEHICLE_BAY_SCENE.instantiate() as Building
	bay.position = local_position
	add_child(bay)
	return bay

func can_support_patrols() -> bool:
	var bay := get_node_or_null("VehicleBay") as Building
	# Older checkpoints retain their original single-building behavior.
	return not is_destroyed and (bay == null or not bay.is_destroyed)

func on_patrol_deployed() -> void:
	var bay := get_node_or_null("VehicleBay")
	if bay != null: bay.begin_deployment()


func _ready() -> void:
	super._ready()
	add_to_group("enemy_outposts")
	add_to_group("origin_shifter")
	_radar = $Model.find_child("radar", true, false) as Node3D
	_build_collisions($Model)
	_scan_timer = float(posmod(hash(outpost_id), 100)) / 100.0 * scan_interval_s


func _build_collisions(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var shape := CollisionShape3D.new()
		shape.shape = node.mesh.create_trimesh_shape()
		add_child(shape)
		_intact_collision_shapes.append(shape)
		shape.transform = global_transform.affine_inverse() * node.global_transform
		if node == _radar:
			_radar_collision = shape
	for child in node.get_children():
		_build_collisions(child)


func _physics_process(delta: float) -> void:
	if is_destroyed or GameSession.has_pending_save_state() or GameSession.is_trailer_scenario:
		return
	if is_instance_valid(_radar):
		_radar.rotate_y(deg_to_rad(radar_degrees_per_second) * delta)
		if _radar_collision != null:
			_radar_collision.transform = global_transform.affine_inverse() * _radar.global_transform
	patrol_cooldown_s = maxf(0.0, patrol_cooldown_s - delta)
	helicopter_cooldown_s = maxf(0.0, helicopter_cooldown_s - delta)
	_service_reports(delta)
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = maxf(scan_interval_s, 0.25)
		_scan_contacts()


func _scan_contacts() -> void:
	var seen: Dictionary = {}
	for group in ["carrier", "aircraft", "ai_aircraft", "ground_vehicles"]:
		for value in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(value) or not value is Node3D:
				continue
			var target := value as Node3D
			if seen.has(target.get_instance_id()) or target.is_in_group("enemies"):
				continue
			seen[target.get_instance_id()] = true
			if target.has_method("get_team") and int(target.call("get_team")) != 1:
				continue
			if "is_destroyed" in target and bool(target.get("is_destroyed")):
				continue
			if not can_observe(target.global_position):
				continue
			var kind := "air"
			if target.is_in_group("carrier"):
				kind = "carrier"
			elif target.is_in_group("ground_vehicles"):
				kind = "ground"
			_queue_report(kind, target.global_position)


func can_observe(target_position: Vector3) -> bool:
	if is_destroyed or global_position.distance_to(target_position) > observation_radius_m:
		return false
	var eye := global_position + Vector3.UP * 12.0
	var target := target_position + Vector3.UP * 2.0
	var distance := Vector2(eye.x - target.x, eye.z - target.z).length()
	var steps := maxi(1, int(ceil(distance / 20.0)))
	for i in range(1, steps):
		var point := eye.lerp(target, float(i) / float(steps))
		var height := _terrain_height(point.x, point.z)
		# Unknown terrain must not become an accidental see-through region.
		if not is_finite(height) or height <= TerrainNavGrid.IMPASSABLE * 0.5 or height > point.y:
			return false
	return true


func _terrain_height(x: float, z: float) -> float:
	return sample_terrain_height(x, z)


static func sample_terrain_height(x: float, z: float) -> float:
	var terrain := TerrainReference.get_terrain_node()
	if is_instance_valid(terrain) and terrain.has_method("get_height"):
		return float(terrain.call("get_height", Vector3(x, 0, z)))
	return TerrainNavGrid.sample_height(x, z)


func _queue_report(kind: String, location: Vector3) -> void:
	# Keep the original observation; a delayed report is never a live target lock.
	for report in _pending_reports:
		if report.type == kind:
			return
	_pending_reports.append({"type": kind, "position": location, "countdown": report_delay_s})
	if kind == "carrier": EnemyOpsManager.notify_carrier_report_pending(self, outpost_id)


func _service_reports(delta: float) -> void:
	if is_destroyed:
		return
	for i in range(_pending_reports.size() - 1, -1, -1):
		_pending_reports[i].countdown -= delta
		if float(_pending_reports[i].countdown) <= 0.0:
			var report := _pending_reports[i]
			EnemyOpsManager.receive_intel(outpost_id, report.type, report.position, 1)
			_pending_reports.remove_at(i)


func _destroy() -> void:
	if is_destroyed:
		return
	_register_plasteel_salvage("Observation outpost ruin salvage", 300.0)
	_set_destroyed_state()
	EnemyOpsManager.report_asset_loss(global_position, "outpost")
	destroyed.emit(self)
	if _explosion_scene != null:
		var explosion := _explosion_scene.instantiate() as Node3D
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = global_position + Vector3.UP * 6.0
	_add_ruin_smoke(self)


func _set_destroyed_state() -> void:
	is_destroyed = true
	current_health = 0.0
	_pending_reports.clear()
	remove_from_group("enemies")
	remove_from_group("team_2")
	$Model.hide()
	for shape in _intact_collision_shapes:
		shape.set_deferred("disabled", true)
	if is_instance_valid(_radar):
		_radar.hide()
	if not is_instance_valid(_destroyed_model):
		_destroyed_model = DESTROYED_SCENE.instantiate() as Node3D
		_destroyed_model.name = "DestroyedModel"
		# Defer new physics shapes if a projectile hit triggered this swap.
		_install_destroyed_model.call_deferred()


func _install_destroyed_model() -> void:
	if is_instance_valid(_destroyed_model) and _destroyed_model.get_parent() == null:
		add_child(_destroyed_model)


func _exit_tree() -> void:
	# A load/test can leave the scene before the deferred collision installation.
	if is_instance_valid(_destroyed_model) and _destroyed_model.get_parent() == null:
		_destroyed_model.free()


func capture_save_state() -> Dictionary:
	var state := {"outpost_id": outpost_id, "faction_id": faction_id,
		"position": global_position, "rotation": rotation,
		"current_health": current_health, "is_destroyed": is_destroyed,
		"patrol_cooldown_s": patrol_cooldown_s,
		"helicopter_cooldown_s": helicopter_cooldown_s,
		"pending_reports": _pending_reports.duplicate(true)}
	var bay := get_node_or_null("VehicleBay")
	if bay != null: state["vehicle_bay"] = bay.capture_save_state()
	return state


func restore_save_state(state: Dictionary) -> void:
	if state.get("vehicle_bay") is Dictionary:
		var bay := get_node_or_null("VehicleBay")
		if bay == null: bay = add_vehicle_bay(Vector3.ZERO)
		bay.restore_save_state(state.vehicle_bay)
	current_health = clampf(float(state.get("current_health", max_health)), 0.0, max_health)
	patrol_cooldown_s = maxf(float(state.get("patrol_cooldown_s", 0.0)), 0.0)
	helicopter_cooldown_s = maxf(float(state.get("helicopter_cooldown_s", 0.0)), 0.0)
	_pending_reports.assign(state.get("pending_reports", []))
	if bool(state.get("is_destroyed", false)) or current_health <= 0.0:
		_set_destroyed_state()


func apply_origin_shift(offset: Vector3) -> void:
	# FloatingOrigin translates scene-root Node3Ds; only cached reports need shifting.
	for report in _pending_reports:
		report.position = (report.position as Vector3) - offset
