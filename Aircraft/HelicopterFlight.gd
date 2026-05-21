extends Node
class_name HelicopterFlight

@export var rb_path: NodePath = NodePath("..")
@export var engine_path: NodePath = NodePath("../Engine")

@export_group("Rotor Lift")
@export var hover_collective: float = 0.56
@export var min_lift_multiplier: float = 0.0
@export var max_lift_multiplier: float = 1.85
@export var translational_lift_bonus: float = 0.12
@export var translational_lift_full_speed_mps: float = 45.0
@export var horizontal_thrust_bias: float = 1.0

@export_group("Cyclic")
@export var pitch_power: float = 1.0
@export var roll_power: float = 1.0
@export var max_disc_tilt_deg: float = 17.0
@export var pitch_trim_deg: float = 0.0
@export var roll_trim_deg: float = 0.0
@export var low_speed_cyclic_response: float = 1.15
@export var high_speed_cyclic_response: float = 4.2
@export var cyclic_full_response_speed_mps: float = 55.0
@export var tilt_input_curve: float = 1.15

@export_group("Attitude")
@export var body_follow_strength: float = 18.0
@export var body_follow_high_speed_bonus: float = 14.0
@export var fuselage_leveling_strength: float = 0.0
@export var fuselage_leveling_high_speed_loss: float = 0.35
@export var angular_damping_strength: float = 9.0
@export var yaw_power: float = 9.0
@export var yaw_damping_strength: float = 4.0
@export var high_speed_yaw_authority_loss: float = 0.35
@export var yaw_input_response: float = 3.0
@export var yaw_input_release_response: float = 1.2
@export var vertical_stabilizer_strength: float = 0.0
@export var vertical_stabilizer_damping: float = 0.0
@export var vertical_stabilizer_full_speed_mps: float = 45.0

@export_group("Drag")
@export var horizontal_drag_strength: float = 0.22
@export var lateral_drag_strength: float = 0.85
@export var vertical_damping_strength: float = 0.08
@export var high_speed_nose_drag_strength: float = 0.015
@export var max_forward_speed_mps: float = 92.0

@export_group("Ground Effect")
@export var ground_effect_height_m: float = 8.0
@export var ground_effect_strength: float = 0.22
@export var ground_probe_up_m: float = 1.0
@export var ground_probe_down_m: float = 80.0

@export_group("Debug")
@export var debug_overlay_enabled: bool = false
@export var debug_only_when_viewed: bool = true
@export var debug_update_interval_s: float = 0.12
@export var debug_console_enabled: bool = false
@export var debug_console_interval_s: float = 1.0

@export_group("Ground Handling")
@export var wheel_brake_when_engine_stopped: bool = true
@export var deck_takeoff_brake_release_collective: float = 0.70
@export var deck_takeoff_brake_release_forward_speed_mps: float = 4.0

var pitch_input: float = 0.0
var roll_input: float = 0.0
var yaw_input: float = 0.0
var current_yaw_input: float = 0.0

var current_disc_tilt: Vector2 = Vector2.ZERO
var target_disc_tilt: Vector2 = Vector2.ZERO
var current_ground_effect: float = 1.0
var max_total_speed_mps: float = 0.0
var max_forward_speed_seen_mps: float = 0.0
var max_climb_rate_mps: float = 0.0
var max_sink_rate_mps: float = 0.0

var _debug_canvas: CanvasLayer = null
var _debug_label: Label = null
var _debug_timer_s: float = 0.0
var _debug_console_timer_s: float = 0.0

@onready var rb: RigidBody3D = get_node_or_null(rb_path) as RigidBody3D
@onready var engine: Node = get_node_or_null(engine_path)


func _ready() -> void:
	if rb == null:
		rb = get_parent() as RigidBody3D
	if rb != null:
		rb.gravity_scale = 1.0
	_setup_debug_overlay()


