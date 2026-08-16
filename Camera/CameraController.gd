extends Node
class_name CameraController

@export var aircraft: RigidBody3D 
@export var cockpit_tripod: Node3D
@export var chase_tripod: Node3D  
@export var cinematic_tripod: Node3D
@export var carrier_cam_path: NodePath  # Optional external cinematic camera (e.g., Carrier control tower)
@export var carrier_orbit_center_path: NodePath  # Center point to orbit around (e.g., bridge center Node3D)
@export var carrier_orbit_radius: float = 3.0
@export var carrier_orbit_height: float = 2.0
@export var carrier_orbit_speed: float = 0.0  # radians/sec (0 = manual only)
@export var carrier_look_sensitivity: float = 1.5  # input sensitivity for yaw/pitch
@export var carrier_pitch_limit_deg: float = 45.0
@export var deathcam_use_chase: bool = true  # If true, use chase cam for deathcam; else use cinematic

# Zoom variables
@export var normal_fov: float = 75.0
@export var zoomed_fov: float = 30.0
@export var cockpit_near: float = 0.01
var is_zoomed: bool = false
var fov_tween: Tween

var cockpit_camera: Camera3D
var chase_camera: Camera3D  
var cinematic_camera: Camera3D
var bridge_camera: Camera3D

var cockpit_script: CockpitCamera
var chase_script: ChaseCamera
var cinematic_script: CinematicCamera
var bridge_script: Node
var _ejected_pilot_focus: Node3D
var _pilot_ejected: bool = false

enum CameraMode { COCKPIT, CHASE, CINEMATIC, BRIDGE, DEATHCAM }
var current_mode: CameraMode = CameraMode.COCKPIT
var last_switch_time: float = 0.0
var switch_cooldown: float = 0.3  # Prevent rapid switching

# Extended cycling: each element is {"aircraft": RigidBody3D or null, "mode": CameraMode}
var _view_targets: Array = []
var _current_view_index: int = 0

# Deathcam variables
var deathcam_active: bool = false
var deathcam_target_position: Vector3
var deathcam_radius: float = 15.0
var deathcam_height: float = 5.0
var deathcam_speed: float = 1.0
var deathcam_time: float = 0.0
var deathcam_duration: float = 10.0  # How long to circle before cleaning up

# Carrier cam state
var _use_external_cinematic: bool = false
var _carrier_center: Node3D
var _carrier_yaw: float = 0.0
var _carrier_pitch: float = 0.0
var _zoom_button_prev_pressed: bool = false
var _pending_forced_camera: Camera3D = null

