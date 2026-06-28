extends InstrumentModule
class_name AoAModule

@export var min_aoa_deg: float = -10.0
@export var max_aoa_deg: float = 35.0
@export var caution_aoa_deg: float = 18.0
@export var stall_aoa_deg: float = 26.0

var aoa_deg: float = 0.0


func configure(config: Dictionary) -> void:
	super.configure(config)
	min_aoa_deg = float(config.get("min_aoa_deg", min_aoa_deg))
	max_aoa_deg = maxf(float(config.get("max_aoa_deg", max_aoa_deg)), min_aoa_deg + 1.0)
	caution_aoa_deg = float(config.get("caution_aoa_deg", caution_aoa_deg))
	stall_aoa_deg = float(config.get("stall_aoa_deg", stall_aoa_deg))
	if title_label != null:
		title_label.text = module_title if not module_title.is_empty() else "AOA"
	body.queue_redraw()


func update_from_aircraft(delta: float) -> void:
	var target := 0.0
	var aero := _find_child_with_method("get_estimated_angle_of_attack_deg")
	if aero != null:
		target = float(aero.call("get_estimated_angle_of_attack_deg"))
	elif aircraft != null and is_instance_valid(aircraft) and aircraft is Node3D and "linear_velocity" in aircraft:
		var local_velocity: Vector3 = (aircraft as Node3D).global_transform.basis.inverse() * aircraft.get("linear_velocity")
		target = rad_to_deg(atan2(-local_velocity.y, maxf(local_velocity.z, 0.1)))
	aoa_deg = lerpf(aoa_deg, target, clampf(delta * 10.0, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	if body == null:
		return
	var rect := Rect2(body.position, body.size)
	if rect.size.x <= 4.0 or rect.size.y <= 4.0:
		return
	if rect.size.y < 54.0:
		_draw_horizontal(rect)
		return

	var margin_x := maxf(rect.size.x * 0.16, 8.0)
	var top := rect.position.y + 8.0
	var bottom := rect.end.y - 10.0
	var center_x := rect.position.x + rect.size.x * 0.45
	var band_left := center_x - 8.0
	var band_right := center_x + 8.0

	_draw_band(band_left, band_right, top, bottom, min_aoa_deg, caution_aoa_deg, Color(0.0, 0.65, 0.38, 0.65))
	_draw_band(band_left, band_right, top, bottom, caution_aoa_deg, stall_aoa_deg, Color(1.0, 0.72, 0.15, 0.78))
	_draw_band(band_left, band_right, top, bottom, stall_aoa_deg, max_aoa_deg, Color(1.0, 0.15, 0.08, 0.78))

	draw_line(Vector2(center_x, top), Vector2(center_x, bottom), COLOR_TEXT, 1.5)
	for tick_aoa in [min_aoa_deg, 0.0, caution_aoa_deg, stall_aoa_deg, max_aoa_deg]:
		if tick_aoa < min_aoa_deg or tick_aoa > max_aoa_deg:
			continue
		var y := _aoa_to_y(tick_aoa, top, bottom)
		var tick_half := 6.0 if absf(tick_aoa) > 0.01 else 10.0
		draw_line(Vector2(center_x - tick_half, y), Vector2(center_x + tick_half, y), COLOR_TEXT, 1.0)

	var clamped_aoa := clampf(aoa_deg, min_aoa_deg, max_aoa_deg)
	var marker_y := _aoa_to_y(clamped_aoa, top, bottom)
	var marker_color := COLOR_BAD if absf(aoa_deg) >= stall_aoa_deg else (COLOR_WARN if absf(aoa_deg) >= caution_aoa_deg else COLOR_TEXT)
	var pointer_left := rect.position.x + margin_x
	var pointer := PackedVector2Array([
		Vector2(pointer_left, marker_y),
		Vector2(center_x - 10.0, marker_y - 7.0),
		Vector2(center_x - 10.0, marker_y + 7.0),
	])
	draw_colored_polygon(pointer, marker_color)
	draw_line(Vector2(center_x + 14.0, marker_y), Vector2(rect.end.x - margin_x * 0.4, marker_y), marker_color, 2.0)

	var font := get_theme_default_font()
	if font != null:
		draw_string(font, Vector2(center_x + 16.0, top + 12.0), "%+.0f" % aoa_deg, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 14, marker_color)
		draw_string(font, Vector2(center_x + 16.0, bottom), "deg", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 10, COLOR_MUTED)


func _draw_band(left: float, right: float, top: float, bottom: float, from_aoa: float, to_aoa: float, color: Color) -> void:
	var y0 := _aoa_to_y(from_aoa, top, bottom)
	var y1 := _aoa_to_y(to_aoa, top, bottom)
	var band := Rect2(Vector2(left, minf(y0, y1)), Vector2(right - left, absf(y1 - y0)))
	draw_rect(band, color, true)


func _draw_horizontal(rect: Rect2) -> void:
	var left := rect.position.x + 8.0
	var right := rect.end.x - 8.0
	var y := rect.position.y + rect.size.y * 0.52
	var band_h := maxf(rect.size.y * 0.34, 6.0)
	_draw_horizontal_band(left, right, y, band_h, min_aoa_deg, caution_aoa_deg, Color(0.0, 0.65, 0.38, 0.65))
	_draw_horizontal_band(left, right, y, band_h, caution_aoa_deg, stall_aoa_deg, Color(1.0, 0.72, 0.15, 0.78))
	_draw_horizontal_band(left, right, y, band_h, stall_aoa_deg, max_aoa_deg, Color(1.0, 0.15, 0.08, 0.78))
	draw_line(Vector2(left, y), Vector2(right, y), COLOR_TEXT, 1.0)

	for tick_aoa in [0.0, caution_aoa_deg, stall_aoa_deg]:
		if tick_aoa < min_aoa_deg or tick_aoa > max_aoa_deg:
			continue
		var x := _aoa_to_x(tick_aoa, left, right)
		draw_line(Vector2(x, y - band_h * 0.7), Vector2(x, y + band_h * 0.7), COLOR_TEXT, 1.0)

	var marker_x := _aoa_to_x(clampf(aoa_deg, min_aoa_deg, max_aoa_deg), left, right)
	var marker_color := COLOR_BAD if absf(aoa_deg) >= stall_aoa_deg else (COLOR_WARN if absf(aoa_deg) >= caution_aoa_deg else COLOR_TEXT)
	var pointer := PackedVector2Array([
		Vector2(marker_x, y - band_h - 2.0),
		Vector2(marker_x - 5.0, y - 2.0),
		Vector2(marker_x + 5.0, y - 2.0),
	])
	draw_colored_polygon(pointer, marker_color)

	var font := get_theme_default_font()
	if font != null:
		draw_string(font, Vector2(left, rect.end.y - 2.0), "%+.0f" % aoa_deg, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 10, marker_color)


func _draw_horizontal_band(left: float, right: float, y: float, height: float, from_aoa: float, to_aoa: float, color: Color) -> void:
	var x0 := _aoa_to_x(from_aoa, left, right)
	var x1 := _aoa_to_x(to_aoa, left, right)
	var band := Rect2(Vector2(minf(x0, x1), y - height * 0.5), Vector2(absf(x1 - x0), height))
	draw_rect(band, color, true)


func _aoa_to_y(value: float, top: float, bottom: float) -> float:
	var t := inverse_lerp(min_aoa_deg, max_aoa_deg, clampf(value, min_aoa_deg, max_aoa_deg))
	return lerpf(bottom, top, t)


func _aoa_to_x(value: float, left: float, right: float) -> float:
	var t := inverse_lerp(min_aoa_deg, max_aoa_deg, clampf(value, min_aoa_deg, max_aoa_deg))
	return lerpf(left, right, t)