func _physics_process(delta: float) -> void:
	if rb == null:
		return

	var collective: float = _get_collective()
	_update_engine_stopped_brake()
	var speed: float = rb.linear_velocity.length()
	var speed_t: float = _smoothstep(0.0, maxf(cyclic_full_response_speed_mps, 0.1), speed)

	_update_disc_tilt(delta, speed_t)
	var rotor_dir: Vector3 = _get_rotor_direction()
	current_ground_effect = _get_ground_effect()

	if bool(rb.get_meta("helicopter_deck_takeoff_ready", false)):
		_update_debug_overlay(delta, collective, speed, rotor_dir)
		return

	_apply_rotor_lift(rotor_dir, collective, speed_t)
	_apply_hanging_attitude(rotor_dir, collective, speed_t)
	_apply_yaw(collective, speed_t, delta)
	_apply_drag(speed)
	_update_debug_overlay(delta, collective, speed, rotor_dir)


func _update_disc_tilt(delta: float, speed_t: float) -> void:
	var max_tilt: float = deg_to_rad(max_disc_tilt_deg)
	var shaped_pitch: float = _shape_axis(pitch_input) * maxf(pitch_power, 0.0)
	var shaped_roll: float = _shape_axis(roll_input) * maxf(roll_power, 0.0)

	# ControlSteering feeds pitch positive for stick-back and roll negative for stick-right.
	target_disc_tilt = Vector2(
		-shaped_pitch * max_tilt + deg_to_rad(pitch_trim_deg),
		shaped_roll * max_tilt + deg_to_rad(roll_trim_deg)
	)
	var response: float = lerpf(low_speed_cyclic_response, high_speed_cyclic_response, speed_t)
	var blend: float = 1.0 - exp(-maxf(response, 0.01) * delta)
	current_disc_tilt = current_disc_tilt.lerp(target_disc_tilt, blend)


func _get_rotor_direction() -> Vector3:
	var basis: Basis = rb.global_transform.basis
	var up: Vector3 = basis.y.normalized()
	var forward: Vector3 = basis.z.normalized()
	var right: Vector3 = basis.x.normalized()
	var rotor_dir: Vector3 = up + forward * sin(current_disc_tilt.x) + right * sin(current_disc_tilt.y)
	if rotor_dir.length_squared() <= 0.0001:
		return up
	return rotor_dir.normalized()


func _apply_rotor_lift(rotor_dir: Vector3, collective: float, speed_t: float) -> void:
	var gravity_mag: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var hover_thrust: float = rb.mass * gravity_mag * maxf(rb.gravity_scale, 0.0)
	var collective_ratio: float = collective / maxf(hover_collective, 0.01)
	var translational_bonus: float = 1.0 + translational_lift_bonus * speed_t
	var lift_multiplier: float = clampf(
		collective_ratio * current_ground_effect * translational_bonus,
		min_lift_multiplier,
		max_lift_multiplier
	)
	var thrust_dir := _get_biased_thrust_direction(rotor_dir)
	rb.apply_central_force(thrust_dir * hover_thrust * lift_multiplier)


func _get_biased_thrust_direction(rotor_dir: Vector3) -> Vector3:
	var vertical: float = rotor_dir.dot(Vector3.UP)
	var horizontal: Vector3 = rotor_dir - Vector3.UP * vertical
	var bias: float = maxf(horizontal_thrust_bias, 0.0)
	var thrust_dir: Vector3 = Vector3.UP * vertical + horizontal * bias
	if thrust_dir.length_squared() <= 0.0001:
		return rotor_dir
	return thrust_dir.normalized()


func _apply_hanging_attitude(rotor_dir: Vector3, collective: float, speed_t: float) -> void:
	var body_up: Vector3 = rb.global_transform.basis.y.normalized()
	var axis: Vector3 = body_up.cross(rotor_dir)
	if axis.length_squared() > 0.000001:
		var angle: float = asin(clampf(axis.length(), -1.0, 1.0))
		var follow_strength: float = body_follow_strength + body_follow_high_speed_bonus * speed_t
		var power_t: float = clampf(collective / maxf(hover_collective, 0.01), 0.0, 1.35)
		rb.apply_torque(axis.normalized() * angle * follow_strength * rb.mass * power_t)
	_apply_fuselage_leveling(collective, speed_t)

	var ang_vel: Vector3 = rb.angular_velocity
	var yaw_axis: Vector3 = rb.global_transform.basis.y.normalized()
	var pitch_roll_ang_vel: Vector3 = ang_vel - yaw_axis * ang_vel.dot(yaw_axis)
	rb.apply_torque(-pitch_roll_ang_vel * angular_damping_strength * rb.mass)


