extends Node3D
class_name BridgeHologram

@export var table_size_m: float = 2.0
@export var table_center_local: Vector3 = Vector3.ZERO
@export var coverage_radius_m: float = 5000.0
@export var terrain_grid_resolution: int = 105
@export var terrain_height_span_m: float = 700.0
@export var terrain_display_height_m: float = 0.46
@export var terrain_dot_scale_m: float = 0.0022
@export var terrain_dot_base_height_m: float = 0.016
@export var terrain_wire_height_offset_m: float = 0.008
@export var terrain_low_color: Color = Color(0.0, 0.1, 0.025, 0.2)
@export var terrain_high_color: Color = Color(0.35, 1.0, 0.18, 0.34)
@export var terrain_wire_thickness_m: float = 0.004
@export var terrain_wire_low_color: Color = Color(0.0, 0.28, 0.06, 0.92)
@export var terrain_wire_high_color: Color = Color(0.45, 1.0, 0.12, 1.0)
@export var contact_altitude_span_m: float = 1200.0
@export var contact_display_height_m: float = 0.8
@export var contact_dot_scale_m: float = 0.032
@export var contact_wire_thickness_m: float = 0.03
@export var ground_contact_scale_m: float = 0.026
@export var ground_contact_hover_m: float = 0.004
@export var carrier_plate_length_m: float = 0.09
@export var carrier_plate_width_m: float = 0.026
@export var carrier_plate_height_m: float = 0.012
@export var carrier_plate_hover_m: float = 0.001
@export var carrier_wire_thickness_m: float = 0.0018
@export var max_contacts: int = 48
@export var terrain_retry_interval_s: float = 0.5
@export var terrain_refresh_interval_s: float = 1.0
@export var contact_refresh_interval_s: float = 1.0
@export var terrain_refresh_distance_m: float = 75.0
@export var terrain_refresh_heading_deg: float = 4.0
@export var waypoint_box_size_m: float = 0.018
@export var waypoint_line_thickness_m: float = 0.005
@export var waypoint_color: Color = Color(1.0, 0.95, 0.8, 0.9)
@export var waypoint_refresh_interval_s: float = 1.0
@export var active_camera_update_distance_m: float = 35.0
@onready var terrain_dots: MultiMeshInstance3D = $TerrainDots
@onready var terrain_lines: MultiMeshInstance3D = $TerrainLines
@onready var contact_dots: MultiMeshInstance3D = $ContactDots
@onready var ground_dots: MultiMeshInstance3D = $GroundDots
@onready var carrier_plate: MeshInstance3D = $CarrierPlate
@onready var waypoint_dots: MultiMeshInstance3D = $WaypointDots
@onready var waypoint_lines: MultiMeshInstance3D = $WaypointLines

var _carrier: Node3D = null
var _terrain_provider: Node3D = null
var _terrain_built: bool = false
var _terrain_retry_timer: float = 0.0
var _terrain_refresh_timer: float = 0.0
var _contact_refresh_timer: float = 0.0
var _last_terrain_center_world: Vector3 = Vector3.INF
var _last_terrain_heading_yaw: float = 0.0
var _was_recently_observed: bool = false
var _waypoint_refresh_timer: float = 0.0

# Incremental terrain rebuild state
var _rebuild_in_progress: bool = false
var _rebuild_row: int = 0
var _rebuild_resolution: int = 0
@export var terrain_rows_per_frame: int = 15
var _rebuild_sampled_heights: PackedFloat32Array
var _rebuild_local_points: Array[Vector3] = []
var _rebuild_point_gradient: Array[float] = []
var _rebuild_valid_points: Array[bool] = []
var _rebuild_valid_count: int = 0
var _rebuild_min_height: float = INF
var _rebuild_max_height: float = -INF
var _rebuild_base_height: float = 0.0
var _rebuild_carrier_surface_height: float = 0.0

