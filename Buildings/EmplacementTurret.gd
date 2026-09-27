extends "res://Weapons/Turrets/ModularTurret.gd"
## Adapt the authored emplacement pivots to the shared +Z-forward gun rig.
## The holder keeps its imported scale/orientation; only the aiming pivot is normalized.

var _holder_from_pitch: Transform3D = Transform3D.IDENTITY

func _bind_rig() -> void:
	var model := get_node("../../Model")
	base_mesh = model.find_child("turret", true, false) as Node3D
	yaw_mount = base_mesh
	barrel_attachment = model.find_child("barrel holder", true, false) as Node3D
	if yaw_mount == null or barrel_attachment == null:
		push_error("Enemy emplacement is missing its authored turret or barrel holder.")
		return
	barrel_mount = Node3D.new()
	barrel_mount.name = "BarrelMount"
	yaw_mount.add_child(barrel_mount)
	barrel_mount.position = barrel_attachment.position
	_holder_from_pitch = barrel_mount.transform.affine_inverse() * barrel_attachment.transform
	barrel_forward_axis_local = Vector3.BACK
	barrel_pitch_axis_local = Vector3.RIGHT
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	barrel_mount.add_child(muzzle)
	firing_points.assign([muzzle])

func tick(delta: float, target_pos: Vector3) -> void:
	super.tick(delta, target_pos)
	if is_instance_valid(barrel_attachment) and is_instance_valid(barrel_mount):
		# Follow pitch without reparenting the authored mesh or including it in recoil.
		barrel_attachment.transform = barrel_mount.transform * _holder_from_pitch
