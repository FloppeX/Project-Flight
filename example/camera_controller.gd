extends Node
class_name CameraController

@export var aircraft: RigidBody3D 
@export var cockpit_tripod: Node3D
@export var chase_tripod: Node3D  
@export var cinematic_tripod: Node3D

# Chase camera settings
@export var chase_distance: float = 15.0
@export var chase_height: float = 5.0
@export var chase_smoothing: float = 3.0

# Cinematic camera settings
@export var cinematic_distance: float = 100.0
@export var cinematic_height_range: Vector2 = Vector2(10, 50)

var cockpit_camera: Camera3D
var chase_camera: Camera3D  
var cinematic_camera: Camera3D

enum CameraMode { COCKPIT, CHASE, CINEMATIC }
var current_mode: CameraMode = CameraMode.COCKPIT

func _ready():
	# Find the Camera3D inside each tripod scene
	cockpit_camera = cockpit_tripod.find_child("Camera3D", true, false)
	chase_camera = chase_tripod.find_child("Camera3D", true, false) 
	cinematic_camera = cinematic_tripod.find_child("Camera3D", true, false)
	
	switch_to_camera(CameraMode.COCKPIT)

func _input(event):
	if Input.is_action_just_pressed("switch_camera"):
		cycle_camera()

func cycle_camera():
	current_mode = (current_mode + 1) % 3
	print("Switching to camera mode: ", current_mode)
	switch_to_camera(current_mode)

func switch_to_camera(mode: CameraMode):
	print("switch_to_camera called with mode: ", mode)
	# Disable all cameras
	cockpit_camera.current = false
	chase_camera.current = false  
	cinematic_camera.current = false
	
	# Enable selected camera
	match mode:
		CameraMode.COCKPIT:
			cockpit_camera.current = true
		CameraMode.CHASE:
			chase_camera.current = true
		CameraMode.CINEMATIC:
			setup_cinematic_shot()
			cinematic_camera.current = true
			
func _process(delta):
	if current_mode == CameraMode.CHASE:
		update_chase_camera(delta)
	elif current_mode == CameraMode.CINEMATIC:
		update_cinematic_camera()

func update_chase_camera(delta):
	var aircraft_pos = aircraft.global_position
	var aircraft_forward = -aircraft.global_transform.basis.z
	
	var target_pos = aircraft_pos - aircraft_forward * chase_distance + Vector3.UP * chase_height
	
	# Debug prints
	print("Aircraft pos: ", aircraft_pos)
	print("Chase current: ", chase_tripod.global_position)
	print("Chase target: ", target_pos)
	
	chase_tripod.global_position = chase_tripod.global_position.lerp(target_pos, chase_smoothing * delta)
	chase_tripod.look_at(aircraft_pos, Vector3.UP)
	
	print("Chase after lerp: ", chase_tripod.global_position)
	print("---")

func setup_cinematic_shot():
	# Same as before - position the tripod
	var aircraft_pos = aircraft.global_position
	var aircraft_forward = -aircraft.global_transform.basis.z
	var aircraft_right = aircraft.global_transform.basis.x
	
	var ahead_distance = randf_range(50, cinematic_distance)
	var side_offset = randf_range(-30, 30)
	var height = randf_range(cinematic_height_range.x, cinematic_height_range.y)
	
	var ahead_pos = aircraft_pos + aircraft_forward * ahead_distance
	ahead_pos += aircraft_right * side_offset
	ahead_pos += Vector3.UP * height
	
	cinematic_tripod.global_position = ahead_pos

func update_cinematic_camera():
	# Rotate the tripod to look at aircraft
	cinematic_tripod.look_at(aircraft.global_position, Vector3.UP)