func _ready() -> void:
	physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_INHERIT
	_carrier = get_tree().get_first_node_in_group("carrier") as Node3D
	_terrain_provider = get_tree().get_first_node_in_group("terrain_provider") as Node3D
	_setup_visuals()
	call_deferred("_try_build_terrain")
	_update_contact_dots()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_carrier):
		_carrier = get_tree().get_first_node_in_group("carrier") as Node3D
		if _carrier == null:
			return

	var is_observed := _is_active_camera_near_hologram()
	if not is_observed:
		_was_recently_observed = false
		return
	if not _was_recently_observed:
		_was_recently_observed = true
		_terrain_refresh_timer = maxf(terrain_refresh_interval_s, 0.1)
		_contact_refresh_timer = maxf(contact_refresh_interval_s, 0.1)

	# Continue incremental terrain rebuild if in progress
	if _rebuild_in_progress:
		_rebuild_terrain_step()
		return

	_terrain_refresh_timer += delta
	if not _terrain_built:
		_terrain_retry_timer += delta
		if _terrain_retry_timer >= maxf(terrain_retry_interval_s, 0.1):
			_terrain_retry_timer = 0.0
			_try_build_terrain()
	elif _terrain_refresh_timer >= maxf(terrain_refresh_interval_s, 0.1) and _should_refresh_terrain():
		_terrain_refresh_timer = 0.0
		_try_build_terrain()

	# Contacts and waypoints are updated together with the terrain rebuild
	# (see _rebuild_terrain_step) so they stay in sync with the wireframe.

func _setup_visuals() -> void:
	terrain_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var terrain_multimesh := MultiMesh.new()
	terrain_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	terrain_multimesh.use_colors = true
	terrain_dots.multimesh = terrain_multimesh
	terrain_dots.visible = false
	terrain_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain_lines.material_override = _make_hologram_shader_material(2.3, 0.14, 3.8)
	var line_mesh := CylinderMesh.new()
	line_mesh.top_radius = 0.5
	line_mesh.bottom_radius = 0.5
	line_mesh.height = 1.0
	var line_multimesh := MultiMesh.new()
	line_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	line_multimesh.use_colors = true
	line_multimesh.mesh = line_mesh
	terrain_lines.multimesh = line_multimesh

	var contact_mesh := _create_contact_arrowhead_mesh()
	contact_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	contact_dots.material_override = _make_hologram_shader_material(2.2, 0.34, 6.5)

	var contact_multimesh := MultiMesh.new()
	contact_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	contact_multimesh.use_colors = true
	contact_multimesh.mesh = contact_mesh
	contact_dots.multimesh = contact_multimesh
	ground_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground_dots.material_override = _make_hologram_shader_material(2.2, 0.34, 6.5)
	var ground_multimesh := MultiMesh.new()
	ground_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	ground_multimesh.use_colors = true
	ground_multimesh.mesh = _create_ground_contact_square_mesh()
	ground_dots.multimesh = ground_multimesh

	_setup_carrier_plate()
	_setup_waypoint_visuals()

func _try_build_terrain() -> void:
	if _rebuild_in_progress:
		return
	if not is_instance_valid(_carrier):
		return
	if not is_instance_valid(_terrain_provider):
		_terrain_provider = get_tree().get_first_node_in_group("terrain_provider") as Node3D
	var terrain_multimesh := terrain_dots.multimesh
	if terrain_multimesh == null:
		return

	# Start incremental rebuild
	_rebuild_resolution = maxi(terrain_grid_resolution, 3)
	if _rebuild_resolution % 2 == 0:
		_rebuild_resolution += 1
	var total := _rebuild_resolution * _rebuild_resolution
	_rebuild_sampled_heights.resize(total)
	_rebuild_local_points.resize(total)
	_rebuild_point_gradient.resize(total)
	_rebuild_valid_points.resize(total)
	_rebuild_valid_count = 0
	_rebuild_min_height = INF
	_rebuild_max_height = -INF
	_rebuild_base_height = _sample_reference_terrain_height()
	_rebuild_carrier_surface_height = _sample_terrain_height_at_local_offset(0.0, 0.0)
	_rebuild_row = 0
	_rebuild_in_progress = true

