extends RefCounted
## Seat the angular turret's authored short axle directly on the mount roof.
## Its housing already has the intended low profile; no mesh deformation is needed.

static func fit(assembly: Node3D, surface_y: float) -> void:
	if assembly.has_meta("carrier_mount_fitted"):
		return
	var turret := assembly.get_node("TurretScene") as Node3D
	var model := turret.get_node("TurretModel") as Node3D
	var body := model.get_node("turret body") as MeshInstance3D
	var mesh_to_mount := assembly.transform * turret.transform * model.transform * body.transform
	var bottom := (mesh_to_mount * body.mesh.get_aabb()).position.y
	assembly.position.y += surface_y - bottom
	assembly.set_meta("carrier_mount_fitted", true)
