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

# Zoom variables
@export var normal_fov: float = 75.0
@export var zoomed_fov: float = 30.0
var is_zoomed: bool = false
var fov_tween: Tween

var cockpit_camera: Camera3D
var chase_camera: Camera3D  
var cinematic_camera: Camera3D

var cockpit_script: CockpitCamera
var chase_script: ChaseCamera
var cinematic_script: CinematicCamera

enum CameraMode { COCKPIT, CHASE, CINEMATIC, DEATHCAM }
var current_mode: CameraMode = CameraMode.COCKPIT
var last_switch_time: float = 0.0
var switch_cooldown: float = 0.3  # Prevent rapid switching

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

func _ready():
	# Add to camera controller group for easy finding
	add_to_group("camera_controller")
	
	# Find the Camera3D inside each tripod scene
	cockpit_camera = cockpit_tripod.find_child("Camera3D", true, false)
	chase_camera = chase_tripod.find_child("Camera3D", true, false) 
	cinematic_camera = null
	
	# Set up camera scripts
	cockpit_tripod.set_script(preload("res://example/scenes/Cameras/CockpitCamera.gd"))
	cockpit_script = cockpit_tripod as CockpitCamera
	
	# For chase and cinematic cameras, we need to detach them from aircraft transform
	# by using global positioning instead of inheriting aircraft movement
	chase_tripod.set_script(preload("res://example/scenes/Cameras/camera_chase.gd"))
	chase_script = chase_tripod as ChaseCamera
	if chase_script:
		chase_script.setup_aircraft(aircraft)
	
	# Prefer external carrier cam for cinematic, else fall back to tripod
	var external_cam: Camera3D = null
	if carrier_cam_path != NodePath():
		external_cam = get_node_or_null(carrier_cam_path) as Camera3D
	if not external_cam:
		external_cam = get_tree().get_first_node_in_group("carrier_cam") as Camera3D
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
		cinematic_tripod.set_script(preload("res://example/scenes/Cameras/CinematicCamera.gd"))
		cinematic_script = cinematic_tripod as CinematicCamera
		if cinematic_script:
			cinematic_script.setup_aircraft(aircraft)
		cinematic_camera = cinematic_tripod.find_child("Camera3D", true, false)
		_use_external_cinematic = false
	
	switch_to_camera(CameraMode.COCKPIT)

func _input(event):
	# Don't allow camera switching during deathcam
	if deathcam_active:
		return
		
	if Input.is_action_just_pressed("switch_camera"):
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_switch_time > switch_cooldown:
			cycle_camera()
			last_switch_time = current_time
	
	# Manual carrier cam control
	if current_mode == CameraMode.CINEMATIC and _use_external_cinematic:
		var look_x = Input.get_action_strength("look_left") - Input.get_action_strength("look_right")
		var look_y = Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
		_carrier_yaw += look_x * carrier_look_sensitivity * 0.02
		_carrier_pitch = clamp(_carrier_pitch + look_y * carrier_look_sensitivity * 0.02, deg_to_rad(-carrier_pitch_limit_deg), deg_to_rad(carrier_pitch_limit_deg))

func _process(delta):
	if deathcam_active:
		update_deathcam(delta)
		return
	
	if current_mode == CameraMode.CINEMATIC and _use_external_cinematic:
		update_carrier_cinematic(delta)

func cycle_camera():
	var old_mode = current_mode
	current_mode = (current_mode + 1) % 3
	print("Camera switching: ", old_mode, " -> ", current_mode)
	switch_to_camera(current_mode)

func switch_to_camera(mode: CameraMode):
	print("switch_to_camera called with mode: ", mode)
	
	# Validate cameras exist
	if not cockpit_camera or not chase_camera or not cinematic_camera:
		print("ERROR: One or more cameras not found!")
		return
	
	# Disable all cameras
	cockpit_camera.current = false
	chase_camera.current = false  
	cinematic_camera.current = false
	
	# Reset camera states when switching
	current_mode = mode
	
	# Enable selected camera and set up scripts
	match mode:
		CameraMode.COCKPIT:
			print("Activating cockpit camera")
			cockpit_camera.current = true
		CameraMode.CHASE:
			print("Activating chase camera")
			if chase_script:
				chase_script.reset_look()
			chase_camera.current = true
		CameraMode.CINEMATIC:
			print("Activating cinematic camera")
			if cinematic_script:
				cinematic_script.setup_shot()
			cinematic_camera.current = true
	
	# Verify which camera is actually active
	print("Camera states - Cockpit:", cockpit_camera.current, " Chase:", chase_camera.current, " Cinematic:", cinematic_camera.current)

func get_current_camera() -> Camera3D:
	match current_mode:
		CameraMode.COCKPIT:
			return cockpit_camera
		CameraMode.CHASE:
			return chase_camera
		CameraMode.CINEMATIC:
			return cinematic_camera
	return null

func update_camera_zoom(instant: bool = false):
	var target_camera = get_current_camera()
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
	deathcam_active = true
	deathcam_target_position = target_pos
	deathcam_time = 0.0
	
	# Switch to cinematic camera for deathcam
	current_mode = CameraMode.DEATHCAM
	cockpit_camera.current = false
	chase_camera.current = false
	cinematic_camera.current = true
	
	# Detach cinematic camera from aircraft transform if using tripod
	if cinematic_tripod:
		cinematic_tripod.top_level = true
	
	print("Deathcam activated at position: ", target_pos)

func update_deathcam(delta):
	if not deathcam_active:
		return
		
	deathcam_time += delta
	
	# Calculate orbital position only if using tripod cinematic camera
	if cinematic_tripod and cinematic_script:
		var angle = deathcam_time * deathcam_speed
		var orbit_pos = Vector3(
			cos(angle) * deathcam_radius,
			deathcam_height,
			sin(angle) * deathcam_radius
		)
		var camera_pos = deathcam_target_position + orbit_pos
		
		# Update camera tripod position and make camera look at target
		cinematic_tripod.global_position = camera_pos
		# Make the camera look at the crash site
		var look_target = deathcam_target_position + Vector3(0, 1, 0)  # Look slightly above crash site
		cinematic_tripod.look_at(look_target, Vector3.UP)
	
	# Clean up after duration expires
	if deathcam_time >= deathcam_duration:
		cleanup_deathcam()

func cleanup_deathcam():
	# Remove the destroyed aircraft
	if aircraft:
		aircraft.queue_free()
	
	# Reset camera controller
	deathcam_active = false
	
	# Could respawn here or return to main menu
	print("Aircraft destroyed - deathcam sequence complete")

func update_carrier_cinematic(delta: float) -> void:
	if not cinematic_camera:
		return
	if not _carrier_center:
		# Without a center, just keep current placement
		if carrier_orbit_speed != 0.0:
			_carrier_yaw += carrier_orbit_speed * delta
		return
	
	# Auto orbit
	if carrier_orbit_speed != 0.0:
		_carrier_yaw += carrier_orbit_speed * delta
	
	# Compute orbit position around center on horizontal plane at desired height
	var center_pos = _carrier_center.global_position
	var offset = Vector3(cos(_carrier_yaw) * carrier_orbit_radius, carrier_orbit_height, sin(_carrier_yaw) * carrier_orbit_radius)
	var cam_pos = center_pos + offset
	cinematic_camera.global_position = cam_pos
	
	# Look at center, then apply local pitch around camera's own X
	cinematic_camera.look_at(center_pos, Vector3.UP)
	var basis = cinematic_camera.global_transform.basis
	basis = basis.rotated(basis.x, _carrier_pitch)
	cinematic_camera.global_transform.basis = basis