func _rebuild_terrain_step() -> void:
	var resolution := _rebuild_resolution
	var half_size_world := coverage_radius_m
	var end_row := mini(_rebuild_row + terrain_rows_per_frame, resolution)

	# Phase 1: sample heights for a batch of rows
	for z_idx in range(_rebuild_row, end_row):
		var z_t := 0.0 if resolution == 1 else float(z_idx) / float(resolution - 1)
		var local_z_world := lerpf(-half_size_world, half_size_world, z_t)
		for x_idx in range(resolution):
			var x_t := 0.0 if resolution == 1 else float(x_idx) / float(resolution - 1)
			var local_x_world := lerpf(-half_size_world, half_size_world, x_t)
			var terrain_y := _sample_terrain_height_at_local_offset(local_x_world, local_z_world)
			var idx := z_idx * resolution + x_idx
			_rebuild_sampled_heights[idx] = terrain_y
			if not is_nan(terrain_y) and not is_nan(_rebuild_base_height):
				_rebuild_min_height = minf(_rebuild_min_height, terrain_y)
				_rebuild_max_height = maxf(_rebuild_max_height, terrain_y)
	_rebuild_row = end_row

	if _rebuild_row < resolution:
		return  # More rows to sample next frame

	# Phase 2: all heights sampled — compute local points and finalize
	_rebuild_in_progress = false
	var base_height := _rebuild_base_height
	if not is_finite(_rebuild_min_height) or not is_finite(_rebuild_max_height):
		_rebuild_min_height = base_height
		_rebuild_max_height = base_height
	var local_height_span := maxf(_rebuild_max_height - _rebuild_min_height, 1.0)
	var table_half_size := table_size_m * 0.5
	var valid_point_count := 0

	for z_idx in range(resolution):
		var z_t := 0.0 if resolution == 1 else float(z_idx) / float(resolution - 1)
		var local_z_world := lerpf(-half_size_world, half_size_world, z_t)
		for x_idx in range(resolution):
			var x_t := 0.0 if resolution == 1 else float(x_idx) / float(resolution - 1)
			var local_x_world := lerpf(-half_size_world, half_size_world, x_t)
			var idx := z_idx * resolution + x_idx
			var terrain_y: float = _rebuild_sampled_heights[idx]
			var local_pos := table_center_local + Vector3(
				(local_x_world / maxf(half_size_world, 1.0)) * table_half_size,
				terrain_dot_base_height_m,
				(local_z_world / maxf(half_size_world, 1.0)) * table_half_size
			)
			var is_valid_point := false
			var gradient_t := 0.0
			if not is_nan(terrain_y) and not is_nan(base_height):
				is_valid_point = true
				valid_point_count += 1
				var rel_height := clampf((terrain_y - base_height) / maxf(terrain_height_span_m, 1.0), -1.0, 1.0)
				local_pos.y += rel_height * terrain_display_height_m
				gradient_t = clampf((terrain_y - _rebuild_min_height) / local_height_span, 0.0, 1.0)
			else:
				local_pos.y -= 0.03
			_rebuild_local_points[idx] = local_pos
			_rebuild_point_gradient[idx] = gradient_t
			_rebuild_valid_points[idx] = is_valid_point

	_rebuild_terrain_wireframe(_rebuild_local_points, _rebuild_point_gradient, _rebuild_valid_points, resolution)
	terrain_dots.visible = false
	terrain_lines.visible = valid_point_count > 0
	_update_carrier_plate_height(base_height, _rebuild_carrier_surface_height)
	_update_contact_dots()
	_update_waypoint_display()
	_terrain_built = valid_point_count > 0
	if _terrain_built and is_instance_valid(_carrier):
		_last_terrain_center_world = _carrier.global_position
		_last_terrain_heading_yaw = _get_carrier_heading_yaw()

