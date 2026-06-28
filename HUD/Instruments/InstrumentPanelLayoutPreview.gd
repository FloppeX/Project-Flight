@tool
extends Control

@export var viewport_resolution: Vector2i = Vector2i(1000, 480):
	set(value):
		viewport_resolution = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		custom_minimum_size = Vector2(viewport_resolution)
		queue_redraw()

@export var module_layout: Array[Dictionary] = []:
	set(value):
		module_layout = value
		queue_redraw()

@export var panel_polygon: PackedVector2Array = PackedVector2Array([
	Vector2(120, 20),
	Vector2(880, 20),
	Vector2(960, 444),
	Vector2(40, 444),
])

@export var grid_size_px: float = 5.0
@export var enable_dragging: bool = true

var _drag_index: int = -1
var _drag_start_mouse_panel: Vector2 = Vector2.ZERO
var _drag_start_rect: Rect2 = Rect2()
var _drag_resize: bool = false
var _viewport_rect: Rect2 = Rect2()


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(viewport_resolution)
	if module_layout.is_empty():
		module_layout = _default_aircraft_5_layout()
	queue_redraw()


func _draw() -> void:
	_viewport_rect = _compute_viewport_rect()
	var screen_rect := Rect2(Vector2.ZERO, size)
	draw_rect(screen_rect, Color(0.015, 0.018, 0.016, 1.0), true)
	draw_rect(_viewport_rect, Color(0.01, 0.014, 0.012, 1.0), true)
	_draw_panel_shape()

	var layout := module_layout
	for i in range(layout.size()):
		var entry := layout[i]
		var rect := entry.get("rect", Rect2(0, 0, 100, 60)) as Rect2
		var screen_module_rect := _panel_rect_to_screen(rect)
		var module_color := _module_color(str(entry.get("type", "readout")))
		draw_rect(screen_module_rect, module_color, true)
		draw_rect(screen_module_rect, Color(0.2, 0.95, 0.62, 0.9), false, 2.0)
		var title := str(entry.get("title", entry.get("id", "MODULE")))
		_draw_centered_text(screen_module_rect, title)
		_draw_corner_handle(screen_module_rect)

	var font := get_theme_default_font()
	if font != null:
		var hint := "Drag to move. Drag lower-right handle to resize. Ctrl+C copies module_layout."
		draw_string(font, Vector2(12, size.y - 12), hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.55, 0.85, 0.68, 0.75))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				grab_focus()
				_start_drag(mouse_button.position)
			else:
				_drag_index = -1
				_drag_resize = false
			accept_event()
	elif event is InputEventMouseMotion and _drag_index >= 0:
		_update_drag((event as InputEventMouseMotion).position)
		accept_event()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.ctrl_pressed and key_event.keycode == KEY_C:
			copy_layout_to_clipboard()
			accept_event()


func set_module_layout(new_layout: Array) -> void:
	module_layout = new_layout.duplicate(true)
	queue_redraw()


func get_module_layout_copy() -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for entry in module_layout:
		copied.append((entry as Dictionary).duplicate(true))
	return copied


func copy_layout_to_clipboard() -> void:
	DisplayServer.clipboard_set(_layout_assignment_text())
	print("[InstrumentPanelLayoutPreview] module_layout copied to clipboard.")


func _draw_panel_shape() -> void:
	if panel_polygon.size() < 3:
		return
	var screen_points := PackedVector2Array()
	for point in panel_polygon:
		screen_points.append(_panel_to_screen(point))
	draw_colored_polygon(screen_points, Color(0.03, 0.055, 0.045, 1.0))
	for i in range(screen_points.size()):
		var a := screen_points[i]
		var b := screen_points[(i + 1) % screen_points.size()]
		draw_line(a, b, Color(0.18, 0.7, 0.42, 0.8), 2.0)


func _draw_centered_text(rect: Rect2, text: String) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := 13
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var pos := rect.position + Vector2(
		maxf((rect.size.x - text_size.x) * 0.5, 4.0),
		maxf((rect.size.y + text_size.y * 0.5) * 0.5, 12.0)
	)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8.0, font_size, Color(0.78, 1.0, 0.86, 0.95))


func _draw_corner_handle(rect: Rect2) -> void:
	var handle_size := 10.0
	var handle_rect := Rect2(rect.end - Vector2.ONE * handle_size, Vector2.ONE * handle_size)
	draw_rect(handle_rect, Color(0.2, 0.95, 0.62, 0.95), true)