func _apply_fuselage_leveling(collective: float, speed_t: float) -> void:
	if fuselage_leveling_strength <= 0.0:
		return
	var body_up: Vector3 = rb.global_transform.basis.y.normalized()
	var axis: Vector3 = body_up.cross(Vector3.UP)
	if axis.length_squared() <= 0.000001:
		return
	var angle: float = asin(clampf(axis.length(), -1.0, 1.0))
	var power_t: float = clampf(collective / maxf(hover_collective, 0.01), 0.0, 1.2)
	var speed_scale: float = lerpf(1.0, 1.0 - clampf(fuselage_leveling_high_speed_loss, 0.0, 0.95), speed_t)
	rb.apply_torque(axis.normalized() * angle * fuselage_leveling_strength * rb.mass * power_t * speed_scale)


func _apply_yaw(collective: float, speed_t: float, delta: float) -> void:
	var yaw_response: float = yaw_input_response if absf(yaw_input) > absf(current_yaw_input) else yaw_input_release_response
	var yaw_blend: float = 1.0 - exp(-maxf(yaw_response, 0.01) * delta)
	current_yaw_input = lerpf(current_yaw_input, yaw_input, yaw_blend)

	var yaw_authority: float = clampf(collective / maxf(hover_collective, 0.01), 0.0, 1.2)
	yaw_authority *= lerpf(1.0, 1.0 - high_speed_yaw_authority_loss, speed_t)
	var yaw_axis: Vector3 = rb.global_transform.basis.y.normalized()
	var yaw_rate: float = rb.angular_velocity.dot(yaw_axis)
	rb.apply_torque(yaw_axis * current_yaw_input * yaw_power * rb.mass * yaw_authority)
	rb.apply_torque(-yaw_axis * yaw_rate * yaw_damping_strength * rb.mass)
	_apply_vertical_stabilizer_yaw(yaw_axis, yaw_rate)


func _apply_vertical_stabilizer_yaw(yaw_axis: Vector3, yaw_rate: float) -> void:
	if vertical_stabilizer_strength <= 0.0:
		return
	var vel_flat := rb.linear_velocity
	vel_flat.y = 0.0
	var speed := vel_flat.length()
	if speed <= 0.5:
		return
	var forward_flat := rb.global_transform.basis.z
	forward_flat.y = 0.0
	if forward_flat.length_squared() <= 0.001:
		return
	forward_flat = forward_flat.normalized()
	var travel_dir := vel_flat / speed
	var yaw_error := forward_flat.signed_angle_to(travel_dir, Vector3.UP)
	var speed_t := _smoothstep(0.0, maxf(vertical_stabilizer_full_speed_mps, 0.1), speed)
	var stabilizer_torque := yaw_error * vertical_stabilizer_strength * speed_t * rb.mass
	var stabilizer_damping := yaw_rate * vertical_stabilizer_damping * speed_t * rb.mass
	rb.apply_torque(yaw_axis * (stabilizer_torque - stabilizer_damping))


func _apply_drag(speed: float) -> void:
	var basis: Basis = rb.global_transform.basis
	var vel: Vector3 = rb.linear_velocity
	var forward: Vector3 = basis.z.normalized()
	var right: Vector3 = basis.x.normalized()
	var up: Vector3 = basis.y.normalized()

	var forward_speed: float = vel.dot(forward)
	var lateral_speed: float = vel.dot(right)
	var vertical_speed: float = vel.dot(up)
	var drag: Vector3 = Vector3.ZERO
	drag += -forward * forward_speed * absf(forward_speed) * horizontal_drag_strength
	drag += -right * lateral_speed * absf(lateral_speed) * lateral_drag_strength
	drag += -up * vertical_speed * absf(vertical_speed) * vertical_damping_strength

	if absf(forward_speed) > max_forward_speed_mps:
		var excess: float = absf(forward_speed) - max_forward_speed_mps
		drag += -forward * signf(forward_speed) * excess * excess * high_speed_nose_drag_strength * rb.mass

	rb.apply_central_force(drag)


