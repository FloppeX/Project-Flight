extends Node3D
class_name WingtipVortexEffect

## Short-lived wingtip condensation driven by sustained aerodynamic load.
## A feathered, camera-facing ribbon records each tip's recent world path.

@export var left_tip_path: NodePath = NodePath("../WingtipLeft")
@export var right_tip_path: NodePath = NodePath("../WingtipRight")
@export var aero_path: NodePath = NodePath("../SimpleAero")
@export var wing_fold_path: NodePath = NodePath("../WingFold")
@export var landing_gear_path: NodePath = NodePath("../LandingGear")

@export_group("Maneuver Gate")
@export_range(1.0, 6.0, 0.05) var load_start_g: float = 1.8
@export_range(1.0, 8.0, 0.05) var load_full_g: float = 3.25
@export_range(0.0, 250.0, 1.0) var speed_start_mps: float = 55.0
@export_range(0.0, 300.0, 1.0) var speed_full_mps: float = 90.0
@export_range(0.0, 30.0, 0.5) var aoa_start_deg: float = 3.0
@export_range(0.0, 45.0, 0.5) var aoa_full_deg: float = 11.0
@export_range(0.0, 1.0, 0.05) var low_aoa_intensity: float = 0.65
@export_range(0.1, 20.0, 0.1) var fade_in_per_s: float = 3.5
@export_range(0.1, 20.0, 0.1) var fade_out_per_s: float = 6.0

@export_group("Appearance")
@export_range(0.05, 2.0, 0.01) var ribbon_width_m: float = 0.26
@export_range(0.1, 2.0, 0.01) var ribbon_lifetime_s: float = 0.42
@export_range(0.1, 5.0, 0.05) var ribbon_sample_spacing_m: float = 0.8
@export_range(0.005, 0.2, 0.005) var ribbon_max_sample_interval_s: float = 0.035
@export_range(2.0, 100.0, 1.0) var ribbon_max_sample_gap_m: float = 15.0
@export_range(4, 96, 1) var ribbon_max_samples: int = 48
@export_range(0.0, 1.0, 0.01) var ribbon_opacity: float = 0.52
@export var ribbon_color: Color = Color(0.88, 0.95, 1.0, 1.0)
@export var visual_budget_enabled: bool = true


class TrailSample:
	var world_position: Vector3
	var age_s: float
	var intensity: float
	var sequence: int

	func _init(position_value: Vector3, intensity_value: float, sequence_value: int) -> void:
		world_position = position_value
		age_s = 0.0
		intensity = intensity_value
		sequence = sequence_value

var _aircraft: RigidBody3D = null
var _aero: Node = null
var _wing_fold: Node = null
var _landing_gear: Node = null
var _left_tip: Node3D = null
var _right_tip: Node3D = null
var _current_intensity: float = 0.0
var _left_samples: Array[TrailSample] = []
var _right_samples: Array[TrailSample] = []
var _left_ribbon: MeshInstance3D = null
var _right_ribbon: MeshInstance3D = null
var _left_ribbon_mesh: ImmediateMesh = null
var _right_ribbon_mesh: ImmediateMesh = null
var _sample_sequence: int = 0
var _cached_camera: Camera3D = null
var _camera_cache_timer_s: float = 0.0
var _ribbon_material: StandardMaterial3D = null


func _ready() -> void:
	_aircraft = get_parent() as RigidBody3D
	_left_tip = get_node_or_null(left_tip_path) as Node3D
	_right_tip = get_node_or_null(right_tip_path) as Node3D
	_aero = get_node_or_null(aero_path)
	_wing_fold = get_node_or_null(wing_fold_path)
	if _wing_fold == null:
		_wing_fold = _find_wing_fold_controller()
	_landing_gear = get_node_or_null(landing_gear_path)

	if _aircraft == null or _left_tip == null or _right_tip == null:
		push_warning("[WingtipVortexEffect] Aircraft body or wingtip anchors are missing")
		set_process(false)
		return

	_left_ribbon = _create_ribbon(&"LeftVortexRibbon")
	_right_ribbon = _create_ribbon(&"RightVortexRibbon")
	_left_ribbon_mesh = _left_ribbon.mesh as ImmediateMesh
	_right_ribbon_mesh = _right_ribbon.mesh as ImmediateMesh
	_rebuild_ribbons()
	set_process(visual_budget_enabled)


func _process(delta: float) -> void:
	var target_intensity := _get_target_intensity() if visual_budget_enabled else 0.0
	var response := fade_in_per_s if target_intensity > _current_intensity else fade_out_per_s
	_current_intensity = move_toward(
		_current_intensity,
		target_intensity,
		maxf(response, 0.0) * maxf(delta, 0.0)
	)
	_update_ribbons(delta, _current_intensity)