func _ready():
	# Add to camera controller group for easy finding
	add_to_group("camera_controller")
	add_to_group("origin_shifter")
	
	# Find the Camera3D inside each tripod scene
	cockpit_camera = cockpit_tripod.find_child("Camera3D", true, false)
	chase_camera = chase_tripod.find_child("Camera3D", true, false)
	cinematic_camera = null
	bridge_camera = null
	_apply_cockpit_camera_settings(cockpit_camera)
	if cockpit_camera:
		cockpit_camera.fov = normal_fov
	if chase_camera:
		chase_camera.fov = normal_fov
	
	# Set up camera scripts
	cockpit_tripod.set_script(preload("res://Camera/CockpitCamera.gd"))
	cockpit_script = cockpit_tripod as CockpitCamera
	
	# For chase and cinematic cameras, we need to detach them from aircraft transform
	# by using global positioning instead of inheriting aircraft movement
	chase_tripod.set_script(preload("res://Camera/camera_chase.gd"))
	chase_script = chase_tripod as ChaseCamera
	if chase_script:
		chase_script.setup_aircraft(aircraft)
	
	# Set up bridge camera
	setup_bridge_camera()
	
	# Prefer external carrier cam for cinematic, else fall back to tripod
	var external_cam: Camera3D = null
	if carrier_cam_path != NodePath():
		external_cam = get_node_or_null(carrier_cam_path) as Camera3D
	var scene_tree := get_tree() if is_inside_tree() else null
	if not external_cam and scene_tree != null:
		external_cam = scene_tree.get_first_node_in_group("carrier_cam") as Camera3D
	if external_cam:
		cinematic_camera = external_cam
		cinematic_script = null
		_use_external_cinematic = true
		# Resolve orbit center
		_carrier_center = null
		if carrier_orbit_center_path != NodePath():
			_carrier_center = get_node_or_null(carrier_orbit_center_path) as Node3D
		if _carrier_center == null and cinematic_camera and cinematic_camera.get_parent() is Node3D:
			_carrier_center = cinematic_camera.get_parent()
		# Initialize yaw from current placement
		if _carrier_center and cinematic_camera:
			var rel = cinematic_camera.global_position - _carrier_center.global_position
			_carrier_yaw = atan2(rel.z, rel.x)
			_carrier_pitch = 0.0
	else:
		cinematic_tripod.set_script(preload("res://Camera/CinematicCamera.gd"))
		cinematic_script = cinematic_tripod as CinematicCamera
		if cinematic_script:
			cinematic_script.setup_aircraft(aircraft)
		cinematic_camera = cinematic_tripod.find_child("Camera3D", true, false)
		if cinematic_camera:
			cinematic_camera.fov = normal_fov
		_use_external_cinematic = false

	# Build view targets for cycling (player + AI aircraft)
	_build_view_targets()

	# Only claim the viewport camera if no camera is currently active.
	# This prevents newly spawned AI aircraft from stealing the view.
	if _should_claim_initial_camera():
		# Start with bridge camera if available, otherwise cockpit
		if _view_targets.is_empty():
			if cockpit_camera:
				cockpit_camera.current = true
		elif bridge_camera:
			var found := false
			for i in range(_view_targets.size()):
				if _view_targets[i].get("mode") == CameraMode.BRIDGE:
					_current_view_index = i
					_switch_to_view_target(_view_targets[i])
					found = true
					break
			if not found:
				_current_view_index = 0
				_switch_to_view_target(_view_targets[0])
		else:
			_current_view_index = 0
			_switch_to_view_target(_view_targets[0])

	# Night vision overlay — player aircraft only
	if aircraft != null and not aircraft.is_in_group("ai_aircraft"):
		var nv_overlay := preload("res://Camera/NightVisionOverlay.gd").new()
		add_child(nv_overlay)

func apply_origin_shift(offset: Vector3) -> void:
	deathcam_target_position -= offset

func setup_bridge_camera():
	# Skip if already set up
	if bridge_script and bridge_camera:
		return

	var bridge_provider := _get_bridge_camera_provider()
	if bridge_provider == null:
		return

	bridge_script = bridge_provider
	if bridge_script.has_method("set_aircraft_reference"):
		bridge_script.call("set_aircraft_reference", aircraft)

	var bridge_cam = bridge_script.call("get_camera")
	if bridge_cam is Camera3D:
		bridge_camera = bridge_cam as Camera3D

func _build_view_targets():
	"""Build list of (aircraft, mode) for camera cycling: player views, bridge, then each AI plane."""
	_view_targets.clear()
	if not is_instance_valid(aircraft):
		aircraft = null
		_current_view_index = -1
		return
	
	# Player aircraft views
	_view_targets.append({"aircraft": aircraft, "mode": CameraMode.COCKPIT})
	_view_targets.append({"aircraft": aircraft, "mode": CameraMode.CHASE})
	_view_targets.append({"aircraft": aircraft, "mode": CameraMode.CINEMATIC})
	if _pilot_ejected:
		return
	if not is_inside_tree():
		return
	var scene_tree := get_tree()
	
	# Bridge (static view)
	if is_instance_valid(bridge_camera):
		_view_targets.append({"aircraft": null, "mode": CameraMode.BRIDGE})
	
	# AI aircraft views (enemies group)
	var enemies = scene_tree.get_nodes_in_group("enemies")
	for node in enemies:
		if node is RigidBody3D and is_instance_valid(node):
			var ac = node as RigidBody3D
			if _get_camera_for(ac, CameraMode.COCKPIT):
				_view_targets.append({"aircraft": ac, "mode": CameraMode.COCKPIT})
			if _get_camera_for(ac, CameraMode.CHASE):
				_view_targets.append({"aircraft": ac, "mode": CameraMode.CHASE})
			if _get_camera_for(ac, CameraMode.CINEMATIC):
				_view_targets.append({"aircraft": ac, "mode": CameraMode.CINEMATIC})

