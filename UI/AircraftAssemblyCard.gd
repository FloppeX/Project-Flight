extends "res://UI/AircraftAssemblyToken.gd"
## Native vector UI: the entire card remains one clickable/draggable button.
const MONO = preload("res://UI/Fonts/JetBrainsMono-Variable.ttf")
const TITLE = preload("res://UI/Fonts/ArchivoNarrow-Variable.ttf")
const CYAN := Color("35dbea")
const INK := Color("081419")
const LINE := Color("496872")
const WHITE := Color("e2edeb")
const MUTED := Color("809ca6")
const RED := Color("ef4b52")
const YELLOW := Color("efdc42")
var record: Dictionary = {}
var pilot_name := "NO PILOT"
var portrait: Texture2D
var outline: Texture2D
var selected := false
var pool_card := false

func _ready() -> void:
	custom_minimum_size = Vector2(240, 160) if pool_card else Vector2(300, 240)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	resized.connect(queue_redraw)

func _draw() -> void:
	if record.is_empty(): return
	var w := size.x
	var border := CYAN if selected or is_hovered() else Color("2bb4c2")
	_frame(Rect2(Vector2(2, 2), size - Vector2(4, 4)), INK, border, 8, 2.5 if selected else 1.5)
	var maximum := float(record.get("max_health", record.model.max_health))
	var health := clampf(float(record.health) / maximum, 0.0, 1.0) if maximum > 0 else -1.0
	var fuel := float(record.get("fuel_fraction", -1))
	if pool_card:
		var aircraft_rect := Rect2(10, 10, w - 20, 70)
		_visual_frame(aircraft_rect, true)
		_draw_outline(aircraft_rect)
		_text(str(record.model.name), Rect2(10, 83, w - 20, 20), 14, WHITE, TITLE)
		_meter("STRUCTURE", Rect2(10, 108, w - 20, 20), health, RED)
		_meter("FUEL", Rect2(10, 134, w - 20, 20), fuel, YELLOW)
		return
	_text("AC · " + airframe_id.right(5).to_upper(), Rect2(10, 6, w - 20, 18), 12, WHITE)
	draw_line(Vector2(14, 15), Vector2(w * 0.23, 15), border)
	draw_line(Vector2(w * 0.77, 15), Vector2(w - 14, 15), border)
	var split := floorf(w * 0.65)
	var aircraft_rect := Rect2(10, 30, split - 16, 72)
	var pilot_rect := Rect2(split + 2, 30, w - split - 12, 72)
	_visual_frame(aircraft_rect, true)
	_visual_frame(pilot_rect, false)
	_draw_outline(aircraft_rect)
	if portrait != null:
		_texture_fit(portrait, pilot_rect.grow(-3))
	else:
		_text("UNASSIGNED" if pilot_name == "NO PILOT" else "NO PORTRAIT", pilot_rect, 9, MUTED)
	_text(str(record.model.name), Rect2(10, 106, split - 16, 20), 14, WHITE, TITLE)
	_text(str(record.model.get("role", "AIRCRAFT")), Rect2(10, 128, split - 16, 13), 9, MUTED)
	_text("PILOT", Rect2(split + 2, 106, pilot_rect.size.x, 12), 9, MUTED)
	_text(pilot_name, Rect2(split + 2, 120, pilot_rect.size.x, 21), 11, WHITE)
	_meter("STRUCTURE", Rect2(10, 148, w - 20, 22), health, RED)
	_meter("FUEL", Rect2(10, 174, w - 20, 22), fuel, YELLOW)
	_loadout(Rect2(10, 202, w - 20, 26))

func _draw_outline(rect: Rect2) -> void:
	if outline != null:
		_texture_fit(outline, rect.grow(-7))
	else:
		_text("OUTLINE PENDING", rect, 10, MUTED)
