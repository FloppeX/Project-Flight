extends CharacterBody3D
class_name Commander

@export var eye_height_m: float = 1.8
@export var walk_speed_mps: float = 2.5
@export var look_sensitivity_deg: float = 120.0
@export var pitch_limit_deg: float = 85.0
@export var gravity_mps2: float = 9.8
@export var bridge_wall_margin_m: float = 0.55
@export var normal_fov: float = 75.0
@export var zoomed_fov: float = 30.0
@export_group("Keyboard Control")
@export var keyboard_turn_speed_degrees_s: float = 120.0
@export_group("Officer Animation")
@export var officer_idle_animation: StringName = &"idle_neutral"
@export var officer_idle_animations: Array[StringName] = [
	&"idle_neutral",
	&"idle_3",
	&"idle_4",
	&"idle_5",
	&"idle_6",
	&"idle_7",
	&"idle_breathing",
]
@export var officer_walk_animation: StringName = &"walk"
@export var officer_walk_reference_speed_mps: float = 2.4
@export var officer_dance_animations: Array[StringName] = [
	&"dance_belly",
	&"dance_booty_hip_hop",
	&"dance_chicken",
	&"dance_gangnam",
	&"dance_hip_hop",
	&"dance_locking_hip_hop",
	&"dance_northern_soul",
]
@export_group("Carrier Cameras")
@export var chase_camera_local_position: Vector3 = Vector3(0.0, 42.0, 120.0)
@export var chase_camera_focus_local_position: Vector3 = Vector3(0.0, 4.0, 0.0)
@export var cinematic_camera_local_position: Vector3 = Vector3(95.0, 58.0, -125.0)
@export var cinematic_camera_focus_local_position: Vector3 = Vector3(0.0, 6.0, 0.0)
@export var control_room_ambience: AudioStream = preload("res://Audio/Carrier/interior_ventilation.ogg")
@export var control_room_ambience_bus: String = "Master"
@export var control_room_ambience_volume_db: float = -10.0
@export var control_room_ambience_pitch_scale: float = 1.0
@export var control_room_ambience_silence_db: float = -80.0
@export_group("Control Room Wind")
@export var control_room_wind: AudioStream = preload("res://Audio/cockpit/wind_sound_cockpit.wav")
@export var control_room_wind_bus: String = "Master"
@export var control_room_wind_idle_volume_db: float = -34.0
@export var control_room_wind_max_volume_db: float = -22.0
@export var control_room_wind_pitch_min: float = 0.72
@export var control_room_wind_pitch_max: float = 1.02
@export var control_room_wind_full_speed_mps: float = 12.0
@export var control_room_wind_silence_db: float = -80.0
@export_group("Computer Stations")
@export var computer_camera_transition_s: float = 0.45
@export var computer_screen_focus_s: float = 0.24
@export var computer_interact_keyboard_key: Key = KEY_E

@onready var commander_camera: Camera3D = $Camera3D
@onready var body_visual: Node3D = $BodyVisual
@onready var male_body_visual: Node3D = $BodyVisualMale

var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _glass_meshes: Array[MeshInstance3D] = []
var _glass_surfaces: Array[Dictionary] = []
var _hidden_glass_material: StandardMaterial3D = null
var _glass_found: bool = false
var _anchor_local_position: Vector3 = Vector3.ZERO
var _bridge_bounds_min: Vector2 = Vector2.ZERO
var _bridge_bounds_max: Vector2 = Vector2.ZERO
var _has_bridge_bounds: bool = false
var _is_zoomed: bool = false
var _zoom_tween: Tween
var _was_active_view: bool = false
var _zoom_button_prev_pressed: bool = false
var _control_room_audio_player: AudioStreamPlayer
var _control_room_wind_player: AudioStreamPlayer
var _audio_room_check_time: float = 0.0
var _audio_inside_room: bool = true
var _active_view_mode: int = 0
var _chase_camera: Camera3D = null
var _cinematic_camera: Camera3D = null
var _walk_area_provider: Node = null
var _pause_menu_settings: Node = null
var _officer_animation_player: AnimationPlayer = null
var _officer_animation: StringName = &""
var _officer_moving: bool = false
var _officer_visuals: Array[Node3D] = []
var _active_officer_index: int = 0
var _officer_dancing: bool = false
var _last_officer_dance: StringName = &""
var _coffee_visual: Node3D = null
var _arrow_forward_pressed: bool = false
var _arrow_backward_pressed: bool = false
var _arrow_left_pressed: bool = false
var _arrow_right_pressed: bool = false
var _computer_station_candidate: Node3D = null
var _active_computer_station: Node3D = null
var _computer_camera_tween: Tween = null
var _computer_camera_transitioning: bool = false
var _standing_camera_transform: Transform3D = Transform3D.IDENTITY
var _standing_camera_fov: float = 75.0

const VIEW_CONTROL_ROOM: int = 0
const VIEW_CHASE: int = 1
const VIEW_CINEMATIC: int = 2
const VIEW_MODE_COUNT: int = 3

