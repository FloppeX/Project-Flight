extends CanvasLayer

var _label: Label
var _hit_assist_label: Label

func _ready() -> void:
	layer = 100
	set_process_input(true)
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

	_hit_assist_label = Label.new()
	_hit_assist_label.anchor_left = 0.0
	_hit_assist_label.anchor_top = 0.0
	_hit_assist_label.anchor_right = 0.0
	_hit_assist_label.anchor_bottom = 0.0
	_hit_assist_label.offset_left = 8
	_hit_assist_label.offset_top = 8
	_hit_assist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hit_assist_label.add_theme_font_size_override("font_size", 16)
	_hit_assist_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85, 1.0))
	_hit_assist_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	_hit_assist_label.add_theme_constant_override("shadow_offset_x", 1)
	_hit_assist_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_hit_assist_label)

func _process(_delta: float) -> void:
	_label.text = "%d FPS" % Engine.get_frames_per_second()
	_hit_assist_label.text = "Hit Assist Radius: %.1fm" % ProjectileNew.get_hit_assist_radius_m()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if not key_event.ctrl_pressed:
		return
	if key_event.keycode == KEY_UP:
		var new_radius_up: float = ProjectileNew.adjust_hit_assist_radius_m(0.2)
		print("[Projectile] Hit assist radius: %.1fm" % new_radius_up)
	elif key_event.keycode == KEY_DOWN:
		var new_radius_down: float = ProjectileNew.adjust_hit_assist_radius_m(-0.2)
		print("[Projectile] Hit assist radius: %.1fm" % new_radius_down)