func _setup_debug_overlay() -> void:
	if not debug_overlay_enabled or _debug_canvas != null:
		return
	_debug_canvas = CanvasLayer.new()
	_debug_canvas.name = "HelicopterDebugOverlay"
	_debug_canvas.layer = 95
	add_child(_debug_canvas)

	_debug_label = Label.new()
	_debug_label.name = "Readout"
	_debug_label.position = Vector2(18.0, 86.0)
	_debug_label.size = Vector2(390.0, 320.0)
	_debug_label.add_theme_font_size_override("font_size", 15)
	_debug_label.add_theme_color_override("font_color", Color(0.72, 1.0, 0.72, 0.92))
	_debug_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_debug_label.add_theme_constant_override("outline_size", 2)
	_debug_canvas.add_child(_debug_label)


func _update_debug_overlay(delta: float, collective: float, speed: float, rotor_dir: Vector3) -> void:
	if not debug_overlay_enabled:
		if _debug_canvas:
			_debug_canvas.visible = false
		return
	if _debug_canvas == null or _debug_label == null:
		_setup_debug_overlay()
		if _debug_canvas == null or _debug_label == null:
			return

	var should_show := _should_show_debug_overlay()
	_debug_canvas.visible = should_show
	if not should_show:
		return

	_debug_timer_s -= delta
	if _debug_timer_s > 0.0:
		return
	_debug_timer_s = maxf(debug_update_interval_s, 0.02)

	var basis: Basis = rb.global_transform.basis
	var vel: Vector3 = rb.linear_velocity
	if rb.freeze and bool(rb.get_meta("helicopter_deck_takeoff_ready", false)):
		vel = _get_takeoff_reference_velocity()
	var rel_vel: Vector3 = VelocityFrame.get_relative_velocity(rb, vel)
	var forward_speed: float = vel.dot(basis.z.normalized())
	var lateral_speed: float = vel.dot(basis.x.normalized())
	var relative_speed: float = rel_vel.length()
	var climb_rate: float = vel.dot(Vector3.UP)

	max_total_speed_mps = maxf(max_total_speed_mps, speed)
	max_forward_speed_seen_mps = maxf(max_forward_speed_seen_mps, absf(forward_speed))
	max_climb_rate_mps = maxf(max_climb_rate_mps, climb_rate)
	max_sink_rate_mps = maxf(max_sink_rate_mps, -climb_rate)

	var body_pitch_deg: float = _signed_pitch_deg()
	var body_roll_deg: float = _signed_roll_deg()
	var disc_pitch_deg: float = rad_to_deg(current_disc_tilt.x)
	var disc_roll_deg: float = rad_to_deg(current_disc_tilt.y)
	var target_disc_pitch_deg: float = rad_to_deg(target_disc_tilt.x)
	var target_disc_roll_deg: float = rad_to_deg(target_disc_tilt.y)
	var rotor_world_tilt_deg: float = rad_to_deg(acos(clampf(rotor_dir.dot(Vector3.UP), -1.0, 1.0)))
	var power: float = _get_engine_target_power()
	var yaw_rate_deg: float = rad_to_deg(rb.angular_velocity.dot(basis.y.normalized()))
	var travel_flat := vel
	travel_flat.y = 0.0
	var forward_flat := basis.z.normalized()
	forward_flat.y = 0.0
	var weather_vane_deg := 0.0
	if travel_flat.length_squared() > 0.25 and forward_flat.length_squared() > 0.001:
		weather_vane_deg = rad_to_deg(forward_flat.normalized().signed_angle_to(travel_flat.normalized(), Vector3.UP))

	var debug_lines := [
		"HELICOPTER DEBUG",
		"speed       %6.1f m/s  %6.0f km/h" % [speed, speed * 3.6],
		"deck rel    %6.1f m/s  %6.0f km/h" % [relative_speed, relative_speed * 3.6],
		"forward     %6.1f m/s  max %5.1f" % [forward_speed, max_forward_speed_seen_mps],
		"lateral     %6.1f m/s" % lateral_speed,
		"climb       %6.1f m/s  max +%4.1f / -%4.1f" % [climb_rate, max_climb_rate_mps, max_sink_rate_mps],
		"body pitch  %6.1f deg" % body_pitch_deg,
		"body roll   %6.1f deg" % body_roll_deg,
		"disc pitch  %6.1f deg  target %6.1f" % [disc_pitch_deg, target_disc_pitch_deg],
		"disc roll   %6.1f deg  target %6.1f" % [disc_roll_deg, target_disc_roll_deg],
		"rotor lean  %6.1f deg world" % rotor_world_tilt_deg,
		"yaw         %6.2f input %6.2f  %6.1f deg/s" % [yaw_input, current_yaw_input, yaw_rate_deg],
		"weathervane %6.1f deg" % weather_vane_deg,
		"collective  %6.2f  target %6.2f  hover %6.2f" % [collective, power, hover_collective],
		"ground fx   %6.2f" % current_ground_effect,
		"max speed   %6.1f m/s  %6.0f km/h" % [max_total_speed_mps, max_total_speed_mps * 3.6],
	]
	_debug_label.text = "\n".join(debug_lines)
	var console_line := "HELI_DEBUG speed=%.1f kmh=%.0f deck_rel=%.1f deck_rel_kmh=%.0f forward=%.1f lateral=%.1f climb=%.1f body_pitch=%.1f body_roll=%.1f disc_pitch=%.1f disc_pitch_target=%.1f disc_roll=%.1f disc_roll_target=%.1f rotor_lean=%.1f yaw_raw=%.2f yaw_input=%.2f yaw_rate=%.1f weathervane=%.1f collective=%.2f target=%.2f hover=%.2f ground_fx=%.2f max_speed=%.1f max_kmh=%.0f" % [
		speed, speed * 3.6,
		relative_speed, relative_speed * 3.6,
		forward_speed, lateral_speed, climb_rate,
		body_pitch_deg, body_roll_deg,
		disc_pitch_deg, target_disc_pitch_deg,
		disc_roll_deg, target_disc_roll_deg,
		rotor_world_tilt_deg,
		yaw_input, current_yaw_input, yaw_rate_deg,
		weather_vane_deg,
		collective, power, hover_collective,
		current_ground_effect,
		max_total_speed_mps, max_total_speed_mps * 3.6
	]
	_maybe_print_debug_line(delta, console_line)


