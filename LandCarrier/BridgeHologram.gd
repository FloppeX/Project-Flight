extends Node3D
class_name BridgeHologram

@export var table_size_m: float = 2.0
@export var coverage_radius_m: float = 5000.0
@export var terrain_grid_resolution: int = 105
@export var terrain_height_span_m: float = 700.0
@export var terrain_display_height_m: float = 0.46
@export var terrain_dot_scale_m: float = 0.0022
@export var terrain_low_color: Color = Color(0.18, 1.0, 0.28, 0.07)
@export var terrain_high_color: Color = Color(1.0, 0.2, 0.16, 0.18)
@export var terrain_wire_thickness_m: float = 0.004
@export var terrain_wire_low_color: Color = Color(0.0, 1.0, 0.2, 0.82)
@export var terrain_wire_high_color: Color = Color(1.0, 0.08, 0.0, 0.92)
@export var contact_altitude_span_m: float = 1200.0
@export var contact_display_height_m: float = 0.8
@export var contact_dot_scale_m: float = 0.045
@export var carrier_plate_length_m: float = 0.029
@export var carrier_plate_width_m: float = 0.008
@export var carrier_plate_height_m: float = 0.004
@export var carrier_plate_hover_m: float = 0.001
@export var max_contacts: int = 48
@export var terrain_retry_interval_s: float = 0.5
@export var terrain_refresh_interval_s: float = 0.3
@export var terrain_refresh_distance_m: float = 45.0
@export var terrain_refresh_heading_deg: float = 2.0
@onready var terrain_dots: MultiMeshInstance3D = $TerrainDots
@onready var terrain_lines: MultiMeshInstance3D = $TerrainLines
@onready var contact_dots: MultiMeshInstance3D = $ContactDots
@onready var carrier_plate: MeshInstance3D = $CarrierPlate

var _carrier: Node3D = null
var _terrain_provider: Node3D = null
var _terrain_built: bool = false
var _terrain_retry_timer: float = 0.0
var _terrain_refresh_timer: float = 0.0
var _last_terrain_center_world: Vector3 = Vector3.INF
var _last_terrain_heading_yaw: float = 0.0

func _ready() -> void:
	_carrier = get_tree().get_first_node_in_group("carrier") as Node3D
	_terrain_provider = get_tree().get_first_node_in_group("terrain_provider") as Node3D
	_setup_visuals()
	call_deferred("_try_build_terrain")
	_update_contact_dots()

func _process(delta: float) -> void:
	if not is_instance_valid(_carrier):
		_carrier = get_tree().get_first_node_in_group("carrier") as Node3D
		if _carrier == null:
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

	_update_contact_dots()

func _setup_visuals() -> void:
	var terrain_mesh := SphereMesh.new()
	terrain_mesh.radius = 0.5
	terrain_mesh.height = 1.0
	terrain_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	terrain_dots.material_override = _make_hologram_shader_material(0.9, 0.18, 3.0)

	var terrain_multimesh := MultiMesh.new()
	terrain_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	terrain_multimesh.use_colors = true
	terrain_multimesh.mesh = terrain_mesh
	terrain_dots.multimesh = terrain_multimesh
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

	var contact_mesh := _create_contact_triangle_mesh()
	contact_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	contact_dots.material_override = _make_hologram_shader_material(2.2, 0.34, 6.5)

	var contact_multimesh := MultiMesh.new()
	contact_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	contact_multimesh.use_colors = true
	contact_multimesh.mesh = contact_mesh
	contact_dots.multimesh = contact_multimesh

	_setup_carrier_plate()

func _try_build_terrain() -> void:
	_terrain_built = _rebuild_terrain_dots()
	if _terrain_built and is_instance_valid(_carrier):
		_last_terrain_center_world = _carrier.global_position
		_last_terrain_heading_yaw = _get_carrier_heading_yaw()

