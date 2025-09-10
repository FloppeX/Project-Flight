# SpringLandingGear.gd
# A new landing gear system with individual wheel RigidBodies and spring suspension
# Each wheel is a separate RigidBody3D with vertical spring movement and damping

extends AircraftModuleSpatial
class_name AircraftModule_SpringLandingGear

signal update_interface(values)

@export var wheel_rigidbodies: Array[RigidBody3D] = []  # Array of wheel RigidBody3D nodes
@export var wheel_meshes: Array[MeshInstance3D] = []    # Array of wheel visual meshes
@export var wheel_colliders: Array[CollisionShape3D] = [] # Array of wheel collision shapes

# Spring suspension parameters
@export var spring_strength: float = 50000.0    # Spring force per meter compressed
@export var spring_damping: float = 8000.0      # Damping to prevent bouncing
@export var wheel_rest_height: float = 1.2      # Normal wheel height above ground
@export var max_compression: float = 0.8        # Maximum compression distance
@export var wheel_mass: float = 5.0             # Mass of each wheel

# Landing gear states
enum LandingGearInitialStates {
	STOWED,
	DEPLOYED
}
@export var InitialState: LandingGearInitialStates = LandingGearInitialStates.DEPLOYED

@export var DeployStowTime: float = 1.0 # secs
@export var DeploySound: AudioStream
@export var StowSound: AudioStream

@export var UINode: NodePath
@onready var ui_node = get_node_or_null(UINode)

var sfx_player = null
var move_timer = Timer.new()
var rotation_tween: Tween

var is_deploying = false
var is_stowing = false
var is_deployed = false
var is_stowed = true

# Store original wheel positions for spring calculations
var original_wheel_positions: Array[Vector3] = []
var wheel_constraints: Array[Joint3D] = []  # Constraints to keep wheels attached to aircraft

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
	
	# Store original positions of wheels
	for wheel_rb in wheel_rigidbodies:
		if wheel_rb:
			original_wheel_positions.append(wheel_rb.position)
	
	# Set up wheel physics
	setup_wheel_physics()
	
	# Create constraints to keep wheels attached to aircraft
	create_wheel_constraints()
	
	# Register wheel colliders as safe colliders
	for collider in wheel_colliders:
		if collider:
			aircraft.register_safe_collider(collider)
	
	match InitialState:
		LandingGearInitialStates.STOWED:
			is_stowed = true
			is_deployed = false
			set_wheel_visibility(false)
			set_wheel_collision_enabled(false)
		
		LandingGearInitialStates.DEPLOYED:
			is_stowed = false
			is_deployed = true
			set_wheel_visibility(true)
			set_wheel_collision_enabled(true)
	
	request_update_interface()

func setup_wheel_physics():
	"""Configure physics properties for each wheel RigidBody3D"""
	for wheel_rb in wheel_rigidbodies:
		if wheel_rb:
			# Set wheel mass and physics properties
			wheel_rb.mass = wheel_mass
			wheel_rb.gravity_scale = 0.0  # Wheels don't fall due to gravity
			wheel_rb.linear_damp = 0.0
			wheel_rb.angular_damp = 0.0
			wheel_rb.contact_monitor = true
			wheel_rb.max_contacts_reported = 1
			
			# Lock rotation and horizontal movement
			wheel_rb.lock_rotation = true
			wheel_rb.freeze = true  # We'll control movement manually

