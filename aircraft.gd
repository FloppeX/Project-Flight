class_name Aircraft
extends RigidBody3D

signal crashed(impact_velocity)
signal parked
signal moved

@export var MaxLandingForce: float = 3.0
@export var Gravity: float = 1.0 # Normalized to Earth average at sea level
@export var SeaLevelFromOrigin: float = 0.0
@export var AltitudeEnabled: bool = true
@export var GForceFactor: float = 1.0
@export var WorldOrientationReference: NodePath
@onready var world_ref : Node3D = get_node_or_null(WorldOrientationReference)
var internal_world_reference : Node3D

const EARTH_GRAVITY = 9.8 # for g-force calculation

##############################################################################
#  SYSTEM SETUP
# ----------------------------------------------------------------------------

var modules = []
var energy_containers = []
var energy_containers_by_type = {}
var available_energy = {
	"fuel": 0.0
}
var energy_budget_frame = {}
var safe_colliders = []

# Shake system
var shake_intensity: float = 0.0
var shake_decay_rate: float = 500.0
var shake_frequency: float = 30.0
var shake_time: float = 0.0

var last_linear_velocity = null
var last_angular_velocity = null
var is_velocity_nonzero = false

# Flight data
var air_velocity = 0.0
var forward_air_speed = 0.0
var local_altitude = 0.0
var local_g_force = 1.0
var local_load_factor = 1.0

func _ready():
	await get_tree().process_frame
	
	# Create world reference (for compatibility)
	var internal_world_reference = get_node_or_null("/root/WorldOrientationReference")
	if not internal_world_reference:
		internal_world_reference = Node3D.new()
		internal_world_reference.name = "WorldOrientationReference"
		get_node("/root/").add_child(internal_world_reference)
	
	connect("body_shape_entered", Callable(self, "_on_Aircraft_body_shape_entered"))
	connect("body_shape_exited", Callable(self, "_on_Aircraft_body_shape_exited"))
	
	# Find all modules
	for child in get_children():
		if (child is AircraftModule) or (child is AircraftModuleSpatial):
			modules.append(child)
			
			if child is AircraftModule_EnergyContainer:
				energy_containers.append(child)
				
				if not child.EnergyType in energy_containers_by_type:
					energy_containers_by_type[child.EnergyType] = []
				energy_containers_by_type[child.EnergyType].append(child)
				
				if not child.EnergyType in available_energy:
					available_energy[child.EnergyType] = 0.0
	
	gravity_scale = 1.0
	linear_damp = 0.0
	angular_damp = 0.0
	
	setup()
	
	physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_ON

func setup():
	for module in modules:
		module.setup(self)

func _unhandled_input(event):
	for module in modules:
		if module.ReceiveInput:
			module.receive_input(event)

func _physics_process(delta):
	prepare_energy_system()
	apply_shake_forces(delta)
	calculate_flight_data(delta)
	
	# Let modules do their physics
	for module in modules:
		if module.ProcessPhysics:
			module.process_physic_frame(delta)
	
	# Clean up energy budget and check movement state
	consume_energy_budget()
	check_movement_state()
	
	last_linear_velocity = linear_velocity
	last_angular_velocity = angular_velocity

func _process(delta):
	for module in modules:
		if module.ProcessRender:
			module.process_render_frame(delta)

##############################################################################
#  COLLISION HANDLING
# ----------------------------------------------------------------------------

func _on_Aircraft_body_shape_entered(body_rid, body, body_shape_index, local_shape_index):
	var collider_shape = shape_owner_get_owner(local_shape_index)
	var impact_force = linear_velocity.length()
	
	if collider_shape in safe_colliders:
		var landing_force = linear_velocity.dot(global_transform.basis.y)
		land(landing_force, impact_force)
	else:
		crash(impact_force)

func _on_Aircraft_body_shape_exited(body_rid, body, body_shape_index, local_shape_index):
	pass

func register_safe_collider(collider: CollisionShape3D):
	if not collider in safe_colliders:
		safe_colliders.append(collider)

func unregister_safe_collider(collider: CollisionShape3D):
	if collider in safe_colliders:
		safe_colliders.erase(collider)

func land(landing_velocity: float, impact_velocity: float):
	if landing_velocity > MaxLandingForce:
		crash(landing_velocity)

func crash(impact_velocity: float):
	emit_signal("crashed", impact_velocity)

##############################################################################
#  ENERGY SYSTEM
# ----------------------------------------------------------------------------

func prepare_energy_system():
	# Calculate available energy from all containers
	var energy_levels = {}
	for energy_cont in energy_containers:
		if energy_cont.ContainerActive:
			if not energy_cont.EnergyType in energy_levels:
				energy_levels[energy_cont.EnergyType] = energy_cont.current_level
			else:
				energy_levels[energy_cont.EnergyType] += energy_cont.current_level
	available_energy = energy_levels
	
	# Reset energy budget for this frame
	for energy_type in available_energy:
		energy_budget_frame[energy_type] = 0.0

