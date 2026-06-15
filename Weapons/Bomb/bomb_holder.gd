extends Weapon
class_name BombHolder

const HELI_TEST_UNLIMITED_AMMO_META := "heli_test_unlimited_ammo"

@export var bomb_projectile_scene: PackedScene
@export var drop_force: float = 0.0
@export var blast_radius: float = 10.0
@export var fire_cooldown: float = 0.1  # Minimum time between bomb drops
@export var bomb_mass_kg: float = 50.0

var hardpoint: Hardpoint
var last_fire_time: float = 0.0
var last_bomb_dropped: BombProjectile = null  # Set after each drop for debug access
var _pending_debug_aim_target: Vector3 = Vector3.ZERO
var _pending_debug_predicted_impact: Vector3 = Vector3.ZERO
var _has_pending_debug_metadata: bool = false
var _payload_aircraft: RigidBody3D = null

func _get_release_transform(node: Node3D) -> Transform3D:
	if node == null:
		return Transform3D.IDENTITY
	if node.has_method("get_global_transform_interpolated"):
		var interpolated: Variant = node.call("get_global_transform_interpolated")
		if interpolated is Transform3D:
			return interpolated
	return node.global_transform

func _ready():
	delete_when_empty = true
	hardpoint = get_parent() as Hardpoint
	automatic_fire = false  # Bombs are single-shot weapons
	ammo_count = 50
	weapon_name = "Bomb"  # Set weapon type name
	_refresh_aircraft_payload_mass()

func _exit_tree() -> void:
	if is_instance_valid(_payload_aircraft) and _payload_aircraft.has_method("clear_payload_mass"):
		_payload_aircraft.clear_payload_mass(self)

func _get_parent_rigidbody() -> RigidBody3D:
	var node: Node = get_parent()
	while node and not (node is RigidBody3D):
		node = node.get_parent()
	return node as RigidBody3D

func _has_unlimited_test_ammo() -> bool:
	var aircraft: RigidBody3D = _get_parent_rigidbody()
	if aircraft == null or not is_instance_valid(aircraft):
		return false
	var value: Variant = aircraft.get_meta(HELI_TEST_UNLIMITED_AMMO_META, false)
	if not (value is bool):
		return false
	var enabled: bool = value
	return enabled

func _get_remaining_visible_bombs() -> int:
	var visible_bomb: Node3D = get_node_or_null("bomb") as Node3D
	return 1 if visible_bomb and visible_bomb.visible else 0

func _refresh_aircraft_payload_mass() -> void:
	if not is_instance_valid(_payload_aircraft):
		_payload_aircraft = _get_parent_rigidbody()
	if _payload_aircraft and _payload_aircraft.has_method("set_payload_mass"):
		_payload_aircraft.set_payload_mass(self, float(_get_remaining_visible_bombs()) * maxf(bomb_mass_kg, 0.0))

func get_predicted_release_transform() -> Transform3D:
	if hardpoint:
		return hardpoint.global_transform
	return global_transform

func get_predicted_initial_velocity(aircraft: RigidBody3D) -> Vector3:
	var aircraft_velocity: Vector3 = aircraft.linear_velocity if aircraft else Vector3.ZERO
	return Vector3.DOWN * drop_force + aircraft_velocity

func set_next_bomb_debug_metadata(aim_target: Vector3, predicted_impact: Vector3 = Vector3.ZERO) -> void:
	_pending_debug_aim_target = aim_target
	_pending_debug_predicted_impact = predicted_impact
	_has_pending_debug_metadata = true

func can_fire() -> bool:
	# Check ammo and cooldown
	var current_time: float = Time.get_ticks_msec() / 1000.0
	return (_has_unlimited_test_ammo() or ammo_count > 0) and (current_time - last_fire_time) >= fire_cooldown

func fire() -> bool:
	if not can_fire():
		return false
	var unlimited_ammo: bool = _has_unlimited_test_ammo()
	
	# Update last fire time
	last_fire_time = Time.get_ticks_msec() / 1000.0

	var visible_bomb: Node3D = get_node_or_null("bomb") as Node3D
	if visible_bomb and not unlimited_ammo:
		visible_bomb.visible = false
	
	# Create and drop bomb projectile
	var bomb_projectile: BombProjectile = bomb_projectile_scene.instantiate()

	# Set transform BEFORE adding to tree so first-frame visuals don't flash at the origin
	if hardpoint:
		var hp_tr: Transform3D = _get_release_transform(hardpoint)
		var hp_rot: Basis = hp_tr.basis.orthonormalized()
		var src_rot: Basis = bomb_projectile.transform.basis.orthonormalized()
		var src_scale: Vector3 = bomb_projectile.transform.basis.get_scale()
		var final_basis: Basis = hp_rot * src_rot
		final_basis = final_basis.scaled(src_scale)
		bomb_projectile.transform = Transform3D(final_basis, hp_tr.origin)
	else:
		# Fallback: keep current position and remove any inherited scale
		bomb_projectile.position = global_position
		bomb_projectile.transform.basis = Basis.IDENTITY
		bomb_projectile.scale = Vector3.ONE
	get_tree().current_scene.add_child(bomb_projectile)
	bomb_projectile.reset_physics_interpolation()

	# Get the aircraft from the hardpoint (parent)
	var aircraft_node: Node = get_parent()
	while aircraft_node and not (aircraft_node is RigidBody3D):
		aircraft_node = aircraft_node.get_parent()
	var aircraft: RigidBody3D = aircraft_node as RigidBody3D
	
	# Calculate drop velocity - inherit aircraft velocity for realistic ballistics
	var aircraft_velocity: Vector3 = aircraft.linear_velocity if aircraft else Vector3.ZERO
	var drop_velocity: Vector3 = Vector3.DOWN * drop_force + aircraft_velocity
	
	# Use the projectile's fire method
	bomb_projectile.fire(drop_velocity, aircraft)
	last_bomb_dropped = bomb_projectile  # Expose for debug access by AI
	if _has_pending_debug_metadata:
		bomb_projectile.set_meta("debug_aim_target", _pending_debug_aim_target)
		bomb_projectile.set_meta("debug_predicted_impact", _pending_debug_predicted_impact)
		_has_pending_debug_metadata = false
		_pending_debug_aim_target = Vector3.ZERO
		_pending_debug_predicted_impact = Vector3.ZERO

	if not unlimited_ammo:
		ammo_count -= 1
		_refresh_aircraft_payload_mass()

		# Self-destruct if enabled and empty
		if delete_when_empty and ammo_count <= 0:
			queue_free()
	
	return true
