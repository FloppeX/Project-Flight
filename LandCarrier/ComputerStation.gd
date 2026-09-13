class_name ComputerStation
extends Node3D

const TACTICAL_SCREEN_DISPLAY := preload("res://UI/TacticalScreenDisplay.gd")
const TACTICAL_SCREEN_DISPLAY_NAME := "TacticalScreenDisplay"

## Reusable carrier-room tactical computer. The Commander owns player input and
## camera movement; this scene supplies the authored model and interaction/view
## anchors so additional stations can be placed without duplicating logic.

@export var interaction_distance_m: float = 2.75
@export var screen_interaction_half_size_m: Vector2 = Vector2(0.32, 0.17)
@export var seated_camera_fov: float = 64.0
@export var screen_mesh_name: StringName = &"computer console screen"
@export_range(1.0, 2.0, 0.01) var screen_focus_margin: float = 1.18
@export_range(5.0, 90.0, 0.5) var screen_focus_min_fov: float = 18.0
@export_range(5.0, 90.0, 0.5) var screen_focus_max_fov: float = 42.0

@onready var model: Node3D = $Model
@onready var interaction_target: Marker3D = $InteractionTarget
@onready var camera_anchor: Marker3D = $CameraAnchor
@onready var use_prompt: Label3D = $InteractionTarget/UsePrompt

var _in_use: bool = false
var _screen_mesh: MeshInstance3D = null
var _screen_anchor_source: String = "authored_fallback"
var _tactical_screen_display: Node = null


func _ready() -> void:
	add_to_group("computer_station")
	_anchor_interaction_to_imported_screen()
	_attach_tactical_screen_display()
	set_interaction_available(false)


func _anchor_interaction_to_imported_screen() -> void:
	if model == null or interaction_target == null:
		return
	_screen_mesh = model.find_child(String(screen_mesh_name), true, false) as MeshInstance3D
	if _screen_mesh == null or _screen_mesh.mesh == null:
		return
	if _screen_mesh.mesh.get_surface_count() <= 0:
		return

	# The screen is an authored four-corner plane. Deriving the target from its
	# vertices keeps the prompt and gaze rectangle attached if the model moves,
	# rotates, scales, or is re-exported with adjusted screen geometry.
	var arrays: Array = _screen_mesh.mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_VERTEX:
		return
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.size() < 4:
		return

	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	var center_mesh := Vector3.ZERO
	for vertex in vertices:
		min_x = minf(min_x, vertex.x)
		max_x = maxf(max_x, vertex.x)
		min_y = minf(min_y, vertex.y)
		max_y = maxf(max_y, vertex.y)
		center_mesh += vertex
	center_mesh /= float(vertices.size())

	var edge_epsilon := 0.0001
	var left_center := Vector3.ZERO
	var right_center := Vector3.ZERO
	var bottom_center := Vector3.ZERO
	var top_center := Vector3.ZERO
	var left_count := 0
	var right_count := 0
	var bottom_count := 0
	var top_count := 0
	for vertex in vertices:
		if absf(vertex.x - min_x) <= edge_epsilon:
			left_center += vertex
			left_count += 1
		if absf(vertex.x - max_x) <= edge_epsilon:
			right_center += vertex
			right_count += 1
		if absf(vertex.y - min_y) <= edge_epsilon:
			bottom_center += vertex
			bottom_count += 1
		if absf(vertex.y - max_y) <= edge_epsilon:
			top_center += vertex
			top_count += 1
	if left_count == 0 or right_count == 0 or bottom_count == 0 or top_count == 0:
		return
	left_center /= float(left_count)
	right_center /= float(right_count)
	bottom_center /= float(bottom_count)
	top_center /= float(top_count)

	var surface_to_station := global_transform.affine_inverse() * _screen_mesh.global_transform
	var center_station := surface_to_station * center_mesh
	var horizontal := (surface_to_station.basis * (right_center - left_center)).normalized()
	var vertical := surface_to_station.basis * (top_center - bottom_center)
	vertical = (vertical - horizontal * horizontal.dot(vertical)).normalized()
	if horizontal.is_zero_approx() or vertical.is_zero_approx():
		return
	var normal := horizontal.cross(vertical).normalized()
	if normal.is_zero_approx():
		return

	interaction_target.transform = Transform3D(Basis(horizontal, vertical, normal), center_station)
	var screen_width := (surface_to_station * right_center).distance_to(surface_to_station * left_center)
	var screen_height := (surface_to_station * top_center).distance_to(surface_to_station * bottom_center)
	screen_interaction_half_size_m = Vector2(screen_width, screen_height) * 0.48
	_screen_anchor_source = String(screen_mesh_name)


