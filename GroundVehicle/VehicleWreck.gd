extends RefCounted
class_name VehicleWreck

# Spawns heavier, faceted wreck pieces with simple ballistic breakup.

static func spawn(parent: Node3D, t: Transform3D, inherited_velocity: Vector3 = Vector3.ZERO) -> void:
	_spawn_body_pieces(parent, t, inherited_velocity)
	_spawn_tyres(parent, t, inherited_velocity)

static func create_angular_chunk_assets(size: Vector3) -> Dictionary:
	var points: Array[Vector3] = _build_angular_chunk_points(size)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(points)
	return {
		"mesh": _build_chunk_mesh(points),
		"shape": shape,
	}

static func _build_angular_chunk_points(size: Vector3) -> Array[Vector3]:
	var half := size * 0.5
	var front_z: float = half.z * randf_range(0.7, 1.1)
	var back_z: float = -half.z * randf_range(0.7, 1.05)
	var front_pull: float = randf_range(0.45, 0.9)
	var back_pull: float = randf_range(0.4, 0.85)
	var top_lift: float = randf_range(0.8, 1.25)
	var bottom_drop: float = randf_range(0.45, 1.0)
	var skew := Vector3(
		randf_range(-half.x * 0.25, half.x * 0.25),
		randf_range(-half.y * 0.2, half.y * 0.2),
		randf_range(-half.z * 0.15, half.z * 0.15)
	)
	return [
		Vector3(-half.x * randf_range(0.55, 1.0), -half.y * bottom_drop, front_z) + skew,
		Vector3(half.x * randf_range(0.35, 0.95), -half.y * randf_range(0.35, 0.95), front_z * front_pull) + skew,
		Vector3(half.x * randf_range(0.25, 0.9), half.y * top_lift, front_z * randf_range(0.25, 0.7)) + skew,
		Vector3(-half.x * randf_range(0.3, 0.85), half.y * randf_range(0.45, 1.05), front_z * randf_range(0.55, 1.0)) + skew,
		Vector3(-half.x * randf_range(0.4, 1.0), -half.y * randf_range(0.35, 0.9), back_z * back_pull) - skew * 0.35,
		Vector3(half.x * randf_range(0.6, 1.0), -half.y * randf_range(0.45, 1.0), back_z) - skew * 0.5,
		Vector3(half.x * randf_range(0.45, 1.0), half.y * randf_range(0.3, 0.95), back_z) - skew * 0.45,
		Vector3(-half.x * randf_range(0.55, 1.0), half.y * randf_range(0.45, 1.0), back_z * randf_range(0.55, 1.0)) - skew * 0.2,
	]

