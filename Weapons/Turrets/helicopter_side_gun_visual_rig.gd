extends Node

@export var yaw_pivot: Node3D
@export var barrel_mount: Node3D
@export var shaft_mesh: Node3D
@export var gun_mesh: Node3D

func _ready() -> void:
	if yaw_pivot and shaft_mesh and is_instance_valid(shaft_mesh):
		shaft_mesh.reparent(yaw_pivot, true)
	if barrel_mount and gun_mesh and is_instance_valid(gun_mesh):
		gun_mesh.reparent(barrel_mount, true)