func focus_ejected_pilot(ejected_body: RigidBody3D, pilot_focus: Node3D) -> void:
	if ejected_body == null or not is_instance_valid(ejected_body):
		return
	if _is_ai_or_enemy_aircraft(aircraft) and not bool(aircraft.get_meta("player_ejection_camera_takeover", false)):
		return

	# Ejection supersedes any crash/death-camera state that may have started from
	# the same damage signal. Every surviving mode belongs to the pilot now.
	deathcam_active = false
	deathcam_time = 0.0
	_pilot_ejected = true
	aircraft = ejected_body
	_ejected_pilot_focus = pilot_focus
	if chase_tripod != null and is_instance_valid(chase_tripod):
		chase_tripod.set_process(true)
		chase_tripod.set_physics_process(true)
	_detach_camera_nodes_for_ejection()
	if cockpit_tripod != null and is_instance_valid(cockpit_tripod):
		cockpit_camera = cockpit_tripod.find_child("Camera3D", true, false) as Camera3D
		_apply_cockpit_camera_settings(cockpit_camera)
	if chase_script:
		chase_script.setup_follow_target(ejected_body, pilot_focus)
	if cinematic_script:
		cinematic_script.setup_follow_target(ejected_body, pilot_focus)
		cinematic_script.setup_shot()
	if bridge_script and bridge_script.has_method("set_aircraft_reference"):
		bridge_script.call("set_aircraft_reference", pilot_focus if pilot_focus != null else ejected_body)

	_build_view_targets()
	for i in range(_view_targets.size()):
		var target: Dictionary = _view_targets[i] as Dictionary
		if target.get("aircraft", null) == ejected_body and target.get("mode", null) == CameraMode.COCKPIT:
			_current_view_index = i
			_switch_to_view_target(target)
			return
	_current_view_index = 0 if not _view_targets.is_empty() else -1
	if _current_view_index >= 0:
		_switch_to_view_target(_view_targets[_current_view_index])


func release_ejected_pilot(new_target: RigidBody3D) -> void:
	_pilot_ejected = false
	_ejected_pilot_focus = null
	if is_instance_valid(new_target):
		aircraft = new_target
		if chase_script:
			chase_script.setup_aircraft(new_target)
		if cinematic_script:
			cinematic_script.setup_aircraft(new_target)
			cinematic_script.setup_shot()
		if bridge_script and bridge_script.has_method("set_aircraft_reference"):
			bridge_script.call("set_aircraft_reference", new_target)
	_build_view_targets()
	_current_view_index = 0
	if not _view_targets.is_empty():
		_switch_to_view_target(_view_targets[0])


func _detach_camera_nodes_for_ejection() -> void:
	_reparent_to_camera_survival_parent(self)
	_reparent_to_camera_survival_parent(chase_tripod)
	if not _use_external_cinematic:
		_reparent_to_camera_survival_parent(cinematic_tripod)


