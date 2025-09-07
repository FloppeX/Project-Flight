extends Node3D
class_name Weapon

@export var weapon_name: String = "Generic Weapon"
@export var ammo_count: int = 100
@export var weight: float = 50.0
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
