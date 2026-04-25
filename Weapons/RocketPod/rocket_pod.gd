extends Weapon
class_name RocketPod

@export var rocket_scene: PackedScene
@export var muzzle_velocity: float = 0.0
@export var fire_cooldown_s: float = 0.35
@export var pod_empty_mass_kg: float = 80.0
@export var rocket_mass_kg: float = 5.0

var hardpoint: Hardpoint
var _fire_timer: float = 0.0
var _payload_aircraft: RigidBody3D = null

func _ready() -> void:
	weapon_name = "Rocket Pod"
	delete_when_empty = false
	automatic_fire = false
	hardpoint = get_parent() as Hardpoint
	if rocket_scene == null:
		rocket_scene = load("res://Projectiles/Rocket/rocket.tscn")
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
		var total_mass_kg: float = maxf(pod_empty_mass_kg, 0.0) + maxf(float(ammo_count), 0.0) * maxf(rocket_mass_kg, 0.0)
		_payload_aircraft.set_payload_mass(self, total_mass_kg)

func get_predicted_release_transform() -> Transform3D:
	if hardpoint:
		return hardpoint.global_transform
	return global_transform

func get_predicted_initial_velocity(aircraft: RigidBody3D) -> Vector3:
	var release_transform: Transform3D = get_predicted_release_transform()
	var initial_velocity: Vector3 = release_transform.basis.z * muzzle_velocity
	if aircraft == null:
		return initial_velocity
	initial_velocity += aircraft.linear_velocity
	var r_offset: Vector3 = release_transform.origin - aircraft.global_position
	initial_velocity += aircraft.angular_velocity.cross(r_offset)
	return initial_velocity

func _process(delta: float) -> void:
	if _fire_timer > 0.0:
		_fire_timer -= delta

func can_fire() -> bool:
	return ammo_count > 0 and _fire_timer <= 0.0

func fire() -> bool:
	if not can_fire():
		return false
	_fire_timer = fire_cooldown_s

	var rocket = rocket_scene.instantiate()
	rocket.position = global_position
	rocket.rotation = global_rotation
	get_tree().current_scene.add_child(rocket)

	var muzzle_vel := hardpoint.get_hardpoint_forward_direction() * muzzle_velocity
	rocket.fire(muzzle_vel, hardpoint.aircraft)

	ammo_count -= 1
	_refresh_aircraft_payload_mass()
	return true