func _reparent_to_camera_survival_parent(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not is_inside_tree():
		return
	var scene_tree := get_tree()
	var new_parent := scene_tree.current_scene
	if new_parent == null:
		new_parent = scene_tree.root
	if new_parent == null or node.get_parent() == new_parent:
		return
	var old_parent := node.get_parent()
	if old_parent == null:
		return
	if node is Node3D:
		var node_3d := node as Node3D
		var saved_global := node_3d.global_transform
		old_parent.remove_child(node)
		new_parent.add_child(node)
		node_3d.global_transform = saved_global
	else:
		old_parent.remove_child(node)
		new_parent.add_child(node)


func _is_ai_or_enemy_aircraft(aircraft_node: Node) -> bool:
	if aircraft_node == null:
		return false
	return aircraft_node.is_in_group("ai_aircraft") or aircraft_node.is_in_group("enemies")


func _get_camera_for(aircraft_candidate: Variant, mode: CameraMode) -> Camera3D:
	"""Get the Camera3D for an aircraft and mode. Works for player or AI aircraft."""
	# Cached camera targets can outlive a crashed aircraft until the end of the
	# frame. Accept Variant here so Godot does not reject the call at the typed
	# function boundary before we can validate the reference.
	if not is_instance_valid(aircraft_candidate) or not (aircraft_candidate is RigidBody3D):
		return null
	var ac := aircraft_candidate as RigidBody3D
	if ac == aircraft:
		match mode:
			CameraMode.COCKPIT: return _valid_camera(cockpit_camera)
			CameraMode.CHASE: return _valid_camera(chase_camera)
			CameraMode.CINEMATIC: return _valid_camera(cinematic_camera)
			_: return null
	
	var tripod_name := ""
	match mode:
		CameraMode.COCKPIT: tripod_name = "CameraCockpit"
		CameraMode.CHASE: tripod_name = "CameraChase"
		CameraMode.CINEMATIC: tripod_name = "CameraCinematic"
		_: return null
	
	# Try direct path first (CameraTripod has Camera3D as direct child)
	var cam = ac.get_node_or_null(tripod_name + "/Camera3D") as Camera3D
	if cam:
		if mode == CameraMode.COCKPIT:
			_apply_cockpit_camera_settings(cam)
		return cam
	# Fallback: find_child for different scene structures
	var tripod = ac.get_node_or_null(tripod_name) as Node3D
	if tripod:
		cam = tripod.find_child("Camera3D", true, false) as Camera3D
		if mode == CameraMode.COCKPIT:
			_apply_cockpit_camera_settings(cam)
		return cam
	return null

func _apply_cockpit_camera_settings(cam: Camera3D) -> void:
	if cam == null:
		return
	cam.near = cockpit_near

func _get_chase_script_for(ac: RigidBody3D) -> ChaseCamera:
	if ac == aircraft:
		return chase_script
	var tripod = ac.get_node_or_null("CameraChase") as Node3D
	return tripod as ChaseCamera if tripod else null

func _get_cinematic_script_for(ac: RigidBody3D):
	if ac == aircraft:
		return cinematic_script
	var tripod = ac.get_node_or_null("CameraCinematic") as Node3D
	if tripod and tripod.get_script():
		return tripod
	return null

func find_node_by_name(parent: Node, target_name: String) -> Node:
	# Recursively search for a node by name
	if parent.name == target_name:
		return parent
	
	for child in parent.get_children():
		var result = find_node_by_name(child, target_name)
		if result:
			return result
	
	return null

func _retry_bridge_camera_setup():
	if bridge_script and bridge_camera:
		return
	setup_bridge_camera()

func _should_claim_initial_camera() -> bool:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return true
	var current_camera: Camera3D = viewport.get_camera_3d()
	return current_camera == null

func _get_bridge_camera_provider() -> Node:
	if not is_inside_tree():
		return null
	var scene_tree := get_tree()
	for node in scene_tree.get_nodes_in_group("carrier_cam"):
		if node != null and node.has_method("get_camera"):
			return node
	return null

func _input(event):
	# Don't allow camera switching during deathcam
	if deathcam_active:
		return
	
	# Manual carrier cam control (only when viewing player's external cinematic)
	if current_mode == CameraMode.CINEMATIC and _use_external_cinematic:
		if _current_view_index >= 0 and _current_view_index < _view_targets.size():
			var t = _view_targets[_current_view_index]
			if t.get("aircraft") == aircraft and t.get("mode") == CameraMode.CINEMATIC:
				var look_x = Input.get_action_strength("look_left") - Input.get_action_strength("look_right")
				var look_y = Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
				_carrier_yaw += look_x * carrier_look_sensitivity * 0.02
				_carrier_pitch = clamp(_carrier_pitch + look_y * carrier_look_sensitivity * 0.02, deg_to_rad(-carrier_pitch_limit_deg), deg_to_rad(carrier_pitch_limit_deg))

func _process(delta):
	var zoom_button_pressed := _is_zoom_button_pressed()
	var zoom_button_just_pressed := zoom_button_pressed and not _zoom_button_prev_pressed
	_zoom_button_prev_pressed = zoom_button_pressed

	if deathcam_active:
		update_deathcam(delta)
		return

	if _is_cockpit_zoom_view_active() and (Input.is_action_just_pressed("toggle_zoom") or zoom_button_just_pressed):
		is_zoomed = not is_zoomed
		update_camera_zoom()
	
	# Only run carrier cinematic orbit when viewing player's external cinematic
	if current_mode == CameraMode.CINEMATIC and _use_external_cinematic:
		if _current_view_index >= 0 and _current_view_index < _view_targets.size():
			var t = _view_targets[_current_view_index]
			if t.get("aircraft") == aircraft and t.get("mode") == CameraMode.CINEMATIC:
				update_carrier_cinematic(delta)

func _is_zoom_button_pressed() -> bool:
	for device in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_STICK):
			return true
	return false