func _maybe_print_debug_line(delta: float, line: String) -> void:
	if not debug_console_enabled:
		return
	_debug_console_timer_s -= delta
	if _debug_console_timer_s > 0.0:
		return
	_debug_console_timer_s = maxf(debug_console_interval_s, 0.1)
	print(line)


func _should_show_debug_overlay() -> bool:
	if not debug_only_when_viewed:
		return true
	if typeof(FlightDirector) == TYPE_NIL:
		return true
	if FlightDirector.current_viewed_aircraft == rb:
		return true
	if FlightDirector.player_controlled_plane == rb:
		return true
	return false


func _signed_pitch_deg() -> float:
	var forward: Vector3 = rb.global_transform.basis.z.normalized()
	return rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))


func _signed_roll_deg() -> float:
	var right: Vector3 = rb.global_transform.basis.x.normalized()
	return rad_to_deg(asin(clampf(right.y, -1.0, 1.0)))


func _get_engine_target_power() -> float:
	if engine == null:
		return 0.0
	var power = engine.get("target_power") if engine.has_method("get") else null
	if power == null:
		return _get_collective()
	return clampf(float(power), 0.0, 1.0)


func _update_engine_stopped_brake() -> void:
	if not wheel_brake_when_engine_stopped or rb == null or engine == null:
		return
	if bool(rb.get_meta("carrier_transport_mode", false)):
		return
	if bool(rb.get_meta("helicopter_deck_takeoff_ready", false)):
		var collective := _get_collective()
		var release_collective: float = clampf(deck_takeoff_brake_release_collective, 0.0, 1.0)
		var planar_speed := 0.0 if rb.freeze else VelocityFrame.planar_speed(VelocityFrame.get_relative_velocity(rb))
		if collective >= release_collective and planar_speed <= maxf(deck_takeoff_brake_release_forward_speed_mps, 0.0):
			var deck_velocity := _get_takeoff_reference_velocity()
			var release_velocity := rb.linear_velocity
			release_velocity.x = deck_velocity.x
			release_velocity.z = deck_velocity.z
			if rb.has_meta("parking_brake"):
				rb.remove_meta("parking_brake")
			rb.remove_meta("helicopter_deck_takeoff_ready")
			if rb.has_meta("helicopter_deck_reference_node"):
				rb.remove_meta("helicopter_deck_reference_node")
			rb.freeze = false
			rb.sleeping = false
			rb.linear_velocity = release_velocity
			if debug_console_enabled:
				print("HELI_DEBUG event=takeoff_release deck_velocity=%s release_velocity=%s" % [str(deck_velocity), str(rb.linear_velocity)])
		else:
			rb.set_meta("parking_brake", true)
			_hold_deck_ready_helicopter()
		return

	if _is_engine_running():
		if rb.has_meta("parking_brake"):
			rb.remove_meta("parking_brake")
	else:
		rb.set_meta("parking_brake", true)


