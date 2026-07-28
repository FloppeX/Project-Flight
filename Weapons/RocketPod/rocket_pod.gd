extends Weapon
class_name RocketPod

const HELI_TEST_UNLIMITED_AMMO_META := "heli_test_unlimited_ammo"
const AIRPLANE_TEST_PERSISTENT_TUNING_META := "airplane_test_persistent_rocket_tuning"

@export var rocket_scene: PackedScene
@export var muzzle_velocity: float = 220.0
@export var fire_cooldown_s: float = 0.35
@export var burst_count: int = 6
@export var burst_interval_s: float = 0.07
@export var pod_empty_mass_kg: float = 80.0
@export var rocket_mass_kg: float = 5.0

var hardpoint: Hardpoint
var _fire_timer: float = 0.0
var _burst_remaining: int = 0
var _burst_timer: float = 0.0
var _payload_aircraft: RigidBody3D = null
var _tuning_launch_callback: Callable = Callable()
var _tuning_impact_callback: Callable = Callable()
var _tuning_impact_detail_callback: Callable = Callable()
var _tuning_trial_id: int = -1
var _tuning_target: Node3D = null

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

func _has_unlimited_test_ammo() -> bool:
	var aircraft: RigidBody3D = _get_parent_rigidbody()
	if aircraft == null or not is_instance_valid(aircraft):
		return false
	var value: Variant = aircraft.get_meta(HELI_TEST_UNLIMITED_AMMO_META, false)
	if not (value is bool):
		return false
	var enabled: bool = value
	return enabled

func _has_persistent_tuning_context() -> bool:
	var aircraft: RigidBody3D = _get_parent_rigidbody()
	if aircraft == null or not is_instance_valid(aircraft):
		return false
	var value: Variant = aircraft.get_meta(AIRPLANE_TEST_PERSISTENT_TUNING_META, false)
	if not (value is bool):
		return false
	var enabled: bool = value
	return enabled

func _refresh_aircraft_payload_mass() -> void:
	if not is_instance_valid(_payload_aircraft):
		_payload_aircraft = _get_parent_rigidbody()
	if _payload_aircraft and _payload_aircraft.has_method("set_payload_mass"):
		var total_mass_kg: float = maxf(pod_empty_mass_kg, 0.0) + maxf(float(ammo_count), 0.0) * maxf(rocket_mass_kg, 0.0)
		_payload_aircraft.set_payload_mass(self, total_mass_kg)

func get_predicted_release_transform() -> Transform3D:
	return global_transform

func get_predicted_initial_velocity(aircraft: RigidBody3D) -> Vector3:
	var release_transform: Transform3D = get_predicted_release_transform()
	var launch_dir: Vector3 = global_transform.basis.z
	if hardpoint:
		launch_dir = hardpoint.get_hardpoint_forward_direction()
	var initial_velocity: Vector3 = launch_dir * muzzle_velocity
	if aircraft == null:
		return initial_velocity
	initial_velocity += aircraft.linear_velocity
	var r_offset: Vector3 = release_transform.origin - aircraft.global_position
	initial_velocity += aircraft.angular_velocity.cross(r_offset)
	return initial_velocity

func _process(delta: float) -> void:
	if _fire_timer > 0.0:
		_fire_timer -= delta
	if _burst_remaining > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_fire_one_rocket()
			_burst_remaining -= 1
			_burst_timer = burst_interval_s
			if _burst_remaining <= 0:
				if not _has_persistent_tuning_context():
					_clear_tuning_context()


func set_tuning_context(
		launch_callback: Callable,
		impact_callback: Callable,
		trial_id: int,
		target: Node3D,
		impact_detail_callback: Callable = Callable()
) -> void:
	_tuning_launch_callback = launch_callback
	_tuning_impact_callback = impact_callback
	_tuning_impact_detail_callback = impact_detail_callback
	_tuning_trial_id = trial_id
	_tuning_target = target


func _clear_tuning_context() -> void:
	_tuning_launch_callback = Callable()
	_tuning_impact_callback = Callable()
	_tuning_impact_detail_callback = Callable()
	_tuning_trial_id = -1
	_tuning_target = null

