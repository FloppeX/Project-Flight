extends Weapon
class_name BombRack

@export var bomb_projectile_scene: PackedScene
@export var drop_force: float = 0.0
@export var fire_cooldown: float = 0.2
@export var bomb_mass_kg: float = 50.0
@export var debug_drop_logging: bool = false

var hardpoint: Hardpoint
var _slots: Array[Node3D] = []
var _last_fire_time: float = 0.0
var last_bomb_dropped: BombProjectile = null
var _pending_debug_aim_target: Vector3 = Vector3.ZERO
var _pending_debug_predicted_impact: Vector3 = Vector3.ZERO
var _has_pending_debug_metadata: bool = false
var _payload_aircraft: RigidBody3D = null

func _ready() -> void:
	weapon_name = "Bomb"
	delete_when_empty = false
	automatic_fire = false
	hardpoint = get_parent() as Hardpoint
	for child in get_children():
		if child.name.begins_with("BombSlot"):
			_slots.append(child as Node3D)
	ammo_count = _slots.size()
	if bomb_projectile_scene == null:
		bomb_projectile_scene = load("res://Projectiles/BombNew/bomb_new.tscn")
	_refresh_aircraft_payload_mass()

func _exit_tree() -> void:
	if is_instance_valid(_payload_aircraft) and _payload_aircraft.has_method("clear_payload_mass"):
		_payload_aircraft.clear_payload_mass(self)

func _get_parent_rigidbody() -> RigidBody3D:
	var node: Node = get_parent()
	while node and not (node is RigidBody3D):
		node = node.get_parent()
	return node as RigidBody3D

func _refresh_aircraft_payload_mass() -> void:
	if not is_instance_valid(_payload_aircraft):
		_payload_aircraft = _get_parent_rigidbody()
	if _payload_aircraft and _payload_aircraft.has_method("set_payload_mass"):
		_payload_aircraft.set_payload_mass(self, maxf(float(ammo_count), 0.0) * maxf(bomb_mass_kg, 0.0))

func _get_physics_step_s() -> float:
	var ticks_per_second: float = float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60.0))
	return 1.0 / maxf(ticks_per_second, 1.0)

func set_next_bomb_debug_metadata(aim_target: Vector3, predicted_impact: Vector3 = Vector3.ZERO) -> void:
	_pending_debug_aim_target = aim_target
	_pending_debug_predicted_impact = predicted_impact
	_has_pending_debug_metadata = true

func get_predicted_release_transform() -> Transform3D:
	if _slots.is_empty():
		return hardpoint.global_transform if hardpoint else global_transform
	var slot: Node3D = _slots[_slots.size() - 1]
	if slot == null or not is_instance_valid(slot):
		return hardpoint.global_transform if hardpoint else global_transform
	var visible_bomb: Node3D = slot.get_node_or_null("bomb") as Node3D
	var release_transform: Transform3D = visible_bomb.global_transform if visible_bomb else slot.global_transform
	var aircraft: RigidBody3D = _get_parent_rigidbody()
	if aircraft == null:
		return release_transform

	var dt: float = _get_physics_step_s()
	var predicted_basis: Basis = release_transform.basis
	var predicted_origin: Vector3 = release_transform.origin
	var angular_speed: float = aircraft.angular_velocity.length()
	if angular_speed > 0.0001:
		var rot: Basis = Basis(aircraft.angular_velocity.normalized(), angular_speed * dt)
		var future_center: Vector3 = aircraft.global_position + aircraft.linear_velocity * dt
		var rel: Vector3 = release_transform.origin - aircraft.global_position
		predicted_origin = future_center + rot * rel
		predicted_basis = rot * predicted_basis
	else:
		predicted_origin += aircraft.linear_velocity * dt
	return Transform3D(predicted_basis, predicted_origin)

func get_predicted_initial_velocity(aircraft: RigidBody3D) -> Vector3:
	var aircraft_velocity: Vector3 = aircraft.linear_velocity if aircraft else Vector3.ZERO
	return Vector3.DOWN * drop_force + aircraft_velocity

func can_fire() -> bool:
	var t := Time.get_ticks_msec() / 1000.0
	return ammo_count > 0 and (t - _last_fire_time) >= fire_cooldown

func fire() -> bool:
	if not can_fire():
		return false
	_last_fire_time = Time.get_ticks_msec() / 1000.0

	var slot: Node3D = _slots.pop_back()
	slot.visible = false
	_spawn_bomb_next_physics(slot)

	ammo_count -= 1
	_refresh_aircraft_payload_mass()
	if delete_when_empty and ammo_count <= 0:
		queue_free()
	return true

func _spawn_bomb_next_physics(slot: Node3D) -> void:
	await get_tree().physics_frame
	if not is_instance_valid(slot):
		return

	var visible_bomb: Node3D = slot.get_node_or_null("bomb") as Node3D
	var release_transform: Transform3D = visible_bomb.global_transform if visible_bomb else slot.global_transform
	var slot_pos: Vector3 = slot.global_position

	var proj: BombProjectile = bomb_projectile_scene.instantiate()
	var release_basis: Basis = release_transform.basis.orthonormalized()
	var src_rot: Basis = proj.transform.basis.orthonormalized()
	var src_scale: Vector3 = proj.transform.basis.get_scale()
	var final_basis: Basis = release_basis * src_rot
	final_basis = final_basis.scaled(src_scale)
	proj.transform = Transform3D(final_basis, release_transform.origin)
	get_tree().current_scene.add_child(proj)
	proj.reset_physics_interpolation()

	var aircraft_node: Node = get_parent()
	while aircraft_node and not (aircraft_node is RigidBody3D):
		aircraft_node = aircraft_node.get_parent()
	var aircraft := aircraft_node as RigidBody3D

	var aircraft_velocity := aircraft.linear_velocity if aircraft else Vector3.ZERO
	var initial_velocity := Vector3.DOWN * drop_force + aircraft_velocity
	proj.fire(initial_velocity, aircraft)
	last_bomb_dropped = proj
	if _has_pending_debug_metadata:
		proj.set_meta("debug_aim_target", _pending_debug_aim_target)
		proj.set_meta("debug_predicted_impact", _pending_debug_predicted_impact)
		_has_pending_debug_metadata = false
		_pending_debug_aim_target = Vector3.ZERO
		_pending_debug_predicted_impact = Vector3.ZERO

	if debug_drop_logging:
		print("=== BOMB DROP ===")
		print("  slot release pos : ", snapped(slot_pos, Vector3.ONE * 0.001))
		print("  visual bomb pos  : ", snapped(release_transform.origin, Vector3.ONE * 0.001))
		print("  bomb global pos  : ", snapped(proj.global_position, Vector3.ONE * 0.001))
		print("  offset (bomb-visual): ", snapped(proj.global_position - release_transform.origin, Vector3.ONE * 0.001))
		print("  initial velocity : ", snapped(initial_velocity, Vector3.ONE * 0.01))
		print("  aircraft vel     : ", snapped(aircraft_velocity, Vector3.ONE * 0.01))
		proj.set_meta("_debug_track", true)

	slot.queue_free()
