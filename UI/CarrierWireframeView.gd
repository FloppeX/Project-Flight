class_name CarrierWireframeView
extends Control

signal model_ready

## Presentation-only carrier schematic sourced from the Technical Index catalog.
##
## The gameplay scene and its authored materials are never modified. A private
## scene instance is frozen, stripped of runtime behaviour, and rendered through
## material overrides in an isolated SubViewport.

const Catalog: Script = preload("res://UI/TechnicalIndexCatalog.gd")
const WIREFRAME_SHADER: Shader = preload("res://Shaders/carrier_console_wireframe.gdshader")
const CARRIER_TREAD_SCRIPT_PATH := "res://LandCarrier/CarrierTread.gd"
const CARRIER_CATALOG_NAME := "LAND CARRIER"
const CREASE_ANGLE_DEGREES := 25.0
const EDGE_POSITION_QUANTIZATION_M := 0.001

const BACKGROUND_COLOR := Color("090d0d")
const WIREFRAME_COLOR := Color("76c7c7")
const HIGHLIGHT_COLOR := Color("b9ffff")
const WARNING_HIGHLIGHT_COLOR := Color("ffb000")
const TEXT_COLOR := Color("c4c7c7")
const ERROR_COLOR := Color("ffb000")

var _preview_container: SubViewportContainer
var _preview_viewport: SubViewport
var _preview_model_root: Node3D
var _preview_camera: Camera3D
var _error_label: Label
var _wireframe_material: ShaderMaterial
var _highlight_material: ShaderMaterial
var _warning_highlight_material: ShaderMaterial
var _model_instance: Node3D
var _highlight_box: MeshInstance3D

var _model_scene_path: String = ""
var _wire_geometry_count: int = 0
var _wire_segment_count: int = 0
var _source_triangle_count: int = 0
var _build_time_ms: float = 0.0
var _build_profile_ms: Dictionary = {}
var _model_bounds: AABB = AABB()
var _model_loaded: bool = false
var _load_requested: bool = false
var _load_request_start_usec: int = 0
var _feature_mesh_cache: Dictionary = {}
var _geometry_records: Array[Dictionary] = []
var _selected_region_id: String = "defenses"
var _selected_region_warning: bool = true
var _highlighted_geometry_count: int = 0
var _dragging: bool = false
var _orbit_yaw: float = 0.68
var _orbit_pitch: float = 0.32
var _zoom: float = 0.8
var _preview_radius: float = 1.0
var _base_camera_distance: float = 10.0
var _camera_target_y: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_build_viewport()
	resized.connect(_sync_viewport_size)
	_sync_viewport_size()
	set_process(false)


func set_console_visible(value: bool) -> void:
	visible = value
	if value and not _model_loaded and not _load_requested and _model_instance == null:
		_request_catalog_carrier()
	if _preview_viewport != null:
		_preview_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
		)


func get_debug_snapshot() -> Dictionary:
	return {
		"source": "technical_index",
		"catalog_name": CARRIER_CATALOG_NAME,
		"scene_path": _model_scene_path,
		"model_loaded": _model_loaded,
		"load_requested": _load_requested,
		"edge_mode": "crease_filtered",
		"crease_angle_degrees": CREASE_ANGLE_DEGREES,
		"wire_geometry_count": _wire_geometry_count,
		"wire_segment_count": _wire_segment_count,
		"source_triangle_count": _source_triangle_count,
		"selected_region": _selected_region_id,
		"highlight_warning": _selected_region_warning,
		"highlighted_geometry_count": _highlighted_geometry_count,
		"build_time_ms": _build_time_ms,
		"build_profile_ms": _build_profile_ms.duplicate(),
		"bounds_size": _model_bounds.size,
		"viewport_size": _preview_viewport.size if _preview_viewport != null else Vector2i.ZERO,
		"presentation_only": true,
	}


func _process(_delta: float) -> void:
	if not _load_requested or _model_scene_path.is_empty():
		set_process(false)
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_model_scene_path, progress)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var percent := int(round(float(progress[0]) * 100.0)) if not progress.is_empty() else 0
		_error_label.text = "LOADING CARRIER SCHEMATIC  //  %02d%%" % percent
		return
	_load_requested = false
	set_process(false)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_show_error("CARRIER MODEL COULD NOT BE LOADED")
		return
	var packed := ResourceLoader.load_threaded_get(_model_scene_path) as PackedScene
	_build_profile_ms["threaded_load"] = float(Time.get_ticks_usec() - _load_request_start_usec) / 1000.0
	if packed == null:
		_show_error("CARRIER MODEL COULD NOT BE LOADED")
		return
	_build_loaded_carrier(packed)


