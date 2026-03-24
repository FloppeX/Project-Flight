extends CanvasLayer

var _label: Label

func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.anchor_left = 1.0
	_label.anchor_top = 0.0
	_label.anchor_right = 1.0
	_label.anchor_bottom = 0.0
	_label.offset_left = -80
	_label.offset_top = 5
	_label.offset_right = -5
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)

func _process(_delta: float) -> void:
	_label.text = "%d FPS" % Engine.get_frames_per_second()
