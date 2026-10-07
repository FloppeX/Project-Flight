extends Building
## Persistent, independently damageable support building for an outpost.

const WRECK := preload("res://Buildings/building_enemy_vehicle_bay_destroyed.tscn")
var _shapes: Array[CollisionShape3D] = []
var _wreck: Node3D
@export var door_travel_time_s: float = 2.0
@export var deployment_open_time_s: float = 10.0
var _door: MeshInstance3D
var _door_shape: CollisionShape3D
var _door_closed: Transform3D
var _door_fraction := 0.0
var _door_hold_s := 0.0

func _ready() -> void:
	super._ready()
	_door = $Model.get_node("door") as MeshInstance3D
	_door_closed = _door.transform
	for mesh: MeshInstance3D in $Model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		var shape := CollisionShape3D.new()
		shape.shape = mesh.mesh.create_trimesh_shape()
		add_child(shape)
		shape.transform = global_transform.affine_inverse() * mesh.global_transform
		_shapes.append(shape)
		if mesh == _door: _door_shape = shape
	set_physics_process(false)

func begin_deployment() -> void:
	if is_destroyed: return
	_door_hold_s = maxf(deployment_open_time_s, door_travel_time_s)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if is_destroyed: return
	var opening := _door_hold_s > 0.0
	_door_hold_s = maxf(0.0, _door_hold_s - delta)
	_door_fraction = move_toward(_door_fraction, 1.0 if opening else 0.0, delta / maxf(door_travel_time_s, 0.01))
	_apply_door_pose()
	if _door_hold_s == 0.0 and _door_fraction == 0.0:
		set_physics_process(false)

func _apply_door_pose() -> void:
	# Retract like a shutter into the lintel: keep the upper edge fixed so the
	# panel is taken into the roof rather than emerging through its top surface.
	var pose := _door_closed
	pose.origin += _door_closed.basis.y * _door.mesh.get_aabb().end.y * _door_fraction
	pose.basis.y *= maxf(1.0 - _door_fraction, 0.001)
	_door.transform = pose
	_door.visible = _door_fraction < 1.0
	_door_shape.transform = global_transform.affine_inverse() * _door.global_transform
	_door_shape.set_deferred("disabled", is_destroyed or _door_fraction >= 1.0)

func _destroy() -> void:
	if is_destroyed: return
	_register_plasteel_salvage("Vehicle bay ruin salvage", 220.0)
	set_destroyed_state()
	EnemyOpsManager.report_asset_loss(global_position, "building")
	destroyed.emit(self)
	if _explosion_scene != null:
		var explosion := _explosion_scene.instantiate() as Node3D
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = global_position + Vector3.UP * 4.0
	_add_ruin_smoke(self)

func set_destroyed_state() -> void:
	is_destroyed = true
	set_physics_process(false)
	current_health = 0.0
	remove_from_group("enemies")
	remove_from_group("team_" + str(team))
	$Model.hide()
	for shape in _shapes: shape.set_deferred("disabled", true)
	if not is_instance_valid(_wreck):
		_wreck = WRECK.instantiate()
		_install_wreck.call_deferred()

func _install_wreck() -> void:
	if is_instance_valid(_wreck) and _wreck.get_parent() == null:
		add_child(_wreck)

func _exit_tree() -> void:
	if is_instance_valid(_wreck) and _wreck.get_parent() == null:
		_wreck.free()

func capture_save_state() -> Dictionary:
	return {"position": position, "rotation": rotation,
		"current_health": current_health, "is_destroyed": is_destroyed,
		"door_fraction": _door_fraction, "door_hold_s": _door_hold_s}

func restore_save_state(state: Dictionary) -> void:
	position = state.get("position", position)
	rotation = state.get("rotation", rotation)
	current_health = clampf(float(state.get("current_health", max_health)), 0.0, max_health)
	_door_fraction = clampf(float(state.get("door_fraction", 0.0)), 0.0, 1.0)
	_door_hold_s = maxf(float(state.get("door_hold_s", 0.0)), 0.0)
	_apply_door_pose()
	set_physics_process(_door_fraction > 0.0 or _door_hold_s > 0.0)
	if bool(state.get("is_destroyed", false)) or current_health <= 0.0:
		set_destroyed_state()
