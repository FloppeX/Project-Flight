extends InstrumentModule
class_name SlipBallModule

var slip_value: float = 0.0


func configure(config: Dictionary) -> void:
	super.configure(config)
	body.queue_redraw()


func update_from_aircraft(delta: float) -> void:
	var target := 0.0
	if aircraft != null and is_instance_valid(aircraft) and aircraft is Node3D and "linear_velocity" in aircraft:
		var local_velocity: Vector3 = (aircraft as Node3D).global_transform.basis.inverse() * aircraft.get("linear_velocity")
		var reference_speed := maxf(absf(local_velocity.z), 20.0)
		target = clampf(local_velocity.x / reference_speed, -1.0, 1.0)
	slip_value = lerpf(slip_value, target, clampf(delta * 8.0, 0.0, 1.0))
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
