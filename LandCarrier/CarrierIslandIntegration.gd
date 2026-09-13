extends Node3D
## Walking collision and lighting for the unified carrier model.
const INTERIOR_LAYER: int = 1 << 20

func _ready() -> void:
	var faces := PackedVector3Array()
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if not mesh.get_meta("carrier_interior", false):
			continue
		if mesh.has_meta("open_offset_x_m"):
			continue
		if mesh.name == "Superstructure elevator":
			add_surface_body(mesh, mesh.mesh.get_faces())
			continue
		var to_model: Transform3D = global_transform.affine_inverse() * mesh.global_transform
		for vertex in mesh.mesh.get_faces():
			faces.append(to_model * vertex)
	add_surface_body(self, faces)
	# The rendered deck includes bevels/underside triangles at the bow. Those
	# are useful for walking queries but must not duplicate the aircraft's
	# compound-hull runway or kick nose wheels upward during catapult release.
	var deck := get_node_or_null("Flight deck") as MeshInstance3D
	if deck:
		var deck_faces := PackedVector3Array()
		var to_model := global_transform.affine_inverse() * deck.global_transform
		for vertex in deck.mesh.get_faces():
			deck_faces.append(to_model * vertex)
		add_surface_body(self, deck_faces, INTERIOR_LAYER, "FlightDeckWalkingCollision")
	for point in [Vector3(21.5, 2.2, -4), Vector3(21.5, 2.2, 1.5),
		Vector3(20.4, 3.8, 6.0), Vector3(19.3, 5.8, 6.0),
		Vector3(21.6, 6.8, 2.3), Vector3(23.7, 6.8, 5.4),
		Vector3(20.4, 8.0, 6.0), Vector3(19.25, 9.5, 7.4),
		Vector3(19.25, 9.5, 4.5), Vector3(21.8, 10.7, 4.5)]:
		var light := OmniLight3D.new()
		light.name = "InteriorUtilityLight"
		light.position = point
		light.light_color = Color(0.78, 0.86, 1.0)
		light.light_energy = 0.65
		light.omni_range = 3.0
		light.distance_fade_enabled = true
		light.distance_fade_begin = 20.0
		light.distance_fade_length = 5.0
		add_child(light)
		light.add_to_group("carrier_interior_light")

func add_surface_body(parent: Node3D, faces: PackedVector3Array, layers: int = 1 | INTERIOR_LAYER, body_name: String = "InteriorSurfaceCollision") -> void:
	var body := AnimatableBody3D.new()
	body.name = body_name
	body.sync_to_physics = false
	body.collision_layer = layers
	body.collision_mask = 0
	parent.add_child(body)
	if get_parent() is PhysicsBody3D:
		body.add_collision_exception_with(get_parent())
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
