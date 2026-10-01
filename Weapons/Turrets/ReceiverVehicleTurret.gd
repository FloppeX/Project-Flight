extends "res://Weapons/Turrets/turret.gd"
## Vehicle pedestal stays level; the receiver elevates on its side trunnions.

@export_node_path("Node3D") var receiver_path := NodePath("BarrelMount/Receiver")
@onready var receiver: Node3D = get_node(receiver_path)

func _ready() -> void:
	_bind_receiver()
	super._ready()

func _bind_receiver() -> void:
	barrel_mount = receiver.get_parent() as Node3D
	firing_points.assign([receiver.muzzle])
	# Use the receiver's barrel-only recoil rig; never recoil the body or pedestal.
	_barrel_recoil = receiver._recoil

func configure_weapon_barrel(weapon: Node) -> bool:
	if not "gun_profile" in weapon or weapon.gun_profile == null:
		return false
	var caliber := int(weapon.gun_profile.caliber_mm)
	if not receiver.GUNS.CALIBERS.has(caliber):
		return false
	if receiver.caliber_mm != caliber:
		receiver.caliber_mm = caliber
	else:
		receiver._recoil.reset()
	_bind_receiver()
	if weapon.has_method("use_turret_barrel_visual"):
		weapon.use_turret_barrel_visual()
	return true

func kick_barrel_recoil(caliber_mm: int, shot_interval_s: float) -> void:
	if enable_barrel_recoil and is_instance_valid(_barrel_recoil):
		_barrel_recoil.kick(caliber_mm, shot_interval_s)

func reset_barrel_recoil() -> void:
	if is_instance_valid(_barrel_recoil):
		_barrel_recoil.reset()
