extends "res://Weapons/Turrets/turret.gd"

const GUNS := preload("res://Weapons/Turrets/TurretGunCatalog.gd")
var mounted_barrel: Node3D
var mounted_caliber_mm: int = 0
var barrel_attachment: Node3D
var muzzle: Marker3D
var barrel_base: Node3D
var _barrel_visual_offset := Vector3.ZERO

func _ready() -> void:
	_bind_rig()
	super._ready()

func _bind_rig() -> void:
	base_mesh = find_child("turret body", true, false) as Node3D
	barrel_attachment = find_child("barrel position", true, false) as Node3D
	barrel_base = find_child("barrel base", true, false) as Node3D
	if barrel_attachment != null:
		# The authored locator's +Y points forward. Its nonuniform scale sizes the
		# marker mesh, not the gun; keep the position/orientation but not that scale.
		barrel_mount = Node3D.new()
		barrel_mount.name = "BarrelMount"
		barrel_attachment.get_parent().add_child(barrel_mount)
		barrel_mount.transform = Transform3D(
			barrel_attachment.transform.basis.orthonormalized() * Basis(Vector3.RIGHT, -PI / 2),
			barrel_attachment.position)
		if barrel_base != null:
			# The separate collar supplies the elevation hinge; retain the gun's
			# authored insertion point relative to it as the whole assembly tilts.
			barrel_mount.global_position = barrel_base.global_position
			_barrel_visual_offset = barrel_mount.to_local(barrel_attachment.global_position)
			barrel_base.reparent(barrel_mount, true)
		barrel_attachment.hide()
		barrel_forward_axis_local = Vector3.BACK
		barrel_pitch_axis_local = Vector3.RIGHT
		muzzle = Marker3D.new()
		muzzle.name = "Muzzle"
		barrel_mount.add_child(muzzle)
		firing_points.assign([muzzle])

func configure_weapon_barrel(weapon: Node) -> bool:
	if barrel_mount == null or not "gun_profile" in weapon:
		return false
	var profile: Resource = weapon.get("gun_profile") as Resource
	var caliber := int(profile.get("caliber_mm")) if profile != null else 0
	var barrel_scene := GUNS.get_barrel_scene(caliber)
	if barrel_scene == null:
		_clear_barrel()
		push_warning("[ModularTurret] No authored barrel for caliber %d." % caliber)
		return false
	_clear_barrel()
	mounted_barrel = barrel_scene.instantiate() as Node3D
	barrel_mount.add_child(mounted_barrel)
	mounted_barrel.position = _barrel_visual_offset
	mounted_caliber_mm = caliber
	# Place the muzzle at the actual model tip, accounting for all imported
	# child transforms. Never spawn rounds from the old locator or a guessed offset.
	var bounds := AABB()
	var has_bounds := false
	var meshes := mounted_barrel.find_children("*", "MeshInstance3D", true, false)
	if mounted_barrel is MeshInstance3D:
		meshes.append(mounted_barrel)
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var local_bounds: AABB = (barrel_mount.global_transform.affine_inverse() * mesh_node.global_transform) * mesh_node.get_aabb()
		bounds = bounds.merge(local_bounds) if has_bounds else local_bounds
		has_bounds = true
	if has_bounds:
		muzzle.position = Vector3(bounds.get_center().x, bounds.get_center().y, bounds.end.z)
	if weapon.has_method("use_turret_barrel_visual"):
		weapon.call("use_turret_barrel_visual")
	return true

func _clear_barrel() -> void:
	reset_barrel_recoil()
	if is_instance_valid(mounted_barrel):
		mounted_barrel.get_parent().remove_child(mounted_barrel)
		mounted_barrel.queue_free()
	mounted_barrel = null
	mounted_caliber_mm = 0
