extends Node

const AIRCRAFT_1_MODEL := "res://Models/Aircraft_1/Aircraft_1.glb"
const TEST_PATTERN_INDEX := 4

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var livery := get_node_or_null("/root/Livery")
	_expect(livery != null, "Livery autoload is available")
	var packed := load(AIRCRAFT_1_MODEL) as PackedScene
	_expect(packed != null, "Aircraft 1 model loads")
	if livery == null or packed == null:
		_finish()
		return

	livery.call("set_player_livery", Color("566b78"), Color("d19a3a"), TEST_PATTERN_INDEX)
	var model := packed.instantiate()
	add_child(model)
	var source_color := _find_named_source_color(model, "upper fuselage")
	_expect(source_color.a >= 0.0, "Aircraft 1 exposes an authored livery source color")
	_add_color_keyed_nested_panel(model, source_color)
	livery.call("apply", model)

	var coverage := _collect_pattern_coverage(model)
	var target_count := int(coverage.get("target_count", 0))
	var patterned_target_count := int(coverage.get("patterned_target_count", 0))
	var patterned_mesh_count := int(coverage.get("patterned_mesh_ids", {}).size())
	var patterned_non_target_count := int(coverage.get("patterned_non_target_count", 0))
	var shared_space_count := int(coverage.get("shared_space_count", 0))
	var mismatched_transform_count := int(coverage.get("mismatched_transform_count", 0))
	_expect(target_count >= 6, "Aircraft 1 exposes fuselage, four wings, and a color-keyed nested target surface")
	_expect(patterned_target_count == target_count, "every nested target-colored surface receives the livery pattern")
	_expect(patterned_mesh_count >= 6, "pattern reaches differently named nested mesh objects as well as the fuselage and wings")
	_expect(patterned_non_target_count == 0, "non-target materials do not receive the livery pattern")
	_expect(shared_space_count == patterned_target_count, "every patterned target uses the shared object-space projection")
	_expect(mismatched_transform_count == 0, "each submesh contributes its authored transform to the shared pattern coordinates")

	model.queue_free()
	_finish()


func _collect_pattern_coverage(node: Node) -> Dictionary:
	var result := {
		"target_count": 0,
		"patterned_target_count": 0,
		"patterned_non_target_count": 0,
		"patterned_mesh_ids": {},
		"shared_space_count": 0,
		"mismatched_transform_count": 0,
	}
	_collect_pattern_coverage_recursive(node, node as Node3D, result)
	return result


func _find_named_source_color(node: Node, material_name: String) -> Color:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface_index)
				if material is StandardMaterial3D and material_name in material.resource_name.to_lower():
					return (material as StandardMaterial3D).albedo_color
	for child in node.get_children():
		var found := _find_named_source_color(child, material_name)
		if found.a >= 0.0:
			return found
	return Color(0.0, 0.0, 0.0, -1.0)


func _add_color_keyed_nested_panel(model: Node, source_color: Color) -> void:
	var nested_root := Node3D.new()
	nested_root.name = "NestedSubObjects"
	nested_root.position = Vector3(3.5, 0.4, -1.25)
	model.add_child(nested_root)
	var nested_child := Node3D.new()
	nested_child.name = "ImportedPartContainer"
	nested_child.position = Vector3(1.75, -0.2, 2.0)
	nested_root.add_child(nested_child)
	var panel := MeshInstance3D.new()
	panel.name = "ColorMatchedPanel"
	var box := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.resource_name = "Detached color keyed panel"
	material.albedo_color = source_color
	box.material = material
	panel.mesh = box
	nested_child.add_child(panel)


func _collect_pattern_coverage_recursive(node: Node, asset_root: Node3D, result: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var source_material := mesh.surface_get_material(surface_index)
				var source_name := source_material.resource_name.to_lower() if source_material != null else ""
				var is_target := "upper fuselage" in source_name or "detached color keyed panel" in source_name
				var override := mesh_instance.get_surface_override_material(surface_index)
				var is_patterned := _is_test_pattern_material(override)
				if is_patterned:
					var shader_material := override as ShaderMaterial
					if bool(shader_material.get_shader_parameter("use_shared_pattern_space")):
						result["shared_space_count"] = int(result["shared_space_count"]) + 1
					var actual_transform: Variant = shader_material.get_shader_parameter("pattern_local_to_root")
					var expected_transform := asset_root.global_transform.affine_inverse() * mesh_instance.global_transform
					if not actual_transform is Transform3D or not _transforms_match(actual_transform as Transform3D, expected_transform):
						result["mismatched_transform_count"] = int(result["mismatched_transform_count"]) + 1
				if is_target:
					result["target_count"] = int(result["target_count"]) + 1
					if is_patterned:
						result["patterned_target_count"] = int(result["patterned_target_count"]) + 1
						(result["patterned_mesh_ids"] as Dictionary)[mesh_instance.get_instance_id()] = true
				elif is_patterned:
					result["patterned_non_target_count"] = int(result["patterned_non_target_count"]) + 1
	for child in node.get_children():
		_collect_pattern_coverage_recursive(child, asset_root, result)


func _transforms_match(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) <= 0.0001 \
			and a.basis.x.distance_to(b.basis.x) <= 0.0001 \
			and a.basis.y.distance_to(b.basis.y) <= 0.0001 \
			and a.basis.z.distance_to(b.basis.z) <= 0.0001


func _is_test_pattern_material(material: Material) -> bool:
	if not material is ShaderMaterial:
		return false
	var shader_material := material as ShaderMaterial
	return shader_material.resource_name == "Livery Test Pattern" \
			and int(shader_material.get_shader_parameter("pattern_mode")) == TEST_PATTERN_INDEX


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("[LiveryHierarchySmoketest] FAIL: %s" % description)


func _finish() -> void:
	if _failures.is_empty():
		print("[LiveryHierarchySmoketest] PASS")
		get_tree().quit(0)
		return
	print("[LiveryHierarchySmoketest] %d failure(s)" % _failures.size())
	get_tree().quit(1)
