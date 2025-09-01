extends Node
class_name SimpleAeroChatGPT

@export var rb_path: NodePath
var rb: RigidBody3D

# --- Geometry / scaling ---
@export var wing_area: float = 8.0
@export var mean_chord: float = 1.2
@export var air_density: float = 1.225
@export var aero_scale: float = 0.05

# --- Lift/drag model (AoA-based) ---
@export var cl_alpha_per_rad: float = 4.5
@export var cl0: float = 0.0
@export var alpha_stall_deg: float = 15.0
@export var alpha_max_deg: float = 35.0
@export var cd0: float = 0.035
@export var k_induced: float = 0.06
@export var cd_beta: float = 1.5

# --- Stability & control ---
@export var control_ref_speed: float = 55.0
@export var pitch_power: float = 0.8
@export var roll_power: float  = 1.0
@export var yaw_power: float   = 0.6
@export var auto_coord: float  = 0.25
@export var pitch_stability: float = 0.6
@export var yaw_stability: float   = 0.6
@export var roll_stability: float  = 0.25
@export var ang_damp: Vector3 = Vector3(0.6, 0.5, 0.6)

# --- Stall behavior ---
@export var stall_nose_down: float = 0.8

# Control inputs (set these every frame from your input code)
var pitch_input: float = 0.0
var roll_input: float = 0.0
var yaw_input: float = 0.0

func _ready() -> void:
	if rb_path.is_empty():
		rb = get_parent() as RigidBody3D
	else:
		rb = get_node(rb_path) as RigidBody3D
	rb.gravity_scale = 1.0

func _physics_process(delta: float) -> void:
	if rb == null:
		return

	var v: Vector3 = rb.linear_velocity
	var speed: float = v.length()
	if speed < 0.1:
		return

	# Local airflow (body axes: +X right, +Y up, -Z forward)
	var basis: Basis = rb.global_transform.basis
	var v_local: Vector3 = basis.inverse() * v
	var v_dir_world: Vector3 = v / speed

	# Angles
	var alpha: float = atan2(v_local.y, -v_local.z) # AoA (rad)
	var beta: float  = atan2(v_local.x, -v_local.z) # sideslip (rad)

	# Dynamic pressure (scaled)
	var qS: float = 0.5 * air_density * speed * speed * wing_area * aero_scale

	# Coefficients
	var a_stall: float = deg_to_rad(alpha_stall_deg)
	var a_max: float   = deg_to_rad(alpha_max_deg)
	var cl: float = _cl_from_alpha(alpha, a_stall, a_max)
	var cd: float = cd0 + k_induced * cl * cl + cd_beta * beta * beta

	# Force directions
	var drag_dir: Vector3 = -v_dir_world
	var body_up: Vector3 = basis.y
	var lift_dir_unnorm: Vector3 = body_up - (body_up.dot(v_dir_world)) * v_dir_world
	var lift_dir: Vector3 = lift_dir_unnorm.normalized() if lift_dir_unnorm.length() > 0.0001 else Vector3.UP

	# Forces
	var lift_force: Vector3 = lift_dir * (qS * cl)
	var drag_force: Vector3 = drag_dir * (qS * cd)
	rb.apply_central_force(lift_force + drag_force)

	# Passive stability moments
	var pitch_moment: float = -alpha * (qS * mean_chord) * pitch_stability
	if abs(alpha) > a_stall:
		var sign_a: float = 1.0 if alpha > 0.0 else (-1.0 if alpha < 0.0 else 0.0)
		pitch_moment += -sign_a * (abs(alpha) - a_stall) * (qS * mean_chord) * stall_nose_down

	var yaw_moment: float = -beta * (qS * mean_chord) * yaw_stability
	var roll_moment: float = -beta * (qS * mean_chord) * roll_stability

	# Control moments (speed-scaled)
	var ctl_eff: float = clamp(speed / control_ref_speed, 0.0, 1.0)
	pitch_moment += pitch_input * pitch_power * ctl_eff * (qS * mean_chord)
	roll_moment  += roll_input  * roll_power  * ctl_eff * (qS * mean_chord)
	yaw_moment   += (yaw_input + auto_coord * roll_input) * yaw_power * ctl_eff * (qS * mean_chord)

	# Angular-rate damping (in body space)
	var w_local: Vector3 = basis.inverse() * rb.angular_velocity
	var damp_local: Vector3 = Vector3(
		-w_local.x * ang_damp.x,
		-w_local.y * ang_damp.y,
		-w_local.z * ang_damp.z
	) * (qS * mean_chord)

	# Compose world torque
	var torque_world: Vector3 = (
		basis.x * (pitch_moment + damp_local.x) +
		basis.y * (yaw_moment   + damp_local.y) +
		basis.z * (roll_moment  + damp_local.z)
	)
	rb.apply_torque(torque_world)

func _cl_from_alpha(a: float, a_stall: float, a_max: float) -> float:
	var s: float = 1.0 if a > 0.0 else (-1.0 if a < 0.0 else 0.0)
	var aa: float = abs(a)

	if aa <= a_stall:
		return cl0 + cl_alpha_per_rad * a

	var cl_peak: float = cl0 + cl_alpha_per_rad * (s * a_stall)
	var t: float = clamp((aa - a_stall) / max(0.0001, (a_max - a_stall)), 0.0, 1.0)
	var cl_post: float = lerp(cl_peak, 0.0, t) * s
	return cl_post
