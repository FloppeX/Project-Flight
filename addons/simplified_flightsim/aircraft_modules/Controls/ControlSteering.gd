extends AircraftModule
class_name AircraftModule_ControlSteering

@export var ControlActive: bool = true
@export var input_curve: float = 1.8   # 1.0 = linear; >1 soft near center
@export var deadzone: float = 0.05
@export var rudder_assist_gain: float = 2.25
@export var rudder_assist_max_input: float = 1.0
@export var rudder_assist_yaw_rate_damping: float = 0.02
@export var rudder_assist_response_speed: float = 30.0
@export var rudder_assist_full_deflection_lateral_g: float = 0.35
@export var rudder_assist_velocity_slip_weight: float = 0.65
@export var rudder_assist_lateral_g_filter_speed: float = 18.0
@export var rudder_assist_center_deadzone: float = 0.055
@export var rudder_assist_manual_override_start: float = 0.05
@export var rudder_assist_manual_override_full: float = 0.30

var steering_module: Node = null
var simple_aero: Node = null
var aero_has_cmds := false
var _filtered_lateral_g: float = 0.0
var _previous_velocity: Vector3 = Vector3.ZERO
var _has_previous_velocity: bool = false
var _filtered_assist_yaw: float = 0.0

func setup(aircraft_node: Node) -> void:
	aircraft = aircraft_node

	# Grab the steering module provided by the addon
	var list = aircraft.find_modules_by_type("steering")
	if list and list.size() > 0:
		steering_module = list.pop_front()
	pass
	simple_aero = aircraft.get_node_or_null("SimpleAero")
	if simple_aero == null:
		simple_aero = aircraft.find_child("SimpleAero", true, false)
	if simple_aero != null and not _node_has_properties(simple_aero, ["pitch_input", "roll_input", "yaw_input"]):
		simple_aero = null

func _physics_process(delta: float) -> void:
	if (not ControlActive) or (steering_module == null):
		return

	# Raw inputs (actions must exist in InputMap)
	var roll_raw  := Input.get_action_strength("roll_right") - Input.get_action_strength("roll_left")
	var pitch_raw := Input.get_action_strength("pitch_up")   - Input.get_action_strength("pitch_down")
	var yaw_raw   := Input.get_action_strength("yaw_left")   - Input.get_action_strength("yaw_right")

	# Shape them
	var roll  := _shape_input(roll_raw)
	var pitch := _shape_input(pitch_raw)
	var yaw   := _shape_input(yaw_raw)
	var assisted_yaw := _apply_rudder_assist(yaw, delta)

	# Drive control surfaces (addon uses z=roll, x=pitch, y=yaw)
	steering_module.set_z(roll)
	steering_module.set_x(pitch)
	steering_module.set_y(assisted_yaw)

	# Feed the same to SimpleAero if present and compatible
	if simple_aero != null and is_instance_valid(simple_aero):
		simple_aero.pitch_input = pitch
		simple_aero.roll_input = -roll
		simple_aero.yaw_input = assisted_yaw

func _shape_input(v: float) -> float:
	if absf(v) < deadzone:
		return 0.0
	var s := (absf(v) - deadzone) / (1.0 - deadzone)
	if input_curve != 1.0:
		s = pow(s, input_curve)
	return s * signf(v)


func _apply_rudder_assist(manual_yaw: float, delta: float) -> float:
	var assist_strength := _get_rudder_assist_strength()
	if assist_strength <= 0.0 or aircraft == null or not is_instance_valid(aircraft) or not (aircraft is RigidBody3D):
		_reset_rudder_assist_state()
		return manual_yaw

	var slip_error := _estimate_slip_ball_error(delta)
	if absf(slip_error) < rudder_assist_center_deadzone:
		slip_error = 0.0

	var basis := (aircraft as Node3D).global_transform.basis.orthonormalized()
	var yaw_rate := 0.0
	if aircraft is RigidBody3D:
		yaw_rate = (aircraft as RigidBody3D).angular_velocity.dot(basis.y)

	var target_assist := -slip_error * rudder_assist_gain - yaw_rate * rudder_assist_yaw_rate_damping
	target_assist = clampf(
		target_assist,
		-rudder_assist_max_input,
		rudder_assist_max_input
	) * assist_strength

	var response_t := clampf(delta * maxf(rudder_assist_response_speed, 0.1), 0.0, 1.0)
	_filtered_assist_yaw = lerpf(_filtered_assist_yaw, target_assist, response_t)

	var manual_fade := 1.0 - _smoothstep(
		rudder_assist_manual_override_start,
		maxf(rudder_assist_manual_override_full, rudder_assist_manual_override_start + 0.01),
		absf(manual_yaw)
	)
	return clampf(manual_yaw + _filtered_assist_yaw * manual_fade, -1.0, 1.0)


func _estimate_slip_ball_error(delta: float) -> float:
	var rb := aircraft as RigidBody3D
	if rb == null:
		return 0.0
	var velocity: Vector3 = rb.linear_velocity
	var basis := rb.global_transform.basis.orthonormalized()
	var local_velocity: Vector3 = basis.inverse() * velocity
	var reference_speed := maxf(absf(local_velocity.z), 20.0)
	var velocity_slip := clampf(local_velocity.x / reference_speed, -1.0, 1.0)

	var lateral_g := 0.0
	if _has_previous_velocity and delta > 0.0001:
		var acceleration := (velocity - _previous_velocity) / delta
		var gravity := Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.80665))
		var specific_force := acceleration - gravity
		var local_specific_force := basis.inverse() * specific_force
		lateral_g = local_specific_force.x / 9.80665
	_previous_velocity = velocity
	_has_previous_velocity = true

	var lateral_filter_t := clampf(delta * maxf(rudder_assist_lateral_g_filter_speed, 0.1), 0.0, 1.0)
	_filtered_lateral_g = lerpf(_filtered_lateral_g, lateral_g, lateral_filter_t)

	var force_slip := _filtered_lateral_g / maxf(rudder_assist_full_deflection_lateral_g, 0.05)
	return clampf(force_slip + velocity_slip * maxf(rudder_assist_velocity_slip_weight, 0.0), -1.0, 1.0)


func _get_rudder_assist_strength() -> float:
	var pause_menu := get_node_or_null("/root/PauseMenu")
	if pause_menu != null and pause_menu.has_method("get_rudder_assist_strength"):
		return clampf(float(pause_menu.call("get_rudder_assist_strength")), 0.0, 1.0)
	return 0.0


func _reset_rudder_assist_state() -> void:
	_filtered_lateral_g = 0.0
	_filtered_assist_yaw = 0.0
	_has_previous_velocity = false


func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / maxf(edge1 - edge0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _node_has_properties(n: Object, names: Array) -> bool:
	var plist := n.get_property_list()
	var have := {}
	for p in plist:
		have[p.name] = true
	for name in names:
		if not have.has(name):
			return false
	return true
