extends RefCounted
## Shared operator-console styling for startup, pause, and settings menus.

const MenuTypography = preload("res://UI/MenuTypography.gd")

const RAIL_WIDTH := 480.0
const PRIMARY := Color(1.0, 0.718, 0.49, 1.0)
const PRIMARY_ACTIVE := Color(1.0, 0.55, 0.0, 1.0)
const HAZARD := Color(1.0, 0.86, 0.28, 1.0)
const SURFACE := Color(0.102, 0.11, 0.118, 0.88)
const SURFACE_SOLID := Color(0.035, 0.039, 0.043, 0.96)
const SURFACE_LOW := Color(0.047, 0.055, 0.063, 0.72)
const OUTLINE := Color(0.337, 0.263, 0.204, 0.78)
const TEXT := Color(0.886, 0.886, 0.898, 1.0)
const TEXT_MUTED := Color(0.867, 0.757, 0.682, 0.62)


static func make_panel_style(
		background: Color = SURFACE,
		border: Color = OUTLINE,
		border_width: int = 1
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	return style


static func make_operator_button_style(
		background: Color,
		border: Color,
		border_width: int = 0
) -> StyleBoxFlat:
	var style := make_panel_style(background, border, border_width)
	style.content_margin_left = 18.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


static func apply_operator_button(button: Button, font_size: int = MenuTypography.MENU_ITEM_SIZE) -> void:
	var normal := make_operator_button_style(Color.TRANSPARENT, Color.TRANSPARENT)
	var active := make_operator_button_style(PRIMARY, HAZARD)
	active.border_width_left = 4
	var pressed := make_operator_button_style(PRIMARY_ACTIVE, HAZARD)
	pressed.border_width_left = 4
	var disabled := make_operator_button_style(Color.TRANSPARENT, Color.TRANSPARENT)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", active)
	button.add_theme_stylebox_override("focus", active)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_font_override("font", MenuTypography.TECH_FONT)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color(0.12, 0.07, 0.025, 1.0))
	button.add_theme_color_override("font_focus_color", Color(0.12, 0.07, 0.025, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.12, 0.07, 0.025, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(TEXT.r, TEXT.g, TEXT.b, 0.24))


static func apply_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(OUTLINE.r, OUTLINE.g, OUTLINE.b, 0.52)
	track.content_margin_top = 3.0
	track.content_margin_bottom = 3.0
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = PRIMARY
	var grabber := GradientTexture2D.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([HAZARD, PRIMARY_ACTIVE])
	grabber.gradient = gradient
	grabber.width = 18
	grabber.height = 18
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.add_theme_icon_override("grabber", grabber)
	slider.add_theme_icon_override("grabber_highlight", grabber)