func set_visual_budget_enabled(value: bool) -> void:
	visual_budget_enabled = value
	set_process(value and _aircraft != null and _left_tip != null and _right_tip != null)
	if not value:
		_current_intensity = 0.0
		_clear_ribbons()


func get_current_intensity() -> float:
	return _current_intensity


func calculate_maneuver_intensity(
		load_factor_g: float,
		aoa_deg: float,
		speed_mps: float,
		fold_fraction: float = 0.0) -> float:
	if fold_fraction > 0.001:
		return 0.0
	var load_t := _smoothstep(load_start_g, maxf(load_full_g, load_start_g + 0.01), load_factor_g)
	var speed_t := _smoothstep(speed_start_mps, maxf(speed_full_mps, speed_start_mps + 0.01), speed_mps)
	var aoa_t := _smoothstep(aoa_start_deg, maxf(aoa_full_deg, aoa_start_deg + 0.01), maxf(aoa_deg, 0.0))
	var aoa_multiplier := lerpf(clampf(low_aoa_intensity, 0.0, 1.0), 1.0, aoa_t)
	return clampf(load_t * speed_t * aoa_multiplier, 0.0, 1.0)


func _get_target_intensity() -> float:
	if _aircraft == null or not is_instance_valid(_aircraft):
		return 0.0
	if _is_landing_gear_deployed():
		return 0.0

	var fold_fraction := 0.0
	if _wing_fold != null and _wing_fold.has_method("get_technical_index_preview_fraction"):
		fold_fraction = float(_wing_fold.call("get_technical_index_preview_fraction"))

	var load_factor := maxf(float(_aircraft.get("local_load_factor")), 0.0)
	var aoa_deg := 0.0
	if _aero != null:
		if _aero.has_method("get_estimated_lift_ratio"):
			load_factor = maxf(load_factor, float(_aero.call("get_estimated_lift_ratio")))
		if _aero.has_method("get_estimated_angle_of_attack_deg"):
			aoa_deg = float(_aero.call("get_estimated_angle_of_attack_deg"))

	return calculate_maneuver_intensity(
		load_factor,
		aoa_deg,
		_aircraft.linear_velocity.length(),
		fold_fraction
	)


func _is_landing_gear_deployed() -> bool:
	if _landing_gear == null:
		return false
	if "is_deployed" in _landing_gear:
		return bool(_landing_gear.get("is_deployed"))
	return false


func _find_wing_fold_controller() -> Node:
	if _aircraft == null:
		return null
	for child in _aircraft.get_children():
		if "wingfold" in String(child.name).to_lower() \
				and child.has_method("get_technical_index_preview_fraction"):
			return child
	return null


func _update_ribbons(delta: float, intensity: float) -> void:
	if not visual_budget_enabled:
		_clear_ribbons()
		return
	_age_and_prune_samples(_left_samples, delta)
	_age_and_prune_samples(_right_samples, delta)
	if intensity > 0.01:
		_record_ribbon_samples(intensity)
	_camera_cache_timer_s = maxf(_camera_cache_timer_s - maxf(delta, 0.0), 0.0)
	_rebuild_ribbons()


func _age_and_prune_samples(samples: Array[TrailSample], delta: float) -> void:
	for sample in samples:
		sample.age_s += maxf(delta, 0.0)
	var lifetime := maxf(ribbon_lifetime_s, 0.01)
	while not samples.is_empty() and samples[0].age_s >= lifetime:
		samples.remove_at(0)


func _record_ribbon_samples(intensity: float) -> void:
	if _left_tip == null or _right_tip == null:
		return
	_append_ribbon_sample(_left_samples, _left_tip.global_position, intensity)
	_append_ribbon_sample(_right_samples, _right_tip.global_position, intensity)


func _append_ribbon_sample(
		samples: Array[TrailSample],
		world_position: Vector3,
		intensity: float) -> void:
	if not samples.is_empty():
		var last_sample := samples[samples.size() - 1]
		var gap_m := last_sample.world_position.distance_to(world_position)
		if gap_m > maxf(ribbon_max_sample_gap_m, ribbon_sample_spacing_m):
			samples.clear()
		elif gap_m < maxf(ribbon_sample_spacing_m, 0.01) \
				and last_sample.age_s < maxf(ribbon_max_sample_interval_s, 0.001):
			return
	_sample_sequence += 1
	samples.append(TrailSample.new(world_position, clampf(intensity, 0.0, 1.0), _sample_sequence))
	while samples.size() > maxi(ribbon_max_samples, 2):
		samples.remove_at(0)


func _rebuild_ribbons() -> void:
	var camera := _get_active_camera()
	_rebuild_ribbon(_left_samples, _left_ribbon_mesh, _left_ribbon, camera)
	_rebuild_ribbon(_right_samples, _right_ribbon_mesh, _right_ribbon, camera)


