extends Node3D
class_name Weapon

@export var weapon_name: String = "Generic Weapon"
@export var ammo_count: int = 100
@export var weight: float = 50.0
@export var delete_when_empty: bool = false

var mounted_aircraft: RigidBody3D

func mount_to_aircraft(aircraft: RigidBody3D):
	mounted_aircraft = aircraft

func fire() -> bool:
	# Override this in child classes
	if not can_fire():
		return false
	
	# Placeholder - actual firing logic goes in subclasses
	ammo_count -= 1
	
	# Self-destruct if enabled and empty
	if delete_when_empty and ammo_count <= 0:
		queue_free()
	
	return true

func can_fire() -> bool:
	return ammo_count > 0

func is_empty() -> bool:
	return ammo_count <= 0

func get_weapon_info() -> Dictionary:
	return {
		"name": weapon_name,
		"ammo": ammo_count,
		"weight": weight,
		"can_fire": can_fire()
	}
