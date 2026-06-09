extends CharacterBody3D
class_name Commander

@export var eye_height_m: float = 1.8
@export var walk_speed_mps: float = 3.5
@export var look_sensitivity_deg: float = 120.0
@export var pitch_limit_deg: float = 85.0
@export var gravity_mps2: float = 9.8
@export var bridge_wall_margin_m: float = 0.55
@export var normal_fov: float = 75.0
@export var zoomed_fov: float = 30.0
@export var control_room_ambience: AudioStream = preload("res://Audio/Carrier/control_room_ambience.wav")
@export var control_room_ambience_bus: String = "Master"
@export var control_room_ambience_volume_db: float = -10.0
@export var control_room_ambience_pitch_scale: float = 1.0
@export var control_room_ambience_silence_db: float = -80.0

@onready var commander_camera: Camera3D = $Camera3D
@onready var body_mesh: MeshInstance3D = $BodyMesh

var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _glass_meshes: Array[MeshInstance3D] = []
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

func _ready() -> void:
	physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_INHERIT
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if commander_camera:
		commander_camera.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_INHERIT
		commander_camera.top_level = false
	if body_mesh:
		body_mesh.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_INHERIT

	_anchor_local_position = position
	_cache_bridge_bounds()
	_anchor_local_position = _clamp_to_bridge_bounds(_anchor_local_position)
	position = _anchor_local_position
	_look_yaw = rotation.y
	if commander_camera:
		commander_camera.position.y = eye_height_m
		_look_pitch = commander_camera.rotation.x
		commander_camera.fov = normal_fov
		# Force a camera switch to initialize Godot's 3D audio listener.
		# Just setting current=true on the first camera isn't enough —
		# Godot needs to see a false→true transition to activate the listener.
		commander_camera.current = false
		call_deferred("_activate_initial_camera")
	else:
		print("[Commander] WARNING: No commander_camera found!")
	_setup_control_room_audio()

func _activate_initial_camera() -> void:
	if commander_camera:
		commander_camera.current = true

func _process(delta: float) -> void:
	var active_view := _is_active_view()
	var zoom_button_pressed := _is_zoom_button_pressed()
	var zoom_button_just_pressed := zoom_button_pressed and not _zoom_button_prev_pressed
	_zoom_button_prev_pressed = zoom_button_pressed
	if active_view and not _was_active_view:
		_apply_zoom(true)
		_set_glass_visible(false)
	elif not active_view and _was_active_view:
		_set_glass_visible(true)
	if active_view and (Input.is_action_just_pressed("toggle_zoom") or zoom_button_just_pressed):
		_is_zoomed = not _is_zoomed
		_apply_zoom()
	_was_active_view = active_view
	_update_body_visibility(active_view)
	_update_control_room_audio(delta, active_view)

func _physics_process(delta: float) -> void:
	if not _is_active_view():
		velocity = Vector3.ZERO
		return

	_update_look(delta)

	var forward_input := Input.get_action_strength("pitch_up") - Input.get_action_strength("pitch_down")
	var strafe_input := Input.get_action_strength("roll_left") - Input.get_action_strength("roll_right")
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
		return

	velocity = Vector3.ZERO
	position = _clamp_to_bridge_bounds(position + move_velocity * delta)
	_anchor_local_position = position

func _update_look(delta: float) -> void:
	var look_yaw_input := Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	var look_pitch_input := Input.get_action_strength("look_up") - Input.get_action_strength("look_down")

	_look_yaw -= look_yaw_input * deg_to_rad(look_sensitivity_deg) * delta
	_look_pitch += look_pitch_input * deg_to_rad(look_sensitivity_deg) * delta
	_look_pitch = clamp(
		_look_pitch,
		deg_to_rad(-pitch_limit_deg),
		deg_to_rad(pitch_limit_deg)
	)

	rotation.y = _look_yaw
	commander_camera.rotation.x = _look_pitch

func _is_active_view() -> bool:
	return commander_camera != null and commander_camera.current

func get_camera() -> Camera3D:
	return commander_camera

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

func _update_body_visibility(active_view: bool) -> void:
	if body_mesh == null:
		return
	body_mesh.visible = not active_view
	body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if active_view else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _is_zoom_button_pressed() -> bool:
	for device in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_STICK):
			return true
	return false

func _apply_zoom(instant: bool = false) -> void:
	if commander_camera == null:
		return
	var target_fov: float = zoomed_fov if _is_zoomed else normal_fov
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	if instant:
		commander_camera.fov = target_fov
	else:
		_zoom_tween = create_tween()
		_zoom_tween.tween_property(commander_camera, "fov", target_fov, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _setup_control_room_audio() -> void:
	if control_room_ambience == null:
		return

	if control_room_ambience is AudioStreamWAV:
		control_room_ambience.loop_mode = AudioStreamWAV.LOOP_FORWARD

	_control_room_audio_player = AudioStreamPlayer.new()
	_control_room_audio_player.name = "ControlRoomAmbience"
	_control_room_audio_player.stream = control_room_ambience
	_control_room_audio_player.bus = control_room_ambience_bus
	_control_room_audio_player.pitch_scale = control_room_ambience_pitch_scale
	_control_room_audio_player.volume_db = control_room_ambience_silence_db
	add_child(_control_room_audio_player)
	_control_room_audio_player.play()

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


func _find_glass_meshes() -> void:
	_glass_meshes.clear()
	var root := get_parent()
	if not is_instance_valid(root):
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back() as Node
		if node is MeshInstance3D and node.name.to_lower() == "glass":
			_glass_meshes.append(node as MeshInstance3D)
		for child in node.get_children():
			stack.append(child)
	_glass_found = true


func _set_glass_visible(visible: bool) -> void:
	if not _glass_found:
		_find_glass_meshes()
	for mi in _glass_meshes:
		if is_instance_valid(mi):
			mi.visible = visible
