extends Node3D
class_name Hardpoint

@export var mounted_weapon: PackedScene  # Drag your weapon scenes here
@export var hardpoint_id: int = 0

var weapon_instance: Weapon = null
var aircraft: RigidBody3D = null

func _ready():
	if mounted_weapon:
		mount_weapon_from_scene(mounted_weapon)

func mount_weapon_from_scene(weapon_scene: PackedScene):
	if weapon_instance:
		weapon_instance.queue_free()
	
	weapon_instance = weapon_scene.instantiate()
	add_child(weapon_instance)
	
	# Find the aircraft once and cache it
	print("[Hardpoint] Looking for aircraft parent...")
	aircraft = get_parent() as RigidBody3D
	print("[Hardpoint] Initial parent: ", get_parent().name if get_parent() else "null", " (", get_parent().get_class() if get_parent() else "null", ")")
	while aircraft and not (aircraft is RigidBody3D):
		print("[Hardpoint] Parent ", aircraft.name, " is not RigidBody3D, checking its parent...")
		aircraft = aircraft.get_parent()
	
	if aircraft:
		print("[Hardpoint] Found aircraft: ", aircraft.name, " (", aircraft.get_class(), ")")
	else:
		print("[Hardpoint] ERROR: No RigidBody3D aircraft found in parent hierarchy!")

func fire():
	if not weapon_instance or not weapon_instance.can_fire():
		return false
	
	# Let the weapon handle its own firing logic (ammo, etc.)
	if not weapon_instance.fire():
		return false
	
	return true

func apply_recoil_force(force_magnitude: float):
	if aircraft:
		# Random force variation ±25%
		var varied_force = force_magnitude * randf_range(0.75, 1.25)
		
		# Add random scatter to recoil direction - use opposite of forward direction
		var base_direction = -get_hardpoint_forward_direction()  # Recoil is opposite to firing direction
		var random_offset = Vector3(
			randf_range(-0.15, 0.15),
			randf_range(-0.15, 0.15), 
			randf_range(-0.1, 0.1)
		)
		var recoil_direction = (base_direction + random_offset).normalized()
		
		# Apply main recoil force
		var recoil_force = recoil_direction * varied_force
		var local_position = global_position - aircraft.global_position
		aircraft.apply_force(recoil_force, local_position)
		
		aircraft.add_shake(varied_force * 0.01, 0.1)  # Scale shake to force magnitude

func get_aircraft_velocity() -> Vector3:
	if aircraft:
		return aircraft.linear_velocity
	else:
		print("No aircraft found!")
		return Vector3.ZERO

func get_hardpoint_world_position() -> Vector3:
	return global_position

func get_hardpoint_forward_direction() -> Vector3:
	return global_transform.basis.z
