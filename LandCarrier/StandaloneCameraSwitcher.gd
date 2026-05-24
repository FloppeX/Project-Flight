extends Node
class_name StandaloneCameraSwitcher

## Handles camera switching (Y button) when there is no player aircraft.
## Used when viewing from bridge only - allows switching to AI plane cameras.

var _cameras: Array = []
var _current_index: int = 0
var _last_switch_time: float = 0.0
var _switch_cooldown: float = 0.3

@export var explosion_linger_s: float = 4.0  # Stay on a destroyed plane's camera for this long
var _explosion_linger_until: float = 0.0     # Absolute time; 0 = no linger active

func _ready():
	add_to_group("standalone_camera_switcher")
	set_process_priority(100)  # Process input early, before other handlers
	# When no player, ensure bridge camera is active on load
	call_deferred("_ensure_bridge_active")

func _ensure_bridge_active():
	if get_tree().get_first_node_in_group("aircraft"):
		return
	var cam := _get_bridge_camera()
	if cam:
		cam.current = true

func _process(_delta: float):
	# Auto-switch away from a destroyed plane once linger time expires.
	if _explosion_linger_until <= 0.0:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _explosion_linger_until:
		return
	_explosion_linger_until = 0.0
	_switch_to_next_live_plane()

func notify_plane_destroyed(destroyed_aircraft: RigidBody3D):
	"""Called by EnemyAircraftSpawner when a plane is destroyed. Only switch if we are watching THAT plane."""
	if not is_instance_valid(destroyed_aircraft):
		return
	_build_camera_list()  # Ensure list is fresh before checking
	var active_cam: Camera3D = _get_active_camera()
	if active_cam == null:
		return
	# Only switch if the active camera belongs to the destroyed aircraft.
	# Bridge camera has no aircraft (returns null) – never switch when viewing bridge.
	var cam_aircraft: Node = _get_camera_aircraft(active_cam)
	if cam_aircraft == null:
		return  # Viewing bridge or other non-aircraft camera – do not switch
	if not is_instance_valid(cam_aircraft):
		return
	if cam_aircraft != destroyed_aircraft:
		return  # Viewing a different plane – do not switch
	# We are watching the plane that just exploded – start the linger timer.
	_explosion_linger_until = Time.get_ticks_msec() / 1000.0 + explosion_linger_s

func _switch_to_next_live_plane():
	_build_camera_list()
	if _cameras.is_empty():
		return
	# Find a camera that belongs to a still-valid (alive) aircraft.
	for i in range(_cameras.size()):
		var idx: int = (_current_index + 1 + i) % _cameras.size()
		var cam: Camera3D = _cameras[idx]
		if not is_instance_valid(cam):
			continue
		var owner_ac: Node = _get_camera_aircraft(cam)
		if owner_ac and is_instance_valid(owner_ac):
			_current_index = idx
			_activate_camera(cam)
			return
	# No live AI plane found – fall back to bridge.
	_ensure_bridge_active()

func _get_active_camera() -> Camera3D:
	for cam in _cameras:
		if is_instance_valid(cam) and cam is Camera3D and cam.current:
			return cam
	# Rebuild and try again in case list is stale.
	_build_camera_list()
	for cam in _cameras:
		if is_instance_valid(cam) and cam is Camera3D and cam.current:
			return cam
	return null

func _get_camera_aircraft(cam: Camera3D) -> Node:
	var parent: Node = cam.get_parent()
	if parent:
		var grandparent: Node = parent.get_parent()
		if grandparent and grandparent is RigidBody3D:
			return grandparent
	return null

func _input(event):
	if not Input.is_action_just_pressed("switch_camera"):
		return
	
	# Only handle when there's no player aircraft - otherwise CameraController on aircraft handles it.
	# An ejected player pilot is also an aircraft camera target.
	if get_tree().get_first_node_in_group("aircraft") or get_tree().get_first_node_in_group("ejected_pilots"):
		return
	
	# Don't allow manual switching during explosion linger.
	if _explosion_linger_until > 0.0 and Time.get_ticks_msec() / 1000.0 < _explosion_linger_until:
		return
	
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_switch_time < _switch_cooldown:
		return
	
	_build_camera_list()
	if _cameras.is_empty():
		return
	
	_last_switch_time = now
	_current_index = (_current_index + 1) % _cameras.size()
	_activate_camera(_cameras[_current_index])

func _build_camera_list():
	_cameras.clear()
	
	# Bridge camera
	var bridge_cam := _get_bridge_camera()
	if bridge_cam:
		_cameras.append(bridge_cam)
	
	# AI aircraft cameras (friendly AI planes)
	for node in get_tree().get_nodes_in_group("ai_aircraft"):
		if not (node is RigidBody3D) or not is_instance_valid(node):
			continue
		var ac = node as RigidBody3D
		for tripod_name in ["CameraCockpit", "CameraChase", "CameraCinematic"]:
			var cam = ac.get_node_or_null(tripod_name + "/Camera3D") as Camera3D
			if not cam:
				var tripod = ac.get_node_or_null(tripod_name) as Node3D
				if tripod:
					cam = tripod.find_child("Camera3D", true, false) as Camera3D
			if cam:
				_cameras.append(cam)

func get_watched_aircraft() -> RigidBody3D:
	"""Return the aircraft whose camera is currently active, or null if watching the bridge."""
	_build_camera_list()
	var active_cam: Camera3D = _get_active_camera()
	if active_cam == null:
		return null
	return _get_camera_aircraft(active_cam) as RigidBody3D

func _activate_camera(cam: Camera3D):
	# Deactivate all known cameras
	for c in _cameras:
		c.current = false
	cam.current = true
	
	# Ensure chase/cinematic scripts run for the activated aircraft
	var cam_parent = cam.get_parent()
	if cam_parent:
		var ac = cam_parent.get_parent()
		if ac is RigidBody3D:
			if cam_parent.name == "CameraChase":
				if cam_parent.has_method("setup_aircraft"):
					cam_parent.setup_aircraft(ac)
				if cam_parent.has_method("reset_look"):
					cam_parent.reset_look()
			elif cam_parent.name == "CameraCinematic":
				if not cam_parent.get_script():
					cam_parent.set_script(preload("res://Camera/CinematicCamera.gd"))
				if cam_parent.has_method("setup_aircraft"):
					cam_parent.setup_aircraft(ac)
				if cam_parent.has_method("setup_shot"):
					cam_parent.setup_shot()

func _get_bridge_camera() -> Camera3D:
	for node in get_tree().get_nodes_in_group("carrier_cam"):
		if node != null and node.has_method("get_camera"):
			var cam = node.call("get_camera")
			if is_instance_valid(cam) and cam is Camera3D:
				return cam as Camera3D
	return null