func request_energy(energy_type: String, amount: float) -> bool:
	if (not energy_type in energy_budget_frame) or (not energy_type in available_energy):
		return false
	
	var new_budget = energy_budget_frame[energy_type] + amount
	if (available_energy[energy_type] < new_budget):
		return false
	else:
		energy_budget_frame[energy_type] = new_budget
		return true

func consume_energy_budget():
	for energy_type in energy_budget_frame:
		var this_budget = energy_budget_frame[energy_type]
		if this_budget > 0:
			var energy_conts = energy_containers_by_type[energy_type]
			for this_container in energy_conts:
				if this_container.ContainerActive:
					var this_ratio = this_container.current_level / available_energy[energy_type]
					this_container.consume_energy(this_budget * this_ratio)

func load_energy(energy_type: String, value: float) -> bool:
	if not energy_type in energy_containers_by_type:
		return false
	
	var selected_energy_containers = energy_containers_by_type[energy_type]
	var number_of_containers = 0
	for this_container in selected_energy_containers:
		if this_container.ContainerActive:
			number_of_containers += 1
	
	if number_of_containers == 0:
		return true
	
	var amount_per_container = value / number_of_containers
	var is_at_least_one_container_not_full = false
	for this_container in selected_energy_containers:
		if this_container.ContainerActive:
			if not this_container.load_energy(amount_per_container):
				is_at_least_one_container_not_full = true
	return (not is_at_least_one_container_not_full)

##############################################################################
#  SHAKE SYSTEM
# ----------------------------------------------------------------------------

func add_shake(intensity: float, duration: float = 0.0):
	shake_intensity = max(shake_intensity, intensity) 
	if duration > 0:
		shake_time = duration

func apply_shake_forces(delta):
	if shake_intensity <= 0:
		return
	
	#print("Shake intensity: ", shake_intensity, " Decay rate: ", shake_decay_rate)
	# Decay shake over time
		
	# Always decay shake, regardless of shake_time
	shake_intensity -= shake_decay_rate * delta
	shake_intensity = max(shake_intensity, 0.0)
	
	# Generate random shake forces
	var shake_force = Vector3(
		sin(Time.get_ticks_msec() * 0.001 * shake_frequency + 0.0) * shake_intensity,
		sin(Time.get_ticks_msec() * 0.001 * shake_frequency + 1.5) * shake_intensity,
		sin(Time.get_ticks_msec() * 0.001 * shake_frequency + 3.0) * shake_intensity
	) * mass
	
	# Apply random torque for rotational shake
	var shake_torque = Vector3(
		sin(Time.get_ticks_msec() * 0.001 * shake_frequency + 4.5) * shake_intensity,
		sin(Time.get_ticks_msec() * 0.001 * shake_frequency + 6.0) * shake_intensity,
		sin(Time.get_ticks_msec() * 0.001 * shake_frequency + 7.5) * shake_intensity
	) * mass * 0.1
	
	apply_central_force(shake_force)
	apply_torque(shake_torque)

##############################################################################
#  FLIGHT DATA CALCULATIONS
# ----------------------------------------------------------------------------

func calculate_flight_data(delta):
	# Calculate speed
	air_velocity = linear_velocity.length()
	forward_air_speed = linear_velocity.dot(global_transform.basis.z)  # Speed in forward direction
	
	# Calculate altitude
	if AltitudeEnabled:
		local_altitude = global_position.y - SeaLevelFromOrigin
	else:
		local_altitude = 0.0
	
	# Calculate G-forces
	if last_linear_velocity != null:
		var up_vector = global_transform.basis.y
		var linear_acceleration = (linear_velocity - last_linear_velocity) / delta
		var vertical_acceleration_normalized = (up_vector.dot(linear_acceleration) / EARTH_GRAVITY) * GForceFactor
		
		local_load_factor = (1.0 + vertical_acceleration_normalized/Gravity) if Gravity > 0 else 0.0
		local_g_force = (Gravity + vertical_acceleration_normalized) if Gravity > 0 else 0.0

##############################################################################
#  MOVEMENT STATE TRACKING
# ----------------------------------------------------------------------------

func check_movement_state():
	var air_velocity = linear_velocity.length()
	var is_moving_now = (air_velocity > 0.005)
	
	# Check for state changes
	if (is_velocity_nonzero) and (not is_moving_now):
		# Just stopped
		emit_signal("parked")
	elif (not is_velocity_nonzero) and (is_moving_now):
		# Just started moving
		emit_signal("moved")
	
	is_velocity_nonzero = is_moving_now

##############################################################################
#  UTILITY FUNCTIONS
# ----------------------------------------------------------------------------

func find_modules_by_type(module_type: String) -> Array:
	var result = []
	for module in modules:
		if module.ModuleType == module_type:
			result.append(module)
	return result

func find_modules_by_tag(module_tag: String) -> Array:
	var result = []
	for module in modules:
		if module_tag in module.ModuleTags:
			result.append(module)
	return result
