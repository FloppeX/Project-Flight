extends Node

const CARRIER_SCENE := preload("res://LandCarrier/LandCarrier2.tscn")
const EXPECTED_FULL_SIZE := Vector3(0.599504, 0.299766, 0.925827)

var _failures: PackedStringArray = []


func _ready() -> void:
	var carrier := CARRIER_SCENE.instantiate() as Node3D
	add_child(carrier)
	await get_tree().process_frame

	for shuttle_name in ["Shuttle", "Shuttle2"]:
		var shuttle := carrier.get_node(shuttle_name) as Node3D
		var model := shuttle.get_node("ShuttleModel") as Node3D
		var bounds := _mesh_bounds_in_space(model, shuttle)
		print("[CatapultShuttleSmoketest] %s model_scale=%s model_y=%.4f bounds=%s" % [
			shuttle_name,
			str(model.scale),
			model.position.y,
			str(bounds),
		])
		_expect(bounds.size.is_equal_approx(EXPECTED_FULL_SIZE), "%s did not restore the GLB mesh to 100%% size: %s" % [shuttle_name, bounds.size])
		_expect(is_zero_approx(bounds.position.y), "%s still floats %.3fm above the deck plane" % [shuttle_name, bounds.position.y])

	carrier.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("CATAPULT_SHUTTLE_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[CatapultShuttleSmoketest] %s" % failure)
	get_tree().quit(1)


func _mesh_bounds_in_space(root_node: Node, target_space: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh_instance := node as MeshInstance3D
			var local_aabb := mesh_instance.mesh.get_aabb()
			var mesh_to_target := target_space.global_transform.affine_inverse() * mesh_instance.global_transform
			for x in [local_aabb.position.x, local_aabb.end.x]:
				for y in [local_aabb.position.y, local_aabb.end.y]:
					for z in [local_aabb.position.z, local_aabb.end.z]:
						var point := mesh_to_target * Vector3(x, y, z)
						if not has_bounds:
							bounds = AABB(point, Vector3.ZERO)
							has_bounds = true
						else:
							bounds = bounds.expand(point)
		for child in node.get_children():
			stack.append(child)
	return bounds


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
