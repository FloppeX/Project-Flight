extends Node
class_name AeroForces

# --- References ---
@export var rb_path: NodePath   # optional; leave empty to auto-find parent RigidBody3D

# --- Airframe params ---
@export var wing_area_m2: float = 16.0
@export var rho: float = 1.225

# --- Lift/drag curve (simple stall) ---
@export var cl_max: float = 0.75
@export var alpha_stall_deg: float = 12.0
@export var alpha_zero_lift_deg: float = 2.0
@export var cd0: float = 0.04
@export var induced_k: float = 0.1
@export var side_force_gain: float = 0.06  # sideslip → sideforce

# --- Stability (angle) & damping (rate) ---
@export var pitch_stab: float = 0.28
@export var roll_stab: float = 0.08
@export var yaw_stab: float = 0.10
@export var pitch_damp: float = 0.45
@export var roll_damp: float = 0.25
@export var yaw_damp: float = 0.30

# --- Controls & effectiveness ---
@export var elev_power: float = 0.8
@export var aileron_power: float = 0.9
@export var rudder_power: float = 0.9
@export var q_effect_scale: float = 0.0025  # stronger controls at high dynamic pressure

# --- Command inputs (feed these from your control module each frame) ---
var cmd_pitch: float = 0.0   # -1..+1
var cmd_roll: float = 0.0    # -1..+1
var cmd_yaw: float = 0.0     # -1..+1

# --- Internals ---
var rb: RigidBody3D = null

func _ready() -> void:
	# Find the aircraft body
	if rb_path != NodePath():
		rb = get_node_or_null(rb_path)
	if rb == null:
		var p: Node = get_parent()
		while p and not (p is RigidBody3D):
			p = p.get_parent()
		if p and p is RigidBody3D:
			rb = p as RigidBody3D

	if rb == null:
		push_error("AeroForces: Could not find RigidBody3D. Set rb_path or make this a child of the Aircraft.")
		return

	# Let aero do the damping; disable built-in dampers
	rb.linear_damp = 0.0
	rb.angular_damp = 0.0

func _physics_process(delta: float) -> void:
	if rb == null:
		return

	# World transform & body axes
	var T: Transform3D = rb.global_transform
	var right_ws: Vector3 = T.basis.x
	var up_ws: Vector3    = T.basis.y
	var fwd_ws: Vector3   = T.basis.z    # your plane faces +Z due to Y = -180°

	# Relative airflow (hook wind here later if you like)
	var v_air_ws: Vector3 = rb.linear_velocity - wind_at(T.origin)
	var speed: float = v_air_ws.length()
	if speed < 0.1:
		return
	var v_dir: Vector3 = v_air_ws / speed
	var q: float = 0.5 * rho * speed * speed   # dynamic pressure

	# Velocity in body for angles
	var v_air_body: Vector3 = T.basis.inverse() * v_air_ws
	var ax: float = v_air_body.x
	var ay: float = v_air_body.y
	var az: float = v_air_body.z
	var alpha: float = atan2(ay,  az)  # for +Z forward
	var beta: float = atan2(ax, sqrt(ay * ay + az * az))       # sideslip (rad)

	# --- Lift curve with stall peak then drop (triangle shape 0..1..0) ---
	var alpha_deg: float = rad_to_deg(alpha)
	var a0: float = alpha_zero_lift_deg
	var a_stall: float = alpha_stall_deg
	var x: float = clamp((alpha_deg - a0) / max(0.001, (a_stall - a0)), 0.0, 2.0)  # 0..~2
	var peak_shape: float = min(x, 2.0 - x)   # 0..1..0
	var cl: float = clamp(cl_max * peak_shape, -cl_max * 0.6, cl_max)

	# Drag: base + induced ~ CL^2
	var cd: float = cd0 + induced_k * cl * cl

	# Sideforce coefficient vs sideslip
	var cy: float = side_force_gain * beta

	# --- Force directions (world space, orthogonal to flow) ---
	var lift_dir_ws: Vector3 = (up_ws - up_ws.dot(v_dir) * v_dir).normalized()
	var side_dir_ws: Vector3 = (right_ws - right_ws.dot(v_dir) * v_dir).normalized()
	var drag_dir_ws: Vector3 = -v_dir

	# --- Forces ---
	var lift_ws: Vector3 = lift_dir_ws * (cl * q * wing_area_m2)
	var side_ws: Vector3 = side_dir_ws * (cy * q * wing_area_m2)
	var drag_ws: Vector3 = drag_dir_ws * (cd * q * wing_area_m2)
	var total_force_ws: Vector3 = lift_ws + side_ws + drag_ws
	rb.apply_central_force(total_force_ws)

	# --- Control & stability torques (body space → world) ---
	var ang_body: Vector3 = T.basis.inverse() * rb.angular_velocity
	var ctrl_gain: float = 1.0 + q_effect_scale * q

	var pitch_m: float = (elev_power * cmd_pitch - pitch_stab * alpha) * ctrl_gain - pitch_damp * ang_body.x
	var yaw_m: float   = (rudder_power * cmd_yaw  - yaw_stab  * beta ) * ctrl_gain - yaw_damp   * ang_body.y
	var roll_m: float  = (aileron_power * cmd_roll - roll_stab * beta) * ctrl_gain - roll_damp  * ang_body.z

	var torque_body: Vector3 = Vector3(pitch_m, yaw_m, roll_m) * wing_area_m2
	rb.apply_torque(T.basis * torque_body)
	
	# print("Velocity: ", rb.linear_velocity.y, " Total Force Y: ", total_force_ws.y)

# --- Wind hook (replace later with your gust/turbulence field) ---
func wind_at(_pos: Vector3) -> Vector3:
	return Vector3.ZERO
