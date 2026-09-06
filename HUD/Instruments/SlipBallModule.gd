extends InstrumentModule
class_name SlipBallModule

@export var full_deflection_lateral_g: float = 0.35
@export var velocity_slip_weight: float = 0.2
@export var lateral_g_filter_speed: float = 3.25
@export var response_speed: float = 3.0
@export var center_deadzone: float = 0.055

var slip_value: float = 0.0
var _filtered_lateral_g: float = 0.0
var _previous_velocity: Vector3 = Vector3.ZERO
var _has_previous_velocity: bool = false
var _previous_process_frame: int = -1
var _autorudder_label: Label = null
var _control_steering: Node = null
var _displayed_autorudder_percent: int = -1


func configure(config: Dictionary) -> void:
	super.configure(config)
	full_deflection_lateral_g = maxf(float(config.get("full_deflection_lateral_g", full_deflection_lateral_g)), 0.05)
	velocity_slip_weight = maxf(float(config.get("velocity_slip_weight", velocity_slip_weight)), 0.0)
	lateral_g_filter_speed = maxf(float(config.get("lateral_g_filter_speed", lateral_g_filter_speed)), 0.1)
	response_speed = maxf(float(config.get("response_speed", response_speed)), 0.1)
	center_deadzone = maxf(float(config.get("center_deadzone", center_deadzone)), 0.0)
	_ensure_autorudder_label()
	body.queue_redraw()


func set_aircraft_reference(aircraft_node: Node) -> void:
	super.set_aircraft_reference(aircraft_node)
	_control_steering = null


func update_from_aircraft(delta: float) -> void:
	var target := 0.0
	if aircraft != null and is_instance_valid(aircraft) and aircraft is Node3D and "linear_velocity" in aircraft:
		var velocity: Vector3 = aircraft.get("linear_velocity")
		var basis := (aircraft as Node3D).global_transform.basis.orthonormalized()
		var local_velocity: Vector3 = basis.inverse() * velocity
		var reference_speed := maxf(absf(local_velocity.z), 20.0)
		var velocity_slip := clampf(local_velocity.x / reference_speed, -1.0, 1.0)

		var process_frame := Engine.get_process_frames()
		var consecutive_sample := _has_previous_velocity \
			and process_frame == _previous_process_frame + 1
		var lateral_g := 0.0
		if consecutive_sample and delta > 0.0001:
			var acceleration := (velocity - _previous_velocity) / delta
			var gravity := Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.80665))
			var specific_force := acceleration - gravity
			var local_specific_force := basis.inverse() * specific_force
			lateral_g = local_specific_force.x / 9.80665
		# Always prime the next sample. Previously these assignments were inside the
		# `_has_previous_velocity` branch, so the first sample could never make the
		# second sample valid and the ball silently ignored lateral acceleration.
		_previous_velocity = velocity
		_has_previous_velocity = true
		_previous_process_frame = process_frame
		_filtered_lateral_g = lerpf(_filtered_lateral_g, lateral_g, clampf(delta * lateral_g_filter_speed, 0.0, 1.0))

		var force_slip := _filtered_lateral_g / full_deflection_lateral_g
		target = clampf(force_slip + velocity_slip * velocity_slip_weight, -1.0, 1.0)
	else:
		_reset_acceleration_history()
		_filtered_lateral_g = lerpf(_filtered_lateral_g, 0.0, clampf(delta * lateral_g_filter_speed, 0.0, 1.0))
	if absf(target) < center_deadzone:
		target = 0.0
	slip_value = lerpf(slip_value, target, clampf(delta * response_speed, 0.0, 1.0))
	_update_autorudder_readout()
	queue_redraw()


func _ensure_autorudder_label() -> void:
	if _autorudder_label != null and is_instance_valid(_autorudder_label):
		return
	_autorudder_label = Label.new()
	_autorudder_label.name = "AutorudderReadout"
	_autorudder_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_autorudder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_autorudder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_autorudder_label.add_theme_color_override("font_color", COLOR_TEXT)
	_autorudder_label.add_theme_font_size_override("font_size", 10)
	_autorudder_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_autorudder_label.offset_top = -17.0
	_autorudder_label.offset_bottom = 0.0
	body.add_child(_autorudder_label)
	_set_autorudder_percent(0)


func _update_autorudder_readout() -> void:
	_ensure_autorudder_label()
	var assist_component := _get_autorudder_assist_component()
	_set_autorudder_percent(roundi(clampf(absf(assist_component), 0.0, 1.0) * 100.0))


func _set_autorudder_percent(percent: int) -> void:
	var clamped_percent := clampi(percent, 0, 100)
	if clamped_percent == _displayed_autorudder_percent:
		return
	_displayed_autorudder_percent = clamped_percent
	_autorudder_label.text = "Autorudder: %d%%" % clamped_percent


func _get_autorudder_assist_component() -> float:
	if aircraft == null or not is_instance_valid(aircraft):
		_control_steering = null
		return 0.0
	if _control_steering == null or not is_instance_valid(_control_steering):
		_control_steering = aircraft.get_node_or_null("ControlSteering")
		if _control_steering == null:
			_control_steering = aircraft.find_child("ControlSteering", true, false)
	if _control_steering == null or not is_instance_valid(_control_steering):
		return 0.0
	if "ControlActive" in _control_steering and not bool(_control_steering.get("ControlActive")):
		return 0.0
	if not ("telemetry_rudder_assist_component" in _control_steering):
		return 0.0
	return float(_control_steering.get("telemetry_rudder_assist_component"))


func _reset_acceleration_history() -> void:
	_previous_velocity = Vector3.ZERO
	_has_previous_velocity = false
	_previous_process_frame = -1


func _draw() -> void:
	if body == null:
		return
	var rect := Rect2(body.position, body.size)
	var y := rect.position.y + rect.size.y * 0.52
	var left := rect.position.x + rect.size.x * 0.15
	var right := rect.position.x + rect.size.x * 0.85
	var center := Vector2((left + right) * 0.5, y)
	draw_line(Vector2(left, y), Vector2(right, y), COLOR_TEXT, 2.0)
	draw_line(Vector2(center.x, y - 12.0), Vector2(center.x, y + 12.0), COLOR_MUTED, 1.0)
	var ball_x := lerpf(left, right, (slip_value + 1.0) * 0.5)
	draw_circle(Vector2(ball_x, y), 9.0, COLOR_TEXT)
