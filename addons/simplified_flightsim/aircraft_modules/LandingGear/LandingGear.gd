# The LandingGear module demonstrates how to deal with timed/animated features
# using states and Timer node callbacks

extends AircraftModuleSpatial
class_name AircraftModule_LandingGear

signal update_interface(values)

@export var GearCollisionShape: NodePath
@export var gear_collision_shapes: Array[CollisionShape3D] = []  # Array for your 3 spheres

enum LandingGearInitialStates {
	STOWED,
	DEPLOYED
}
@export var InitialState: LandingGearInitialStates = LandingGearInitialStates.STOWED

@export var DeployStowTime: float = 1.0 # secs
@export var DeploySound: AudioStream
@export var StowSound: AudioStream

# Gear springyness
@export var spring_strength: float = 15000.0    # Spring force per meter compressed
@export var spring_damping: float = 3000.0      # Damping to prevent bouncing  
@export var wheel_rest_height: float = 1.0      # Normal wheel height above ground
@export var max_compression: float = 0.5        # Maximum compression distance

# You don't really *need* to use this property, as any node can receive the
# signals. This is just a helper to automatically connect all possible signals
# assigning the node just once 
@export var UINode: NodePath
@onready var ui_node = get_node_or_null(UINode)

var sfx_player = null

var move_timer = Timer.new()

var is_deploying = false
var is_stowing = false
var is_deployed = false
var is_stowed = true


func _ready():
	add_child(move_timer)
	move_timer.one_shot = true
	move_timer.connect("timeout", Callable(self, "_on_move_timer_timeout"))
	
	if DeploySound or StowSound:
		sfx_player = AudioStreamPlayer.new()
		add_child(sfx_player)
	
	if ui_node:
		connect("update_interface", Callable(ui_node, "update_interface"))
	
	ModuleType = "landing_gear"
	ProcessPhysics = true

func setup(aircraft_node):
	aircraft = aircraft_node
	# Register all gear collision shapes as safe colliders
	for collision_shape in gear_collision_shapes:
		if collision_shape:
			aircraft.register_safe_collider(collision_shape)
	
	match InitialState:
		LandingGearInitialStates.STOWED:
			is_stowed = true
			is_deployed = false
		
		LandingGearInitialStates.DEPLOYED:
			is_stowed = false
			is_deployed = true
	
	# Set initial collision state for all gear
	for collision_shape in gear_collision_shapes:
		if collision_shape:
			collision_shape.disabled = not is_deployed
	
	request_update_interface()


#func receive_input(event):
#	pass

#func process_physic_frame(delta):
#	pass

#func process_render_frame(delta):
#	pass

func _on_move_timer_timeout():
	if is_deploying:
		_on_deploy_completed()
	if is_stowing:
		_on_stow_completed()


# -----------------------------------------------------------------------------

func request_update_interface():
	var message = {
		"lgear_deploying": is_deploying,
		"lgear_stowing": is_stowing,
		"lgear_down": is_deployed,
		"lgear_up": is_stowed,
	}
	emit_signal("update_interface", message)


func deploy():
	if is_deployed or is_deploying:
		return
	
	var timer_time = DeployStowTime
	var sfx_position = 0.0
	
	# Do we have to abort a stowing process?
	if is_stowing:
		timer_time = DeployStowTime - move_timer.time_left
		sfx_position = move_timer.time_left
		
		move_timer.stop()
		sfx_player.stop()
	
	# Start process
	move_timer.start(timer_time)
	
	if DeploySound:
		sfx_player.stream = DeploySound
		sfx_player.play(sfx_position)
	
	is_deploying = true
	is_stowing = false
	is_stowed = false
	request_update_interface()


func _on_deploy_completed():
	is_deploying = false
	is_deployed = true
	
	# Enable all gear collisions
	for collision_shape in gear_collision_shapes:
		if collision_shape:
			collision_shape.disabled = false
	
	request_update_interface()



func stow():
	if is_stowed or is_stowing:
		return
	
	var timer_time = DeployStowTime
	var sfx_position = 0.0
	
	# Do we have to abort a deploying process?
	if is_deploying:
		timer_time = DeployStowTime - move_timer.time_left
		sfx_position = move_timer.time_left
		
		move_timer.stop()
		sfx_player.stop()
	
	# Start process
	move_timer.start(timer_time)
	
	if StowSound:
		sfx_player.stream = StowSound
		sfx_player.play(sfx_position)
	
	is_deployed = false
	is_deploying = false
	is_stowing = true
	
	# Disable all gear collisions
	for collision_shape in gear_collision_shapes:
		if collision_shape:
			collision_shape.disabled = true
	
	request_update_interface()


func _on_stow_completed():
	is_stowing = false
	is_stowed = true
	
	request_update_interface()
	
func process_physic_frame(delta):
	if not is_deployed:
		return
	
	# Apply spring forces for each deployed wheel
	for collision_shape in gear_collision_shapes:
		if collision_shape and not collision_shape.disabled:
			apply_wheel_spring(collision_shape)
			
func apply_wheel_spring(wheel_collision: CollisionShape3D):
	# Don't apply springs if we're moving fast upward (taking off)
	var vertical_velocity = aircraft.linear_velocity.y
	if vertical_velocity > 2.0:  # If climbing fast, disable springs
		return
	# Cast a ray down from wheel to detect ground compression
	var space_state = wheel_collision.get_world_3d().direct_space_state
	var wheel_pos = wheel_collision.global_position
	var ray_start = wheel_pos
	var ray_end = wheel_pos + Vector3.DOWN * (wheel_rest_height + max_compression)
	
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [aircraft.get_rid()]  # Don't hit the aircraft itself
	var result = space_state.intersect_ray(query)
	
	if result:
		var ground_distance = wheel_pos.distance_to(result.position)
		var compression = wheel_rest_height - ground_distance
		
		if compression > 0.0:  # Wheel is compressed
			# Spring force (Hooke's law)
			var spring_force = compression * spring_strength
			
			# Damping force (based on vertical velocity)
			var wheel_velocity = aircraft.linear_velocity.y
			var damping_force = -wheel_velocity * spring_damping
			
			# Apply combined force at wheel position
			var total_force = Vector3.UP * (spring_force + damping_force)
			var force_position = wheel_collision.global_position - aircraft.global_position
			aircraft.apply_force(total_force, force_position)
