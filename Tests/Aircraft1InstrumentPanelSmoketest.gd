extends Node

const AIRCRAFT_1_SCENE: PackedScene = preload("res://Aircraft/Aircraft_1.tscn")
const AIRCRAFT_5_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")

var _failures: PackedStringArray = []


func _ready() -> void:
	var aircraft_1 := AIRCRAFT_1_SCENE.instantiate() as RigidBody3D
	var aircraft_5 := AIRCRAFT_5_SCENE.instantiate() as RigidBody3D
	_expect(aircraft_1 != null and aircraft_5 != null, "comparison aircraft did not instantiate")
	if aircraft_1 == null or aircraft_5 == null:
		_finish(aircraft_1, aircraft_5)
		return

	var panel_1 := aircraft_1.get_node_or_null("InstrumentPanel") as Node3D
	var panel_5 := aircraft_5.get_node_or_null("InstrumentPanel") as Node3D
	_expect(panel_1 != null and panel_5 != null, "instrument panel nodes were not found")
	if panel_1 != null and panel_5 != null:
		var camera_1 := aircraft_1.get_node_or_null("CameraCockpit") as Node3D
		var camera_5 := aircraft_5.get_node_or_null("CameraCockpit") as Node3D
		_expect(camera_1 != null and camera_5 != null, "cockpit camera nodes were not found")
		if camera_1 != null and camera_5 != null:
			_expect(panel_1.transform.basis.is_equal_approx(panel_5.transform.basis), "Aircraft 1 panel orientation or scale differs from Aircraft 5")
		_expect(panel_1.get("panel_size") == panel_5.get("panel_size"), "panel sizes differ")
		_expect(panel_1.get("viewport_resolution") == panel_5.get("viewport_resolution"), "panel resolutions differ")
		_expect(panel_1.get("module_layout") == panel_5.get("module_layout"), "instrument module layouts differ")
		_expect(bool(panel_1.get("render_to_model_surface")), "Aircraft 1 does not render through its cockpit material")
		_expect(not bool(panel_1.get("model_panel_use_mesh_uv")), "Aircraft 1 still uses the rotated and center-mirrored panel UV island")
		var panel_mesh_path := panel_1.get("model_panel_mesh_path") as NodePath
		_expect(panel_mesh_path == NodePath("../aircraft_1/fuselage"), "Aircraft 1 does not target its cockpit mesh")
		var model_panel_mesh := aircraft_1.get_node_or_null("aircraft_1/fuselage") as MeshInstance3D
		_expect(model_panel_mesh != null and model_panel_mesh.mesh != null, "Aircraft 1 cockpit mesh could not be resolved")
		if model_panel_mesh != null and model_panel_mesh.mesh != null:
			var matching_surface_count := 0
			var panel_local_bounds := Rect2()
			for surface_index in range(model_panel_mesh.mesh.get_surface_count()):
				var material := model_panel_mesh.get_surface_override_material(surface_index)
				if material == null:
					material = model_panel_mesh.mesh.surface_get_material(surface_index)
				if material == null or material.resource_name != "Instrument panel material":
					continue
				matching_surface_count += 1
				var arrays := model_panel_mesh.mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				_expect(not vertices.is_empty(), "Aircraft 1 cockpit display surface has no geometry")
				if not vertices.is_empty():
					var min_xy := Vector2(vertices[0].x, vertices[0].y)
					var max_xy := min_xy
					for vertex in vertices:
						min_xy = Vector2(minf(min_xy.x, vertex.x), minf(min_xy.y, vertex.y))
						max_xy = Vector2(maxf(max_xy.x, vertex.x), maxf(max_xy.y, vertex.y))
					panel_local_bounds = Rect2(min_xy, max_xy - min_xy)
			_expect(matching_surface_count == 1, "Aircraft 1 dedicated instrument-panel material was not resolved exactly once")
			if panel_local_bounds.size.y > 0.0001:
				var surface_aspect := panel_local_bounds.size.x / panel_local_bounds.size.y
				var panel_resolution := panel_1.get("viewport_resolution") as Vector2i
				var viewport_aspect := float(panel_resolution.x) / float(panel_resolution.y)
				_expect(absf(surface_aspect - viewport_aspect) < 0.05, "Aircraft 1 panel surface does not match the instrument viewport aspect ratio")
		_expect(bool(panel_1.get("model_panel_flip_x")) == bool(panel_5.get("model_panel_flip_x")), "panel texture orientation differs")

	_finish(aircraft_1, aircraft_5)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(aircraft_1: Node, aircraft_5: Node) -> void:
	if aircraft_1 != null:
		aircraft_1.free()
	if aircraft_5 != null:
		aircraft_5.free()
	if _failures.is_empty():
		print("AIRCRAFT_1_INSTRUMENT_PANEL_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[Aircraft1InstrumentPanelSmoketest] %s" % failure)
	get_tree().quit(1)