static func _build_chunk_mesh(points: Array[Vector3]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_face(surface, points, 0, 1, 2, 3)
	_add_face(surface, points, 5, 4, 7, 6)
	_add_face(surface, points, 4, 0, 3, 7)
	_add_face(surface, points, 1, 5, 6, 2)
	_add_face(surface, points, 3, 2, 6, 7)
	_add_face(surface, points, 4, 5, 1, 0)
	return surface.commit()

static func _add_face(surface: SurfaceTool, points: Array[Vector3], a: int, b: int, c: int, d: int) -> void:
	_add_triangle(surface, points[a], points[b], points[c])
	_add_triangle(surface, points[a], points[c], points[d])

static func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := Plane(a, b, c).normal
	if normal.length_squared() <= 0.000001:
		normal = (b - a).cross(c - a).normalized()
	if normal.length_squared() <= 0.000001:
		normal = Vector3.UP
	surface.set_normal(normal)
	surface.add_vertex(a)
	surface.set_normal(normal)
	surface.add_vertex(b)
	surface.set_normal(normal)
	surface.add_vertex(c)

static func _spawn_body_pieces(parent: Node3D, t: Transform3D, inherited_velocity: Vector3) -> void:
	var shard_specs := [
		{"size": Vector3(2.6, 1.1, 2.8), "offset": Vector3(0.0, 1.0, 0.5), "mass": 260.0},
		{"size": Vector3(1.9, 0.9, 2.4), "offset": Vector3(-1.05, 0.65, 1.8), "mass": 180.0},
		{"size": Vector3(1.8, 0.95, 2.2), "offset": Vector3(1.05, 0.7, 1.5), "mass": 175.0},
		{"size": Vector3(2.1, 0.8, 2.5), "offset": Vector3(-0.95, 0.55, -1.5), "mass": 170.0},
		{"size": Vector3(2.0, 0.85, 2.4), "offset": Vector3(1.0, 0.55, -1.8), "mass": 165.0},
		{"size": Vector3(1.35, 0.55, 1.8), "offset": Vector3(0.0, 0.45, 2.9), "mass": 110.0},
	]

	for i in range(shard_specs.size()):
		var spec: Dictionary = shard_specs[i]
		var rb := RigidBody3D.new()
		rb.name = "VehicleWreckShard_%d" % i
		rb.mass = float(spec.get("mass", 160.0)) * randf_range(0.85, 1.2)
		rb.contact_monitor = true
		rb.max_contacts_reported = 4
		parent.add_child(rb)

		var local_offset: Vector3 = spec["offset"] + Vector3(
			randf_range(-0.25, 0.25),
			randf_range(-0.1, 0.25),
			randf_range(-0.35, 0.35)
		)
		rb.global_position = t.origin + t.basis * local_offset
		rb.global_rotation = t.basis.get_euler() + Vector3(
			randf_range(-0.8, 0.8),
			randf_range(-PI, PI),
			randf_range(-0.7, 0.7)
		)

		var base_size: Vector3 = spec["size"]
		var size := Vector3(
			base_size.x * randf_range(0.85, 1.2),
			base_size.y * randf_range(0.8, 1.25),
			base_size.z * randf_range(0.85, 1.2)
		)
		var assets := create_angular_chunk_assets(size)

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = assets["mesh"] as ArrayMesh
		var mat := StandardMaterial3D.new()
		var shade: float = randf_range(0.08, 0.22)
		var warmth: float = randf_range(0.0, 0.04)
		mat.albedo_color = Color(shade + warmth, shade, shade * randf_range(0.9, 1.2))
		mat.roughness = 0.96
		mesh_instance.material_override = mat
		rb.add_child(mesh_instance)

		var collider := CollisionShape3D.new()
		collider.shape = assets["shape"] as Shape3D
		rb.add_child(collider)

		var outward: Vector3 = (rb.global_position - t.origin).normalized()
		if outward == Vector3.ZERO:
			outward = Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)).normalized()
		outward.y = maxf(outward.y + randf_range(0.25, 0.8), 0.25)
		rb.linear_velocity = inherited_velocity + outward.normalized() * randf_range(9.0, 22.0)
		rb.angular_velocity = Vector3(
			randf_range(-9.0, 9.0),
			randf_range(-8.0, 8.0),
			randf_range(-9.0, 9.0)
		)

		_auto_free(rb, randf_range(9.0, 13.0))

static func _spawn_tyres(parent: Node3D, t: Transform3D, inherited_velocity: Vector3) -> void:
	var tyre_offsets := [
		Vector3(-1.5, -0.9, 2.5),
		Vector3(1.5, -0.9, 2.5),
		Vector3(-1.5, -0.9, -1.0),
		Vector3(1.5, -0.9, -1.0),
		Vector3(-1.5, -0.9, -3.1),
		Vector3(1.5, -0.9, -3.1),
	]
	tyre_offsets.shuffle()
	tyre_offsets = tyre_offsets.slice(0, 4)

	for off in tyre_offsets:
		var rb := RigidBody3D.new()
		rb.mass = 14.0
		parent.add_child(rb)
		rb.global_position = t * off
		rb.global_rotation = t.basis.get_euler() + Vector3(
			randf_range(-0.5, 0.5),
			randf_range(-0.5, 0.5),
			randf_range(-0.5, 0.5)
		)

		var cyl := CylinderMesh.new()
		cyl.height = 0.32
		cyl.top_radius = 0.42
		cyl.bottom_radius = 0.42
		cyl.rings = 1
		cyl.radial_segments = 12
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.rotation_degrees = Vector3(90, 0, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.08, 0.08, 0.08)
		mat.roughness = 1.0
		mi.material_override = mat
		rb.add_child(mi)

		var col := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.height = 0.32
		sh.radius = 0.42
		col.shape = sh
		rb.add_child(col)

		var outward: Vector3 = (t.basis * off).normalized()
		outward.y = max(outward.y + 1.2, 0.8)
		rb.linear_velocity = inherited_velocity + outward.normalized() * randf_range(7.0, 16.0)
		var spin_axis: Vector3 = (t.basis.x if randf() > 0.5 else t.basis.z).normalized()
		rb.angular_velocity = spin_axis * randf_range(18.0, 45.0)

		_auto_free(rb, randf_range(8.0, 12.0))

static func _auto_free(node: Node, delay: float) -> void:
	var timer := Timer.new()
	timer.wait_time = delay
	timer.one_shot = true
	timer.timeout.connect(node.queue_free)
	timer.timeout.connect(timer.queue_free)
	node.add_child(timer)
	timer.start()