func reset_view() -> void:
	_orbit_yaw = 0.68
	_orbit_pitch = 0.32
	_zoom = 0.8
	_apply_camera()


func set_highlighted_region(region_id: String, warning: bool = false) -> void:
	_selected_region_id = region_id
	_selected_region_warning = warning
	_apply_region_highlight()


func _build_viewport() -> void:
	_preview_container = SubViewportContainer.new()
	_preview_container.name = "CarrierSchematicViewport"
	_preview_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_container.stretch = true
	_preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_container.gui_input.connect(_on_preview_gui_input)
	add_child(_preview_container)

	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "WireframeViewport"
	_preview_viewport.size = Vector2i(1280, 720)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_preview_viewport.own_world_3d = true
	_preview_viewport.add_to_group("settings_aa_viewport")
	var root_viewport := get_tree().root as Viewport
	if root_viewport != null:
		_preview_viewport.msaa_3d = root_viewport.msaa_3d
		_preview_viewport.screen_space_aa = root_viewport.screen_space_aa
		_preview_viewport.use_taa = root_viewport.use_taa
	_preview_container.add_child(_preview_viewport)

	var environment_node := WorldEnvironment.new()
	environment_node.name = "SchematicEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = WIREFRAME_COLOR
	environment.ambient_light_energy = 0.2
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	_preview_viewport.add_child(environment_node)

	_preview_model_root = Node3D.new()
	_preview_model_root.name = "CarrierModelRoot"
	_preview_viewport.add_child(_preview_model_root)

	_preview_camera = Camera3D.new()
	_preview_camera.name = "SchematicCamera"
	_preview_camera.fov = 35.0
	_preview_camera.current = true
	_preview_viewport.add_child(_preview_camera)

	_error_label = Label.new()
	_error_label.name = "SchematicStatus"
	_error_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_error_label.add_theme_font_size_override("font_size", 13)
	_error_label.add_theme_color_override("font_color", TEXT_COLOR)
	_error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_error_label.text = "CARRIER SCHEMATIC STANDBY"
	add_child(_error_label)

	_wireframe_material = ShaderMaterial.new()
	_wireframe_material.shader = WIREFRAME_SHADER
	_wireframe_material.set_shader_parameter("wire_color", WIREFRAME_COLOR)
	_highlight_material = ShaderMaterial.new()
	_highlight_material.shader = WIREFRAME_SHADER
	_highlight_material.set_shader_parameter("wire_color", HIGHLIGHT_COLOR)
	_highlight_material.set_shader_parameter("emission_strength", 2.15)
	_warning_highlight_material = ShaderMaterial.new()
	_warning_highlight_material.shader = WIREFRAME_SHADER
	_warning_highlight_material.set_shader_parameter("wire_color", WARNING_HIGHLIGHT_COLOR)
	_warning_highlight_material.set_shader_parameter("emission_strength", 2.0)


func _request_catalog_carrier() -> void:
	var entry := _find_catalog_carrier_entry()
	_model_scene_path = str(entry.get("scene", ""))
	if _model_scene_path.is_empty() or not ResourceLoader.exists(_model_scene_path):
		_show_error("CARRIER MODEL UNAVAILABLE")
		return
	_build_profile_ms.clear()
	_load_request_start_usec = Time.get_ticks_usec()
	var request_error := ResourceLoader.load_threaded_request(_model_scene_path, "PackedScene")
	if request_error != OK:
		_show_error("CARRIER MODEL COULD NOT BE LOADED")
		return
	_load_requested = true
	_error_label.text = "LOADING CARRIER SCHEMATIC  //  00%"
	_error_label.add_theme_color_override("font_color", TEXT_COLOR)
	_error_label.visible = true
	set_process(true)


