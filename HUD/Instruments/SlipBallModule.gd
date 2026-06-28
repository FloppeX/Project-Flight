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


func configure(config: Dictionary) -> void:
	super.configure(config)
	full_deflection_lateral_g = maxf(float(config.get("full_deflection_lateral_g", full_deflection_lateral_g)), 0.05)
	velocity_slip_weight = maxf(float(config.get("velocity_slip_weight", velocity_slip_weight)), 0.0)
	lateral_g_filter_speed = maxf(float(config.get("lateral_g_filter_speed", lateral_g_filter_speed)), 0.1)
	response_speed = maxf(float(config.get("response_speed", response_speed)), 0.1)
	center_deadzone = maxf(float(config.get("center_deadzone", center_deadzone)), 0.0)
	body.queue_redraw()


func update_from_aircraft(delta: float) -> void:
	var target := 0.0
	if aircraft != null and is_instance_valid(aircraft) and aircraft is Node3D and "linear_velocity" in aircraft:
		var velocity: Vector3 = aircraft.get("linear_velocity")
		var basis := (aircraft as Node3D).global_transform.basis.orthonormalized()
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
		_filtered_lateral_g = lerpf(_filtered_lateral_g, lateral_g, clampf(delta * lateral_g_filter_speed, 0.0, 1.0))

		var force_slip := _filtered_lateral_g / full_deflection_lateral_g
		target = clampf(force_slip + velocity_slip * velocity_slip_weight, -1.0, 1.0)
	else:
		_has_previous_velocity = false
		_filtered_lateral_g = lerpf(_filtered_lateral_g, 0.0, clampf(delta * lateral_g_filter_speed, 0.0, 1.0))
	if absf(target) < center_deadzone:
		target = 0.0
	slip_value = lerpf(slip_value, target, clampf(delta * response_speed, 0.0, 1.0))
	queue_redraw()


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
