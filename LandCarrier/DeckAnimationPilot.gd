extends Node3D
class_name DeckAnimationPilot

## Stationary deck mannequin for reviewing the shared pilot animation library.
## Press A to advance to the next clip. Authored loops keep looping; one-shot
## gestures and the death clip play once and hold their final frame.

const ANIMATION_SEQUENCE: Array[StringName] = [
	&"idle_breathing",
	&"idle_neutral",
	&"walk",
	&"run",
	&"turn_left",
	&"turn_right",
	&"sit_1",
	&"sit_2",
	&"piloting",
	&"salute",
	&"wave",
	&"die",
	&"parachute",
]
const IN_PLACE_REVIEW_CLIPS: Array[StringName] = [
	&"walk", &"run", &"turn_left", &"turn_right",
]
const TURN_PREVIEW_DEGREES := 90.0

@export var initial_animation: StringName = &"idle_breathing"

@onready var _pilot: Node3D = $Pilot
@onready var _animation_player: AnimationPlayer = $Pilot/BakedAnimationPlayer

var _available_animations: Array[StringName] = []
var _current_index: int = 0
var _pilot_base_transform := Transform3D.IDENTITY


func _ready() -> void:
	_pilot_base_transform = _pilot.transform
	if not _install_review_library():
		push_warning("DeckAnimationPilot: shared baked animation library was unavailable")
		return
	for animation_name in ANIMATION_SEQUENCE:
		if _animation_player.has_animation(animation_name):
			_available_animations.append(animation_name)
		else:
			push_warning("DeckAnimationPilot: missing animation '%s'" % animation_name)
	if _available_animations.is_empty():
		push_warning("DeckAnimationPilot: no reviewable pilot animations were found")
		return
	var initial_index: int = _available_animations.find(initial_animation)
	_current_index = initial_index if initial_index >= 0 else 0
	_play_current_animation()
	print("[DeckAnimationPilot] A cycles %d clips; current=%s" % [
		_available_animations.size(),
		get_current_animation(),
	])


func _process(_delta: float) -> void:
	var animation_name := get_current_animation()
	if animation_name not in [&"turn_left", &"turn_right"]:
		return
	var animation := _animation_player.get_animation(animation_name)
	if animation == null or animation.length <= 0.0:
		return
	var turn_sign := 1.0 if animation_name == &"turn_left" else -1.0
	var progress := clampf(_animation_player.current_animation_position / animation.length, 0.0, 1.0)
	var rotation := _pilot_base_transform.basis.get_euler()
	rotation.y += deg_to_rad(TURN_PREVIEW_DEGREES * turn_sign * progress)
	_pilot.position = _pilot_base_transform.origin
	_pilot.rotation = rotation


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.physical_keycode != KEY_A and key_event.keycode != KEY_A:
		return
	cycle_animation()


func cycle_animation() -> bool:
	if _available_animations.is_empty():
		return false
	_current_index = wrapi(_current_index + 1, 0, _available_animations.size())
	var played := _play_current_animation()
	if played:
		print("[DeckAnimationPilot] animation -> %s" % get_current_animation())
	return played


func get_current_animation() -> StringName:
	if _available_animations.is_empty() or _current_index < 0 \
			or _current_index >= _available_animations.size():
		return &""
	return _available_animations[_current_index]


func get_animation_names() -> Array[StringName]:
	var names: Array[StringName] = []
	names.assign(_available_animations)
	return names


func _play_current_animation() -> bool:
	var animation_name := get_current_animation()
	if animation_name == &"":
		return false
	_pilot.transform = _pilot_base_transform
	if _pilot.has_method("play_baked_animation") \
			and bool(_pilot.call("play_baked_animation", animation_name, 1.0)):
		return true
	if _animation_player.has_animation(animation_name):
		_animation_player.play(animation_name)
		_animation_player.advance(0.0)
		return true
	return false


func _install_review_library() -> bool:
	if _animation_player == null:
		return false
	var source_library := _animation_player.get_animation_library(&"")
	if source_library == null:
		return false
	var stationary_library := AnimationLibrary.new()
	for animation_name in ANIMATION_SEQUENCE:
		if not source_library.has_animation(animation_name):
			continue
		var source_animation := source_library.get_animation(animation_name)
		if source_animation == null:
			continue
		var animation := source_animation.duplicate(true) as Animation
		if animation == null:
			continue
		# Locomotion is intentionally in place because the mannequin has no movement
		# controller. Other clips must retain their internal root travel: freezing
		# the death fall's forward travel stretched the body grotesquely across the
		# deck. Preserve authored loop modes so gestures and death do not snap-repeat.
		if IN_PLACE_REVIEW_CLIPS.has(animation_name):
			_lock_horizontal_root_motion(animation)
		if stationary_library.add_animation(animation_name, animation) != OK:
			return false
	if stationary_library.get_animation_list().is_empty():
		return false
	_animation_player.remove_animation_library(&"")
	return _animation_player.add_animation_library(&"", stationary_library) == OK


func _lock_horizontal_root_motion(animation: Animation) -> void:
	for track_index in range(animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		if not String(animation.track_get_path(track_index)).ends_with(":root.x"):
			continue
		var key_count := animation.track_get_key_count(track_index)
		if key_count <= 0:
			continue
		var first_value: Variant = animation.track_get_key_value(track_index, 0)
		if not (first_value is Vector3):
			continue
		var anchor := first_value as Vector3
		for key_index in range(key_count):
			var value := animation.track_get_key_value(track_index, key_index) as Vector3
			value.x = anchor.x
			value.z = anchor.z
			animation.track_set_key_value(track_index, key_index, value)