func _ready() -> void:
	add_to_group("commander_camera_controller")
	physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_INHERIT
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if commander_camera:
		commander_camera.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_INHERIT
		commander_camera.top_level = false
	if body_visual != null:
		_officer_visuals.append(body_visual)
	if male_body_visual != null:
		_officer_visuals.append(male_body_visual)
	for officer_index in range(_officer_visuals.size()):
		var officer_visual := _officer_visuals[officer_index]
		officer_visual.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_INHERIT
		var rig_controls := officer_visual.find_child("cs_grp", true, false) as Node3D
		if rig_controls != null:
			rig_controls.visible = false
		var animation_player := officer_visual.get_node_or_null(
			"BakedAnimationPlayer"
		) as AnimationPlayer
		if animation_player != null:
			animation_player.animation_finished.connect(
				_on_officer_animation_finished.bind(officer_index)
			)
	_activate_officer(0)
	if GameSession.is_trailer_scenario:
		hold_coffee_cup()

	_anchor_local_position = position
	_cache_bridge_bounds()
	_anchor_local_position = _clamp_to_bridge_bounds(_anchor_local_position)
	position = _anchor_local_position
	_look_yaw = rotation.y
	if commander_camera:
		commander_camera.position.y = eye_height_m
		_look_pitch = commander_camera.rotation.x
		commander_camera.fov = _user_camera_fov()
		# Force a camera switch to initialize Godot's 3D audio listener.
		# Just setting current=true on the first camera isn't enough —
		# Godot needs to see a false→true transition to activate the listener.
		commander_camera.current = false
		call_deferred("_activate_initial_camera")
	else:
		print("[Commander] WARNING: No commander_camera found!")
	_setup_control_room_audio()
	var footsteps := preload("res://Audio/OfficerFootsteps.gd").new()
	footsteps.name = "OfficerFootsteps"
	add_child(footsteps)
	_setup_control_room_wind_audio()
	_connect_carrier_console()


func _input(event: InputEvent) -> void:
	if FlightDirector.recording_camera_active: return
	if _handle_computer_station_input(event):
		get_viewport().set_input_as_handled()
		return
	var key_event := event as InputEventKey
	if key_event == null:
		return
	var keycode := key_event.physical_keycode
	if keycode == KEY_NONE:
		keycode = key_event.keycode
	match keycode:
		KEY_UP:
			_arrow_backward_pressed = key_event.pressed
		KEY_DOWN:
			_arrow_forward_pressed = key_event.pressed
		KEY_LEFT:
			_arrow_left_pressed = key_event.pressed
		KEY_RIGHT:
			_arrow_right_pressed = key_event.pressed
		KEY_I:
			if key_event.pressed and not key_event.echo \
					and (_is_active_view() or _is_free_camera_view()):
				_cycle_officer_idle()
		KEY_O:
			if key_event.pressed and not key_event.echo \
					and (_is_active_view() or _is_free_camera_view()):
				_switch_officer()
		KEY_D:
			if key_event.pressed and not key_event.echo and key_event.shift_pressed \
					and (_is_active_view() or _is_free_camera_view()):
				_start_random_officer_dance()
		KEY_B:
			if key_event.pressed and not key_event.echo \
					and (_is_active_view() or _is_free_camera_view()) \
					and _active_computer_station == null \
					and not _computer_camera_transitioning \
					and get_viewport().gui_get_focus_owner() == null:
				_start_officer_sip()
				get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset_arrow_key_state()

func _activate_initial_camera() -> void:
	if commander_camera:
		get_viewport().audio_listener_enable_3d = true
		commander_camera.current = true

func _process(delta: float) -> void:
	var active_view := _is_active_view()
	var zoom_button_pressed := _is_zoom_button_pressed()
	var zoom_button_just_pressed := zoom_button_pressed and not _zoom_button_prev_pressed
	_zoom_button_prev_pressed = zoom_button_pressed
	if active_view and not _was_active_view:
		if _active_computer_station == null and not _computer_camera_transitioning:
			_apply_zoom(true)
		_set_glass_visible(false)
	elif not active_view and _was_active_view:
		_set_glass_visible(true)
	if active_view and _active_computer_station == null and not _computer_camera_transitioning \
			and (Input.is_action_just_pressed("toggle_zoom") or zoom_button_just_pressed):
		_is_zoomed = not _is_zoomed
		_apply_zoom()
	_was_active_view = active_view
	_update_body_visibility(active_view)
	_audio_room_check_time -= delta
	if _audio_room_check_time <= 0.0:
		_audio_room_check_time = 0.25
		_audio_inside_room = _has_interior_ceiling()
	_update_control_room_audio(delta, active_view and _audio_inside_room)
	_update_control_room_wind_audio(delta, active_view and _audio_inside_room)
	_update_external_camera_transforms()
	_update_computer_station_candidate()