func _hold_deck_ready_helicopter() -> void:
	var deck_velocity := _get_takeoff_reference_velocity()
	var vel := rb.linear_velocity
	vel.x = deck_velocity.x
	vel.z = deck_velocity.z
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3.ZERO
	rb.freeze = true
	rb.sleeping = false


func _get_takeoff_reference_velocity() -> Vector3:
	if rb != null and rb.has_meta("helicopter_deck_reference_node"):
		var reference_node = rb.get_meta("helicopter_deck_reference_node")
		if reference_node is Node and is_instance_valid(reference_node):
			return VelocityFrame.get_node_velocity(reference_node)
	var deck_velocity := VelocityFrame.get_reference_velocity(rb)
	if deck_velocity.length_squared() > 0.0001:
		return deck_velocity
	var carrier := get_tree().get_first_node_in_group("carrier")
	if carrier is Node:
		return VelocityFrame.get_node_velocity(carrier as Node)
	return Vector3.ZERO


func _is_engine_running() -> bool:
	if engine == null:
		return false
	var working = engine.get("is_engine_working") if engine.has_method("get") else null
	if working != null and bool(working):
		return true
	var power = engine.get("current_power") if engine.has_method("get") else null
	return power != null and float(power) > 0.03


func _get_collective() -> float:
	if engine == null:
		return 0.0
	var power = engine.get("current_power") if engine.has_method("get") else null
	if power == null:
		return 0.0
	return clampf(float(power), 0.0, 1.0)


func _get_ground_effect() -> float:
	if rb == null or ground_effect_height_m <= 0.0:
		return 1.0
	var space_state: PhysicsDirectSpaceState3D = rb.get_world_3d().direct_space_state
	var from: Vector3 = rb.global_position + Vector3.UP * ground_probe_up_m
	var to: Vector3 = rb.global_position + Vector3.DOWN * ground_probe_down_m
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [rb.get_rid()]
	query.collision_mask = 0xFFFFFFFF
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty() or not result.has("position"):
		return 1.0
	var agl: float = rb.global_position.y - (result.position as Vector3).y
	var t: float = clampf(1.0 - agl / ground_effect_height_m, 0.0, 1.0)
	return 1.0 + ground_effect_strength * t * t


func _shape_axis(value: float) -> float:
	var clamped: float = clampf(value, -1.0, 1.0)
	if is_equal_approx(clamped, 0.0):
		return 0.0
	var curve: float = maxf(tilt_input_curve, 0.01)
	return signf(clamped) * pow(absf(clamped), curve)


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 1.0 if value >= edge1 else 0.0
	var t: float = clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
