extends Node3D
class_name InstrumentPanelMount

## Lightweight per-aircraft socket for the shared live instrument display.
## Aircraft keep their authored transform and model-surface configuration here;
## the expensive UI, render targets, radar, and target camera live in the pool.

@export var aircraft_path: NodePath = NodePath("..")
@export var panel_size: Vector2 = Vector2(1.0, 0.8)
@export var viewport_resolution: Vector2i = Vector2i(1000, 480)
@export var auto_build_default_modules: bool = true
@export var update_only_when_viewed: bool = true
@export var module_layout: Array[Dictionary] = []
@export var show_interaction_cursor: bool = true
@export var interaction_cursor_radius_px: float = 4.0
@export var interaction_cursor_color: Color = Color(0.75, 1.0, 0.85, 0.95)
@export var interaction_cursor_outline_color: Color = Color(0.0, 0.0, 0.0, 0.8)

@export var render_to_model_surface: bool = false
@export var model_panel_mesh_path: NodePath
@export var model_panel_mesh_name: String = "instrument panel"
@export var model_panel_material_names: PackedStringArray = PackedStringArray(["Instrument panel material"])
@export var hide_panel_quad_when_rendering_to_model: bool = true
@export var auto_fit_model_panel_local_rect: bool = true
@export var model_panel_local_rect: Rect2 = Rect2(-0.5, -0.5, 1.0, 1.0)
@export var model_panel_use_mesh_uv: bool = false
@export var model_panel_flip_x: bool = false

@export var camera_target_path: NodePath = NodePath("../CameraTarget")
@export var assumed_target_width_m: float = 10.0
@export_range(1.0, 10.0, 0.05) var min_fov_deg: float = 1.0
@export var max_fov_deg: float = 60.0
@export var fov_lerp_speed: float = 8.0
@export var idle_fov_deg: float = 30.0
@export var target_camera_slew_deg_s: float = 120.0
@export var target_camera_zoom_lerp_speed: float = 6.0
@export var zoom_distance: float = 50.0
@export var obstacle_margin: float = 1.0
@export var scan_spacing_px: float = 3.0
@export var scan_thickness_px: float = 1.0
@export var scan_strength: float = 0.35
@export var grayscale_strength: float = 1.0
@export var destroyed_target_hold_s: float = 10.0

var _view_updates_active: bool = false
var _nv_mode_enabled: bool = false
var _pool_ref: WeakRef = null


func _ready() -> void:
	add_to_group("instrument_panel")
	var pool := get_node_or_null("/root/InstrumentPanelPool")
	_pool_ref = weakref(pool) if pool != null else null


func _exit_tree() -> void:
	var pool := _get_pool()
	if pool != null and pool.has_method("release"):
		pool.call("release", self)
	_view_updates_active = false


func get_aircraft() -> Aircraft:
	if aircraft_path != NodePath():
		var explicit_aircraft := get_node_or_null(aircraft_path) as Aircraft
		if explicit_aircraft != null:
			return explicit_aircraft
	var parent_aircraft := get_parent() as Aircraft
	if parent_aircraft != null:
		return parent_aircraft
	return null


func resolve_model_panel_mesh() -> MeshInstance3D:
	if model_panel_mesh_path != NodePath():
		var explicit_mesh := get_node_or_null(model_panel_mesh_path) as MeshInstance3D
		if explicit_mesh != null:
			return explicit_mesh
	var aircraft := get_aircraft()
	if aircraft != null:
		return aircraft.find_child(model_panel_mesh_name, true, false) as MeshInstance3D
	return null


func get_effective_module_layout() -> Array[Dictionary]:
	if not module_layout.is_empty():
		return module_layout.duplicate(true)
	var pool := _get_pool()
	if pool != null and pool.has_method("standard_module_layout"):
		return pool.call("standard_module_layout") as Array[Dictionary]
	return []


func set_view_updates_active(active: bool) -> void:
	if _view_updates_active == active and (not active or get_live_panel() != null):
		return
	_view_updates_active = active
	var pool := _get_pool()
	if pool == null:
		return
	if active and pool.has_method("acquire"):
		var live_panel := pool.call("acquire", self) as Node
		if live_panel != null and live_panel.has_method("set_nv_mode"):
			live_panel.call("set_nv_mode", _nv_mode_enabled)
	elif not active and pool.has_method("release"):
		pool.call("release", self)


func get_live_panel() -> Node3D:
	var pool := _get_pool()
	if pool != null and pool.has_method("get_panel_for_mount"):
		return pool.call("get_panel_for_mount", self) as Node3D
	return null


func set_nv_mode(enabled: bool) -> void:
	_nv_mode_enabled = enabled
	var live_panel := get_live_panel()
	if live_panel != null and live_panel.has_method("set_nv_mode"):
		live_panel.call("set_nv_mode", enabled)


func start_missile_camera_tracking(missile: Node3D) -> void:
	if not _view_updates_active:
		return
	var live_panel := get_live_panel()
	if live_panel != null and live_panel.has_method("start_missile_camera_tracking"):
		live_panel.call("start_missile_camera_tracking", missile)


func interact_from_camera(camera: Camera3D, max_distance_m: float = 2.5) -> bool:
	var live_panel := get_live_panel()
	return live_panel != null \
		and live_panel.has_method("interact_from_camera") \
		and bool(live_panel.call("interact_from_camera", camera, max_distance_m))


func interact_from_ray(ray_origin: Vector3, ray_direction: Vector3, max_distance_m: float = 2.5) -> bool:
	var live_panel := get_live_panel()
	return live_panel != null \
		and live_panel.has_method("interact_from_ray") \
		and bool(live_panel.call("interact_from_ray", ray_origin, ray_direction, max_distance_m))


func is_target_camera_focusing_node(node: Node3D) -> bool:
	var live_panel := get_live_panel()
	return live_panel != null \
		and live_panel.has_method("is_target_camera_focusing_node") \
		and bool(live_panel.call("is_target_camera_focusing_node", node))


func is_pooled_instrument_panel_mount() -> bool:
	return true


func _get_pool() -> Node:
	if _pool_ref != null:
		var cached := _pool_ref.get_ref() as Node
		if cached != null and is_instance_valid(cached):
			return cached
	if not is_inside_tree():
		return null
	var pool := get_node_or_null("/root/InstrumentPanelPool")
	_pool_ref = weakref(pool) if pool != null else null
	return pool