func _physics_process(delta: float) -> void:
	if FlightDirector.recording_camera_active:
		velocity = Vector3.ZERO
		_set_officer_moving(false)
		return
	var active_commander_view := _is_active_view()
	var active_free_camera_view := _is_free_camera_view()
	if _active_computer_station != null or _computer_camera_transitioning:
		if not is_instance_valid(_active_computer_station) and not _computer_camera_transitioning:
			leave_computer_station()
		elif not _computer_camera_transitioning \
				and _active_computer_station.has_method("update_station_control"):
			if _active_computer_station.has_method("is_station_control_active") \
					and not bool(_active_computer_station.call("is_station_control_active")):
				leave_computer_station()
			else:
				_active_computer_station.call("update_station_control", delta)
		velocity = Vector3.ZERO
		_set_officer_moving(false)
		return
	if not active_commander_view and not active_free_camera_view:
		velocity = Vector3.ZERO
		_set_officer_moving(false)
		return

	position = _constrain_walk_position(position, position)

	_update_look(delta, active_commander_view)

	var forward_input := _keyboard_forward_input()
	var strafe_input := 0.0
	if active_commander_view:
		forward_input += Input.get_action_strength("pitch_up") \
			- Input.get_action_strength("pitch_down")
		strafe_input = Input.get_action_strength("roll_left") \
			- Input.get_action_strength("roll_right")
	forward_input = clampf(forward_input, -1.0, 1.0)
	var move_input := Vector2(strafe_input, forward_input)
	if move_input.length_squared() > 1.0:
		move_input = move_input.normalized()

	var move_basis := basis
	var right_dir := move_basis.x
	right_dir.y = 0.0
	right_dir = right_dir.normalized()

	var forward_dir := -move_basis.z
	forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()

	var move_velocity: Vector3 = ((right_dir * move_input.x) + (forward_dir * move_input.y)) * walk_speed_mps

	# When standing still, just hold the last valid local spot.
	if move_input.length_squared() < 0.001:
		velocity = Vector3.ZERO
		_set_officer_moving(false)
		return

	velocity = Vector3.ZERO
	var previous_position := position
	position = _constrain_walk_position(position, position + move_velocity * delta)
	_anchor_local_position = position
	_set_officer_moving(position.distance_squared_to(previous_position) > 0.000001)


func _set_officer_moving(moving: bool) -> void:
	_officer_moving = moving
	if _coffee_visual != null and _active_officer_visual() == _coffee_visual:
		_coffee_visual.call("set_walking", moving, walk_speed_mps)
		return
	if _officer_dancing:
		if not moving:
			return
		_officer_dancing = false
	var active_visual := _active_officer_visual()
	if active_visual == null:
		return
	var target_animation := officer_walk_animation if moving else officer_idle_animation
	if target_animation == &"":
		return
	var playback_speed := 1.0
	if moving:
		playback_speed = clampf(
			walk_speed_mps / maxf(officer_walk_reference_speed_mps, 0.1),
			0.55,
			1.6
		)
	if target_animation == _officer_animation \
			and _officer_animation_player != null \
			and _officer_animation_player.is_playing():
		_officer_animation_player.speed_scale = playback_speed
		return
	var played := false
	if active_visual.has_method("play_baked_animation"):
		played = bool(active_visual.call("play_baked_animation", target_animation, playback_speed))
	elif _officer_animation_player != null and _officer_animation_player.has_animation(target_animation):
		_officer_animation_player.speed_scale = playback_speed
		_officer_animation_player.play(target_animation)
		played = true
	if played:
		_officer_animation = target_animation


func _start_officer_sip() -> void:
	if _officer_moving:
		return
	hold_coffee_cup()
	var player := _coffee_visual.get_node("AnimationPlayer") as AnimationPlayer
	if player.current_animation != &"Coffee_Sip" or not player.is_playing():
		_coffee_visual.call("play_sip")


func hold_coffee_cup() -> void:
	# Prepare the existing coffee rig without starting a sip. This also works
	# before a paused trailer's first frame, so the cup is already in her hand.
	if _coffee_visual == null:
		_coffee_visual = load("res://Models/Characters/OfficerFemaleCoffee.tscn").instantiate()
		_coffee_visual.name = "BodyVisualCoffee"
		add_child(_coffee_visual)
		_officer_visuals.append(_coffee_visual)
		var livery := get_node_or_null("/root/Livery")
		if livery != null:
			livery.call("apply", _coffee_visual)
	if _active_officer_visual() != _coffee_visual:
		_activate_officer(_officer_visuals.find(_coffee_visual))
		(_coffee_visual.get_node("AnimationPlayer") as AnimationPlayer).advance(0.0)


func _visual_animation_player(visual: Node3D) -> AnimationPlayer:
	var player := visual.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer
	return player if player != null else visual.get_node_or_null("AnimationPlayer") as AnimationPlayer


func _cycle_officer_idle() -> void:
	if _officer_animation_player == null:
		return
	var available_idles: Array[StringName] = []
	for animation_name in officer_idle_animations:
		if animation_name != &"" and _officer_animation_player.has_animation(animation_name):
			available_idles.append(animation_name)
	if available_idles.is_empty():
		return
	var current_index := available_idles.find(officer_idle_animation)
	officer_idle_animation = available_idles[(current_index + 1) % available_idles.size()]
	if not _officer_moving and not _officer_dancing:
		_officer_animation = &""
		_set_officer_moving(false)
	print(
		"[Commander] Officer idle animation: %s"
		% officer_idle_animation
	)


func _start_random_officer_dance() -> void:
	if _officer_dancing or _officer_moving or _officer_animation_player == null:
		return
	var available_dances: Array[StringName] = []
	for animation_name in officer_dance_animations:
		if animation_name != &"" and _officer_animation_player.has_animation(animation_name):
			available_dances.append(animation_name)
	if available_dances.is_empty():
		return
	var dance_index := randi_range(0, available_dances.size() - 1)
	if available_dances.size() > 1 and available_dances[dance_index] == _last_officer_dance:
		dance_index = (dance_index + 1) % available_dances.size()
	_play_officer_dance(available_dances[dance_index])


