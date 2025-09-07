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

enum CameraMode { COCKPIT, CHASE, CINEMATIC }
var current_mode: CameraMode = CameraMode.COCKPIT
var last_switch_time: float = 0.0
var switch_cooldown: float = 0.3  # Prevent rapid switching

func _ready():
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
	if Input.is_action_just_pressed("switch_camera"):
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_switch_time > switch_cooldown:
			cycle_camera()
			last_switch_time = current_time

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
