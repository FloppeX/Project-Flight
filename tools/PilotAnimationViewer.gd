extends Node3D
## Interactive viewer for the canonical pilot's baked animation library.
## Run PilotAnimationViewer.tscn with F6 and select a clip from the toolbar.

const DEFAULT_CLIP := &"piloting"

@onready var _pilot: Node3D = $Pilot
@onready var _player: AnimationPlayer = $Pilot/BakedAnimationPlayer

var _clip_selector: OptionButton
var _play_button: Button
var _timeline: HSlider
var _time_label: Label
var _speed_spin: SpinBox
var _updating_timeline: bool = false
var _timeline_dragging: bool = false
var _resume_after_drag: bool = false


func _ready() -> void:
	_build_interface()
	_populate_clips()
	await get_tree().process_frame
	_select_clip(DEFAULT_CLIP)


func _process(_delta: float) -> void:
	if _player == null or _timeline == null or _timeline_dragging:
		return
	_updating_timeline = true
	_timeline.value = _player.current_animation_position
	_updating_timeline = false
	_update_time_label()
	_update_play_button()


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.offset_left = 18.0
	margin.offset_top = 18.0
	margin.offset_right = -18.0
	margin.offset_bottom = 112.0
	layer.add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.075, 0.94)
	style.border_color = Color(0.22, 0.32, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var title := Label.new()
	title.text = "PILOT ANIMATION"
	title.custom_minimum_size.x = 185.0
	title.add_theme_font_size_override("font_size", 19)
	row.add_child(title)

	_clip_selector = OptionButton.new()
	_clip_selector.name = "ClipSelector"
	_clip_selector.custom_minimum_size.x = 190.0
	_clip_selector.item_selected.connect(_on_clip_selected)
	row.add_child(_clip_selector)

	_play_button = Button.new()
	_play_button.name = "PlayPause"
	_play_button.custom_minimum_size.x = 76.0
	_play_button.pressed.connect(_on_play_pressed)
	row.add_child(_play_button)

	_timeline = HSlider.new()
	_timeline.name = "Timeline"
	_timeline.min_value = 0.0
	_timeline.max_value = 1.0
	_timeline.step = 0.001
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.value_changed.connect(_on_timeline_changed)
	_timeline.drag_started.connect(_on_timeline_drag_started)
	_timeline.drag_ended.connect(_on_timeline_drag_ended)
	row.add_child(_timeline)

	_time_label = Label.new()
	_time_label.name = "TimeLabel"
	_time_label.custom_minimum_size.x = 105.0
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_time_label)

	var speed_label := Label.new()
	speed_label.text = "Speed"
	row.add_child(speed_label)
	_speed_spin = SpinBox.new()
	_speed_spin.name = "Speed"
	_speed_spin.min_value = 0.1
	_speed_spin.max_value = 2.0
	_speed_spin.step = 0.1
	_speed_spin.value = 1.0
	_speed_spin.suffix = "x"
	_speed_spin.custom_minimum_size.x = 92.0
	_speed_spin.value_changed.connect(_on_speed_changed)
	row.add_child(_speed_spin)

	var angle_label := Label.new()
	angle_label.text = "View"
	row.add_child(angle_label)
	var angle := HSlider.new()
	angle.name = "ViewAngle"
	angle.min_value = -180.0
	angle.max_value = 180.0
	angle.step = 1.0
	angle.custom_minimum_size.x = 150.0
	angle.value_changed.connect(_on_view_angle_changed)
	row.add_child(angle)


func _populate_clips() -> void:
	_clip_selector.clear()
	for animation_name in _player.get_animation_list():
		_clip_selector.add_item(String(animation_name))
		_clip_selector.set_item_metadata(_clip_selector.item_count - 1, animation_name)


func _select_clip(animation_name: StringName) -> void:
	if not _player.has_animation(animation_name):
		return
	for index in range(_clip_selector.item_count):
		if StringName(_clip_selector.get_item_metadata(index)) == animation_name:
			_clip_selector.select(index)
			break
	_pilot.call("play_baked_animation", animation_name, _speed_spin.value)
	var animation := _player.get_animation(animation_name)
	_timeline.max_value = maxf(animation.length, 0.001)
	_timeline.value = 0.0
	_update_time_label()
	_update_play_button()


func _on_clip_selected(index: int) -> void:
	_select_clip(StringName(_clip_selector.get_item_metadata(index)))


func _on_play_pressed() -> void:
	if _player.is_playing():
		_player.pause()
	else:
		_player.play()
	_update_play_button()


func _on_timeline_changed(value: float) -> void:
	if _updating_timeline:
		return
	_player.seek(value, true)
	_player.advance(0.0)
	_update_time_label()


func _on_timeline_drag_started() -> void:
	_timeline_dragging = true
	_resume_after_drag = _player.is_playing()
	_player.pause()


func _on_timeline_drag_ended(_value_changed: bool) -> void:
	_timeline_dragging = false
	if _resume_after_drag:
		_player.play()
	_resume_after_drag = false


func _on_speed_changed(value: float) -> void:
	_player.speed_scale = value


func _on_view_angle_changed(value: float) -> void:
	_pilot.rotation_degrees.y = value


func _update_play_button() -> void:
	_play_button.text = "Pause" if _player.is_playing() else "Play"


func _update_time_label() -> void:
	_time_label.text = "%.2f / %.2f s" % [_timeline.value, _timeline.max_value]