func create_wheel_constraints():
	"""Create constraints to keep wheels attached to aircraft while allowing vertical movement"""
	for i in range(wheel_rigidbodies.size()):
		var wheel_rb = wheel_rigidbodies[i]
		if not wheel_rb:
			continue
			
		# Create a Generic6DOFJoint3D to constrain wheel movement
		var constraint = Generic6DOFJoint3D.new()
		aircraft.add_child(constraint)
		
		# Set up the constraint
		constraint.set_node_a(aircraft.get_path())
		constraint.set_node_b(wheel_rb.get_path())
		
		# Allow only vertical (Y) movement
		constraint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		constraint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, false)  # Allow Y movement
		constraint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		
		# Set limits for X and Z (no horizontal movement)
		constraint.set_linear_limit_lower(Vector3(-0.01, -max_compression, -0.01))
		constraint.set_linear_limit_upper(Vector3(0.01, max_compression, 0.01))
		
		# Lock all rotations
		constraint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		constraint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		constraint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		
		constraint.set_angular_limit_lower(Vector3(0, 0, 0))
		constraint.set_angular_limit_upper(Vector3(0, 0, 0))
		
		wheel_constraints.append(constraint)

func process_physic_frame(delta):
	if not is_deployed:
		return
	
	# Apply spring forces to each wheel
	for i in range(wheel_rigidbodies.size()):
		var wheel_rb = wheel_rigidbodies[i]
		if wheel_rb and wheel_rb.freeze:
			apply_wheel_spring(wheel_rb, i, delta)

func apply_wheel_spring(wheel_rb: RigidBody3D, wheel_index: int, delta: float):
	"""Apply spring suspension forces to a wheel"""
	# Don't apply springs if we're moving fast upward (taking off)
	var vertical_velocity = aircraft.linear_velocity.y
	if vertical_velocity > 2.0:  # If climbing fast, disable springs
		return
	
	# Cast a ray down from wheel to detect ground
	var space_state = wheel_rb.get_world_3d().direct_space_state
	var wheel_pos = wheel_rb.global_position
	var ray_start = wheel_pos
	var ray_end = wheel_pos + Vector3.DOWN * (wheel_rest_height + max_compression)
	
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [aircraft.get_rid()]  # Don't hit the aircraft itself
	var result = space_state.intersect_ray(query)
	
	if result:
		var ground_distance = wheel_pos.distance_to(result.position)
		var compression = wheel_rest_height - ground_distance
		
		if compression > 0.0:  # Wheel is compressed
			# Calculate spring force (Hooke's law)
			var spring_force = compression * spring_strength
			
			# Calculate damping force (based on vertical velocity)
			var wheel_velocity = wheel_rb.linear_velocity.y
			var damping_force = -wheel_velocity * spring_damping
			
			# Apply combined force
			var total_force = Vector3.UP * (spring_force + damping_force)
			
			# Apply force to the wheel
			wheel_rb.apply_central_force(total_force)
			
			# Also apply some force to the aircraft to simulate the spring
			var aircraft_force = total_force * 0.8  # Reduce force on aircraft
			var force_position = wheel_rb.global_position - aircraft.global_position
			aircraft.apply_force(aircraft_force, force_position)

func set_wheel_visibility(visible: bool):
	"""Show or hide wheel meshes"""
	for mesh in wheel_meshes:
		if mesh:
			mesh.visible = visible

func set_wheel_collision_enabled(enabled: bool):
	"""Enable or disable wheel collision shapes"""
	for collider in wheel_colliders:
		if collider:
			collider.disabled = not enabled

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
	
	# Enable wheel collisions and visibility
	set_wheel_collision_enabled(true)
	set_wheel_visibility(true)
	
	# Unfreeze wheels so they can move with springs
	for wheel_rb in wheel_rigidbodies:
		if wheel_rb:
			wheel_rb.freeze = false
	
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
	
	# Disable wheel collisions and visibility
	set_wheel_collision_enabled(false)
	set_wheel_visibility(false)
	
	# Freeze wheels
	for wheel_rb in wheel_rigidbodies:
		if wheel_rb:
			wheel_rb.freeze = true
	
	request_update_interface()

func _on_stow_completed():
	is_stowing = false
	is_stowed = true
	
	request_update_interface()

func request_update_interface():
	var message = {
		"lgear_deploying": is_deploying,
		"lgear_stowing": is_stowing,
		"lgear_down": is_deployed,
		"lgear_up": is_stowed,
	}
	emit_signal("update_interface", message)
