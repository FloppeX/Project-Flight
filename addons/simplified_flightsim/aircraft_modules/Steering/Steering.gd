extends AircraftModule
class_name AircraftModule_Steering

signal update_interface(values)

@export var PowerFactor: float = 1.0

# Control surface distances from center
@export var XPointDistance: float = 1.0  # Elevator
@export var YPointDistance: float = 0.5  # Rudder
@export var ZPointDistance: float = 1.0  # Ailerons

@export var FuelRate: float = 1.0 # Fuel units per second per axis, at max power

@export var UINode: NodePath
@onready var ui_node = get_node_or_null(UINode)

# Control inputs
var axis_x = 0.0 # Elevators
var axis_y = 0.0 # Rudder
var axis_z = 0.0 # Ailerons

var energy_failed = false

# Nose wheel steering
@export var max_nose_wheel_angle: float = 45.0  # Maximum nose wheel rotation in degrees
var nose_gear_visual: Node3D
var nose_gear_collider: Node3D

func _ready():
	ProcessPhysics = true
	ModuleType = "steering"
	
	if ui_node:
		connect("update_interface", Callable(ui_node, "update_interface"))

func setup(aircraft_node):
	aircraft = aircraft_node
	
	# Find nose gear collider and visual for steering
	nose_gear_collider = aircraft.get_node_or_null("CenterGearCollider")
	if nose_gear_collider:
		nose_gear_visual = nose_gear_collider.get_node_or_null("Aircraft 1 nose gear")
	
	request_update_interface()

func request_update_interface():
	var message = {
		"axis_x": axis_x,
		"axis_y": axis_y,
		"axis_z": axis_z,
		"energy_failed": energy_failed
	}
	emit_signal("update_interface", message)

func process_physic_frame(delta):
	if not aircraft:
		return
	
	var fuel_budget
	
	# =================================
	# Z - AILERONS
	
	if axis_z != 0:
		if UsesEnergy:
			fuel_budget = abs(axis_z) * FuelRate * delta
			if not aircraft.request_energy(EnergyType, fuel_budget):
				energy_failed = true
				return
			else:
				energy_failed = false
		
		# Control effectiveness scales with airspeed (realistic aerodynamics)
		var base_force = PowerFactor * axis_z * 0.5 * aircraft.air_velocity * 0.1
		
		var force_vector_right = -aircraft.global_transform.basis.y * base_force
		var force_vector_left = aircraft.global_transform.basis.y * base_force
		
		var thruster_rotated_position_right = aircraft.global_transform.basis.x * ZPointDistance
		aircraft.apply_force(force_vector_right, thruster_rotated_position_right)
		
		var thruster_rotated_position_left = -aircraft.global_transform.basis.x * ZPointDistance
		aircraft.apply_force(force_vector_left, thruster_rotated_position_left)
	
	# =================================
	# X - ELEVATOR
	
	if axis_x != 0:
		if UsesEnergy:
			fuel_budget = abs(axis_x) * FuelRate * delta
			if not aircraft.request_energy(EnergyType, fuel_budget):
				energy_failed = true
				return
			else:
				energy_failed = false
		
		# Control effectiveness scales with airspeed (realistic aerodynamics)
		var base_force = PowerFactor * axis_x * 0.5 * aircraft.air_velocity * 0.1
		
		var force_vector_up = -aircraft.global_transform.basis.y * base_force
		var force_vector_down = aircraft.global_transform.basis.y * base_force
		
		var thruster_rotated_position_back = aircraft.global_transform.basis.z * XPointDistance
		aircraft.apply_force(force_vector_up, thruster_rotated_position_back)
		
		var thruster_rotated_position_front = -aircraft.global_transform.basis.z * XPointDistance
		aircraft.apply_force(force_vector_down, thruster_rotated_position_front)
	
	# =================================
	# Y - RUDDER
	
	if axis_y != 0:
		if UsesEnergy:
			fuel_budget = abs(axis_y) * FuelRate * delta
			if not aircraft.request_energy(EnergyType, fuel_budget):
				energy_failed = true
				return
			else:
				energy_failed = false
		
		# Control effectiveness scales with airspeed (realistic aerodynamics)
		var base_force = PowerFactor * axis_y * 0.5 * aircraft.air_velocity * 0.1
		
		var force_vector_rleft = -aircraft.global_transform.basis.x * base_force
		var force_vector_rright = aircraft.global_transform.basis.x * base_force
		
		var thruster_rotated_position_rback = aircraft.global_transform.basis.z * YPointDistance
		var thruster_rotated_position_rfront = -aircraft.global_transform.basis.z * YPointDistance
		
		# Rudder axis positive turns the plane to left (positive rotation on Y axis)
		aircraft.apply_force(force_vector_rleft, thruster_rotated_position_rfront)
		aircraft.apply_force(force_vector_rright, thruster_rotated_position_rback)

func set_x(value: float):
	axis_x = value
	request_update_interface()

func set_y(value: float):
	axis_y = value
	
	# Update nose wheel rotation based on rudder input
	var target_angle = axis_y * max_nose_wheel_angle
	var target_rotation = deg_to_rad(target_angle)
	
	# Rotate the collider (for physics damping direction)
	if nose_gear_collider:
		nose_gear_collider.rotation.y = target_rotation
	
	# Rotate the visual (relative to the collider, so reset to 0)
	if nose_gear_visual:
		nose_gear_visual.rotation.y = 0
	
	request_update_interface()

func set_z(value: float):
	axis_z = value
	request_update_interface()