func _is_cockpit_zoom_view_active() -> bool:
	return current_mode == CameraMode.COCKPIT and cockpit_camera != null

func cycle_camera():
	# Rebuild targets each cycle so we pick up newly spawned AI planes
	_build_view_targets()
	if _view_targets.is_empty():
		return
	
	_current_view_index = (_current_view_index + 1) % _view_targets.size()
	_switch_to_view_target(_view_targets[_current_view_index])

func _switch_to_view_target(target: Dictionary):
	var mode: CameraMode = target.get("mode", CameraMode.COCKPIT)
	var ac: RigidBody3D = null
	if mode != CameraMode.BRIDGE:
		ac = _get_aircraft_from_view_target(target)
		if ac == null:
			_recover_from_invalid_view_target()
			return
	
	# Deactivate all cameras we know about
	_deactivate_all_cameras()
	
	current_mode = mode
	
	if mode == CameraMode.BRIDGE:
		if is_instance_valid(bridge_camera):
			bridge_camera.current = true
		else:
			_recover_from_invalid_view_target()
		return
	
	var cam = _get_camera_for(ac, mode)
	if not cam:
		return
	
	# Ensure chase/cinematic scripts are set up for this aircraft
	if mode == CameraMode.CHASE:
		var ch = _get_chase_script_for(ac)
		if ch:
			if ac == aircraft and _ejected_pilot_focus != null and is_instance_valid(_ejected_pilot_focus):
				ch.setup_follow_target(ac, _ejected_pilot_focus)
			else:
				ch.setup_aircraft(ac)
			ch.reset_look()
	elif mode == CameraMode.CINEMATIC:
		var ci: CinematicCamera = cinematic_script if ac == aircraft else null
		if ci == null:
			var tripod = ac.get_node_or_null("CameraCinematic") as Node3D
			if tripod and not tripod.get_script():
				tripod.set_script(preload("res://Camera/CinematicCamera.gd"))
				ci = tripod as CinematicCamera
				if ci:
					ci.setup_aircraft(ac)
			else:
				ci = tripod as CinematicCamera if tripod else null
		if ci:
			if ac == aircraft and _ejected_pilot_focus != null and is_instance_valid(_ejected_pilot_focus):
				ci.setup_follow_target(ac, _ejected_pilot_focus)
			else:
				ci.setup_aircraft(ac)
			ci.setup_shot()
	
	_force_current_camera(cam)
	if mode == CameraMode.COCKPIT:
		update_camera_zoom(true, cockpit_camera)
	else:
		cam.fov = normal_fov

func _deactivate_all_cameras():
	"""Deactivate every known Camera3D before switching to the selected target."""
	if not is_inside_tree():
		return
	var scene_tree := get_tree()
	var root := scene_tree.root
	if root == null:
		return
	_deactivate_cameras_recursive(root)


func _deactivate_cameras_recursive(node: Node) -> void:
	if node is Camera3D:
		(node as Camera3D).current = false
	for child in node.get_children():
		_deactivate_cameras_recursive(child)


func _force_current_camera(camera: Camera3D) -> void:
	if not is_instance_valid(camera):
		return
	var viewport := get_viewport()
	if viewport:
		viewport.audio_listener_enable_3d = true
	_pending_forced_camera = camera
	camera.current = false
	camera.current = true
	call_deferred("_force_current_camera_deferred", camera)


func _force_current_camera_deferred(camera: Camera3D) -> void:
	if not is_instance_valid(camera):
		return
	if camera != _pending_forced_camera:
		return
	camera.current = false
	camera.current = true