func _update_contact_dots() -> void:
	if not is_instance_valid(_carrier):
		return

	var air_multimesh := contact_dots.multimesh
	var ground_multimesh := ground_dots.multimesh
	if air_multimesh == null or ground_multimesh == null:
		return

	var air_contacts: Array[Dictionary] = []
	var ground_contacts: Array[Dictionary] = []
	_collect_contacts_for_group(
		"friendlies",
		Color(0.18, 0.72, 1.0, 1.0),
		Color(0.18, 0.72, 1.0, 1.0),
		air_contacts,
		ground_contacts
	)
	_collect_contacts_for_group(
		"enemies",
		Color(1.0, 0.22, 0.22, 1.0),
		Color(1.0, 0.22, 0.22, 1.0),
		air_contacts,
		ground_contacts
	)
	air_contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance_sq"] < b["distance_sq"])
	ground_contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance_sq"] < b["distance_sq"])
	var base_height := _sample_reference_terrain_height()

	var air_visible_count := mini(air_contacts.size(), max_contacts)
	air_multimesh.instance_count = max_contacts
	air_multimesh.visible_instance_count = air_visible_count

	for i in range(air_visible_count):
		var entry := air_contacts[i]
		var rel_local: Vector3 = entry["local_position"]
		var hologram_pos := table_center_local + Vector3(
			(rel_local.x / maxf(coverage_radius_m, 1.0)) * (table_size_m * 0.5),
			0.08 + clampf(rel_local.y / maxf(contact_altitude_span_m, 1.0), -0.1, 1.0) * contact_display_height_m,
			(rel_local.z / maxf(coverage_radius_m, 1.0)) * (table_size_m * 0.5)
		)
		var orientation_basis: Basis = entry["orientation_basis"]
		var marker_basis := orientation_basis.orthonormalized().scaled(Vector3.ONE * contact_dot_scale_m)
		air_multimesh.set_instance_transform(i, Transform3D(marker_basis, hologram_pos))
		air_multimesh.set_instance_color(i, entry["color"])

	var ground_visible_count := mini(ground_contacts.size(), max_contacts)
	ground_multimesh.instance_count = max_contacts
	ground_multimesh.visible_instance_count = ground_visible_count
	for i in range(ground_visible_count):
		var entry := ground_contacts[i]
		var rel_local: Vector3 = entry["local_position"]
		var terrain_y := _sample_terrain_height_at_local_offset(rel_local.x, rel_local.z)
		var surface_y := _world_height_to_hologram_surface_y(terrain_y, base_height)
		var marker_half_height := 0.1 * ground_contact_scale_m
		var marker_y := surface_y + terrain_wire_height_offset_m + marker_half_height + ground_contact_hover_m
		if is_nan(terrain_y) or is_nan(base_height):
			marker_y = 0.03
		var hologram_pos := table_center_local + Vector3(
			(rel_local.x / maxf(coverage_radius_m, 1.0)) * (table_size_m * 0.5),
			marker_y,
			(rel_local.z / maxf(coverage_radius_m, 1.0)) * (table_size_m * 0.5)
		)
		var square_basis := Basis().scaled(Vector3.ONE * ground_contact_scale_m)
		ground_multimesh.set_instance_transform(i, Transform3D(square_basis, hologram_pos))
		ground_multimesh.set_instance_color(i, entry["color"])

func _collect_contacts_for_group(group_name: String, air_color: Color, ground_color: Color, air_contacts: Array[Dictionary], ground_contacts: Array[Dictionary]) -> void:
	for node in get_tree().get_nodes_in_group(group_name):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		if node == _carrier or node == get_parent():
			continue
		var node_3d := node as Node3D
		var rel_local := _carrier_world_to_planar_local(node_3d.global_position)
		if absf(rel_local.x) > coverage_radius_m or absf(rel_local.z) > coverage_radius_m:
			continue
		var orientation_basis := (_carrier.global_basis.inverse() * node_3d.global_basis).orthonormalized()
		var entry := {
			"local_position": rel_local,
			"orientation_basis": orientation_basis,
			"distance_sq": rel_local.x * rel_local.x + rel_local.z * rel_local.z,
			"color": air_color,
		}
		if _is_ground_contact(node_3d):
			entry["color"] = ground_color
			ground_contacts.append(entry)
		else:
			air_contacts.append(entry)

func _sample_reference_terrain_height() -> float:
	var center_world := _carrier.global_position if is_instance_valid(_carrier) else global_position
	return _sample_terrain_world_height(center_world)