func _build_loaded_carrier(packed: PackedScene) -> void:
	var build_start_usec := Time.get_ticks_usec()
	var phase_start_usec := build_start_usec
	phase_start_usec = Time.get_ticks_usec()
	var instance := packed.instantiate()
	_build_profile_ms["instantiate"] = float(Time.get_ticks_usec() - phase_start_usec) / 1000.0
	if not instance is Node3D:
		if instance != null:
			instance.free()
		_show_error("CARRIER MODEL HAS NO 3D ROOT")
		return

	phase_start_usec = Time.get_ticks_usec()
	_prepare_generated_track_geometry(instance)
	_build_profile_ms["tracks"] = float(Time.get_ticks_usec() - phase_start_usec) / 1000.0
	phase_start_usec = Time.get_ticks_usec()
	var edge_result := _replace_geometry_with_feature_edges(instance)
	_build_profile_ms["feature_edges"] = float(Time.get_ticks_usec() - phase_start_usec) / 1000.0
	_wire_geometry_count = int(edge_result.get("geometry_count", 0))
	_wire_segment_count = int(edge_result.get("segment_count", 0))
	_source_triangle_count = int(edge_result.get("triangle_count", 0))
	phase_start_usec = Time.get_ticks_usec()
	_sanitize_preview_tree(instance)
	_model_instance = instance as Node3D
	_preview_model_root.add_child(_model_instance)

	var bounds_data := _calculate_model_bounds()
	if not bool(bounds_data.get("found", false)):
		_preview_model_root.remove_child(_model_instance)
		_model_instance.queue_free()
		_model_instance = null
		_show_error("CARRIER MODEL HAS NO VISIBLE GEOMETRY")
		return
	_model_bounds = bounds_data.get("bounds", AABB()) as AABB
	_model_instance.position -= _model_bounds.get_center()
	_capture_geometry_records()
	_apply_region_highlight()
	_fit_camera(_model_bounds.size)
	_model_loaded = true
	_build_profile_ms["finish"] = float(Time.get_ticks_usec() - phase_start_usec) / 1000.0
	_build_profile_ms["main_thread_finalize"] = float(Time.get_ticks_usec() - build_start_usec) / 1000.0
	_build_time_ms = float(Time.get_ticks_usec() - _load_request_start_usec) / 1000.0
	_error_label.visible = false
	model_ready.emit()


func _find_catalog_carrier_entry() -> Dictionary:
	for category: String in Catalog.categories():
		for entry: Dictionary in Catalog.entries_for(category):
			if str(entry.get("name", "")).to_upper() == CARRIER_CATALOG_NAME:
				return entry
	return {}


