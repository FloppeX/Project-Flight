extends Node3D

@export var horizontal_sensitivity: float = 120.0  # degrees for left/right
@export var vertical_sensitivity: float = 90.0    # degrees for up/down  
@export var return_speed: float = 5.0             # how fast it snaps back to center

var base_rotation: Vector3 = Vector3.ZERO
var current_look: Vector3 = Vector3.ZERO

func _ready():
	base_rotation = rotation

func _process(delta):
	# Get right stick input
	var look_x = Input.get_action_strength("look_left") - Input.get_action_strength("look_right")
	var look_y = Input.get_action_strength("look_down") - Input.get_action_strength("look_up") 
	
	# Target look angles in radians with separate sensitivities
	var target_look = Vector3(
		deg_to_rad(-look_y * vertical_sensitivity),
		deg_to_rad(look_x * horizontal_sensitivity), 
		0
	)
	
	# Smoothly move to target
	current_look = current_look.lerp(target_look, return_speed * delta)
	
	# Apply to camera
	rotation = base_rotation + current_look