func switch_to_camera(mode):
	## Accepts either a CameraMode enum value or an int (0=COCKPIT,1=CHASE,2=CINEMATIC,3=BRIDGE).
	if not cockpit_camera or not chase_camera:
		return
	
	# Convert int shorthand to CameraMode
	var cam_mode: CameraMode
	if mode is int:
		match mode:
			0: cam_mode = CameraMode.COCKPIT
			1: cam_mode = CameraMode.CHASE
			2: cam_mode = CameraMode.CINEMATIC
			3: cam_mode = CameraMode.BRIDGE
			_: cam_mode = CameraMode.COCKPIT
	else:
		cam_mode = mode
	
	_build_view_targets()
	if _view_targets.is_empty():
		_current_view_index = -1
		return
	
	# Find matching view target and switch
	for i in range(_view_targets.size()):
		var t = _view_targets[i]
		if t.get("aircraft", null) == aircraft and t.get("mode", CameraMode.COCKPIT) == cam_mode:
			_current_view_index = i
			_switch_to_view_target(t)
			return
	
	# Fallback for BRIDGE
	if cam_mode == CameraMode.BRIDGE:
		for i in range(_view_targets.size()):
			if _view_targets[i].get("mode") == CameraMode.BRIDGE:
				_current_view_index = i
				_switch_to_view_target(_view_targets[i])
				return
	
	# Default to first view
	_current_view_index = 0
	_switch_to_view_target(_view_targets[0])

func switch_to_aircraft_and_mode(aircraft_candidate: Variant, mode_index: int):
	"""Direct the camera toward a specific aircraft at the given mode (0=COCKPIT,1=CHASE,2=CINEMATIC).
	This is called by FlightDirector when spectating friendly / enemy aircraft."""
	if not is_instance_valid(aircraft_candidate) or not (aircraft_candidate is RigidBody3D):
		return
	var ac := aircraft_candidate as RigidBody3D
	
	var target_mode: CameraMode
	match mode_index:
		0: target_mode = CameraMode.COCKPIT
		1: target_mode = CameraMode.CHASE
		2: target_mode = CameraMode.CINEMATIC
		_: target_mode = CameraMode.COCKPIT
	
	_build_view_targets()
	
	# Search the target list for this aircraft+mode combination
	for i in range(_view_targets.size()):
		var t = _view_targets[i]
		if t.get("aircraft") == ac and t.get("mode") == target_mode:
			_current_view_index = i
			_switch_to_view_target(t)
			return
	
	# Fallback: just switch to whatever mode we can find for this aircraft
	for i in range(_view_targets.size()):
		var t = _view_targets[i]
		if t.get("aircraft") == ac:
			_current_view_index = i
			_switch_to_view_target(t)
			return

func get_current_camera() -> Camera3D:
	_prune_invalid_view_targets()
	if _current_view_index >= 0 and _current_view_index < _view_targets.size():
		var t := _view_targets[_current_view_index] as Dictionary
		var mode: CameraMode = t.get("mode", CameraMode.COCKPIT)
		if mode == CameraMode.BRIDGE:
			return _valid_camera(bridge_camera)
		var ac := _get_aircraft_from_view_target(t)
		if ac != null:
			var c := _get_camera_for(ac, mode)
			if is_instance_valid(c):
				return c
	match current_mode:
		CameraMode.COCKPIT: return _valid_camera(cockpit_camera)
		CameraMode.CHASE: return _valid_camera(chase_camera)
		CameraMode.CINEMATIC: return _valid_camera(cinematic_camera)
		CameraMode.BRIDGE: return _valid_camera(bridge_camera)
		_: return _valid_camera(cockpit_camera)


func _get_aircraft_from_view_target(target: Dictionary) -> RigidBody3D:
	var candidate: Variant = target.get("aircraft", null)
	if not is_instance_valid(candidate) or not (candidate is RigidBody3D):
		return null
	return candidate as RigidBody3D


func _prune_invalid_view_targets() -> void:
	for i in range(_view_targets.size() - 1, -1, -1):
		var target := _view_targets[i] as Dictionary
		var mode: CameraMode = target.get("mode", CameraMode.COCKPIT)
		if mode != CameraMode.BRIDGE and _get_aircraft_from_view_target(target) == null:
			_view_targets.remove_at(i)
	if _view_targets.is_empty():
		_current_view_index = -1
	else:
		_current_view_index = clampi(_current_view_index, 0, _view_targets.size() - 1)


func _recover_from_invalid_view_target() -> void:
	# Keep the currently active camera for this frame. FlightDirector may already
	# have installed a crash-linger camera; forcing a fallback here would steal it.
	_build_view_targets()
	if _view_targets.is_empty():
		_current_view_index = -1
		return
	_current_view_index = clampi(_current_view_index, 0, _view_targets.size() - 1)


