extends Node3D
## Stationary, spawnable art prototype: two faceted shells and one local volume.
## Keep radius/envelope math aligned with fog_bank_shape.gdshaderinc.
@export var enabled := true
@export var radii := Vector3(460.0, 160.0, 280.0)
@export var extinction_per_m := 0.025
var initialized := false
var elapsed_s := 0.0
var _surfaces: Array[ShaderMaterial] = []
var _volume_material: ShaderMaterial
var _volume: FogVolume
var _tint := Color(0.74, 0.59, 0.43)

func _ready() -> void:
	add_to_group("faceted_fog_bank")
	# Only elapsed time drives the GPU deformation, so pause freezes every layer.
	var mesh := _make_mesh()
	for layer in 2:
		var model := MeshInstance3D.new()
		model.name = "InnerBillows" if layer == 0 else "OuterBillows"
		model.mesh = mesh
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.custom_aabb = AABB(-radii * 1.35, radii * 2.7)
		var material := ShaderMaterial.new()
		material.shader = preload("res://Weather/fog_bank_surface.gdshader")
		material.set_shader_parameter("radii", radii)
		material.set_shader_parameter("shell", 0.89 if layer == 0 else 1.0)
		material.set_shader_parameter("shell_opacity", 0.85 if layer == 0 else 0.68)
		material.render_priority = layer
		model.material_override = material
		_surfaces.append(material)
		add_child(model)
	_volume = FogVolume.new()
	_volume.name = "InteriorFog"
	_volume.size = radii * 2.9
	_volume_material = ShaderMaterial.new()
	_volume_material.shader = preload("res://Weather/fog_bank_volume.gdshader")
	_volume_material.set_shader_parameter("radii", radii)
	_volume_material.set_shader_parameter("box_size", _volume.size)
	_volume.material = _volume_material
	add_child(_volume)
	visible = false

func start_at(ground_position: Vector3, forward: Vector3) -> void:
	var direction := Vector3(forward.x, 0, forward.z).normalized()
	if direction.is_zero_approx():
		direction = Vector3.BACK
	global_transform = Transform3D(Basis(Vector3.UP.cross(direction), Vector3.UP, direction), ground_position + Vector3.UP * radii.y * 0.45)
	elapsed_s = 0.0
	initialized = true
	enabled = true

func _physics_process(delta: float) -> void:
	if enabled and initialized:
		elapsed_s += delta

func _process(delta: float) -> void:
	visible = enabled and initialized
	var strength := 1.0 if visible else 0.0
	var dust := DustEffect._sanitize_dust_color(DustEffect._shared_dust_color)
	_tint = _tint.lerp(dust.lerp(Color(0.94, 0.86, 0.72), 0.70), minf(delta, 1.0))
	var camera := get_viewport().get_camera_3d()
	var exterior := 1.0
	if camera != null:
		var local_camera := to_local(camera.global_position)
		exterior = smoothstep(0.6, 1.06, _envelope(local_camera))
		_volume_material.set_shader_parameter("clear_center", local_camera)
	for material in _surfaces:
		material.set_shader_parameter("elapsed", elapsed_s)
		material.set_shader_parameter("strength", strength)
		material.set_shader_parameter("tint", _tint)
		material.set_shader_parameter("exterior_visibility", exterior)
	_volume_material.set_shader_parameter("elapsed", elapsed_s)
	_volume_material.set_shader_parameter("strength", strength)
	_volume_material.set_shader_parameter("extinction", extinction_per_m)
	_volume_material.set_shader_parameter("tint", _tint)

func _envelope(p: Vector3) -> float:
	var q := p / radii
	var r := q.length()
	var direction := q / maxf(r, 0.0001)
	var radius := 0.94 \
		+ 0.12 * sin(direction.x * 5.0 + elapsed_s * 0.045) * sin(direction.z * 4.0 - elapsed_s * 0.035) \
		+ 0.07 * cos(direction.x * 8.0 - direction.z * 6.0 + direction.y * 3.0 + elapsed_s * 0.025) \
		+ 0.09 * sin(direction.z * 7.0 + direction.y * 4.0 - elapsed_s * 0.03)
	return r / radius

func get_intensity_at(point: Vector3) -> float:
	if not enabled or not initialized:
		return 0.0
	return 1.0 - smoothstep(0.65, 1.12, _envelope(to_local(point)))

func get_visibility_m(point: Vector3) -> float:
	return minf(10000.0, 3.912 / maxf(extinction_per_m * get_intensity_at(point), 0.00001))

func _make_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 12:
		for column in 32:
			# Godot uses clockwise front faces; keep the near skin visible.
			for corner in [Vector2(0, 0), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]:
				var angle: float = (column + corner.x) / 32.0 * TAU
				var latitude: float = (row + corner.y) / 12.0 * PI
				var direction := Vector3(sin(latitude) * cos(angle), cos(latitude), sin(latitude) * sin(angle))
				st.set_normal(direction)
				st.add_vertex(direction)
	return st.commit()