func _prepare_generated_track_geometry(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var node_script := node.get_script() as Script
		if node_script != null \
				and node_script.resource_path == CARRIER_TREAD_SCRIPT_PATH \
				and node.has_method("_rebuild_track_multimesh"):
			node.call("_rebuild_track_multimesh")
		for child in node.get_children():
			stack.append(child as Node)


func _replace_geometry_with_feature_edges(root: Node) -> Dictionary:
	var geometry_count := 0
	var segment_count := 0
	var triangle_count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh_node := node as MeshInstance3D
			var edge_data := _feature_edges_for_mesh(mesh_node.mesh)
			var feature_mesh := edge_data.get("mesh") as Mesh
			if feature_mesh != null:
				mesh_node.mesh = feature_mesh
				mesh_node.material_override = _wireframe_material
				mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				geometry_count += 1
				segment_count += int(edge_data.get("segment_count", 0))
				triangle_count += int(edge_data.get("triangle_count", 0))
			else:
				mesh_node.visible = false
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			var multimesh_node := node as MultiMeshInstance3D
			var source_multimesh := multimesh_node.multimesh
			if source_multimesh.mesh != null:
				var edge_data := _feature_edges_for_mesh(source_multimesh.mesh)
				var feature_mesh := edge_data.get("mesh") as Mesh
				if feature_mesh != null:
					var feature_multimesh := _copy_multimesh_with_mesh(source_multimesh, feature_mesh)
					multimesh_node.multimesh = feature_multimesh
					multimesh_node.material_override = _wireframe_material
					multimesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					var instance_multiplier := maxi(source_multimesh.instance_count, 1)
					geometry_count += 1
					segment_count += int(edge_data.get("segment_count", 0)) * instance_multiplier
					triangle_count += int(edge_data.get("triangle_count", 0)) * instance_multiplier
				else:
					multimesh_node.visible = false
		for child in node.get_children():
			stack.append(child as Node)
	return {
		"geometry_count": geometry_count,
		"segment_count": segment_count,
		"triangle_count": triangle_count,
	}


func _copy_multimesh_with_mesh(source: MultiMesh, feature_mesh: Mesh) -> MultiMesh:
	var result := MultiMesh.new()
	result.transform_format = source.transform_format
	result.use_colors = source.use_colors
	result.use_custom_data = source.use_custom_data
	result.mesh = feature_mesh
	result.instance_count = source.instance_count
	for instance_index in range(source.instance_count):
		if source.transform_format == MultiMesh.TRANSFORM_3D:
			result.set_instance_transform(instance_index, source.get_instance_transform(instance_index))
		else:
			result.set_instance_transform_2d(instance_index, source.get_instance_transform_2d(instance_index))
		if source.use_colors:
			result.set_instance_color(instance_index, source.get_instance_color(instance_index))
		if source.use_custom_data:
			result.set_instance_custom_data(instance_index, source.get_instance_custom_data(instance_index))
	result.visible_instance_count = source.visible_instance_count
	return result


func _feature_edges_for_mesh(source_mesh: Mesh) -> Dictionary:
	var cache_key := source_mesh.get_instance_id()
	if _feature_mesh_cache.has(cache_key):
		return _feature_mesh_cache[cache_key] as Dictionary
	var result := _build_feature_edge_mesh(source_mesh)
	_feature_mesh_cache[cache_key] = result
	return result


func _build_feature_edge_mesh(source_mesh: Mesh) -> Dictionary:
	var edges: Dictionary = {}
	var topology_point_ids: Dictionary = {}
	var preserved_lines := PackedVector3Array()
	var triangle_count := 0
	for surface_index in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface_index)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if vertices.is_empty():
			continue
		var topology_ids := PackedInt32Array()
		topology_ids.resize(vertices.size())
		for vertex_index in range(vertices.size()):
			topology_ids[vertex_index] = _topology_point_id(vertices[vertex_index], topology_point_ids)
		# PrimitiveMesh (BoxMesh, CylinderMesh, and similar) always supplies
		# triangle surfaces but does not expose ArrayMesh's query method.
		var primitive := Mesh.PRIMITIVE_TRIANGLES
		if source_mesh.has_method("surface_get_primitive_type"):
			primitive = int(source_mesh.call("surface_get_primitive_type", surface_index))
		if primitive == Mesh.PRIMITIVE_LINES:
			_append_existing_lines(vertices, indices, preserved_lines)
			continue
		if primitive != Mesh.PRIMITIVE_TRIANGLES:
			continue
		if indices.is_empty():
			for vertex_index in range(0, vertices.size() - 2, 3):
				if _record_triangle_edges(
					edges,
					vertices[vertex_index],
					vertices[vertex_index + 1],
					vertices[vertex_index + 2],
					topology_ids[vertex_index],
					topology_ids[vertex_index + 1],
					topology_ids[vertex_index + 2]
				):
					triangle_count += 1
		else:
			for index_offset in range(0, indices.size() - 2, 3):
				var index_a := indices[index_offset]
				var index_b := indices[index_offset + 1]
				var index_c := indices[index_offset + 2]
				if index_a < 0 or index_b < 0 or index_c < 0 \
						or index_a >= vertices.size() \
						or index_b >= vertices.size() \
						or index_c >= vertices.size():
					continue
				if _record_triangle_edges(
					edges,
					vertices[index_a],
					vertices[index_b],
					vertices[index_c],
					topology_ids[index_a],
					topology_ids[index_b],
					topology_ids[index_c]
				):
					triangle_count += 1

	var line_vertices := preserved_lines
	var crease_cosine := cos(deg_to_rad(CREASE_ANGLE_DEGREES))
	for edge_variant in edges.values():
		var edge := edge_variant as Array
		if not _is_feature_edge(edge, crease_cosine):
			continue
		line_vertices.append(edge[0] as Vector3)
		line_vertices.append(edge[1] as Vector3)

	if line_vertices.is_empty():
		return {
			"mesh": null,
			"segment_count": 0,
			"triangle_count": triangle_count,
		}
	var line_arrays := []
	line_arrays.resize(Mesh.ARRAY_MAX)
	line_arrays[Mesh.ARRAY_VERTEX] = line_vertices
	var feature_mesh := ArrayMesh.new()
	feature_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)
	return {
		"mesh": feature_mesh,
		"segment_count": line_vertices.size() / 2,
		"triangle_count": triangle_count,
	}


