extends Node

const AIRCRAFT_14_SCENE: PackedScene = preload("res://Aircraft/Aircraft_14.tscn")
const AIRCRAFT_5_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft_14 := AIRCRAFT_14_SCENE.instantiate() as RigidBody3D
	var aircraft_5 := AIRCRAFT_5_SCENE.instantiate() as RigidBody3D
	_expect(aircraft_14 != null and aircraft_5 != null, "comparison aircraft did not instantiate")
	if aircraft_14 == null or aircraft_5 == null:
		_finish(aircraft_14, aircraft_5)
		return

	var panel_14 := aircraft_14.get_node_or_null("InstrumentPanel") as Node3D
	var panel_5 := aircraft_5.get_node_or_null("InstrumentPanel") as Node3D
	_expect(panel_14 != null and panel_5 != null, "instrument panel nodes were not found")
	if panel_14 == null or panel_5 == null:
		_finish(aircraft_14, aircraft_5)
		return

	_expect(panel_14.get("panel_size") == panel_5.get("panel_size"), "panel sizes differ")
	_expect(panel_14.get("viewport_resolution") == panel_5.get("viewport_resolution"), "panel resolutions differ")
	_expect(panel_14.get("module_layout") == panel_5.get("module_layout"), "instrument module layouts differ")
	_expect(bool(panel_14.get("render_to_model_surface")), "Aircraft 14 does not render through its cockpit material")
	_expect(not bool(panel_14.get("model_panel_use_mesh_uv")), "Aircraft 14 does not use Aircraft 5's local panel projection")
	_expect(bool(panel_14.get("model_panel_flip_x")) == bool(panel_5.get("model_panel_flip_x")), "panel texture orientation differs")
	_expect(panel_14.get("camera_target_path") == panel_5.get("camera_target_path"), "target-camera binding differs")
	_expect(panel_14.get("zoom_distance") == panel_5.get("zoom_distance"), "target-camera zoom distance differs")

	var panel_mesh_path := panel_14.get("model_panel_mesh_path") as NodePath
	var material_names := panel_14.get("model_panel_material_names") as PackedStringArray
	_expect(panel_mesh_path == NodePath("PanelModel/instrument panel"), "Aircraft 14 does not target the standalone panel scene's display surface")
	_expect(material_names == PackedStringArray(["Instrument panel material"]), "Aircraft 14 does not target its instrument panel material")
	_expect(aircraft_14.get_node_or_null("aircraft_14/instrument panel") == null, "Aircraft 14 still contains an embedded instrument panel mesh")

	var model_panel_mesh := panel_14.get_node_or_null(panel_mesh_path) as MeshInstance3D
	_expect(model_panel_mesh != null and model_panel_mesh.mesh != null, "standalone instrument panel mesh could not be resolved")
	var fallback_panel_mesh := panel_14.get_node_or_null("PanelScreen") as MeshInstance3D
	_expect(fallback_panel_mesh != null and not fallback_panel_mesh.visible, "standalone panel still exposes the old fallback screen")
	if model_panel_mesh != null and model_panel_mesh.mesh != null:
		var matching_surfaces := PackedInt32Array()
		for surface_index in range(model_panel_mesh.mesh.get_surface_count()):
			var material := model_panel_mesh.mesh.surface_get_material(surface_index)
			if material != null and material.resource_name == "Instrument panel material":
				matching_surfaces.append(surface_index)
		_expect(matching_surfaces == PackedInt32Array([1]), "instrument panel material is not uniquely authored on surface 1")

	aircraft_14.freeze = true
	add_child(aircraft_14)
	await get_tree().process_frame
	var bound_mesh := panel_14.get("model_panel_mesh") as MeshInstance3D
	var bound_surfaces := panel_14.get("model_panel_surface_indices") as PackedInt32Array
	_expect(bound_mesh == model_panel_mesh, "instrument panel projection did not bind to the Aircraft 14 mesh")
	_expect(bound_surfaces == PackedInt32Array([1]), "instrument panel projection did not bind only to surface 1")
	if model_panel_mesh != null:
		var camera := aircraft_14.get_node_or_null("CameraCockpit/Camera3D") as Camera3D
		var arrays := model_panel_mesh.mesh.surface_get_arrays(1)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var local_center := Vector3.ZERO
		var local_normal := Vector3.ZERO
		for vertex in vertices:
			local_center += vertex
		for normal in normals:
			local_normal += normal
		if not vertices.is_empty():
			local_center /= float(vertices.size())
		if not normals.is_empty():
			local_normal = (local_normal / float(normals.size())).normalized()
		var world_normal := (model_panel_mesh.global_transform.basis * local_normal).normalized()
		var toward_camera := (camera.global_position - model_panel_mesh.to_global(local_center)).normalized() if camera != null else Vector3.ZERO
		_expect(camera != null and world_normal.dot(toward_camera) > 0.8, "standalone instrument panel surface is turned away from the pilot")
		var override_material := model_panel_mesh.get_surface_override_material(1) as ShaderMaterial
		_expect(override_material != null, "instrument panel material was not replaced by the live display shader")
		if override_material != null:
			_expect(override_material.get_shader_parameter("panel_texture") != null, "live display shader has no viewport texture")

	_finish(aircraft_14, aircraft_5)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(aircraft_14: Node, aircraft_5: Node) -> void:
	if aircraft_14 != null:
		aircraft_14.free()
	if aircraft_5 != null:
		aircraft_5.free()
	if _failures.is_empty():
		print("AIRCRAFT_14_INSTRUMENT_PANEL_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[Aircraft14InstrumentPanelSmoketest] %s" % failure)
	get_tree().quit(1)
