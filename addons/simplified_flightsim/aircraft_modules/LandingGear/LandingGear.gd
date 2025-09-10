# The LandingGear module demonstrates how to deal with timed/animated features
# using states and Timer node callbacks

extends AircraftModuleSpatial
class_name AircraftModule_LandingGear

signal update_interface(values)

@export var GearCollisionShape: NodePath
@export var gear_collision_shapes: Array[CollisionShape3D] = []  # Array for wheel collision shapes
@export var gear_visuals: Array[Node3D] = []  # Array for visual gear meshes
@export var gear_rotation_axes: Array[Vector3] = []  # Rotation axis for each gear (empty = no rotation)
@export var gear_rotation_angles: Array[float] = []  # Rotation angle in degrees for each gear when stowed

enum LandingGearInitialStates {
	STOWED,
	DEPLOYED
}
@export var InitialState: LandingGearInitialStates = LandingGearInitialStates.STOWED

@export var DeployStowTime: float = 1.0 # secs
@export var DeploySound: AudioStream
@export var StowSound: AudioStream

# Gear suspension (simplified)
@export var spring_strength: float = 50000.0   # Spring force per meter compressed
@export var spring_damping: float = 8000.0     # Damping to prevent bouncing  
@export var wheel_rest_height: float = 1.2     # Normal wheel height above ground
@export var max_compression: float = 0.8       # Maximum compression distance

# Directional wheel friction
@export var forward_friction: float = 0.1      # Low resistance for rolling forward/backward
@export var sideways_friction: float = 8.0     # High resistance for sliding sideways
@export var friction_force_multiplier: float = 1000.0  # Overall friction strength

var current_state: LandingGearInitialStates
var deploy_timer: Timer
var audio_player: AudioStreamPlayer3D

# Properties for external access
var is_deployed: bool = false
var is_stowed: bool = true

func _ready():
	"""Set up module properties"""
	ModuleType = "landing_gear"
	ProcessPhysics = true
	
	# Set up timer
	deploy_timer = Timer.new()
	add_child(deploy_timer)
	deploy_timer.one_shot = true
	deploy_timer.timeout.connect(_on_timer_timeout)
	
	# Set up audio player
	audio_player = AudioStreamPlayer3D.new()
	add_child(audio_player)

func setup(aircraft_node):
	"""Initialize the landing gear system"""
	super.setup(aircraft_node)
	
	# Register wheel colliders as safe colliders (for landing detection)
	for collider in gear_collision_shapes:
		if collider:
			aircraft.register_safe_collider(collider)
	
	# Set initial state
	current_state = InitialState
	if current_state == LandingGearInitialStates.STOWED:
		stow()
	else:
		deploy()

func process_physic_frame(delta: float):
	"""Apply spring physics to each wheel"""
	if current_state != LandingGearInitialStates.DEPLOYED:
		return
		
	# Only apply springs if we have proper values set
	if spring_strength > 0 and wheel_rest_height > 0:
		# Apply spring forces to each collision shape
		for i in range(gear_collision_shapes.size()):
			apply_spring_physics(gear_collision_shapes[i], i, delta)

func apply_spring_physics(collision_shape: CollisionShape3D, gear_index: int, delta: float):
	"""Apply spring and damping forces to a gear collision shape"""
	if not collision_shape or collision_shape.disabled:
		return
		
	# Cast ray downward from collision shape to detect ground
	var space_state = collision_shape.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		collision_shape.global_position,
		collision_shape.global_position + Vector3.DOWN * (wheel_rest_height + max_compression)
	)
	query.exclude = [aircraft.get_rid()]
	
	var result = space_state.intersect_ray(query)
	
	if result:
		# Ground detected - calculate compression
		var distance_to_ground = collision_shape.global_position.distance_to(result.position)
		var compression = wheel_rest_height - distance_to_ground
		compression = clamp(compression, 0.0, max_compression)
		
		if compression > 0.01:  # Small threshold to avoid jittering
			# Calculate spring force (Hooke's law)
			var spring_force = spring_strength * compression
			
			# Calculate damping force (opposes velocity)
			var aircraft_velocity = aircraft.linear_velocity.y
			var damping_force = -spring_damping * aircraft_velocity * compression
			
			# Apply vertical forces (spring + damping)
			var total_vertical_force = spring_force + damping_force
			var force_position = collision_shape.global_position - aircraft.global_position
			aircraft.apply_force(Vector3.UP * total_vertical_force, force_position)
			
			# Apply directional wheel friction
			apply_wheel_friction(collision_shape, compression)

func deploy():
	"""Deploy the landing gear"""
	if current_state == LandingGearInitialStates.DEPLOYED:
		return
	
	# Start deploy animation/timer
	deploy_timer.start(DeployStowTime)
	
	# Play deploy sound
	if DeploySound:
		play_sound(DeploySound)
	
	# Update state immediately for interface
	current_state = LandingGearInitialStates.DEPLOYED
	is_deployed = true
	is_stowed = false
	
	# Enable collision shapes immediately
	for collision_shape in gear_collision_shapes:
		if collision_shape:
			collision_shape.disabled = false
	
	# Show visual meshes immediately
	for visual in gear_visuals:
		if visual:
			visual.visible = true
	
	# Emit interface update
	update_interface.emit({"landing_gear": "deployed"})

func stow():
	"""Stow the landing gear"""
	if current_state == LandingGearInitialStates.STOWED:
		return
	
	# Start stow animation/timer
	deploy_timer.start(DeployStowTime)
	
	# Play stow sound
	if StowSound:
			play_sound(StowSound)
	
	# Update state immediately for interface
	current_state = LandingGearInitialStates.STOWED
	is_deployed = false
	is_stowed = true
	
	# Disable collision shapes immediately
	for collision_shape in gear_collision_shapes:
		if collision_shape:
			collision_shape.disabled = true
	
	# Hide visual meshes immediately
	for visual in gear_visuals:
		if visual:
			visual.visible = false
	
	# Emit interface update
	update_interface.emit({"landing_gear": "stowed"})

func _on_timer_timeout():
	"""Called when deploy/stow timer completes"""
	# Animation is complete, nothing more to do since we handle states immediately
	pass

func play_sound(sound: AudioStream):
	"""Play a sound effect"""
	if sound and audio_player:
		audio_player.stream = sound
		audio_player.play()

func apply_wheel_friction(collision_shape: CollisionShape3D, compression: float):
	"""Apply directional friction to simulate realistic wheel behavior"""
	if not aircraft or compression <= 0.01:
		return
	
	# Get aircraft's local coordinate system
	var aircraft_forward = -aircraft.global_transform.basis.z  # Aircraft forward direction
	var aircraft_right = aircraft.global_transform.basis.x     # Aircraft right direction
	
	# Get aircraft velocity in world space
	var world_velocity = aircraft.linear_velocity
	
	# Project velocity onto aircraft's local axes
	var forward_velocity = world_velocity.dot(aircraft_forward)
	var sideways_velocity = world_velocity.dot(aircraft_right)
	
	# Calculate friction forces
	var forward_friction_force = -forward_velocity * forward_friction * friction_force_multiplier * compression
	var sideways_friction_force = -sideways_velocity * sideways_friction * friction_force_multiplier * compression
	
	# Apply friction forces in aircraft's local coordinate system
	var total_friction = (aircraft_forward * forward_friction_force) + (aircraft_right * sideways_friction_force)
	
	# Apply friction force at wheel position
	var force_position = collision_shape.global_position - aircraft.global_position
	aircraft.apply_force(total_friction, force_position)