func _start_drag(mouse_position: Vector2) -> void:
	if not enable_dragging:
		return
	var panel_position := _screen_to_panel(mouse_position)
	_drag_index = _find_module_at(panel_position)
	if _drag_index < 0:
		return
	var entry := module_layout[_drag_index]
	_drag_start_rect = entry.get("rect", Rect2(0, 0, 100, 60)) as Rect2
	_drag_start_mouse_panel = panel_position
	var handle_size_panel := _screen_delta_to_panel(Vector2.ONE * 14.0)
	_drag_resize = Rect2(_drag_start_rect.end - handle_size_panel, handle_size_panel).has_point(panel_position)


func _update_drag(mouse_position: Vector2) -> void:
	if _drag_index < 0 or _drag_index >= module_layout.size():
		return
	var panel_position := _screen_to_panel(mouse_position)
	var delta := panel_position - _drag_start_mouse_panel
	var rect := _drag_start_rect
	if _drag_resize:
		rect.size = Vector2(
			maxf(30.0, _snap(_drag_start_rect.size.x + delta.x)),
			maxf(24.0, _snap(_drag_start_rect.size.y + delta.y))
		)
	else:
		rect.position = Vector2(
			_snap(_drag_start_rect.position.x + delta.x),
			_snap(_drag_start_rect.position.y + delta.y)
		)
	rect.position.x = clampf(rect.position.x, 0.0, float(viewport_resolution.x) - rect.size.x)
	rect.position.y = clampf(rect.position.y, 0.0, float(viewport_resolution.y) - rect.size.y)
	_set_module_rect(_drag_index, rect)


func _set_module_rect(index: int, rect: Rect2) -> void:
	var next_layout := module_layout.duplicate(true)
	var entry := (next_layout[index] as Dictionary).duplicate(true)
	entry["rect"] = rect
	next_layout[index] = entry
	module_layout = next_layout
	queue_redraw()


func _find_module_at(panel_position: Vector2) -> int:
	for i in range(module_layout.size() - 1, -1, -1):
		var rect := module_layout[i].get("rect", Rect2()) as Rect2
		if rect.has_point(panel_position):
			return i
	return -1


func _panel_to_screen(point: Vector2) -> Vector2:
	var viewport_rect := _compute_viewport_rect()
	var scale := _panel_uniform_scale()
	return viewport_rect.position + point * scale


func _panel_delta_to_screen(delta: Vector2) -> Vector2:
	return delta * _panel_uniform_scale()


func _screen_to_panel(point: Vector2) -> Vector2:
	var viewport_rect := _compute_viewport_rect()
	var scale := _panel_uniform_scale()
	return (point - viewport_rect.position) / maxf(scale, 0.0001)


func _screen_delta_to_panel(delta: Vector2) -> Vector2:
	var scale := _panel_uniform_scale()
	return delta / maxf(scale, 0.0001)


func _panel_rect_to_screen(rect: Rect2) -> Rect2:
	return Rect2(_panel_to_screen(rect.position), _panel_delta_to_screen(rect.size))


func _panel_uniform_scale() -> float:
	var available := size
	var panel_size := Vector2(viewport_resolution)
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return 1.0
	return minf(available.x / panel_size.x, available.y / panel_size.y)


func _compute_viewport_rect() -> Rect2:
	var panel_size := Vector2(viewport_resolution)
	var scale := _panel_uniform_scale()
	var fitted_size := panel_size * scale
	var offset := (size - fitted_size) * 0.5
	return Rect2(offset, fitted_size)


func _snap(value: float) -> float:
	if grid_size_px <= 0.0:
		return value
	return roundf(value / grid_size_px) * grid_size_px


func _module_color(module_type: String) -> Color:
	match module_type:
		"mfd":
			return Color(0.02, 0.15, 0.12, 0.9)
		"warning_lights":
			return Color(0.18, 0.08, 0.035, 0.9)
		"slip_ball":
			return Color(0.08, 0.12, 0.13, 0.9)
		"aoa":
			return Color(0.12, 0.13, 0.065, 0.9)
		_:
			return Color(0.035, 0.09, 0.075, 0.9)


