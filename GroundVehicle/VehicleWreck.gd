extends RefCounted
class_name VehicleWreck

# Spawns placeholder wreck pieces (4 body chunks + 4 tyres) at the given world transform.
# Call from explode() before queue_free():
#   VehicleWreck.spawn(get_parent(), global_transform)

static func spawn(parent: Node3D, t: Transform3D) -> void:
	_spawn_body_pieces(parent, t)
	_spawn_tyres(parent, t)

# ---------------------------------------------------------------------------

static func _spawn_body_pieces(parent: Node3D, t: Transform3D) -> void:
	# Four box chunks: front-left, front-right, rear-left, rear-right
	var pieces := [
		{"size": Vector3(0.85, 0.55, 2.1), "offset": Vector3(-0.55, 0.5,  1.1), "color": Color(0.28, 0.25, 0.20)},
		{"size": Vector3(0.85, 0.55, 2.1), "offset": Vector3( 0.55, 0.5,  1.1), "color": Color(0.30, 0.27, 0.22)},
		{"size": Vector3(0.85, 0.45, 2.2), "offset": Vector3(-0.55, 0.5, -1.1), "color": Color(0.22, 0.20, 0.18)},
		{"size": Vector3(0.85, 0.45, 2.2), "offset": Vector3( 0.55, 0.5, -1.1), "color": Color(0.25, 0.22, 0.20)},
	]

	for p in pieces:
		var rb := RigidBody3D.new()
		rb.mass = 180.0
		parent.add_child(rb)
		rb.global_transform = t
		# Offset the piece from the vehicle centre in world space
		rb.global_position += t.basis * (p["offset"] as Vector3)

		# Mesh
		var box := BoxMesh.new()
		box.size = p["size"]
		var mi := MeshInstance3D.new()
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p["color"]
		mat.roughness = 0.9
		mi.material_override = mat
		rb.add_child(mi)

		# Collision
		var col := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = p["size"]
		col.shape = sh
		rb.add_child(col)

		# Impulse: outward + upward
		var outward: Vector3 = (t.basis * (p["offset"] as Vector3)).normalized()
		outward.y = max(outward.y + 0.6, 0.3)
		rb.apply_impulse(outward.normalized() * randf_range(800.0, 3500.0))
		rb.apply_torque_impulse(Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)) * randf_range(200.0, 800.0))

		_auto_free(rb, randf_range(7.0, 10.0))

static func _spawn_tyres(parent: Node3D, t: Transform3D) -> void:
	# Approximate wheel positions matching the .tscn (local space)
	var tyre_offsets := [
		Vector3(-1.5, -0.9,  2.5),   # front-right
		Vector3( 1.5, -0.9,  2.5),   # front-left
		Vector3(-1.5, -0.9, -1.0),   # mid-right
		Vector3( 1.5, -0.9, -1.0),   # mid-left
		Vector3(-1.5, -0.9, -3.1),   # rear-right
		Vector3( 1.5, -0.9, -3.1),   # rear-left
	]

	# Only spawn 4 of the 6 — pick random ones so each explosion looks different
	tyre_offsets.shuffle()
	tyre_offsets = tyre_offsets.slice(0, 4)

	for off in tyre_offsets:
		var rb := RigidBody3D.new()
		rb.mass = 14.0
		parent.add_child(rb)
		rb.global_position = t * (off as Vector3)
		rb.global_rotation = t.basis.get_euler() + Vector3(
			randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))

		# Tyre mesh
		var cyl := CylinderMesh.new()
		cyl.height = 0.32
		cyl.top_radius = 0.42
		cyl.bottom_radius = 0.42
		cyl.rings = 1
		cyl.radial_segments = 12
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.rotation_degrees = Vector3(90, 0, 0)  # stand the cylinder upright
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.08, 0.08, 0.08)
		mat.roughness = 1.0
		mi.material_override = mat
		rb.add_child(mi)

		# Collision
		var col := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.height = 0.32
		sh.radius = 0.42
		col.shape = sh
		rb.add_child(col)

		# Tyres fly sideways and bounce
		var outward: Vector3 = (t.basis * (off as Vector3)).normalized()
		outward.y = max(outward.y + 1.2, 0.8)
		rb.apply_impulse(outward.normalized() * randf_range(300.0, 1200.0))
		# Spin the tyre as if it's rolling away
		var spin_axis: Vector3 = (t.basis.x if randf() > 0.5 else t.basis.z).normalized()
		rb.apply_torque_impulse(spin_axis * randf_range(500.0, 2000.0))

		_auto_free(rb, randf_range(8.0, 12.0))

static func _auto_free(node: Node, delay: float) -> void:
	var timer := Timer.new()
	timer.wait_time = delay
	timer.one_shot = true
	timer.timeout.connect(node.queue_free)
	timer.timeout.connect(timer.queue_free)
	node.add_child(timer)
	timer.start()