func can_fire() -> bool:
	return (_has_unlimited_test_ammo() or ammo_count > 0) and _fire_timer <= 0.0 and _burst_remaining == 0

func is_burst_in_progress() -> bool:
	return _burst_remaining > 0

func fire() -> bool:
	if not can_fire():
		return false
	var unlimited_ammo: bool = _has_unlimited_test_ammo()
	_fire_timer = fire_cooldown_s
	_fire_one_rocket()
	_burst_remaining = maxi(burst_count - 1, 0) if unlimited_ammo else mini(maxi(burst_count - 1, 0), ammo_count)
	_burst_timer = burst_interval_s
	if _burst_remaining <= 0 and not _has_persistent_tuning_context():
		_clear_tuning_context()
	return true

func _fire_one_rocket() -> void:
	var unlimited_ammo: bool = _has_unlimited_test_ammo()
	if ammo_count <= 0 and not unlimited_ammo:
		_burst_remaining = 0
		return
	var rocket = rocket_scene.instantiate()
	rocket.position = global_position
	rocket.rotation = global_rotation
	get_tree().current_scene.add_child(rocket)
	if _tuning_impact_callback.is_valid() and _tuning_trial_id >= 0 and rocket.has_signal("tuning_impact"):
		var impact_callback_args: int = _get_callable_argument_count(_tuning_impact_callback, 3)
		var impact_callback: Callable = _tuning_impact_callback.bind(_tuning_trial_id, _tuning_target, rocket) \
				if impact_callback_args >= 4 else _tuning_impact_callback.bind(_tuning_trial_id, _tuning_target)
		rocket.connect(
			"tuning_impact",
			impact_callback,
			CONNECT_ONE_SHOT
		)
	if _tuning_impact_detail_callback.is_valid() and _tuning_trial_id >= 0 and rocket.has_signal("tuning_impact_detail"):
		var detail_callback_args: int = _get_callable_argument_count(_tuning_impact_detail_callback, 4)
		var detail_callback: Callable = _tuning_impact_detail_callback.bind(_tuning_trial_id, _tuning_target, rocket) \
				if detail_callback_args >= 5 else _tuning_impact_detail_callback.bind(_tuning_trial_id, _tuning_target)
		rocket.connect(
			"tuning_impact_detail",
			detail_callback,
			CONNECT_ONE_SHOT
		)
	var muzzle_vel := hardpoint.get_hardpoint_forward_direction() * muzzle_velocity
	rocket.fire(muzzle_vel, hardpoint.aircraft)
	# Report the launch after fire() has installed the rocket's real inherited
	# platform velocity. Test diagnostics can now compare the predictor against
	# the exact initial state used by the live projectile.
	_call_tuning_launch_callback(rocket)
	if not unlimited_ammo:
		ammo_count -= 1
		_refresh_aircraft_payload_mass()


func _get_callable_argument_count(callback: Callable, fallback: int) -> int:
	var callback_object: Object = callback.get_object()
	if callback_object == null or not is_instance_valid(callback_object):
		return fallback
	var callback_method: StringName = callback.get_method()
	for method_info_value: Variant in callback_object.get_method_list():
		if not method_info_value is Dictionary:
			continue
		var method_info: Dictionary = method_info_value as Dictionary
		if str(method_info.get("name", "")) != str(callback_method):
			continue
		var args_value: Variant = method_info.get("args", [])
		if args_value is Array:
			var args: Array = args_value as Array
			return args.size()
		return fallback
	return fallback


func _call_tuning_launch_callback(rocket: Node) -> void:
	if not _tuning_launch_callback.is_valid() or _tuning_trial_id < 0:
		return
	var argument_count: int = _get_callable_argument_count(_tuning_launch_callback, 1)
	if argument_count >= 3:
		_tuning_launch_callback.call(_tuning_trial_id, rocket, _tuning_target)
	elif argument_count >= 2:
		_tuning_launch_callback.call(_tuning_trial_id, rocket)
	else:
		_tuning_launch_callback.call(_tuning_trial_id)