func _attach_tactical_screen_display() -> void:
	if _screen_mesh == null or _screen_mesh.mesh == null or get_tree() == null:
		return
	var tree_root := get_tree().root
	var display_parent: Node = get_tree().current_scene
	if display_parent == null:
		display_parent = tree_root
	_tactical_screen_display = get_tree().get_first_node_in_group("tactical_screen_display")
	if _tactical_screen_display == null:
		_tactical_screen_display = display_parent.get_node_or_null(
			TACTICAL_SCREEN_DISPLAY_NAME
		)
	if _tactical_screen_display == null:
		_tactical_screen_display = TACTICAL_SCREEN_DISPLAY.new()
		_tactical_screen_display.name = TACTICAL_SCREEN_DISPLAY_NAME
		display_parent.add_child(_tactical_screen_display)
	if not _tactical_screen_display.has_method("get_screen_material"):
		return
	var screen_aabb := _screen_mesh.mesh.get_aabb()
	var mesh_min := Vector2(screen_aabb.position.x, screen_aabb.position.y)
	var mesh_max := Vector2(screen_aabb.end.x, screen_aabb.end.y)
	_screen_mesh.material_override = _tactical_screen_display.call(
		"get_screen_material",
		mesh_min,
		mesh_max
	) as Material


func get_interaction_score(camera: Camera3D) -> float:
	if _in_use or camera == null or interaction_target == null:
		return -INF
	var ray_origin := camera.global_position
	var ray_direction := (-camera.global_basis.z).normalized()
	var screen_origin := interaction_target.global_position
	var screen_normal := interaction_target.global_basis.z.normalized()
	var ray_plane_dot := screen_normal.dot(ray_direction)
	if absf(ray_plane_dot) <= 0.0001:
		return -INF
	var distance := screen_normal.dot(screen_origin - ray_origin) / ray_plane_dot
	if distance <= 0.001 or distance > interaction_distance_m:
		return -INF
	var screen_hit := interaction_target.to_local(ray_origin + ray_direction * distance)
	if absf(screen_hit.x) > screen_interaction_half_size_m.x \
			or absf(screen_hit.y) > screen_interaction_half_size_m.y:
		return -INF
	# The gaze ray can cross more than one station screen; the closest hit wins.
	return -distance


func get_camera_anchor_transform() -> Transform3D:
	return camera_anchor.global_transform if camera_anchor != null else global_transform


func get_seated_camera_fov() -> float:
	return seated_camera_fov


func get_screen_focus_camera_transform() -> Transform3D:
	if camera_anchor == null or interaction_target == null:
		return get_camera_anchor_transform()
	var camera_transform := camera_anchor.global_transform
	var screen_direction := interaction_target.global_position - camera_transform.origin
	if screen_direction.is_zero_approx():
		return camera_transform
	var station_up := global_transform.basis.y.normalized()
	return camera_transform.looking_at(interaction_target.global_position, station_up)


func get_screen_focus_fov(viewport_aspect: float = 16.0 / 9.0) -> float:
	if camera_anchor == null or interaction_target == null:
		return seated_camera_fov
	var screen_distance := camera_anchor.global_position.distance_to(
		interaction_target.global_position
	)
	if screen_distance <= 0.001:
		return screen_focus_min_fov
	var half_width_world := (
		screen_interaction_half_size_m.x * interaction_target.global_basis.x.length()
	)
	var half_height_world := (
		screen_interaction_half_size_m.y * interaction_target.global_basis.y.length()
	)
	var safe_aspect := maxf(viewport_aspect, 0.1)
	var required_vertical_half_extent := maxf(
		half_height_world,
		half_width_world / safe_aspect
	) * screen_focus_margin
	var fitted_fov := rad_to_deg(
		2.0 * atan(required_vertical_half_extent / screen_distance)
	)
	var minimum_fov := minf(screen_focus_min_fov, screen_focus_max_fov)
	var maximum_fov := maxf(screen_focus_min_fov, screen_focus_max_fov)
	return clampf(fitted_fov, minimum_fov, maximum_fov)


func set_interaction_available(available: bool) -> void:
	if use_prompt != null:
		use_prompt.visible = available and not _in_use


func set_in_use(in_use: bool) -> void:
	_in_use = in_use
	set_interaction_available(false)


func is_in_use() -> bool:
	return _in_use


func get_debug_snapshot() -> Dictionary:
	return {
		"in_use": _in_use,
		"interaction_distance_m": interaction_distance_m,
		"screen_interaction_half_size_m": screen_interaction_half_size_m,
		"screen_mesh_name": String(screen_mesh_name),
		"screen_mesh_found": is_instance_valid(_screen_mesh),
		"screen_anchor_source": _screen_anchor_source,
		"screen_focus_fov_16_9": get_screen_focus_fov(),
		"has_tactical_screen_display": is_instance_valid(_tactical_screen_display),
		"has_tactical_screen_material": _screen_mesh != null \
			and _screen_mesh.material_override is ShaderMaterial,
		"has_model": get_node_or_null("Model") != null,
		"has_interaction_target": interaction_target != null,
		"has_camera_anchor": camera_anchor != null,
	}
