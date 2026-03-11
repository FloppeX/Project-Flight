extends Node3D
class_name Turret

# --- Output Signals ---
signal target_acquired(target: Node3D)
signal target_lost()
signal fired()

# --- Configuration ---
@export_group("Aiming Restrictions")
@export var turn_speed: float = 60.0  # degrees per second
@export var pitch_speed: float = 60.0 # degrees per second
@export var max_pitch_up: float = 85.0 # degrees
@export var max_pitch_down: float = -15.0 # degrees

@export_group("References")
@export var base_mesh: Node3D # The Y-axis rotation part
@export var barrel_mount: Node3D # The X-axis pitch part (child of base)
@export var firing_points: Array[Node3D] = [] # Where projectiles spawn/weapons attach

# --- State ---
var current_target: Node3D = null
var current_target_position: Vector3 = Vector3.ZERO
var is_aiming_at_point: bool = false

# For alternating fire points
var _current_fire_point_idx: int = 0

func _ready() -> void:
	if not base_mesh:
		push_warning("Turret: base_mesh not assigned!")
	if not barrel_mount:
		push_warning("Turret: barrel_mount not assigned!")

func set_target(target: Node3D) -> void:
	if current_target != target:
		current_target = target
		if target:
			emit_signal("target_acquired", target)
		else:
			emit_signal("target_lost")
			is_aiming_at_point = false

func aim_at_point(point: Vector3) -> void:
	current_target_position = point
	is_aiming_at_point = true

func _process(delta: float) -> void:
	if not base_mesh or not barrel_mount:
		return
		
	var target_pos: Vector3
	var has_target = false
	
	if current_target and is_instance_valid(current_target):
		target_pos = current_target.global_position
		has_target = true
	elif is_aiming_at_point:
		target_pos = current_target_position
		has_target = true
		
	if has_target:
		_rotate_towards(target_pos, delta)
	else:
		# Optionally return to resting position
		pass

func _rotate_towards(target_pos: Vector3, delta: float) -> void:
	# 1. Yaw (Base Y rotation)
	var local_target = base_mesh.to_local(target_pos)
	# We want to rotate the base so its -Z axis points towards the target's X,Z
	var target_dir_2d = Vector2(local_target.x, local_target.z).normalized()
	
	if target_dir_2d.length() > 0.01:
		var yaw_angle = atan2(target_dir_2d.x, target_dir_2d.y) # We assume forward is -Z in local space (y in 2d is Z)
		# Note: Depending on model orientation, this might need tweaking
		# Godot standard forward is -Z. atan2(x, z) gives angle from Z axis.
		
		# We need a smooth rotation
		var turn_amount = deg_to_rad(turn_speed) * delta
		base_mesh.rotate_y(clamp(yaw_angle, -turn_amount, turn_amount))

	# 2. Pitch (Barrel X rotation)
	# Get target relative to the barrel mount, but only look at Y and local Z distance
	var barrel_local_target = barrel_mount.to_local(target_pos)
	# The pure horizontal distance in front of the barrel
	var horizontal_dist = Vector2(barrel_local_target.x, barrel_local_target.z).length()
	
	if horizontal_dist > 0.01:
		# Calculate pitch
		var pitch_angle = atan2(barrel_local_target.y, -barrel_local_target.z) # -Z is forward
		
		var pitch_amount = deg_to_rad(pitch_speed) * delta
		var applied_pitch = clamp(pitch_angle, -pitch_amount, pitch_amount)
		
		barrel_mount.rotate_x(applied_pitch)
		
		# Clamp total pitch
		var current_pitch = barrel_mount.rotation_degrees.x
		barrel_mount.rotation_degrees.x = clamp(current_pitch, max_pitch_down, max_pitch_up)

func is_aimed_at_target(tolerance_degrees: float = 5.0) -> bool:
	if not current_target and not is_aiming_at_point:
		return false
		
	var target_pos = current_target.global_position if current_target else current_target_position
	
	if barrel_mount:
		var to_target = (target_pos - barrel_mount.global_position).normalized()
		var forward = -barrel_mount.global_transform.basis.z
		
		var angle = rad_to_deg(acos(clamp(forward.dot(to_target), -1.0, 1.0)))
		return angle <= tolerance_degrees
		
	return false

func get_next_firing_transform() -> Transform3D:
	if firing_points.is_empty() and barrel_mount:
		return barrel_mount.global_transform
		
	if firing_points.is_empty():
		return global_transform
		
	var point = firing_points[_current_fire_point_idx]
	_current_fire_point_idx = (_current_fire_point_idx + 1) % firing_points.size()
	return point.global_transform

func fire() -> void:
	# Trigger attached weapons or emit signal for controller to handle
	emit_signal("fired")
	
	# Minimal recoil animation placeholder
	if barrel_mount:
		# Simple procedural recoil
		var tween = create_tween()
		var original_z = barrel_mount.position.z
		tween.tween_property(barrel_mount, "position:z", original_z + 0.1, 0.05)
		tween.tween_property(barrel_mount, "position:z", original_z, 0.1)