func _rebuild_terrain_dots() -> bool:
	if not is_instance_valid(_carrier):
		return false

	if not is_instance_valid(_terrain_provider):
		_terrain_provider = get_tree().get_first_node_in_group("terrain_provider") as Node3D

	var terrain_multimesh := terrain_dots.multimesh
	if terrain_multimesh == null:
		return false

	var resolution := maxi(terrain_grid_resolution, 3)
	if resolution % 2 == 0:
		resolution += 1
	var total_instances := resolution * resolution
	terrain_multimesh.instance_count = total_instances
	terrain_multimesh.visible_instance_count = total_instances

	var half_size_world := coverage_radius_m
	var table_half_size := table_size_m * 0.5
	var base_height := _sample_reference_terrain_height()
	var carrier_surface_height := _sample_terrain_height_at_local_offset(0.0, 0.0)
	var scale_basis := Basis().scaled(Vector3.ONE * terrain_dot_scale_m)
	var local_points: Array[Vector3] = []
	local_points.resize(total_instances)
	var point_colors: Array[Color] = []
	point_colors.resize(total_instances)
	var point_gradient: Array[float] = []
	point_gradient.resize(total_instances)
	var valid_points: Array[bool] = []
	valid_points.resize(total_instances)
	var valid_point_count := 0

	var instance_index := 0
	for z_idx in range(resolution):
		var z_t := 0.0 if resolution == 1 else float(z_idx) / float(resolution - 1)
		var local_z_world := lerpf(-half_size_world, half_size_world, z_t)
		for x_idx in range(resolution):
			var x_t := 0.0 if resolution == 1 else float(x_idx) / float(resolution - 1)
			var local_x_world := lerpf(-half_size_world, half_size_world, x_t)
			var terrain_y := _sample_terrain_height_at_local_offset(local_x_world, local_z_world)

			var local_pos := Vector3(
				(local_x_world / half_size_world) * table_half_size,
				0.02,
				(local_z_world / half_size_world) * table_half_size
			)
			var dot_color := terrain_low_color
			var is_valid_point := false
			var gradient_t := 0.0
			if not is_nan(terrain_y) and not is_nan(base_height):
				is_valid_point = true
				valid_point_count += 1
				var rel_height := clampf((terrain_y - base_height) / maxf(terrain_height_span_m, 1.0), -1.0, 1.0)
				local_pos.y += rel_height * terrain_display_height_m
				gradient_t = clampf((rel_height + 1.0) * 0.5, 0.0, 1.0)
				dot_color = terrain_low_color.lerp(terrain_high_color, gradient_t)
			else:
				local_pos.y -= 0.03
				dot_color.a *= 0.4

			local_points[instance_index] = local_pos
			point_colors[instance_index] = dot_color
			point_gradient[instance_index] = gradient_t
			valid_points[instance_index] = is_valid_point
			terrain_multimesh.set_instance_transform(instance_index, Transform3D(scale_basis, local_pos))
			terrain_multimesh.set_instance_color(instance_index, dot_color)
			instance_index += 1

	_rebuild_terrain_wireframe(local_points, point_gradient, valid_points, resolution)
	terrain_dots.visible = valid_point_count > 0
	terrain_lines.visible = valid_point_count > 0
	_update_carrier_plate_height(base_height, carrier_surface_height)
	return valid_point_count > 0