func _valid_camera(camera: Variant) -> Camera3D:
	if is_instance_valid(camera):
		return camera as Camera3D
	return null

func update_camera_zoom(instant: bool = false, camera_override: Camera3D = null):
	var target_camera: Camera3D = camera_override
	if target_camera == null:
		target_camera = cockpit_camera
	if not target_camera:
		return

	var target_fov = zoomed_fov if is_zoomed else normal_fov

	# Kill any existing tween to avoid conflicts
	if fov_tween and fov_tween.is_valid():
		fov_tween.kill()

	if instant:
		target_camera.fov = target_fov
	else:
		fov_tween = create_tween()
		fov_tween.tween_property(target_camera, "fov", target_fov, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func activate_deathcam(target_pos: Vector3):
	if _pilot_ejected:
		return
	deathcam_active = true
	deathcam_target_position = target_pos
	deathcam_time = 0.0
	
	# Choose outside camera for deathcam
	current_mode = CameraMode.DEATHCAM
	cockpit_camera.current = false
	if deathcam_use_chase:
		if chase_script:
			chase_script.reset_look()
		# Detach chase tripod so it survives aircraft removal and stop its own updates
		if chase_tripod:
			chase_tripod.top_level = true
			chase_tripod.set_process(false)
			chase_tripod.set_physics_process(false)
		if chase_camera:
			chase_camera.current = true
		if cinematic_camera:
			cinematic_camera.current = false
	else:
		if chase_camera:
			chase_camera.current = false
		if cinematic_camera:
			cinematic_camera.current = true
		# Detach cinematic camera from aircraft transform if using tripod
		if cinematic_tripod:
			cinematic_tripod.top_level = true
	
	print("Deathcam activated at position: ", target_pos)

func update_deathcam(delta):
	if not deathcam_active:
		return
		
	deathcam_time += delta
	
	# Calculate orbital position for chosen outside camera
	var angle = deathcam_time * deathcam_speed
	var orbit_pos = Vector3(
		cos(angle) * deathcam_radius,
		deathcam_height,
		sin(angle) * deathcam_radius
	)
	var camera_pos = deathcam_target_position + orbit_pos
	var look_target = deathcam_target_position + Vector3(0, 1, 0)
	
	if deathcam_use_chase and chase_tripod:
		chase_tripod.global_position = camera_pos
		chase_tripod.look_at(look_target, Vector3.UP)
	elif cinematic_tripod and cinematic_script:
		cinematic_tripod.global_position = camera_pos
		cinematic_tripod.look_at(look_target, Vector3.UP)
	
	# Clean up after duration expires
	if deathcam_time >= deathcam_duration:
		cleanup_deathcam()

func cleanup_deathcam():
	# Remove the destroyed aircraft (not the ejected pilot body)
	if not _pilot_ejected and aircraft:
		aircraft.queue_free()
	
	# Reset camera controller
	deathcam_active = false
	
	# Could respawn here or return to main menu
	print("Aircraft destroyed - deathcam sequence complete")

func update_carrier_cinematic(delta: float) -> void:
	if not cinematic_camera:
		return
	if _ejected_pilot_focus != null and not is_instance_valid(_ejected_pilot_focus):
		_ejected_pilot_focus = null
	if not _carrier_center and _ejected_pilot_focus == null:
		# Without a center, just keep current placement
		if carrier_orbit_speed != 0.0:
			_carrier_yaw += carrier_orbit_speed * delta
		return
	
	# Auto orbit
	if carrier_orbit_speed != 0.0:
		_carrier_yaw += carrier_orbit_speed * delta
	
	# Compute orbit position around center on horizontal plane at desired height
	var center_pos = _ejected_pilot_focus.global_position if _ejected_pilot_focus != null else _carrier_center.global_position
	var offset = Vector3(cos(_carrier_yaw) * carrier_orbit_radius, carrier_orbit_height, sin(_carrier_yaw) * carrier_orbit_radius)
	var cam_pos = center_pos + offset
	cinematic_camera.global_position = cam_pos
	
	# Look at center, then apply local pitch around camera's own X
	cinematic_camera.look_at(center_pos, Vector3.UP)
	var basis = cinematic_camera.global_transform.basis
	basis = basis.rotated(basis.x, _carrier_pitch)
	cinematic_camera.global_transform.basis = basis