func _play_officer_dance(animation_name: StringName) -> bool:
	var active_visual := _active_officer_visual()
	if active_visual == null or _officer_animation_player == null \
			or not _officer_animation_player.has_animation(animation_name):
		return false
	var played := false
	if active_visual.has_method("play_baked_animation"):
		played = bool(active_visual.call("play_baked_animation", animation_name, 1.0))
	else:
		_officer_animation_player.speed_scale = 1.0
		_officer_animation_player.play(animation_name)
		played = true
	if not played:
		return false
	_officer_dancing = true
	_officer_animation = animation_name
	_last_officer_dance = animation_name
	print("[Commander] Officer dance: %s" % animation_name)
	return true


func _on_officer_animation_finished(
		animation_name: StringName,
		officer_index: int
) -> void:
	if officer_index != _active_officer_index \
			or not _officer_dancing \
			or animation_name != _officer_animation:
		return
	_officer_dancing = false
	_officer_animation = &""
	_set_officer_moving(false)


func _switch_officer() -> void:
	if _officer_visuals.size() < 2:
		return
	_activate_officer((_active_officer_index + 1) % _officer_visuals.size())
	print(
		"[Commander] Officer: %s"
		% ("coffee officer" if _active_officer_visual() == _coffee_visual else "male" if _active_officer_index == 1 else "female")
	)


func _activate_officer(officer_index: int) -> void:
	if _officer_visuals.is_empty():
		_officer_animation_player = null
		return
	_officer_dancing = false
	_active_officer_index = wrapi(officer_index, 0, _officer_visuals.size())
	for index in range(_officer_visuals.size()):
		var animation_player := _visual_animation_player(_officer_visuals[index])
		if animation_player == null:
			continue
		if index == _active_officer_index:
			_officer_visuals[index].process_mode = Node.PROCESS_MODE_INHERIT
			animation_player.active = true
			if _officer_visuals[index] == _coffee_visual:
				_coffee_visual.call("set_walking", false)
				animation_player.play(&"Coffee_Hold")
		else:
			if _officer_visuals[index].has_method("stop_baked_animation"):
				_officer_visuals[index].call("stop_baked_animation", false)
			else:
				animation_player.stop()
			animation_player.active = false
			_officer_visuals[index].process_mode = Node.PROCESS_MODE_DISABLED
	_officer_animation_player = _visual_animation_player(_active_officer_visual())
	_officer_animation = &""
	_set_officer_moving(_officer_moving)
	_update_body_visibility(_is_active_view())


func _active_officer_visual() -> Node3D:
	if _officer_visuals.is_empty() \
			or _active_officer_index < 0 \
			or _active_officer_index >= _officer_visuals.size():
		return null
	return _officer_visuals[_active_officer_index]

func _update_look(delta: float, include_gamepad_look: bool = true) -> void:
	var look_yaw_input := 0.0
	var look_pitch_input := 0.0
	var sensitivity_scale := 1.0
	if include_gamepad_look:
		look_yaw_input = Input.get_action_strength("look_right") \
			- Input.get_action_strength("look_left")
		look_pitch_input = Input.get_action_strength("look_up") \
			- Input.get_action_strength("look_down")
		sensitivity_scale = _user_look_sensitivity_multiplier()
		if _user_invert_look_y():
			look_pitch_input = -look_pitch_input

	_look_yaw -= look_yaw_input * deg_to_rad(look_sensitivity_deg) * sensitivity_scale * delta
	_look_yaw -= _keyboard_turn_input() * deg_to_rad(keyboard_turn_speed_degrees_s) * delta
	_look_pitch += look_pitch_input * deg_to_rad(look_sensitivity_deg) * sensitivity_scale * delta
	_look_pitch = clamp(
		_look_pitch,
		deg_to_rad(-pitch_limit_deg),
		deg_to_rad(pitch_limit_deg)
	)

	rotation.y = _look_yaw
	if include_gamepad_look and commander_camera != null:
		commander_camera.rotation.x = _look_pitch


func _keyboard_forward_input() -> float:
	return float(_arrow_forward_pressed) - float(_arrow_backward_pressed)


func _keyboard_turn_input() -> float:
	return float(_arrow_right_pressed) - float(_arrow_left_pressed)


func _reset_arrow_key_state() -> void:
	_arrow_forward_pressed = false
	_arrow_backward_pressed = false
	_arrow_left_pressed = false
	_arrow_right_pressed = false


func _handle_computer_station_input(event: InputEvent) -> bool:
	if _active_computer_station != null or _computer_camera_transitioning:
		if _is_computer_exit_event(event):
			leave_computer_station()
			return true
		if is_instance_valid(_active_computer_station) \
				and _active_computer_station.has_method("handle_station_input"):
			if _computer_camera_transitioning:
				return event is InputEventJoypadButton or event is InputEventJoypadMotion
			return bool(_active_computer_station.call("handle_station_input", event))
		return false
	if not _is_computer_use_event(event):
		return false
	_update_computer_station_candidate()
	if _computer_station_candidate == null:
		return false
	return enter_computer_station(_computer_station_candidate)


