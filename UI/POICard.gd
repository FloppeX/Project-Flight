extends CanvasLayer
class_name POICard
## POI reveal card. Shown over a paused game. Built entirely in code.
## Emits confirmed(choice_idx) when the player confirms or picks a choice.
## choice_idx == -1 means the plain no-choice Confirm button.
## Dismiss/Cancel is separate so postponing a decision never consumes the POI.

const MENU_FONT: FontFile = preload("res://UI/Orbitron-VariableFont_wght.ttf")

# ── Steel blue vector palette ─────────────────────────────────────────────────
const COLOR_OVERLAY  := Color(0.00, 0.02, 0.06, 0.68)
const COLOR_CARD_BG  := Color(0.13, 0.14, 0.16, 0.97)
const COLOR_BORDER   := Color(0.27, 0.51, 0.71, 0.75)   # CSS steelblue
const COLOR_BRACKET  := Color(0.45, 0.75, 0.96, 1.00)   # brighter for corner marks
const COLOR_TICK     := Color(0.27, 0.51, 0.71, 0.40)   # dim mid-edge ticks
const COLOR_CATEGORY := Color(0.42, 0.68, 0.88, 0.60)
const COLOR_TITLE    := Color(0.88, 0.95, 1.00, 1.00)
const COLOR_BODY     := Color(0.68, 0.82, 0.94, 0.88)
const COLOR_DIV      := Color(0.27, 0.51, 0.71, 0.35)
const COLOR_BTN      := Color(0.45, 0.75, 0.96, 0.85)
const COLOR_BTN_HOV  := Color(0.88, 0.95, 1.00, 1.00)

# ── Card geometry ─────────────────────────────────────────────────────────────
## Half-width → card is 1760 px wide.
const CARD_HALF_W    := 880.0
## Half-height → card is 1040 px tall.
const CARD_HALF_H    := 520.0
## Content padding inside the card.
const CARD_MARGIN    := 56.0
## Image height.
const IMG_HEIGHT     := 650.0
## Corner bracket arm length and line thickness.
const BRACKET_ARM    := 144.0
const BRACKET_THICK  := 6.0

signal confirmed(choice_idx: int)
signal dismissed

var _data: POIData = null
var _confirm_btn: Button = null

func setup(data: POIData) -> void:
	_data = data

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128
	if _data != null:
		_build_ui()

# ── Inner class: vector corner-bracket overlay ────────────────────────────────
class VectorFrame extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var a := BRACKET_ARM
		var t := BRACKET_THICK
		var bc := COLOR_BRACKET
		var tc := COLOR_TICK

		# Corner brackets — four L-shapes at the corners.
		# Top-left
		draw_rect(Rect2(0,     0,     a,     t), bc)
		draw_rect(Rect2(0,     0,     t,     a), bc)
		# Top-right
		draw_rect(Rect2(w - a, 0,     a,     t), bc)
		draw_rect(Rect2(w - t, 0,     t,     a), bc)
		# Bottom-left
		draw_rect(Rect2(0,     h - t, a,     t), bc)
		draw_rect(Rect2(0,     h - a, t,     a), bc)
		# Bottom-right
		draw_rect(Rect2(w - a, h - t, a,     t), bc)
		draw_rect(Rect2(w - t, h - a, t,     a), bc)

		# Subtle mid-edge tick marks.
		var half_tick := 28.0
		var ht := t * 0.5
		draw_rect(Rect2(w * 0.5 - half_tick, 0,         half_tick * 2, ht), tc)
		draw_rect(Rect2(w * 0.5 - half_tick, h - ht,    half_tick * 2, ht), tc)
		draw_rect(Rect2(0,                   h * 0.5 - half_tick, ht, half_tick * 2), tc)
		draw_rect(Rect2(w - ht,              h * 0.5 - half_tick, ht, half_tick * 2), tc)

