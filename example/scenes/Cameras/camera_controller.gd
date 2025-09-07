extends Node
class_name CameraController

@export var aircraft: RigidBody3D 
@export var cockpit_tripod: Node3D
@export var chase_tripod: Node3D  
@export var cinematic_tripod: Node3D

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

func _ready():
	# Add to camera controller group for easy finding
	add_to_group("camera_controller")
	
	# Find the Camera3D inside each tripod scene
	cockpit_camera = cockpit_tripod.find_child("Camera3D", true, false)
	chase_camera = chase_tripod.find_child("Camera3D", true, false) 
	cinematic_camera = cinematic_tripod.find_child("Camera3D", true, false)
	
	# Set up camera scripts
	cockpit_tripod.set_script(preload("res://example/scenes/Cameras/CockpitCamera.gd"))
	cockpit_script = cockpit_tripod as CockpitCamera
	
	# For chase and cinematic cameras, we need to detach them from aircraft transform
	# by using global positioning instead of inheriting aircraft movement
	chase_tripod.set_script(preload("res://example/scenes/Cameras/camera_chase.gd"))
	chase_script = chase_tripod as ChaseCamera
	if chase_script:
		chase_script.setup_aircraft(aircraft)
	
	cinematic_tripod.set_script(preload("res://example/scenes/Cameras/CinematicCamera.gd"))
	cinematic_script = cinematic_tripod as CinematicCamera
	if cinematic_script:
		cinematic_script.setup_aircraft(aircraft)
	
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

func _process(delta):
	if deathcam_active:
		update_deathcam(delta)

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

func activate_deathcam(target_pos: Vector3):
	deathcam_active = true
	deathcam_target_position = target_pos
	deathcam_time = 0.0
	
	# Switch to cinematic camera for deathcam
	current_mode = CameraMode.DEATHCAM
	cockpit_camera.current = false
	chase_camera.current = false
	cinematic_camera.current = true
	
	# Detach cinematic camera from aircraft transform
	if cinematic_tripod:
		cinematic_tripod.top_level = true
	
	print("Deathcam activated at position: ", target_pos)

func update_deathcam(delta):
	if not deathcam_active:
		return
		
	deathcam_time += delta
	
	# Calculate orbital position
	var angle = deathcam_time * deathcam_speed
	var orbit_pos = Vector3(
		cos(angle) * deathcam_radius,
		deathcam_height,
		sin(angle) * deathcam_radius
	)
	var camera_pos = deathcam_target_position + orbit_pos
	
	# Update camera tripod position and make camera look at target
	if cinematic_tripod and cinematic_camera:
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
