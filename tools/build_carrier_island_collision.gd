extends SceneTree
## Rebuild exterior convex volumes from the authored island, in model space.
## Run with --headless --path . --script res://tools/build_carrier_island_collision.gd
const OUTPUT := "res://LandCarrier/CarrierIslandCollision.tscn"
# Follow the main changes in the island silhouette, rather than bridging from
# the broad lower structure directly to its narrow observation room and mast.
const HEIGHTS := [-2.60, 0.0, 4.78, 8.85, 11.15, 12.02, 13.34, 15.40, 16.33, 19.20, 23.20]

func _init() -> void:
	call_deferred("run")

func clip_height(polygon: PackedVector3Array, height: float, keep_above: bool) -> PackedVector3Array:
	var result := PackedVector3Array()
	if polygon.is_empty():
		return result
	var previous := polygon[-1]
	var previous_inside := previous.y >= height if keep_above else previous.y <= height
	for point in polygon:
		var inside := point.y >= height if keep_above else point.y <= height
		if inside != previous_inside:
			result.append(previous.lerp(point, (height - previous.y) / (point.y - previous.y)))
		if inside:
			result.append(point)
		previous = point
		previous_inside = inside
	return result

func run() -> void:
	var model := (load("res://Models/LandCarrier/Land carrier 4.glb") as PackedScene).instantiate()
	var mesh := model.get_node("superstructure main island") as MeshInstance3D
	var faces := mesh.mesh.get_faces()
	for i in faces.size():
		faces[i] = mesh.transform * faces[i]
	var body := AnimatableBody3D.new()
	body.name = "IslandExteriorCollision"
	body.set_script(load("res://LandCarrier/CarrierIslandCollision.gd"))
	body.collision_layer = 1
	body.collision_mask = 0
	body.sync_to_physics = false
	body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	for band in range(HEIGHTS.size() - 1):
		var points := PackedVector3Array()
		var seen := {}
		for i in range(0, faces.size(), 3):
			var polygon := PackedVector3Array([faces[i], faces[i + 1], faces[i + 2]])
			polygon = clip_height(polygon, HEIGHTS[band], true)
			polygon = clip_height(polygon, HEIGHTS[band + 1], false)
			for point in polygon:
				var key := point.snapped(Vector3.ONE * 0.001)
				if not seen.has(key):
					seen[key] = true
					points.append(point)
		if points.size() < 4:
			continue
		# Let Godot remove redundant interior points before saving the hull.
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		var cloud := ArrayMesh.new()
		cloud.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
		var shape := cloud.create_convex_shape(true, false)
		var collision := CollisionShape3D.new()
		collision.name = "IslandBand%02d" % band
		collision.shape = shape
		body.add_child(collision)
		collision.owner = body
	var packed := PackedScene.new()
	var error := packed.pack(body)
	if error == OK:
		error = ResourceSaver.save(packed, OUTPUT)
	print("ISLAND_COLLISION_BUILD shapes=%d result=%d" % [body.get_child_count(), error])
	model.free()
	body.free()
	quit(0 if error == OK else 1)