func _sample_terrain_height_at_local_offset(local_x_world: float, local_z_world: float) -> float:
	var world_pos := _carrier_planar_local_to_world(local_x_world, local_z_world)
	return _sample_terrain_world_height(world_pos)

func _sample_terrain_world_height(world_pos: Vector3) -> float:
	var baked_height := TerrainNavGrid.sample_height(world_pos.x, world_pos.z)
	if baked_height > TerrainNavGrid.IMPASSABLE * 0.5:
		return baked_height

	if is_instance_valid(_terrain_provider) and _terrain_provider.has_method("get_height"):
		var query := Vector3(world_pos.x, _terrain_provider.global_position.y, world_pos.z)
		return float(_terrain_provider.call("get_height", query))

	return NAN

func _rebuild_terrain_wireframe(local_points: Array[Vector3], point_gradient: Array[float], valid_points: Array[bool], resolution: int) -> void:
	if terrain_lines == null:
		return

	var line_multimesh := terrain_lines.multimesh
	if line_multimesh == null:
		return

	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []

	for z_idx in range(resolution):
		for x_idx in range(resolution):
			var idx := z_idx * resolution + x_idx
			if not valid_points[idx]:
				continue

			if x_idx + 1 < resolution:
				var right_idx := idx + 1
				if valid_points[right_idx]:
					_append_line_segment(
						transforms,
						colors,
						local_points[idx],
						local_points[right_idx],
						_make_wire_color(point_gradient[idx], point_gradient[right_idx])
					)

			if z_idx + 1 < resolution:
				var forward_idx := idx + resolution
				if valid_points[forward_idx]:
					_append_line_segment(
						transforms,
						colors,
						local_points[idx],
						local_points[forward_idx],
						_make_wire_color(point_gradient[idx], point_gradient[forward_idx])
					)

	line_multimesh.instance_count = transforms.size()
	line_multimesh.visible_instance_count = transforms.size()
	for i in range(transforms.size()):
		line_multimesh.set_instance_transform(i, transforms[i])
		line_multimesh.set_instance_color(i, colors[i])

func _append_line_segment(transforms: Array[Transform3D], colors: Array[Color], from_point: Vector3, to_point: Vector3, color: Color) -> void:
	var offset := Vector3.UP * terrain_wire_height_offset_m
	var from_adjusted := from_point + offset
	var to_adjusted := to_point + offset
	var delta := to_adjusted - from_adjusted
	var length := delta.length()
	if length <= 0.0001:
		return

	var y_axis := delta / length
	var x_axis := Vector3.UP.cross(y_axis)
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3.RIGHT.cross(y_axis)
	x_axis = x_axis.normalized()
	var z_axis := y_axis.cross(x_axis).normalized()
	var basis := Basis(
		x_axis * terrain_wire_thickness_m,
		y_axis * length,
		z_axis * terrain_wire_thickness_m
	)
	transforms.append(Transform3D(basis, (from_adjusted + to_adjusted) * 0.5))
	colors.append(color)

func _make_wire_color(a_gradient: float, b_gradient: float) -> Color:
	return terrain_wire_low_color.lerp(terrain_wire_high_color, clampf((a_gradient + b_gradient) * 0.5, 0.0, 1.0))

func _setup_carrier_plate() -> void:
	if carrier_plate == null:
		return

	var plate_mesh := _create_wire_box_mesh(
		Vector3(carrier_plate_width_m, carrier_plate_height_m, carrier_plate_length_m),
		carrier_wire_thickness_m
	)
	carrier_plate.mesh = plate_mesh
	carrier_plate.position = table_center_local
	_update_carrier_plate_height(NAN, NAN)
	carrier_plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var plate_material := _make_hologram_shader_material(1.6, 0.18, 4.2)
	plate_material.set_shader_parameter("tint_color", Color(0.2, 0.78, 1.0, 1.0))
	carrier_plate.material_override = plate_material

func _update_carrier_plate_height(base_height: float, carrier_surface_height: float) -> void:
	if carrier_plate == null:
		return
	var center_surface_y := _world_height_to_hologram_surface_y(carrier_surface_height, base_height)
	carrier_plate.position.y = center_surface_y + terrain_wire_height_offset_m + carrier_plate_height_m * 0.5 + carrier_plate_hover_m