func _layout_assignment_text() -> String:
	var lines: Array[String] = ["module_layout = Array[Dictionary](["]
	for i in range(module_layout.size()):
		var entry := module_layout[i]
		var suffix := "," if i < module_layout.size() - 1 else ""
		lines.append(_entry_text(entry) + suffix)
	lines.append("])")
	return "\n".join(lines)


func _entry_text(entry: Dictionary) -> String:
	var rect := entry.get("rect", Rect2(0, 0, 100, 60)) as Rect2
	var parts: Array[String] = [
		"\"type\": \"%s\"" % str(entry.get("type", "readout")),
		"\"id\": \"%s\"" % str(entry.get("id", "")),
		"\"title\": \"%s\"" % str(entry.get("title", "")),
		"\"rect\": Rect2(%d, %d, %d, %d)" % [roundi(rect.position.x), roundi(rect.position.y), roundi(rect.size.x), roundi(rect.size.y)],
	]
	if entry.has("instrument"):
		parts.append("\"instrument\": \"%s\"" % str(entry["instrument"]))
	if entry.has("modes"):
		parts.append("\"modes\": %s" % _string_array_text(entry["modes"]))
	if entry.has("lights"):
		parts.append("\"lights\": %s" % _string_array_text(entry["lights"]))
	return "{\n%s\n}" % ",\n".join(parts.map(func(part: String) -> String: return "\t" + part))


func _string_array_text(value: Variant) -> String:
	var items: Array[String] = []
	if value is Array:
		for item in value:
			items.append("\"%s\"" % str(item))
	elif value is PackedStringArray:
		for item in value:
			items.append("\"%s\"" % item)
	return "[" + ", ".join(items) + "]"


func _default_aircraft_5_layout() -> Array[Dictionary]:
	return [
		{"type": "warning_lights", "id": "warning_strip", "title": "WARNINGS", "rect": Rect2(135, 26, 730, 44), "lights": ["ENGINE", "WEAPONS", "CONTROLS", "GEAR", "STALL", "MISSILE"]},
		{"type": "mfd", "id": "mfd_left", "title": "MFD L", "rect": Rect2(92, 92, 235, 235), "modes": ["MAP", "WEAPONS", "DAMAGE", "SYSTEMS"]},
		{"type": "mfd", "id": "mfd_right", "title": "MFD R", "rect": Rect2(673, 92, 235, 235), "modes": ["TARGET", "MAP", "WEAPONS", "DAMAGE", "SYSTEMS"]},
		{"type": "readout", "id": "speed", "title": "SPEED", "instrument": "speed", "rect": Rect2(360, 92, 125, 54)},
		{"type": "readout", "id": "altitude", "title": "ALT", "instrument": "altitude", "rect": Rect2(515, 92, 125, 54)},
		{"type": "readout", "id": "vertical_speed", "title": "V/S", "instrument": "vertical_speed", "rect": Rect2(360, 158, 125, 54)},
		{"type": "readout", "id": "fuel", "title": "FUEL", "instrument": "fuel", "rect": Rect2(515, 158, 125, 54)},
		{"type": "readout", "id": "gear", "title": "GEAR", "instrument": "gear", "rect": Rect2(360, 224, 125, 54)},
		{"type": "readout", "id": "flaps", "title": "FLAPS", "instrument": "flaps", "rect": Rect2(515, 224, 125, 54)},
		{"type": "aoa", "id": "aoa", "title": "AOA", "rect": Rect2(360, 290, 125, 84)},
		{"type": "readout", "id": "stall", "title": "STALL", "instrument": "stall", "rect": Rect2(515, 290, 125, 40)},
		{"type": "readout", "id": "missile_lock", "title": "M LOCK", "instrument": "missile_lock", "rect": Rect2(515, 338, 125, 36)},
		{"type": "slip_ball", "id": "slip_ball", "title": "BALL", "rect": Rect2(120, 376, 220, 68)},
		{"type": "readout", "id": "engine", "title": "ENGINE", "instrument": "engine", "rect": Rect2(370, 376, 120, 68)},
		{"type": "readout", "id": "damage", "title": "STRUCT", "instrument": "damage", "rect": Rect2(510, 376, 120, 68)},
		{"type": "readout", "id": "g_force", "title": "G", "instrument": "g_force", "rect": Rect2(660, 376, 110, 68)},
		{"type": "readout", "id": "weapons", "title": "WEAPONS", "instrument": "weapons", "rect": Rect2(790, 376, 110, 68)},
	]