func _update_contact_dots() -> void:
	if not is_instance_valid(_carrier):
		return

	var contact_multimesh := contact_dots.multimesh
	if contact_multimesh == null:
		return

	var contacts: Array[Dictionary] = []
	_collect_contacts_for_group("friendlies", Color(0.2, 0.5, 1.0, 1.0), contacts)
	_collect_contacts_for_group("enemies", Color(1.0, 0.2, 0.2, 1.0), contacts)
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance_sq"] < b["distance_sq"])

	var visible_count := mini(contacts.size(), max_contacts)
	contact_multimesh.instance_count = max_contacts
	contact_multimesh.visible_instance_count = visible_count

	var scale_basis := Basis().scaled(Vector3.ONE * contact_dot_scale_m)
	for i in range(visible_count):
		var entry := contacts[i]
		var rel_local: Vector3 = entry["local_position"]
		var heading_local: Vector3 = entry["heading_local"]
		var hologram_pos := Vector3(
			(rel_local.x / maxf(coverage_radius_m, 1.0)) * (table_size_m * 0.5),
			0.08 + clampf(rel_local.y / maxf(contact_altitude_span_m, 1.0), -0.1, 1.0) * contact_display_height_m,
			(rel_local.z / maxf(coverage_radius_m, 1.0)) * (table_size_m * 0.5)
		)
		var yaw := atan2(heading_local.x, -heading_local.z)
		var heading_basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * contact_dot_scale_m)
		contact_multimesh.set_instance_transform(i, Transform3D(heading_basis, hologram_pos))
		contact_multimesh.set_instance_color(i, entry["color"])

func _collect_contacts_for_group(group_name: String, color: Color, contacts: Array[Dictionary]) -> void:
	for node in get_tree().get_nodes_in_group(group_name):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		if node == _carrier or node == get_parent():
			continue
		var node_3d := node as Node3D
		var rel_local := _carrier.to_local(node_3d.global_position)
		if absf(rel_local.x) > coverage_radius_m or absf(rel_local.z) > coverage_radius_m:
			continue
		var heading_local := _carrier.global_basis.inverse() * (-node_3d.global_basis.z)
		heading_local.y = 0.0
		if heading_local.length_squared() < 0.0001:
			heading_local = Vector3.FORWARD
		else:
			heading_local = heading_local.normalized()
		contacts.append({
			"local_position": rel_local,
			"heading_local": heading_local,
			"distance_sq": rel_local.x * rel_local.x + rel_local.z * rel_local.z,
			"color": color,
		})

func _sample_reference_terrain_height() -> float:
	var center_world := _carrier.global_position if is_instance_valid(_carrier) else global_position
	return _sample_terrain_world_height(center_world)

func _sample_terrain_height_at_local_offset(local_x_world: float, local_z_world: float) -> float:
	var world_pos := _carrier.to_global(Vector3(local_x_world, 0.0, local_z_world))
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
	var delta := to_point - from_point
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
	transforms.append(Transform3D(basis, (from_point + to_point) * 0.5))
	colors.append(color)

func _make_wire_color(a_gradient: float, b_gradient: float) -> Color:
	return terrain_wire_low_color.lerp(terrain_wire_high_color, clampf((a_gradient + b_gradient) * 0.5, 0.0, 1.0))

func _setup_carrier_plate() -> void:
	if carrier_plate == null:
		return

	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(carrier_plate_width_m, carrier_plate_height_m, carrier_plate_length_m)
	carrier_plate.mesh = plate_mesh
	carrier_plate.position = Vector3.ZERO
	_update_carrier_plate_height(NAN, NAN)
	carrier_plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var plate_material := _make_hologram_shader_material(1.6, 0.18, 4.2)
	plate_material.set_shader_parameter("tint_color", Color(0.2, 0.55, 1.0, 0.55))
	carrier_plate.material_override = plate_material

func _update_carrier_plate_height(base_height: float, carrier_surface_height: float) -> void:
	if carrier_plate == null:
		return
	var center_surface_y := _world_height_to_hologram_surface_y(carrier_surface_height, base_height)
	carrier_plate.position.y = center_surface_y + carrier_plate_height_m * 0.5 + carrier_plate_hover_m

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
	var forward := -_carrier.global_basis.z
	return atan2(forward.x, forward.z)

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

func _create_contact_triangle_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0.0, 0.0, -0.7),
		Vector3(-0.45, 0.0, 0.45),
		Vector3(0.45, 0.0, 0.45),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.UP,
		Vector3.UP,
		Vector3.UP,
	])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
