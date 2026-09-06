extends CanvasLayer
class_name POIDecisionNotice

## Persistent, non-modal field-decision notice. It never grabs focus or pauses
## play; the player chooses when to review the associated POI card.

const HEADLINE_FONT: FontFile = preload("res://UI/Fonts/ArchivoNarrow-Variable.ttf")
const DATA_FONT: FontFile = preload("res://UI/Fonts/JetBrainsMono-Variable.ttf")
const AMBER := Color("ffb000")
const TEXT := Color("e5e2e1")
const PANEL_BG := Color(0.055, 0.052, 0.052, 0.96)

signal review_requested(poi_id: int)

var _poi_id: int = -1
var _title_text: String = "FIELD SITE"
var _pending_count: int = 1
var _root: Control = null
var _panel: PanelContainer = null
var _title: Label = null
var _status: Label = null


class StarIcon extends Control:
	func _draw() -> void:
		var center := size * 0.5
		var outer := minf(size.x, size.y) * 0.43
		var inner := outer * 0.42
		var points := PackedVector2Array()
		for i in range(10):
			var angle := -PI * 0.5 + float(i) * PI / 5.0
			var radius := outer if i % 2 == 0 else inner
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(points, AMBER)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, Color.WHITE, 1.2)


func setup(poi_id: int, title_text: String, pending_count: int = 1) -> void:
	_poi_id = poi_id
	_title_text = title_text
	_pending_count = maxi(pending_count, 1)
	_refresh_text()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	_build_ui()
	_refresh_text()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = AMBER
	style.set_border_width_all(2)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3

	_panel = PanelContainer.new()
	_panel.name = "AwaitingOrdersPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var star := StarIcon.new()
	star.custom_minimum_size = Vector2(42.0, 42.0)
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(star)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 2)
	row.add_child(text_column)

	_title = Label.new()
	_title.add_theme_font_override("font", HEADLINE_FONT)
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", TEXT)
	text_column.add_child(_title)

	_status = Label.new()
	_status.add_theme_font_override("font", DATA_FONT)
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", AMBER)
	text_column.add_child(_status)

	var review := Button.new()
	review.name = "ReviewButton"
	review.text = "REVIEW"
	review.focus_mode = Control.FOCUS_NONE
	review.add_theme_font_override("font", DATA_FONT)
	review.add_theme_font_size_override("font_size", 13)
	review.add_theme_color_override("font_color", AMBER)
	review.add_theme_color_override("font_hover_color", Color.WHITE)
	review.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	review.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	review.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	review.pressed.connect(func() -> void: review_requested.emit(_poi_id))
	row.add_child(review)

	_root.resized.connect(_layout_ui)
	_layout_ui()


func _layout_ui() -> void:
	if _root == null or _panel == null:
		return
	var width := minf(510.0, maxf(_root.size.x - 32.0, 280.0))
	_panel.position = Vector2(maxf(_root.size.x - width - 24.0, 16.0), 82.0)
	_panel.size = Vector2(width, 78.0)


func _refresh_text() -> void:
	if _title == null or _status == null:
		return
	_title.text = _title_text.to_upper()
	_status.text = "FIELD TEAM AWAITING ORDERS"
	if _pending_count > 1:
		_status.text += "  //  +%d MORE" % (_pending_count - 1)
