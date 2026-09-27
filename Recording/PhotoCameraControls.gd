extends Node
## Uses the trailer free-camera controls, without recording/subject shortcuts.
const Controls := preload("res://Recording/CinematicCameraInput.gd")
var camera: Camera3D
var active := false
var move_speed_level := 4
var move_speed := 10.0
var motion := Vector3.ZERO
var _look := Vector2.ZERO
var _editing := false
var _pad_device := -1
var _pad_axes: Dictionary = {}
var _pad_buttons: Dictionary = {}
var _previous_mouse := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_pad_connection)
	set_process(false)

func begin(view: Camera3D) -> void:
	camera = view
	active = true
	_previous_mouse = Input.mouse_mode
	_clear_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)

func end() -> void:
	active = false
	_clear_input()
	Input.mouse_mode = _previous_mouse
	camera = null
	set_process(false)

func _clear_input() -> void:
	_pad_device = -1
	_pad_axes.clear()
	_pad_buttons.clear()
	_look = Vector2.ZERO
	_editing = false
	motion = Vector3.ZERO

func _on_pad_connection(device: int, connected: bool) -> void:
	if not connected and device == _pad_device:
		_clear_input()
		if active: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_input()
		if active: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func handle_input(event: InputEvent) -> bool:
	if not active or not is_instance_valid(camera): return false
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		if event is InputEventJoypadButton and event.button_index not in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]: return false
		if _pad_device != event.device:
			_pad_axes.clear()
			_pad_buttons.clear()
			motion = Vector3.ZERO
			_pad_device = event.device
		if event is InputEventJoypadMotion:
			_pad_axes[event.axis] = event.axis_value
		else:
			var was_pressed := bool(_pad_buttons.get(event.button_index, false))
			_pad_buttons[event.button_index] = event.pressed
			if event.pressed and not was_pressed and event.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
				move_speed_level = clampi(move_speed_level + (1 if event.button_index == JOY_BUTTON_DPAD_UP else -1), 0, Controls.MOVE_SPEED_LEVELS.size() - 1)
				motion = Vector3.ZERO
		return true
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_editing = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _editing else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera.fov = clampf(camera.fov + (-2.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 2.0), 15.0, 110.0)
		return true
	if event is InputEventMouseMotion:
		if _editing: _look += event.relative * 0.002
		return true
	if event is InputEventKey:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_Z, KEY_C, KEY_SHIFT, KEY_CTRL]
	return false

func _process(delta: float) -> void:
	if not active or not is_instance_valid(camera): return
	var direction := Vector3.ZERO
	var roll := 0.0
	if _editing:
		direction = Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		roll = float(Input.is_physical_key_pressed(KEY_C)) - float(Input.is_physical_key_pressed(KEY_Z))
	var pad := Controls.pad_motion(_pad_axes, _pad_buttons)
	direction += pad.move
	_look += pad.look * delta * 1.4
	roll += pad.roll
	camera.fov = clampf(camera.fov + float(pad.zoom) * 40.0 * delta, 15.0, 110.0)
	move_speed = clampf(float(Controls.MOVE_SPEED_LEVELS[move_speed_level]) * (4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else (0.2 if Input.is_physical_key_pressed(KEY_CTRL) else 1.0)), Controls.MOVE_SPEED_LEVELS.front(), Controls.MOVE_SPEED_LEVELS.back())
	# Same world-attached motion and rotation as RecordingCamera.move_camera().
	var pose := camera.global_transform
	if direction.is_zero_approx(): motion = Vector3.ZERO
	else: motion = motion.lerp(pose.basis * direction.limit_length() * move_speed, 1.0 - exp(-10.0 * delta))
	pose.origin += motion * delta
	pose.basis = (Basis(Vector3.UP, -_look.x) * pose.basis * Basis(Vector3.RIGHT, -_look.y) * Basis(Vector3.BACK, roll * delta)).orthonormalized()
	camera.global_transform = pose
	_look = Vector2.ZERO
	if get_tree().paused:
		var terrain := TerrainReference.get_terrain_node()
		if terrain != null and terrain.has_method("update_paused_camera_stream"):
			terrain.call("update_paused_camera_stream", delta)
