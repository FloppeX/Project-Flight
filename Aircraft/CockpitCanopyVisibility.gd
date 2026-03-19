extends Node
class_name CockpitCanopyVisibility

@export var cockpit_camera_path: NodePath = NodePath("../CameraCockpit/Camera3D")
@export var canopy_node_paths: Array[NodePath] = [NodePath("../Aircraft 2 body/canopy")]
@export var canopy_surface_mesh_paths: Array[NodePath] = []
@export var canopy_surface_indices: PackedInt32Array = PackedInt32Array()
@export var cockpit_shadow_disable_paths: Array[NodePath] = []

var _cockpit_camera: Camera3D
var _canopy_nodes: Array[Node3D] = []
var _canopy_surfaces: Array[Dictionary] = []
var _shadow_nodes: Array[Dictionary] = []
var _last_hidden: bool = false

func _ready() -> void:
	_cockpit_camera = get_node_or_null(cockpit_camera_path) as Camera3D
	for canopy_path in canopy_node_paths:
		var canopy := get_node_or_null(canopy_path) as Node3D
		if canopy:
			_canopy_nodes.append(canopy)
	var surface_count := mini(canopy_surface_mesh_paths.size(), canopy_surface_indices.size())
	for i in range(surface_count):
		var mesh_instance := get_node_or_null(canopy_surface_mesh_paths[i]) as MeshInstance3D
		if mesh_instance == null:
			continue
		var surface_index := int(canopy_surface_indices[i])
		if mesh_instance.mesh == null or surface_index < 0 or surface_index >= mesh_instance.mesh.get_surface_count():
			continue
		_canopy_surfaces.append({
			"mesh": mesh_instance,
			"surface": surface_index,
			"original_override": mesh_instance.get_surface_override_material(surface_index),
			"hidden_override": _make_hidden_material(mesh_instance, surface_index),
		})
	for shadow_path in cockpit_shadow_disable_paths:
		var mesh_instance := get_node_or_null(shadow_path) as GeometryInstance3D
		if mesh_instance:
			_shadow_nodes.append({
				"mesh": mesh_instance,
				"original_cast_shadow": mesh_instance.cast_shadow,
			})
	if _cockpit_camera == null:
		push_warning("[CockpitCanopyVisibility] Cockpit camera not found")
	if _canopy_nodes.is_empty() and _canopy_surfaces.is_empty() and _shadow_nodes.is_empty():
		push_warning("[CockpitCanopyVisibility] No canopy nodes, surfaces, or shadow nodes found")
	_update_canopy_visibility()

func _process(_delta: float) -> void:
	_update_canopy_visibility()

func _update_canopy_visibility() -> void:
	if _canopy_nodes.is_empty() and _canopy_surfaces.is_empty() and _shadow_nodes.is_empty():
		return
	var should_hide := _cockpit_camera != null and _cockpit_camera.current
	if should_hide == _last_hidden:
		return
	_last_hidden = should_hide
	for canopy in _canopy_nodes:
		if is_instance_valid(canopy):
			canopy.visible = not should_hide
	for surface_data in _canopy_surfaces:
		var mesh_instance := surface_data.get("mesh") as MeshInstance3D
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		var surface_index := int(surface_data.get("surface", -1))
		var material: Material = (surface_data.get("hidden_override") if should_hide else surface_data.get("original_override")) as Material
		mesh_instance.set_surface_override_material(surface_index, material)
	for shadow_data in _shadow_nodes:
		var mesh_instance := shadow_data.get("mesh") as GeometryInstance3D
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if should_hide else int(shadow_data.get("original_cast_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_ON))

func _make_hidden_material(mesh_instance: MeshInstance3D, surface_index: int) -> Material:
	var source: Material = mesh_instance.get_active_material(surface_index)
	var hidden: BaseMaterial3D = (source.duplicate() as BaseMaterial3D) if source is BaseMaterial3D else StandardMaterial3D.new()
	hidden.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hidden.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	hidden.metallic = 0.0
	hidden.roughness = 1.0
	hidden.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hidden.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return hidden