func _rebuild_ribbon(
		samples: Array[TrailSample],
		immediate_mesh: ImmediateMesh,
		mesh_instance: MeshInstance3D,
		camera: Camera3D) -> void:
	if immediate_mesh == null or mesh_instance == null:
		return
	if not visual_budget_enabled or samples.size() < 2:
		if immediate_mesh.get_surface_count() > 0:
			immediate_mesh.clear_surfaces()
		mesh_instance.visible = false
		return
	immediate_mesh.clear_surfaces()

	var effect_to_local := global_transform.affine_inverse()
	var fallback_view := _aircraft.global_transform.basis.y if is_instance_valid(_aircraft) else Vector3.UP
	var lifetime := maxf(ribbon_lifetime_s, 0.01)
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _get_ribbon_material())
	for i in range(samples.size()):
		var sample := samples[i]
		var previous_position := samples[maxi(i - 1, 0)].world_position
		var next_position := samples[mini(i + 1, samples.size() - 1)].world_position
		var tangent := (next_position - previous_position).normalized()
		if tangent.length_squared() <= 0.0001:
			tangent = _aircraft.global_transform.basis.z.normalized() if is_instance_valid(_aircraft) else Vector3.FORWARD
		var view_direction := (
			(camera.global_position - sample.world_position).normalized()
			if camera != null and is_instance_valid(camera)
			else fallback_view
		)
		var side := tangent.cross(view_direction).normalized()
		if side.length_squared() <= 0.0001:
			side = tangent.cross(fallback_view).normalized()
		if side.length_squared() <= 0.0001:
			side = Vector3.RIGHT

		var age_t := clampf(sample.age_s / lifetime, 0.0, 1.0)
		var fade := 1.0 - _smoothstep(0.0, 1.0, age_t)
		var taper := lerpf(1.0, 0.18, age_t)
		var width_noise := 0.92 + sin(float(sample.sequence) * 1.73) * 0.08
		var half_width := maxf(ribbon_width_m, 0.01) * taper * width_noise * 0.5
		var color := ribbon_color
		color.a *= clampf(ribbon_opacity, 0.0, 1.0) * sample.intensity * fade
		var left_vertex := effect_to_local * (sample.world_position - side * half_width)
		var right_vertex := effect_to_local * (sample.world_position + side * half_width)
		immediate_mesh.surface_set_color(color)
		immediate_mesh.surface_set_uv(Vector2(0.0, age_t))
		immediate_mesh.surface_add_vertex(left_vertex)
		immediate_mesh.surface_set_color(color)
		immediate_mesh.surface_set_uv(Vector2(1.0, age_t))
		immediate_mesh.surface_add_vertex(right_vertex)
	immediate_mesh.surface_end()
	mesh_instance.visible = true


func _get_active_camera() -> Camera3D:
	if _cached_camera != null and is_instance_valid(_cached_camera) and _camera_cache_timer_s > 0.0:
		return _cached_camera
	_cached_camera = get_viewport().get_camera_3d()
	_camera_cache_timer_s = 0.2
	return _cached_camera


func _clear_ribbons() -> void:
	_left_samples.clear()
	_right_samples.clear()
	for immediate_mesh in [_left_ribbon_mesh, _right_ribbon_mesh]:
		if immediate_mesh != null:
			immediate_mesh.clear_surfaces()
	for mesh_instance in [_left_ribbon, _right_ribbon]:
		if mesh_instance != null:
			mesh_instance.visible = false


func _create_ribbon(ribbon_name: StringName) -> MeshInstance3D:
	var immediate_mesh := ImmediateMesh.new()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = ribbon_name
	mesh_instance.mesh = immediate_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.visible = false
	add_child(mesh_instance)
	return mesh_instance


func _get_ribbon_material() -> StandardMaterial3D:
	if _ribbon_material != null:
		return _ribbon_material
	_ribbon_material = StandardMaterial3D.new()
	_ribbon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ribbon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ribbon_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ribbon_material.vertex_color_use_as_albedo = true
	_ribbon_material.albedo_color = Color.WHITE
	_ribbon_material.albedo_texture = _create_soft_ribbon_texture()
	return _ribbon_material


func _create_soft_ribbon_texture() -> ImageTexture:
	const TEXTURE_WIDTH := 48
	const TEXTURE_HEIGHT := 4
	var image := Image.create(TEXTURE_WIDTH, TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8)
	for y in range(TEXTURE_HEIGHT):
		for x in range(TEXTURE_WIDTH):
			var across := float(x) / float(TEXTURE_WIDTH - 1)
			var alpha := pow(maxf(sin(across * PI), 0.0), 0.72)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


static func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t := clampf((value - edge0) / maxf(edge1 - edge0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
