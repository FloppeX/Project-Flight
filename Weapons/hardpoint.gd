extends Node3D
class_name Hardpoint

const RETIRED_WEAPON_NAME_TOKEN := "missile"

@export var mounted_weapon: PackedScene  # Drag your weapon scenes here
@export var hardpoint_id: int = 0
@export var allowed_weapon_scene_paths: PackedStringArray = PackedStringArray()
@export var allowed_weapon_names: PackedStringArray = PackedStringArray()

var weapon_instance: Weapon = null
var aircraft: RigidBody3D = null

func _ready():
	if mounted_weapon:
		mount_weapon_from_scene(mounted_weapon)

func mount_weapon_from_scene(weapon_scene: PackedScene) -> bool:
	if not weapon_scene:
		return false
	if RETIRED_WEAPON_NAME_TOKEN in weapon_scene.resource_path.to_lower():
		push_warning("Hardpoint %s rejected retired missile weapon: %s" % [name, weapon_scene.resource_path])
		mounted_weapon = null
		return false

	var next_weapon := weapon_scene.instantiate() as Weapon
	if not next_weapon:
		push_warning("Hardpoint %s rejected a non-Weapon scene." % name)
		return false
	if RETIRED_WEAPON_NAME_TOKEN in _get_candidate_weapon_name(next_weapon).to_lower():
		push_warning("Hardpoint %s rejected retired missile weapon: %s" % [name, weapon_scene.resource_path])
		next_weapon.free()
		mounted_weapon = null
		return false

	if not _is_weapon_allowed(weapon_scene, next_weapon):
		push_warning("Hardpoint %s rejected weapon scene: %s" % [name, weapon_scene.resource_path])
		next_weapon.queue_free()
		return false

	if weapon_instance:
		weapon_instance.queue_free()

	weapon_instance = next_weapon
	add_child(weapon_instance)

	var attachment_point := weapon_instance.get_node_or_null("AttachmentPoint") as Node3D
	if attachment_point:
		weapon_instance.position = -attachment_point.position

	aircraft = _find_parent_aircraft()

	return true

func _find_parent_aircraft() -> RigidBody3D:
	var node := get_parent()
	while node:
		if node is RigidBody3D:
			return node as RigidBody3D
		node = node.get_parent()
	return null

func _is_weapon_allowed(weapon_scene: PackedScene, candidate_weapon: Weapon) -> bool:
	if allowed_weapon_scene_paths.size() == 0 and allowed_weapon_names.size() == 0:
		return true

	var scene_path := weapon_scene.resource_path
	if not scene_path.is_empty() and allowed_weapon_scene_paths.has(scene_path):
		return true

	var weapon_name := _get_candidate_weapon_name(candidate_weapon)
	return not weapon_name.is_empty() and allowed_weapon_names.has(weapon_name)

func _get_candidate_weapon_name(candidate_weapon: Weapon) -> String:
	if not candidate_weapon.weapon_name.is_empty() and candidate_weapon.weapon_name != "Generic Weapon":
		return candidate_weapon.weapon_name

	var gun_profile = candidate_weapon.get("gun_profile")
	if gun_profile and gun_profile.get("weapon_name") != null:
		return str(gun_profile.get("weapon_name"))

	return candidate_weapon.weapon_name

func fire():
	if not weapon_instance or not weapon_instance.can_fire():
		return false
	
	# Let the weapon handle its own firing logic (ammo, etc.)
	if not weapon_instance.fire():
		return false
	
	return true

func apply_recoil_force(force_magnitude: float, add_shake: bool = true, shake_scale: float = 0.01, shake_duration_s: float = 0.1):
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
		
		if add_shake and aircraft.has_method("add_shake"):
			aircraft.add_shake(varied_force * maxf(shake_scale, 0.0), maxf(shake_duration_s, 0.01))

func get_aircraft_velocity() -> Vector3:
	if aircraft:
		return aircraft.linear_velocity
	else:
		return Vector3.ZERO

func get_hardpoint_world_position() -> Vector3:
	return global_position

func get_hardpoint_forward_direction() -> Vector3:
	return global_transform.basis.z