# ── Build ─────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	# Dim overlay
	var overlay := ColorRect.new()
	overlay.color = COLOR_OVERLAY
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Full-screen anchor container
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	# ── Card background panel ─────────────────────────────────────────────────
	var style := StyleBoxFlat.new()
	style.bg_color       = COLOR_CARD_BG
	style.border_color   = COLOR_BORDER
	style.set_border_width_all(1)
	style.corner_radius_top_left     = 0
	style.corner_radius_top_right    = 0
	style.corner_radius_bottom_left  = 0
	style.corner_radius_bottom_right = 0
	style.set_content_margin_all(CARD_MARGIN)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", style)
	_center_rect(card, anchor)
	anchor.add_child(card)

	# ── Vector corner brackets — sibling to card, same rect ───────────────────
	var frame := VectorFrame.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_rect(frame, anchor)
	anchor.add_child(frame)

	# ── Content layout ────────────────────────────────────────────────────────
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	card.add_child(vbox)

	# Category
	var cat_lbl := Label.new()
	cat_lbl.text = _category_string(_data.category).to_upper()
	cat_lbl.add_theme_font_override("font", MENU_FONT)
	cat_lbl.add_theme_font_size_override("font_size", 26)
	cat_lbl.add_theme_color_override("font_color", COLOR_CATEGORY)
	cat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(cat_lbl)

	# Title — above the image
	var title := Label.new()
	title.text = _data.title.to_upper()
	title.add_theme_font_override("font", MENU_FONT)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_make_divider())

	# Image — prominent, centre of the card
	if _data.image != null:
		var tex := TextureRect.new()
		tex.texture = _data.image
		tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(0, IMG_HEIGHT)
		vbox.add_child(tex)

	vbox.add_child(_make_divider())

	# Body — below the image
	var body := Label.new()
	body.text = _data.body
	body.add_theme_font_override("font", MENU_FONT)
	body.add_theme_font_size_override("font_size", 30)
	body.add_theme_color_override("font_color", COLOR_BODY)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)

	vbox.add_child(_make_spacer(16))

	# Choice buttons
	var initial_focus: Button = null
	if _data.choices.size() > 0:
		var hbox := HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", 28)
		for i in range(_data.choices.size()):
			var btn := _make_button(_data.choices[i])
			var idx := i
			btn.pressed.connect(func(): confirmed.emit(idx))
			hbox.add_child(btn)
			if initial_focus == null:
				initial_focus = btn
		vbox.add_child(hbox)

	# Confirm / Defer
	var confirm_text := "CONFIRM" if _data.choices.is_empty() else "DEFER"
	_confirm_btn = _make_button(confirm_text)
	if _data.choices.is_empty():
		_confirm_btn.pressed.connect(func(): confirmed.emit(-1))
	else:
		_confirm_btn.pressed.connect(func(): dismissed.emit())
	vbox.add_child(_confirm_btn)
	(initial_focus if initial_focus != null else _confirm_btn).call_deferred("grab_focus")

# ── Helpers ───────────────────────────────────────────────────────────────────
func _center_rect(ctrl: Control, parent: Control) -> void:
	ctrl.set_anchor(SIDE_LEFT,   0.5)
	ctrl.set_anchor(SIDE_RIGHT,  0.5)
	ctrl.set_anchor(SIDE_TOP,    0.5)
	ctrl.set_anchor(SIDE_BOTTOM, 0.5)
	ctrl.set_offset(SIDE_LEFT,   -CARD_HALF_W)
	ctrl.set_offset(SIDE_RIGHT,   CARD_HALF_W)
	ctrl.set_offset(SIDE_TOP,    -CARD_HALF_H)
	ctrl.set_offset(SIDE_BOTTOM,  CARD_HALF_H)

func _make_divider() -> Control:
	var sep := ColorRect.new()
	sep.color = COLOR_DIV
	sep.custom_minimum_size = Vector2(0, 1)
	return sep

func _make_spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s

func _make_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text.to_upper()
	btn.add_theme_font_override("font", MENU_FONT)
	btn.add_theme_font_size_override("font_size", 34)
	btn.add_theme_color_override("font_color",       COLOR_BTN)
	btn.add_theme_color_override("font_hover_color", COLOR_BTN_HOV)
	btn.add_theme_color_override("font_focus_color", COLOR_BTN_HOV)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, empty)
	btn.focus_mode = Control.FOCUS_ALL
	return btn

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		dismissed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and _data != null and _data.choices.is_empty():
		confirmed.emit(-1)
		get_viewport().set_input_as_handled()

func _category_string(cat: int) -> String:
	match cat:
		POIData.Category.RESOURCE_CACHE: return "Resource Cache"
		POIData.Category.WATER:          return "Water Source"
		POIData.Category.SETTLEMENT:     return "Settlement"
		POIData.Category.BLUEPRINT:      return "Blueprint Site"
		POIData.Category.INTEL:          return "Intel"
		POIData.Category.HAZARD:         return "Hazard"
	return "Point of Interest"