func _append_existing_lines(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	out_lines: PackedVector3Array
) -> void:
	if indices.is_empty():
		for vertex_index in range(0, vertices.size() - 1, 2):
			out_lines.append(vertices[vertex_index])
			out_lines.append(vertices[vertex_index + 1])
		return
	for index_offset in range(0, indices.size() - 1, 2):
		var index_a := indices[index_offset]
		var index_b := indices[index_offset + 1]
		if index_a < 0 or index_b < 0 or index_a >= vertices.size() or index_b >= vertices.size():
			continue
		out_lines.append(vertices[index_a])
		out_lines.append(vertices[index_b])


func _record_triangle_edges(
	edges: Dictionary,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	topology_a: int,
	topology_b: int,
	topology_c: int
) -> bool:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() <= 0.00000001:
		return false
	normal = normal.normalized()
	_record_edge(edges, topology_a, topology_b, a, b, normal)
	_record_edge(edges, topology_b, topology_c, b, c, normal)
	_record_edge(edges, topology_c, topology_a, c, a, normal)
	return true


func _record_edge(
	edges: Dictionary,
	topology_a: int,
	topology_b: int,
	a: Vector3,
	b: Vector3,
	face_normal: Vector3
) -> void:
	if a.distance_squared_to(b) <= 0.00000001:
		return
	var lower_id := mini(topology_a, topology_b)
	var upper_id := maxi(topology_a, topology_b)
	var edge_key := (lower_id << 32) | upper_id
	if not edges.has(edge_key):
		# [endpoint A, endpoint B, adjacent face count, first normal, minimum dot]
		edges[edge_key] = [a, b, 1, face_normal, 1.0]
		return
	var edge := edges[edge_key] as Array
	edge[2] = int(edge[2]) + 1
	var first_normal := edge[3] as Vector3
	edge[4] = minf(float(edge[4]), first_normal.dot(face_normal))


func _is_feature_edge(edge: Array, crease_cosine: float) -> bool:
	if int(edge[2]) <= 1:
		return true
	return float(edge[4]) <= crease_cosine


func _topology_point_id(point: Vector3, point_ids: Dictionary) -> int:
	var quantized := Vector3i(
		roundi(point.x / EDGE_POSITION_QUANTIZATION_M),
		roundi(point.y / EDGE_POSITION_QUANTIZATION_M),
		roundi(point.z / EDGE_POSITION_QUANTIZATION_M)
	)
	if not point_ids.has(quantized):
		point_ids[quantized] = point_ids.size()
	return int(point_ids[quantized])


func _capture_geometry_records() -> void:
	_geometry_records.clear()
	if not is_instance_valid(_model_instance):
		return
	var root_inverse := _preview_model_root.global_transform.affine_inverse()
	var stack: Array[Node] = [_model_instance]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var local_bounds := AABB()
		var has_geometry := false
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh_node := node as MeshInstance3D
			local_bounds = (root_inverse * mesh_node.global_transform) * mesh_node.mesh.get_aabb()
			has_geometry = true
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			var multimesh_node := node as MultiMeshInstance3D
			local_bounds = (root_inverse * multimesh_node.global_transform) * multimesh_node.get_aabb()
			has_geometry = true
		if has_geometry:
			_geometry_records.append({
				"node": node,
				"path": str(_model_instance.get_path_to(node)).to_lower(),
				"bounds": local_bounds,
			})
		for child in node.get_children():
			stack.append(child as Node)


func _apply_region_highlight() -> void:
	_highlighted_geometry_count = 0
	var active_material := _warning_highlight_material if _selected_region_warning else _highlight_material
	for record: Dictionary in _geometry_records:
		var geometry := record.get("node") as GeometryInstance3D
		if not is_instance_valid(geometry):
			continue
		var highlighted := _record_matches_region(record, _selected_region_id)
		geometry.material_override = active_material if highlighted else _wireframe_material
		if highlighted:
			_highlighted_geometry_count += 1
	_clear_highlight_box()
	if _selected_region_id == "overview" or not _model_loaded and _geometry_records.is_empty():
		return
	var region_bounds := _region_bounds(_selected_region_id)
	if region_bounds.size.length_squared() > 0.001:
		_highlight_box = _make_bounds_wireframe(region_bounds, active_material)
		_preview_model_root.add_child(_highlight_box)


