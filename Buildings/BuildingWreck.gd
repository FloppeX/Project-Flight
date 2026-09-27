extends StaticBody3D
## Inert authored ruin. Collision follows the damaged silhouette, including holes.

func _ready() -> void:
	add_to_group("building_wrecks")
	for mesh: MeshInstance3D in $Model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var collision := CollisionShape3D.new()
		collision.shape = mesh.mesh.create_trimesh_shape()
		add_child(collision)
		collision.transform = global_transform.affine_inverse() * mesh.global_transform
	if has_meta("emplacement_main_color"):
		var color: Color = get_meta("emplacement_main_color")
		for mesh: MeshInstance3D in $Model.find_children("*", "MeshInstance3D", true, false):
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.get_active_material(surface)
				if material is StandardMaterial3D and material.resource_name.to_lower().replace("_", " ") == "main color":
					var paint := material.duplicate() as StandardMaterial3D
					paint.albedo_color = color
					mesh.set_surface_override_material(surface, paint)