func _world_height_to_hologram_surface_y(world_height: float, reference_height: float) -> float:
	var base_surface_y := 0.02
	if is_nan(world_height) or is_nan(reference_height):
		return base_surface_y
	var rel_height := clampf((world_height - reference_height) / maxf(terrain_height_span_m, 1.0), -1.0, 1.0)
	return base_surface_y + rel_height * terrain_display_height_m

func _should_refresh_terrain() -> bool:
	if not is_instance_valid(_carrier):
		return false
	if _last_terrain_center_world == Vector3.INF:
		return true
	var planar_delta := Vector2(
		_carrier.global_position.x - _last_terrain_center_world.x,
		_carrier.global_position.z - _last_terrain_center_world.z
	).length()
	if planar_delta >= maxf(terrain_refresh_distance_m, 1.0):
		return true
	var heading_delta := absf(wrapf(_get_carrier_heading_yaw() - _last_terrain_heading_yaw, -PI, PI))
	return heading_delta >= deg_to_rad(maxf(terrain_refresh_heading_deg, 0.1))

func _get_carrier_heading_yaw() -> float:
	if not is_instance_valid(_carrier):
		return 0.0
	var forward := _get_carrier_planar_basis().z
	return atan2(forward.x, forward.z)

func _get_carrier_planar_basis() -> Basis:
	if not is_instance_valid(_carrier):
		return Basis.IDENTITY
	var forward := Vector3(_carrier.global_basis.z.x, 0.0, _carrier.global_basis.z.z)
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := Vector3.UP.cross(forward).normalized()
	return Basis(right, Vector3.UP, forward)

func _carrier_planar_local_to_world(local_x: float, local_z: float) -> Vector3:
	if not is_instance_valid(_carrier):
		return global_position + Vector3(local_x, 0.0, local_z)
	var planar_basis := _get_carrier_planar_basis()
	return _carrier.global_position + planar_basis.x * local_x + planar_basis.z * local_z

func _carrier_world_to_planar_local(world_pos: Vector3) -> Vector3:
	if not is_instance_valid(_carrier):
		return world_pos - global_position
	var planar_basis := _get_carrier_planar_basis()
	var delta := world_pos - _carrier.global_position
	return Vector3(
		delta.dot(planar_basis.x),
		world_pos.y - _carrier.global_position.y,
		delta.dot(planar_basis.z)
	)

func _is_active_camera_near_hologram() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return true
	var active_camera := viewport.get_camera_3d()
	if active_camera == null or not is_instance_valid(active_camera):
		return true
	var max_distance := maxf(active_camera_update_distance_m, 1.0)
	return active_camera.global_position.distance_squared_to(global_position) <= max_distance * max_distance