func _text(value: String, rect: Rect2, font_size: int, color: Color, font: Font = MONO) -> void:
	var fitted := value
	while fitted.length() > 1 and font.get_string_size(fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x:
		fitted = fitted.left(fitted.length() - 2) + "…"
	var width := font.get_string_size(fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := rect.position.y + (rect.size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	draw_string(font, Vector2(rect.position.x + (rect.size.x - width) * 0.5, baseline), fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _frame(rect: Rect2, fill: Color, stroke: Color, cut: float = 5, thickness: float = 1.0) -> void:
	var p := rect.position
	var e := rect.end
	var points := PackedVector2Array([Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut), Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut)])
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, stroke, thickness, true)

func _visual_frame(rect: Rect2, grid: bool) -> void:
	draw_rect(rect, Color("0b1b22"))
	if grid:
		for x in range(1, 8):
			var pos := rect.position.x + rect.size.x * x / 8.0
			draw_line(Vector2(pos, rect.position.y), Vector2(pos, rect.end.y), Color("15343d"))
		for y in range(1, 5):
			var pos := rect.position.y + rect.size.y * y / 5.0
			draw_line(Vector2(rect.position.x, pos), Vector2(rect.end.x, pos), Color("15343d"))
	draw_rect(rect, LINE, false, 1)
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var direction: Vector2 = (rect.get_center() - corner).sign()
		draw_line(corner + Vector2(direction.x * 11, 3 * direction.y), corner + Vector2(3 * direction.x, direction.y * 11), CYAN, 3, true)

func _texture_fit(texture: Texture2D, rect: Rect2) -> void:
	var ratio := minf(rect.size.x / texture.get_width(), rect.size.y / texture.get_height())
	var extent := texture.get_size() * ratio
	draw_texture_rect(texture, Rect2(rect.get_center() - extent * 0.5, extent), false)

func _meter(caption: String, rect: Rect2, fraction: float, color: Color) -> void:
	_frame(rect, Color("0b191e"), color.darkened(0.4), 4)
	_text(caption, Rect2(rect.position + Vector2(4, 0), Vector2(78, rect.size.y)), 11, color)
	var bar := Rect2(rect.position + Vector2(86, 5), Vector2(rect.size.x - 135, rect.size.y - 10))
	draw_rect(bar.grow(2), color.darkened(0.55), false, 1)
	for i in range(12):
		var segment := Rect2(bar.position + Vector2(i * bar.size.x / 12.0, 0), Vector2(bar.size.x / 12.0 - 2, bar.size.y))
		draw_rect(segment, color.darkened(0.85))
		var amount := clampf(fraction * 12.0 - i, 0.0, 1.0)
		if amount > 0:
			segment.size.x *= amount
			draw_rect(segment, color)
	_text("%d%%" % roundi(fraction * 100) if fraction >= 0 else "—", Rect2(rect.end.x - 46, rect.position.y, 43, rect.size.y), 12, WHITE)

func _loadout(rect: Rect2) -> void:
	_frame(rect, Color("0b191e"), LINE)
	var payload: Dictionary = record.get("payload", {})
	if not payload.is_empty():
		var i := 0
		for category in ["guns", "bombs", "rockets"]:
			var cell := Rect2(rect.position.x + i * rect.size.x / 3, rect.position.y, rect.size.x / 3, rect.size.y)
			if i > 0: draw_line(cell.position + Vector2(0, 5), Vector2(cell.position.x, cell.end.y - 5), LINE)
			var count := int(payload.get(category, -1))
			_text(("ROUNDS" if category == "guns" else category.to_upper()) + " " + (str(count) if count >= 0 else "—"), cell.grow(-3), 11, WHITE)
			i += 1
	else:
		var preset := str(record.get("loadout", ""))
		var caption := str({"gun_only": "GUNS", "bomb_strike": "BOMBS + GUNS", "rocket_strike": "ROCKETS + GUNS"}.get(preset, "STANDARD LOADOUT"))
		_text("LOADOUT · " + caption, rect.grow(-6), 11, MUTED)
