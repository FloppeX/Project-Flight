extends Node3D
class_name Weapon

@export var weapon_name: String = "Generic Weapon"
## Broad category used for grouping (e.g. "Guns"). When set, selection and firing
## use this instead of weapon_name so all guns fire together regardless of calibre.
var weapon_category: String = ""
@export var ammo_count: int = 100:
	set(value):
		ammo_count = value
		if is_inside_tree():
			_refresh_aircraft_payload_mass()
## Empty weapon hardware mass in kilograms (ammunition is added separately).
@export var weight: float = 50.0
@export var round_mass_kg: float = 0.0
@export var delete_when_empty: bool = false
@export var automatic_fire: bool = false

func get_recoil_force() -> float:  # Returns magnitude, not vector
	return 0.0  # Override in child classes

func fire() -> bool:
	if not can_fire():
		return false
	
	# Let the hardpoint handle aircraft-specific stuff
	ammo_count -= 1
	
	if delete_when_empty and ammo_count <= 0:
		queue_free()
	
	return true

func can_fire() -> bool:
	return ammo_count > 0


var _payload_aircraft: RigidBody3D = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_refresh_aircraft_payload_mass.call_deferred()
	elif what == NOTIFICATION_EXIT_TREE:
		if is_instance_valid(_payload_aircraft) and _payload_aircraft.has_method("clear_payload_mass"):
			_payload_aircraft.clear_payload_mass(self)
		_payload_aircraft = null

func _get_parent_rigidbody() -> RigidBody3D:
	var node := get_parent()
	while node != null and not (node is RigidBody3D):
		node = node.get_parent()
	return node as RigidBody3D

func get_payload_mass_kg() -> float:
	return maxf(weight, 0.0) + maxf(ammo_count, 0) * maxf(round_mass_kg, 0.0)

func _refresh_aircraft_payload_mass() -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(_payload_aircraft):
		_payload_aircraft = _get_parent_rigidbody()
	if is_instance_valid(_payload_aircraft) and _payload_aircraft.has_method("set_payload_mass"):
		_payload_aircraft.set_payload_mass(self, get_payload_mass_kg())
