extends Node3D
class_name Hardpoint

@export var mounted_weapon: PackedScene  # Drag your weapon scenes here
@export var hardpoint_id: int = 0

var weapon_instance: Weapon = null

func _ready():
	if mounted_weapon:
		mount_weapon_from_scene(mounted_weapon)

func mount_weapon_from_scene(weapon_scene: PackedScene):
	if weapon_instance:
		weapon_instance.queue_free()
	
	weapon_instance = weapon_scene.instantiate()
	add_child(weapon_instance)
		# Find the RigidBody3D (Aircraft) up the tree
	var aircraft = get_parent()
	while aircraft and not (aircraft is RigidBody3D):
		aircraft = aircraft.get_parent()

	if aircraft:
		weapon_instance.mount_to_aircraft(aircraft)
	


func fire():
	if weapon_instance:
		return weapon_instance.fire()
	return false