func _record_matches_region(record: Dictionary, region_id: String) -> bool:
	var path := str(record.get("path", ""))
	if region_id == "overview":
		return false
	if region_id == "defenses":
		return "carrierdefenseturret" in path or "turret" in path
	if region_id == "elevators":
		return "elevator" in path
	if region_id == "drive":
		return "tread" in path or "track" in path or "wheel" in path
	var bounds: AABB = record.get("bounds", AABB()) as AABB
	return bounds.intersects(_region_bounds(region_id))


func _region_bounds(region_id: String) -> AABB:
	var size := _model_bounds.size
	if size.length_squared() <= 0.001:
		return AABB()
	var center := Vector3.ZERO
	var region_size := size * Vector3(0.45, 0.30, 0.42)
	match region_id:
		"flight_deck":
			center = Vector3(0.0, size.y * 0.08, 0.0)
			region_size = Vector3(size.x * 0.96, size.y * 0.18, size.z * 0.96)
		"hangar":
			center = Vector3(0.0, -size.y * 0.10, 0.0)
			region_size = Vector3(size.x * 0.72, size.y * 0.28, size.z * 0.62)
		"elevators":
			center = Vector3(0.0, size.y * 0.03, size.z * 0.08)
			region_size = Vector3(size.x * 0.92, size.y * 0.24, size.z * 0.62)
		"island":
			center = Vector3(-size.x * 0.23, size.y * 0.27, -size.z * 0.12)
			region_size = Vector3(size.x * 0.30, size.y * 0.48, size.z * 0.28)
		"vehicle_bay":
			center = Vector3(0.0, -size.y * 0.20, size.z * 0.18)
			region_size = Vector3(size.x * 0.64, size.y * 0.26, size.z * 0.34)
		"replicator":
			center = Vector3(-size.x * 0.16, -size.y * 0.18, -size.z * 0.10)
			region_size = Vector3(size.x * 0.30, size.y * 0.24, size.z * 0.30)
		"habitation":
			center = Vector3(size.x * 0.13, -size.y * 0.02, -size.z * 0.15)
			region_size = Vector3(size.x * 0.34, size.y * 0.30, size.z * 0.34)
		"defenses":
			center = Vector3(0.0, size.y * 0.10, 0.0)
			region_size = Vector3(size.x * 0.88, size.y * 0.34, size.z * 0.72)
		"drive":
			center = Vector3(0.0, -size.y * 0.24, 0.0)
			region_size = Vector3(size.x, size.y * 0.36, size.z)
		"stores":
			center = Vector3(0.0, -size.y * 0.16, -size.z * 0.10)
			region_size = Vector3(size.x * 0.62, size.y * 0.24, size.z * 0.46)
	return AABB(center - region_size * 0.5, region_size)


func _make_bounds_wireframe(bounds: AABB, material: Material) -> MeshInstance3D:
	var corners: Array[Vector3] = []
	for corner_index in range(8):
		corners.append(bounds.get_endpoint(corner_index))
	var edge_indices := [
		0, 1, 0, 2, 0, 4,
		1, 3, 1, 5,
		2, 3, 2, 6,
		3, 7,
		4, 5, 4, 6,
		5, 7,
		6, 7,
	]
	var vertices := PackedVector3Array()
	for corner_index in edge_indices:
		vertices.append(corners[corner_index])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "SelectedRegionBounds"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance


func _clear_highlight_box() -> void:
	if not is_instance_valid(_highlight_box):
		_highlight_box = null
		return
	if _highlight_box.get_parent() != null:
		_highlight_box.get_parent().remove_child(_highlight_box)
	_highlight_box.queue_free()
	_highlight_box = null


