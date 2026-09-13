class_name MonitorStation
extends "res://LandCarrier/ComputerStation.gd"

## Screen-focused mast camera controls. Every instance receives the same shared
## camera texture; walking up to another monitor does not create another render.

var _carrier_camera: Node = null
var _control_device: int = 0


func _ready() -> void:
	super._ready()
	add_to_group("monitor_station")
	# Fit the approach to the named, transformed screen after every re-export.
	camera_anchor.transform = interaction_target.transform
	camera_anchor.position += interaction_target.basis.z * 1.15
	use_prompt.text = "[A]  MAST CAMERA"

func _attach_tactical_screen_display() -> void:
	call_deferred("_attach_carrier_camera_feed")

func activate_station() -> void:
	if is_instance_valid(_carrier_camera):
		_carrier_camera.call("begin_control")
		_carrier_camera.call("begin_fullscreen_view")

func is_station_control_active() -> bool:
	return is_instance_valid(_carrier_camera) and bool(_carrier_camera.get("_controlled"))

func set_in_use(value: bool) -> void:
	super.set_in_use(value)
	if not value and is_instance_valid(_carrier_camera):
		_carrier_camera.call("end_control")

func handle_station_input(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		_control_device = event.device
		return true
	if event is InputEventJoypadButton:
		_control_device = event.device
		if event.button_index == JOY_BUTTON_START:
			return false
		if event.pressed and is_instance_valid(_carrier_camera):
			if event.button_index == JOY_BUTTON_DPAD_LEFT:
				_carrier_camera.call("cycle_target", -1)
			elif event.button_index == JOY_BUTTON_DPAD_RIGHT:
				_carrier_camera.call("cycle_target", 1)
		return true
	return false

func update_station_control(delta: float) -> void:
	if not is_instance_valid(_carrier_camera):
		return
	var stick := Vector2(Input.get_joy_axis(_control_device, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(_control_device, JOY_AXIS_RIGHT_Y))
	if stick.length() < 0.18:
		stick = Vector2.ZERO
	else:
		stick = stick.normalized() * clampf((stick.length() - 0.18) / 0.82, 0.0, 1.0)
	var zoom := maxf(Input.get_joy_axis(_control_device, JOY_AXIS_TRIGGER_RIGHT), 0.0) \
		- maxf(Input.get_joy_axis(_control_device, JOY_AXIS_TRIGGER_LEFT), 0.0)
	_carrier_camera.call("apply_manual_input", stick, zoom, delta)


func _exit_tree() -> void:
	if _in_use and is_instance_valid(_carrier_camera):
		_carrier_camera.call("end_control")
	if is_instance_valid(_carrier_camera) and _screen_mesh != null \
			and _carrier_camera.has_method("unregister_screen"):
		_carrier_camera.call("unregister_screen", _screen_mesh)


func get_debug_snapshot() -> Dictionary:
	return {
		"screen_mesh_name": String(screen_mesh_name),
		"screen_mesh_found": _screen_mesh != null and is_instance_valid(_screen_mesh),
		"has_carrier_camera": _carrier_camera != null and is_instance_valid(_carrier_camera),
		"has_camera_material": _screen_mesh != null \
			and _screen_mesh.material_override is ShaderMaterial,
		"interactive": true,
	}


func _attach_carrier_camera_feed() -> void:
	if _screen_mesh == null or _screen_mesh.mesh == null:
		push_warning("[MonitorStation] screen mesh '%s' was not found." % screen_mesh_name)
		return
	_carrier_camera = _find_carrier_camera()
	if _carrier_camera == null or not _carrier_camera.has_method("register_screen"):
		push_warning("[MonitorStation] no carrier target camera is available for %s." % name)
		return
	_screen_mesh.material_override = _carrier_camera.call(
		"register_screen",
		_screen_mesh
	) as Material


func _find_carrier_camera() -> Node:
	var ancestor := get_parent()
	while ancestor != null:
		var named_camera := ancestor.get_node_or_null("CarrierTargetCamera")
		if named_camera != null and named_camera.has_method("register_screen"):
			return named_camera
		ancestor = ancestor.get_parent()
	if get_tree() != null:
		return get_tree().get_first_node_in_group("carrier_target_camera")
	return null
