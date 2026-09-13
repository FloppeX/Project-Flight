extends Node3D

const GUNS := preload("res://Weapons/Turrets/TurretGunCatalog.gd")
const ASSEMBLY := preload("res://LandCarrier/CarrierDefenseTurretAssembly.tscn")
@export var turret_anchor_path: NodePath = NodePath(".")
var built_turret: Node3D
var installed_caliber_mm: int = 0

func is_built() -> bool:
	return is_instance_valid(built_turret) and not built_turret.is_queued_for_deletion()

func build_turret(caliber_mm: int) -> bool:
	if is_built() or not is_inside_tree():
		return false
	var profile := GUNS.get_profile(caliber_mm)
	var anchor := get_node_or_null(turret_anchor_path) as Node3D
	if profile == null or anchor == null:
		return false
	built_turret = ASSEMBLY.instantiate() as Node3D
	built_turret.set("gun_profile_override", profile)
	anchor.add_child(built_turret)
	installed_caliber_mm = caliber_mm
	return true

func clear_turret() -> void:
	if is_instance_valid(built_turret):
		built_turret.get_parent().remove_child(built_turret)
		built_turret.queue_free()
	built_turret = null
	installed_caliber_mm = 0