func _sanitize_preview_tree(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	if node is SubViewport:
		(node as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
	if node is Camera3D:
		(node as Camera3D).current = false
	if node is Light3D:
		(node as Light3D).visible = false
	if node is WorldEnvironment:
		(node as WorldEnvironment).environment = null
	if node is Decal:
		(node as Decal).visible = false
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
	if node is CPUParticles3D:
		(node as CPUParticles3D).emitting = false
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	if node is AudioStreamPlayer2D:
		(node as AudioStreamPlayer2D).stop()
	if node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stop()
	for child in node.get_children():
		_sanitize_preview_tree(child as Node)
	if node.get_script() != null:
		node.set_script(null)


func _calculate_model_bounds() -> Dictionary:
	var found := false
	var bounds := AABB()
	var root_inverse := _preview_model_root.global_transform.affine_inverse()
	var stack: Array[Node] = [_preview_model_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D \
				and (node as MeshInstance3D).mesh != null \
				and (node as MeshInstance3D).visible:
			var mesh_node := node as MeshInstance3D
			var local_bounds: AABB = (root_inverse * mesh_node.global_transform) * mesh_node.mesh.get_aabb()
			bounds = local_bounds if not found else bounds.merge(local_bounds)
			found = true
		elif node is MultiMeshInstance3D \
				and (node as MultiMeshInstance3D).multimesh != null \
				and (node as MultiMeshInstance3D).visible:
			var multimesh_node := node as MultiMeshInstance3D
			var local_bounds: AABB = (root_inverse * multimesh_node.global_transform) * multimesh_node.get_aabb()
			bounds = local_bounds if not found else bounds.merge(local_bounds)
			found = true
		for child in node.get_children():
			stack.append(child as Node)
	return {"found": found, "bounds": bounds}


func _fit_camera(extents: Vector3) -> void:
	_preview_radius = maxf(extents.length() * 0.5, 0.5)
	var vertical_tangent := tan(deg_to_rad(_preview_camera.fov * 0.5))
	var viewport_aspect := float(_preview_viewport.size.x) / maxf(float(_preview_viewport.size.y), 1.0)
	var horizontal_tangent := vertical_tangent * viewport_aspect
	var half_height := maxf(extents.y * 0.5, 0.25)
	var horizontal_radius := maxf(Vector2(extents.x, extents.z).length() * 0.5, 0.25)
	var projected_vertical_radius := half_height * cos(_orbit_pitch) + horizontal_radius * sin(_orbit_pitch)
	_base_camera_distance = maxf(
		projected_vertical_radius / vertical_tangent,
		horizontal_radius / horizontal_tangent
	) * 1.48
	_base_camera_distance = maxf(_base_camera_distance, _preview_radius * 1.28)
	_camera_target_y = -_preview_radius * 0.06
	_apply_camera()


func _apply_camera() -> void:
	if not is_instance_valid(_preview_camera):
		return
	var distance := _base_camera_distance * _zoom
	_preview_camera.near = maxf(0.05, distance - _preview_radius * 1.45)
	_preview_camera.far = maxf(1000.0, distance + _preview_radius * 7.0)
	var target := Vector3(0.0, _camera_target_y, 0.0)
	var horizontal_distance := cos(_orbit_pitch) * distance
	var offset := Vector3(
		sin(_orbit_yaw) * horizontal_distance,
		sin(_orbit_pitch) * distance,
		cos(_orbit_yaw) * horizontal_distance
	)
	_preview_camera.position = target + offset
	_preview_camera.look_at(target, Vector3.UP)


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse_button.pressed
			if mouse_button.double_click:
				reset_view()
			accept_event()
			return
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * 0.9, 0.62, 2.2)
			_apply_camera()
			accept_event()
			return
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * 1.1, 0.62, 2.2)
			_apply_camera()
			accept_event()
			return
	if event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_orbit_yaw -= motion.relative.x * 0.008
		_orbit_pitch = clampf(_orbit_pitch - motion.relative.y * 0.006, -0.12, 1.15)
		_apply_camera()
		accept_event()


func _sync_viewport_size() -> void:
	if _preview_viewport == null:
		return
	var render_size := Vector2i(
		maxi(int(round(size.x)), 2),
		maxi(int(round(size.y)), 2)
	)
	if _preview_viewport.size != render_size:
		_preview_viewport.size = render_size
		if _model_loaded:
			_fit_camera(_model_bounds.size)


func _show_error(message: String) -> void:
	_model_loaded = false
	_load_requested = false
	set_process(false)
	_error_label.text = message
	_error_label.add_theme_color_override("font_color", ERROR_COLOR)
	_error_label.visible = true
