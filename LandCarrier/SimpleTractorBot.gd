class_name SimpleTractorBot
extends Node3D

# Simple tractorbot that follows aircraft movement for visual effect
# The actual aircraft movement is handled by FlightDeckManager

@export var target_aircraft: RigidBody3D
@export var target_wheel_node: Node3D
@export var wheel_position_offset: Vector3 = Vector3.ZERO  # Offset from aircraft center to wheel
@export var follow_height: float = 0.2  # Height above flight deck when "lifting" aircraft (should match _aircraft_lift_height)
@export var move_speed: float = 15.0  # Speed to follow aircraft
@export var positioning_speed: float = 3.0  # Speed when initially positioning at gear
@export var rotation_speed: float = 180.0  # Degrees per second to rotate

var is_active: bool = false
var is_positioned: bool = false  # Whether we've reached the gear position
var fixed_target_position: Vector3 = Vector3.ZERO  # Fixed position to move to, not following aircraft
var target_position: Vector3
var target_rotation: float = 0.0
var external_target_set: bool = false  # Whether target was set externally (e.g., by elevator)
var movement_disabled: bool = false  # Whether movement logic is disabled (e.g., during elevator)

func _ready():
	# Create visual disk
	var mesh_instance = MeshInstance3D.new()
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.height = 0.3
	cylinder_mesh.top_radius = 1.2
	cylinder_mesh.bottom_radius = 1.2
	mesh_instance.mesh = cylinder_mesh
	
	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 0.0, 1.0)  # Bright yellow
	material.emission = Color(0.2, 0.2, 0.0, 1.0)  # Slight glow
	material.metallic = 0.1
	material.roughness = 0.3
	mesh_instance.material_override = material
	
	add_child(mesh_instance)
	
	# Position disk flat on ground
	mesh_instance.position.y = -0.15

func activate(aircraft: RigidBody3D, wheel_offset: Vector3, wheel_node: Node3D = null):
	"""Activate this tractorbot to position at a specific aircraft wheel"""
	target_aircraft = aircraft
	target_wheel_node = wheel_node
	wheel_position_offset = wheel_offset
	is_active = true
	is_positioned = false
	movement_disabled = false
	external_target_set = false
	
	# Calculate fixed target position (aircraft position + wheel offset) at the correct height
	var deck_height = _get_deck_height()
	fixed_target_position = aircraft.global_position + wheel_offset
	fixed_target_position.y = deck_height + follow_height
	
	pass  # activated

func deactivate():
	"""Deactivate this tractorbot"""
	is_active = false
	target_aircraft = null
	target_wheel_node = null
	movement_disabled = false
	external_target_set = false
	pass  # deactivated

func is_positioned_at_gear() -> bool:
	"""Check if this tractorbot is positioned at its target gear"""
	return is_positioned

func set_external_target(new_target: Vector3):
	"""Set target position externally (e.g., by elevator)"""
	target_position = new_target
	external_target_set = true
	pass  # external target set

func clear_external_target():
	"""Clear external target and return to following aircraft"""
	external_target_set = false

func disable_movement():
	"""Disable movement logic (e.g., during elevator sequence)"""
	movement_disabled = true

func enable_movement():
	"""Re-enable movement logic"""
	movement_disabled = false

func _get_deck_height() -> float:
	"""Get the flight deck height from the carrier"""
	var carrier = get_parent()
	if carrier and carrier.has_method("get_deck_height"):
		return carrier.get_deck_height()
	# Fallback to carrier's global Y + 0.5
	if carrier and carrier is Node3D:
		return (carrier as Node3D).global_position.y + 0.5
	return 0.5

func _physics_process(delta: float):
	if not is_active or not target_aircraft or movement_disabled:
		return
	
	# Use external target if set (e.g., by elevator), otherwise calculate from aircraft
	if not external_target_set:
		# Track live wheel position if available; fallback to stored aircraft offset.
		var deck_height = _get_deck_height()
		if is_instance_valid(target_wheel_node):
			target_position = target_wheel_node.global_position
		else:
			target_position = target_aircraft.global_position + wheel_position_offset
		target_position.y = deck_height + follow_height
	
	# First phase: Move to gear position (slower, smoother)
	if not is_positioned:
		var distance = global_position.distance_to(target_position)
		if distance > 0.1:
			var move_amount = min(positioning_speed * delta, distance)  # Don't overshoot
			var direction = (target_position - global_position).normalized()
			global_position += direction * move_amount
		else:
			global_position = target_position
			is_positioned = true
	
	# Second phase: Follow aircraft movement (smooth lerp)
	else:
		# Use lerp for very smooth following movement
		var lerp_factor = 8.0 * delta  # Adjust this for smoothness vs responsiveness
		global_position = global_position.lerp(target_position, lerp_factor)
		
		# Rotate to face movement direction
		var direction = (target_position - global_position).normalized()
		if direction.length() > 0.1:
			var target_angle = atan2(direction.x, direction.z)
			var current_angle = global_rotation.y
			var angle_diff = target_angle - current_angle
			
			# Normalize angle difference
			while angle_diff > PI:
				angle_diff -= TAU
			while angle_diff < -PI:
				angle_diff += TAU
			
			# Rotate towards target angle
			var rotation_speed_rad = deg_to_rad(rotation_speed)
			var rotation_amount = sign(angle_diff) * min(abs(angle_diff), rotation_speed_rad * delta)
			global_rotation.y += rotation_amount