func _is_computer_use_event(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		var button_event := event as InputEventJoypadButton
		return button_event.pressed and button_event.button_index == JOY_BUTTON_A
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var keycode := key_event.physical_keycode
		if keycode == KEY_NONE:
			keycode = key_event.keycode
		return key_event.pressed and not key_event.echo and keycode == computer_interact_keyboard_key
	return false


func _is_computer_exit_event(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		var button_event := event as InputEventJoypadButton
		return button_event.pressed and button_event.button_index == JOY_BUTTON_B
	return event.is_action_pressed("ui_cancel", false)


func _update_computer_station_candidate() -> void:
	var previous_candidate := _computer_station_candidate
	_computer_station_candidate = null
	if _can_offer_computer_station_interaction():
		var best_score := -INF
		for node in get_tree().get_nodes_in_group("computer_station"):
			if not is_instance_valid(node) or not node.has_method("get_interaction_score"):
				continue
			var score := float(node.call("get_interaction_score", commander_camera))
			if score > best_score:
				best_score = score
				_computer_station_candidate = node as Node3D
	if previous_candidate != _computer_station_candidate \
			and is_instance_valid(previous_candidate) \
			and previous_candidate.has_method("set_interaction_available"):
		previous_candidate.call("set_interaction_available", false)
	if is_instance_valid(_computer_station_candidate) \
			and _computer_station_candidate.has_method("set_interaction_available"):
		_computer_station_candidate.call("set_interaction_available", true)


func _can_offer_computer_station_interaction() -> bool:
	if not _is_active_view() or _active_view_mode != VIEW_CONTROL_ROOM \
			or _active_computer_station != null or _computer_camera_transitioning:
		return false
	var console := _carrier_console()
	return console == null or not console.has_method("is_open") \
		or not bool(console.call("is_open"))


func enter_computer_station(station: Node3D) -> bool:
	if station == null or not is_instance_valid(station) \
			or not station.has_method("get_camera_anchor_transform") \
			or commander_camera == null or not _is_active_view() \
			or _active_computer_station != null:
		return false
	_active_computer_station = station
	_computer_camera_transitioning = true
	_standing_camera_transform = commander_camera.transform
	_standing_camera_fov = commander_camera.fov
	velocity = Vector3.ZERO
	_set_officer_moving(false)
	_clear_computer_station_candidate()
	if station.has_method("set_in_use"):
		station.call("set_in_use", true)

	var anchor_global: Transform3D = station.call("get_camera_anchor_transform") as Transform3D
	var target_transform := global_transform.affine_inverse() * anchor_global
	var target_fov := _standing_camera_fov
	if station.has_method("get_seated_camera_fov"):
		target_fov = float(station.call("get_seated_camera_fov"))
	var focus_transform := target_transform
	if station.has_method("get_screen_focus_camera_transform"):
		var focus_global: Transform3D = station.call(
			"get_screen_focus_camera_transform"
		) as Transform3D
		focus_transform = global_transform.affine_inverse() * focus_global
	var focus_fov := target_fov
	if station.has_method("get_screen_focus_fov"):
		var viewport_size := get_viewport().get_visible_rect().size
		var viewport_aspect := 16.0 / 9.0
		if viewport_size.y > 0.0:
			viewport_aspect = viewport_size.x / viewport_size.y
		focus_fov = float(station.call("get_screen_focus_fov", viewport_aspect))
	_start_computer_enter_camera_tween(
		target_transform,
		target_fov,
		focus_transform,
		focus_fov
	)
	return true


func leave_computer_station(close_console: bool = true) -> bool:
	if _active_computer_station == null and not _computer_camera_transitioning:
		return false
	var station := _active_computer_station
	_active_computer_station = null
	_computer_camera_transitioning = true
	if is_instance_valid(station) and station.has_method("set_in_use"):
		station.call("set_in_use", false)
	if close_console:
		var console := _carrier_console()
		if console != null and console.has_method("is_open") \
				and bool(console.call("is_open")) and console.has_method("set_open"):
			console.call("set_open", false)
	_start_computer_camera_tween(
		_standing_camera_transform,
		_standing_camera_fov,
		false
	)
	return true


func is_using_computer_station() -> bool:
	return _active_computer_station != null


func _start_computer_enter_camera_tween(
	anchor_transform: Transform3D,
	anchor_fov: float,
	focus_transform: Transform3D,
	focus_fov: float
) -> void:
	if _computer_camera_tween != null and _computer_camera_tween.is_valid():
		_computer_camera_tween.kill()
	var seat_duration := maxf(computer_camera_transition_s, 0.0)
	var focus_duration := maxf(computer_screen_focus_s, 0.0)
	if seat_duration <= 0.0 and focus_duration <= 0.0:
		_apply_computer_camera_pose(focus_transform, focus_fov)
		_finish_computer_camera_transition(true)
		return

	_computer_camera_tween = create_tween()
	if seat_duration > 0.0:
		_computer_camera_tween.tween_property(
			commander_camera,
			"transform",
			anchor_transform,
			seat_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_computer_camera_tween.parallel().tween_property(
			commander_camera,
			"fov",
			anchor_fov,
			seat_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_apply_computer_camera_pose(anchor_transform, anchor_fov)

	if focus_duration > 0.0:
		_computer_camera_tween.tween_property(
			commander_camera,
			"transform",
			focus_transform,
			focus_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_computer_camera_tween.parallel().tween_property(
			commander_camera,
			"fov",
			focus_fov,
			focus_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif seat_duration > 0.0:
		_computer_camera_tween.tween_callback(
			_apply_computer_camera_pose.bind(focus_transform, focus_fov)
		)
	else:
		_apply_computer_camera_pose(focus_transform, focus_fov)

	_computer_camera_tween.tween_callback(
		_finish_computer_camera_transition.bind(true)
	)


func _apply_computer_camera_pose(target_transform: Transform3D, target_fov: float) -> void:
	commander_camera.transform = target_transform
	commander_camera.fov = target_fov


func _start_computer_camera_tween(
		target_transform: Transform3D,
		target_fov: float,
		entering: bool
) -> void:
	if _computer_camera_tween != null and _computer_camera_tween.is_valid():
		_computer_camera_tween.kill()
	var duration := maxf(computer_camera_transition_s, 0.0)
	if duration <= 0.0:
		commander_camera.transform = target_transform
		commander_camera.fov = target_fov
		_finish_computer_camera_transition(entering)
		return
	_computer_camera_tween = create_tween()
	_computer_camera_tween.set_parallel(true)
	_computer_camera_tween.tween_property(
		commander_camera,
		"transform",
		target_transform,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_computer_camera_tween.tween_property(
		commander_camera,
		"fov",
		target_fov,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_computer_camera_tween.chain().tween_callback(
		_finish_computer_camera_transition.bind(entering)
	)


func _finish_computer_camera_transition(entering: bool) -> void:
	_computer_camera_transitioning = false
	if not entering or _active_computer_station == null:
		return
	if _active_computer_station.has_method("activate_station"):
		_active_computer_station.call("activate_station")
		return
	var console := _carrier_console()
	if console != null and console.has_method("show_page"):
		console.call("show_page", "tactical", true)


func _clear_computer_station_candidate() -> void:
	if is_instance_valid(_computer_station_candidate) \
			and _computer_station_candidate.has_method("set_interaction_available"):
		_computer_station_candidate.call("set_interaction_available", false)
	_computer_station_candidate = null


func _connect_carrier_console() -> void:
	var console := _carrier_console()
	var callback := Callable(self, "_on_carrier_console_closed")
	if console != null and console.has_signal("closed") \
			and not console.is_connected("closed", callback):
		console.connect("closed", callback)


func _on_carrier_console_closed() -> void:
	if _active_computer_station != null:
		leave_computer_station(false)


func _carrier_console() -> Node:
	return get_node_or_null("/root/CarrierConsole")

func _is_active_view() -> bool:
	return commander_camera != null and commander_camera.current


func _is_free_camera_view() -> bool:
	var flight_director := get_node_or_null("/root/FlightDirector")
	return flight_director != null \
			and flight_director.has_method("is_free_camera_active") \
			and bool(flight_director.call("is_free_camera_active"))

func get_camera() -> Camera3D:
	return get_camera_for_mode(_active_view_mode)

func get_camera_for_mode(mode: int) -> Camera3D:
	_ensure_external_cameras()
	match wrapi(mode, 0, VIEW_MODE_COUNT):
		VIEW_CHASE:
			return _chase_camera
		VIEW_CINEMATIC:
			return _cinematic_camera
		_:
			return commander_camera

func activate_view_mode(mode: int) -> Camera3D:
	_active_view_mode = wrapi(mode, 0, VIEW_MODE_COUNT)
	_update_external_camera_transforms()
	return get_camera_for_mode(_active_view_mode)

func get_view_mode_count() -> int:
	return VIEW_MODE_COUNT

func get_current_view_mode() -> int:
	return _active_view_mode

func is_control_room_camera(camera: Camera3D) -> bool:
	return camera != null and commander_camera != null and camera == commander_camera

func is_carrier_camera(camera: Camera3D) -> bool:
	if camera == null:
		return false
	_ensure_external_cameras()
	return camera == commander_camera or camera == _chase_camera or camera == _cinematic_camera

func set_aircraft_reference(_aircraft_node: Node3D) -> void:
	pass

func set_tracking_enabled(_enabled: bool) -> void:
	pass

func _cache_bridge_bounds() -> void:
	var bridge_body := get_parent().get_node_or_null("BridgeWalkCollision") as Node3D
	if bridge_body == null:
		return

	var floor_shape := bridge_body.get_node_or_null("Floor") as CollisionShape3D
	if floor_shape == null:
		return

	var box_shape := floor_shape.shape as BoxShape3D
	if box_shape == null:
		return

	var local_floor_transform: Transform3D = bridge_body.transform * floor_shape.transform
	var half_extents := box_shape.size * 0.5
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF

	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := local_floor_transform * Vector3(half_extents.x * sx, 0.0, half_extents.z * sz)
			min_x = minf(min_x, corner.x)
			max_x = maxf(max_x, corner.x)
			min_z = minf(min_z, corner.z)
			max_z = maxf(max_z, corner.z)

	_bridge_bounds_min = Vector2(min_x + bridge_wall_margin_m, min_z + bridge_wall_margin_m)
	_bridge_bounds_max = Vector2(max_x - bridge_wall_margin_m, max_z - bridge_wall_margin_m)
	_has_bridge_bounds = _bridge_bounds_min.x < _bridge_bounds_max.x and _bridge_bounds_min.y < _bridge_bounds_max.y

func _clamp_to_bridge_bounds(local_position: Vector3) -> Vector3:
	var clamped := local_position
	clamped.y = _anchor_local_position.y
	if not _has_bridge_bounds:
		return clamped

	clamped.x = clampf(clamped.x, _bridge_bounds_min.x, _bridge_bounds_max.x)
	# _bridge_bounds_min/max are Vector2(x, z) — .y component stores Z bounds
	clamped.z = clampf(clamped.z, _bridge_bounds_min.y, _bridge_bounds_max.y)
	return clamped

func _constrain_walk_position(current_position: Vector3, desired_position: Vector3) -> Vector3:
	if _walk_area_provider == null:
		_walk_area_provider = get_parent().get_node_or_null("CommanderWalkArea")
	if _walk_area_provider != null and _walk_area_provider.has_method("constrain_commander_position"):
		return _walk_area_provider.call("constrain_commander_position", current_position, desired_position) as Vector3
	return _clamp_to_bridge_bounds(desired_position)

func _update_body_visibility(active_view: bool) -> void:
	for index in range(_officer_visuals.size()):
		var officer_visual := _officer_visuals[index]
		var is_selected := index == _active_officer_index
		officer_visual.visible = is_selected and not active_view
		for child in officer_visual.find_children("*", "GeometryInstance3D", true, false):
			var geometry := child as GeometryInstance3D
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
				if is_selected and not active_view \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _is_zoom_button_pressed() -> bool:
	for device in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_STICK):
			return true
	return false

func _apply_zoom(instant: bool = false) -> void:
	if commander_camera == null:
		return
	var target_fov: float = zoomed_fov if _is_zoomed else _user_camera_fov()
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	if instant:
		commander_camera.fov = target_fov
	else:
		_zoom_tween = create_tween()
		_zoom_tween.tween_property(commander_camera, "fov", target_fov, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func apply_user_camera_settings() -> void:
	_apply_zoom(true)
	if is_instance_valid(_chase_camera):
		_chase_camera.fov = _user_camera_fov()
	if is_instance_valid(_cinematic_camera):
		_cinematic_camera.fov = _user_camera_fov()


func _user_camera_fov() -> float:
	var settings := _user_settings_node()
	if settings != null and settings.has_method("get_camera_fov"):
		return float(settings.call("get_camera_fov"))
	return normal_fov


func _user_look_sensitivity_multiplier() -> float:
	var settings := _user_settings_node()
	if settings != null and settings.has_method("get_look_sensitivity_multiplier"):
		return float(settings.call("get_look_sensitivity_multiplier"))
	return 1.0


func _user_invert_look_y() -> bool:
	var settings := _user_settings_node()
	return settings != null \
			and settings.has_method("get_invert_look_y") \
			and bool(settings.call("get_invert_look_y"))


func _user_settings_node() -> Node:
	if not is_instance_valid(_pause_menu_settings):
		_pause_menu_settings = get_node_or_null("/root/PauseMenu")
	return _pause_menu_settings

func _setup_control_room_audio() -> void:
	if control_room_ambience == null:
		return

	control_room_ambience = preload("res://Audio/RuntimeAudio.gd").loop_stream(control_room_ambience)

	_control_room_audio_player = AudioStreamPlayer.new()
	_control_room_audio_player.name = "ControlRoomAmbience"
	_control_room_audio_player.stream = control_room_ambience
	_control_room_audio_player.bus = control_room_ambience_bus
	_control_room_audio_player.pitch_scale = control_room_ambience_pitch_scale
	_control_room_audio_player.volume_db = control_room_ambience_silence_db
	add_child(_control_room_audio_player)
	_control_room_audio_player.play()

func _has_interior_ceiling() -> bool:
	var carrier := get_parent() as Node3D
	if carrier.get_node_or_null("CommanderWalkArea") == null:
		return true
	var head := position + Vector3.UP * 1.8
	var query := PhysicsRayQueryParameters3D.create(carrier.to_global(head), carrier.to_global(head + Vector3.UP * 6.0), 1 << 20)
	query.hit_back_faces = true
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _setup_control_room_wind_audio() -> void:
	if control_room_wind == null:
		return

	if control_room_wind is AudioStreamWAV:
		control_room_wind.loop_mode = AudioStreamWAV.LOOP_FORWARD

	_control_room_wind_player = AudioStreamPlayer.new()
	_control_room_wind_player.name = "ControlRoomMuffledWind"
	_control_room_wind_player.stream = control_room_wind
	_control_room_wind_player.bus = control_room_wind_bus
	_control_room_wind_player.pitch_scale = control_room_wind_pitch_min
	_control_room_wind_player.volume_db = control_room_wind_silence_db
	add_child(_control_room_wind_player)
	_control_room_wind_player.play()

func _update_control_room_audio(delta: float, active_view: bool) -> void:
	if _control_room_audio_player == null:
		return

	var target_volume: float = control_room_ambience_volume_db if active_view else control_room_ambience_silence_db
	var blend := clampf(delta * 4.0, 0.0, 1.0)
	_control_room_audio_player.volume_db = lerpf(_control_room_audio_player.volume_db, target_volume, blend)
	if absf(_control_room_audio_player.volume_db - target_volume) < 0.05:
		_control_room_audio_player.volume_db = target_volume

	if not _control_room_audio_player.playing:
		_control_room_audio_player.play()

func _update_control_room_wind_audio(delta: float, active_view: bool) -> void:
	if _control_room_wind_player == null:
		return

	var carrier_speed: float = 0.0
	var carrier_node := get_parent()
	if carrier_node != null and carrier_node.has_method("get_speed"):
		carrier_speed = absf(float(carrier_node.call("get_speed")))

	var speed_factor := clampf(carrier_speed / maxf(control_room_wind_full_speed_mps, 0.01), 0.0, 1.0)
	speed_factor = speed_factor * speed_factor * (3.0 - 2.0 * speed_factor)
	var moving_volume := lerpf(control_room_wind_idle_volume_db, control_room_wind_max_volume_db, speed_factor)
	var target_volume := moving_volume if active_view else control_room_wind_silence_db
	var target_pitch := lerpf(control_room_wind_pitch_min, control_room_wind_pitch_max, speed_factor)
	var blend := clampf(delta * 3.0, 0.0, 1.0)
	_control_room_wind_player.volume_db = lerpf(_control_room_wind_player.volume_db, target_volume, blend)
	_control_room_wind_player.pitch_scale = lerpf(_control_room_wind_player.pitch_scale, target_pitch, blend)
	if absf(_control_room_wind_player.volume_db - target_volume) < 0.05:
		_control_room_wind_player.volume_db = target_volume

	if not _control_room_wind_player.playing:
		_control_room_wind_player.play()

func _ensure_external_cameras() -> void:
	if _chase_camera != null and _cinematic_camera != null:
		return
	var carrier_node := get_parent() as Node3D
	if carrier_node == null:
		return
	if _chase_camera == null:
		_chase_camera = _make_external_camera("CarrierChaseCamera")
		carrier_node.add_child(_chase_camera)
	if _cinematic_camera == null:
		_cinematic_camera = _make_external_camera("CarrierCinematicCamera")
		carrier_node.add_child(_cinematic_camera)
	_update_external_camera_transforms()

func _make_external_camera(camera_name: String) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = camera_name
	camera.fov = _user_camera_fov()
	camera.far = 5000.0
	camera.current = false
	return camera

func _update_external_camera_transforms() -> void:
	_ensure_external_cameras()
	var carrier_node := get_parent() as Node3D
	if carrier_node == null:
		return
	_place_external_camera(_chase_camera, carrier_node, chase_camera_local_position, chase_camera_focus_local_position)
	_place_external_camera(_cinematic_camera, carrier_node, cinematic_camera_local_position, cinematic_camera_focus_local_position)

func _place_external_camera(camera: Camera3D, carrier_node: Node3D, local_position: Vector3, local_focus: Vector3) -> void:
	if camera == null:
		return
	camera.global_position = carrier_node.global_transform * local_position
	var focus_position: Vector3 = carrier_node.global_transform * local_focus
	if not camera.global_position.is_equal_approx(focus_position):
		camera.look_at(focus_position, Vector3.UP)


func _find_glass_meshes() -> void:
	_glass_meshes.clear()
	_glass_surfaces.clear()
	var root := get_parent()
	if not is_instance_valid(root):
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back() as Node
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if node.name.to_lower() == "glass":
				# Legacy carrier: its windows are a dedicated mesh.
				_glass_meshes.append(mesh_instance)
			else:
				_find_glass_material_surfaces(mesh_instance)
		for child in node.get_children():
			stack.append(child)
	_glass_found = true


func _find_glass_material_surfaces(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null:
		return
	for surface_index in mesh_instance.mesh.get_surface_count():
		var override_material := mesh_instance.get_surface_override_material(surface_index)
		var surface_material := override_material
		if surface_material == null:
			surface_material = mesh_instance.mesh.surface_get_material(surface_index)
		if surface_material == null or surface_material.resource_name.strip_edges().to_lower() != "glass":
			continue
		_glass_surfaces.append({
			"mesh": mesh_instance,
			"surface": surface_index,
			"original_override": override_material,
		})


func _get_hidden_glass_material() -> StandardMaterial3D:
	if _hidden_glass_material == null:
		_hidden_glass_material = StandardMaterial3D.new()
		_hidden_glass_material.resource_name = "CommanderHiddenGlass"
		_hidden_glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hidden_glass_material.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
		_hidden_glass_material.no_depth_test = true
	return _hidden_glass_material


func _set_glass_visible(visible: bool) -> void:
	if not _glass_found:
		_find_glass_meshes()
	for mi in _glass_meshes:
		if is_instance_valid(mi):
			mi.visible = visible
	for entry in _glass_surfaces:
		var mesh_instance := entry.get("mesh") as MeshInstance3D
		if not is_instance_valid(mesh_instance):
			continue
		var surface_index := int(entry.get("surface", -1))
		if surface_index < 0 or mesh_instance.mesh == null or surface_index >= mesh_instance.mesh.get_surface_count():
			continue
		var material := entry.get("original_override") as Material if visible else _get_hidden_glass_material()
		mesh_instance.set_surface_override_material(surface_index, material)