func _make_hologram_shader_material(emission_strength: float, flicker_strength: float, flicker_speed: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float emission_strength = 1.0;
uniform vec4 tint_color : source_color = vec4(1.0);

void fragment() {
	vec4 base_color = COLOR * tint_color;
	float intensity = base_color.a;
	ALBEDO = base_color.rgb * intensity;
	EMISSION = base_color.rgb * emission_strength * intensity;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("emission_strength", emission_strength)
	material.set_shader_parameter("tint_color", Color(1.0, 1.0, 1.0, 1.0))
	return material

func _create_contact_arrowhead_mesh() -> ArrayMesh:
	var points := [
		Vector3(0.0, 0.0, 0.65),
		Vector3(-0.34, 0.0, -0.14),
		Vector3(0.34, 0.0, -0.14),
		Vector3(0.0, 0.22, -0.04),
		Vector3(0.0, -0.22, -0.04),
		Vector3(0.0, 0.0, -0.38),
	]
	var edges := PackedInt32Array([
		0, 1,
		0, 2,
		0, 3,
		0, 4,
		1, 3,
		3, 2,
		2, 4,
		4, 1,
		1, 5,
		2, 5,
		3, 5,
		4, 5,
	])
	return _create_wireframe_mesh(points, edges, contact_wire_thickness_m)

func _create_ground_contact_square_mesh() -> Mesh:
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.0, 0.2, 1.0)
	return box_mesh

func _is_ground_contact(node: Node3D) -> bool:
	return node is VehicleBody3D

func _create_wire_box_mesh(size: Vector3, thickness: float) -> ArrayMesh:
	var half := size * 0.5
	var points := [
		Vector3(-half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, half.y, -half.z),
		Vector3(-half.x, half.y, -half.z),
		Vector3(-half.x, -half.y, half.z),
		Vector3(half.x, -half.y, half.z),
		Vector3(half.x, half.y, half.z),
		Vector3(-half.x, half.y, half.z),
	]
	var edges := PackedInt32Array([
		0, 1,
		1, 2,
		2, 3,
		3, 0,
		4, 5,
		5, 6,
		6, 7,
		7, 4,
		0, 4,
		1, 5,
		2, 6,
		3, 7,
	])
	return _create_wireframe_mesh(points, edges, thickness)

func _create_wireframe_mesh(points: Array, edges: PackedInt32Array, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge_index in range(0, edges.size(), 2):
		var from_idx := edges[edge_index]
		var to_idx := edges[edge_index + 1]
		if from_idx < 0 or from_idx >= points.size() or to_idx < 0 or to_idx >= points.size():
			continue
		_append_beam(st, points[from_idx], points[to_idx], thickness)
	st.generate_normals()
	return st.commit()

func _append_beam(st: SurfaceTool, from_point: Vector3, to_point: Vector3, thickness: float) -> void:
	var delta := to_point - from_point
	var length := delta.length()
	if length <= 0.0001:
		return

	var forward := delta / length
	var right := Vector3.UP.cross(forward)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT.cross(forward)
	right = right.normalized()
	var up := forward.cross(right).normalized()
	var half_thickness := maxf(thickness, 0.0001) * 0.5
	var right_offset := right * half_thickness
	var up_offset := up * half_thickness

	var start_corners := [
		from_point - right_offset - up_offset,
		from_point + right_offset - up_offset,
		from_point + right_offset + up_offset,
		from_point - right_offset + up_offset,
	]
	var end_corners := [
		to_point - right_offset - up_offset,
		to_point + right_offset - up_offset,
		to_point + right_offset + up_offset,
		to_point - right_offset + up_offset,
	]

	_add_quad(st, start_corners[0], start_corners[1], end_corners[1], end_corners[0])
	_add_quad(st, start_corners[1], start_corners[2], end_corners[2], end_corners[1])
	_add_quad(st, start_corners[2], start_corners[3], end_corners[3], end_corners[2])
	_add_quad(st, start_corners[3], start_corners[0], end_corners[0], end_corners[3])

func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

# --- Waypoint display ---

func _setup_waypoint_visuals() -> void:
	if waypoint_dots == null or waypoint_lines == null:
		return

	waypoint_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dot_mat := _make_hologram_shader_material(2.0, 0.1, 3.0)
	dot_mat.set_shader_parameter("tint_color", waypoint_color)
	waypoint_dots.material_override = dot_mat
	var dot_mesh := BoxMesh.new()
	dot_mesh.size = Vector3.ONE  # scaled per-instance
	var dot_mm := MultiMesh.new()
	dot_mm.transform_format = MultiMesh.TRANSFORM_3D
	dot_mm.use_colors = true
	dot_mm.mesh = dot_mesh
	waypoint_dots.multimesh = dot_mm

	waypoint_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var line_mat := _make_hologram_shader_material(2.0, 0.1, 3.0)
	line_mat.set_shader_parameter("tint_color", waypoint_color)
	waypoint_lines.material_override = line_mat
	var line_mesh := CylinderMesh.new()
	line_mesh.top_radius = 0.5
	line_mesh.bottom_radius = 0.5
	line_mesh.height = 1.0
	var line_mm := MultiMesh.new()
	line_mm.transform_format = MultiMesh.TRANSFORM_3D
	line_mm.use_colors = true
	line_mm.mesh = line_mesh
	waypoint_lines.multimesh = line_mm

func _update_waypoint_display() -> void:
	if waypoint_dots == null or waypoint_lines == null:
		return
	if not is_instance_valid(_carrier):
		return

	var dot_mm := waypoint_dots.multimesh
	var line_mm := waypoint_lines.multimesh
	if dot_mm == null or line_mm == null:
		return

	# Get waypoints from the carrier
	var wp_positions: Array[Vector3] = []
	if _carrier.has_method("get_active_waypoints"):
		wp_positions = _carrier.get_active_waypoints()
	elif "_waypoint_positions" in _carrier and "_waypoint_index" in _carrier:
		var all_wps: Array = _carrier._waypoint_positions
		var idx: int = _carrier._waypoint_index
		for i in range(idx, all_wps.size()):
			wp_positions.append(all_wps[i] as Vector3)

	if wp_positions.is_empty():
		dot_mm.visible_instance_count = 0
		line_mm.visible_instance_count = 0
		waypoint_dots.visible = false
		waypoint_lines.visible = false
		return

	var base_height := _sample_reference_terrain_height()
	var table_half := table_size_m * 0.5

	# Convert world waypoints to hologram-local positions
	var holo_positions: Array[Vector3] = []
	for wp in wp_positions:
		var rel := _carrier_world_to_planar_local(wp)
		# Skip waypoints outside hologram coverage
		if absf(rel.x) > coverage_radius_m or absf(rel.z) > coverage_radius_m:
			continue
		var terrain_y := _sample_terrain_height_at_local_offset(rel.x, rel.z)
		var surface_y := _world_height_to_hologram_surface_y(terrain_y, base_height)
		if is_nan(surface_y):
			surface_y = 0.03
		var holo_pos := table_center_local + Vector3(
			(rel.x / maxf(coverage_radius_m, 1.0)) * table_half,
			surface_y + terrain_wire_height_offset_m + waypoint_box_size_m * 0.5 + 0.003,
			(rel.z / maxf(coverage_radius_m, 1.0)) * table_half
		)
		holo_positions.append(holo_pos)

	# Dots — small cream boxes at each waypoint
	var dot_count := holo_positions.size()
	dot_mm.instance_count = dot_count
	dot_mm.visible_instance_count = dot_count
	var box_scale := Vector3.ONE * waypoint_box_size_m
	for i in range(dot_count):
		dot_mm.set_instance_transform(i, Transform3D(Basis().scaled(box_scale), holo_positions[i]))
		dot_mm.set_instance_color(i, waypoint_color)
	waypoint_dots.visible = dot_count > 0

	# Lines — carrier to first waypoint, then consecutive waypoints
	var carrier_holo_pos := carrier_plate.position if carrier_plate else table_center_local
	var line_points: Array[Vector3] = [carrier_holo_pos]
	line_points.append_array(holo_positions)

	var line_transforms: Array[Transform3D] = []
	var line_colors: Array[Color] = []
	for i in range(line_points.size() - 1):
		var from_pos := line_points[i]
		var to_pos := line_points[i + 1]
		var delta := to_pos - from_pos
		var length := delta.length()
		if length < 0.0001:
			continue
		var y_axis := delta / length
		var x_axis := Vector3.UP.cross(y_axis)
		if x_axis.length_squared() < 0.0001:
			x_axis = Vector3.RIGHT.cross(y_axis)
		x_axis = x_axis.normalized()
		var z_axis := y_axis.cross(x_axis).normalized()
		var basis := Basis(
			x_axis * waypoint_line_thickness_m,
			y_axis * length,
			z_axis * waypoint_line_thickness_m
		)
		line_transforms.append(Transform3D(basis, (from_pos + to_pos) * 0.5))
		line_colors.append(waypoint_color)

	var line_count := line_transforms.size()
	line_mm.instance_count = line_count
	line_mm.visible_instance_count = line_count
	for i in range(line_count):
		line_mm.set_instance_transform(i, line_transforms[i])
		line_mm.set_instance_color(i, line_colors[i])
	waypoint_lines.visible = line_count > 0
