extends Node3D
## Fixed GPU instance counts; only 64 ground puffs need terrain samples at 10 Hz.
var _twister: Node3D
var _materials: Array[ShaderMaterial] = []
var _ground: MultiMeshInstance3D
var _ground_material: StandardMaterial3D
var _fog_material: ShaderMaterial
var _audio: AudioStreamPlayer3D
var _ground_timer := 0.0
var _tint := Color(0.65, 0.46, 0.3)

func setup(twister: Node3D) -> void:
	_twister = twister
	var mesh := _funnel_mesh()
	for shell in [0.85, 1.0, 1.16]:
		var model := MeshInstance3D.new()
		model.mesh = mesh
		model.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, twister.height_m + 150, 1000))
		var material := ShaderMaterial.new()
		material.shader = preload("res://Weather/twister_funnel.gdshader")
		material.set_shader_parameter("shell", shell)
		model.material_override = material
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(model)
		_materials.append(material)
	_make_orbiting_particles(900, false)
	_make_orbiting_particles(64, true)
	_ground = MultiMeshInstance3D.new()
	_ground.name = "TerrainDust"
	_ground.multimesh = _multimesh(64)
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground_material = StandardMaterial3D.new()
	_ground_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ground_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ground.material_override = _ground_material
	add_child(_ground)
	var fog := FogVolume.new()
	fog.size = Vector3(1000, twister.height_m + 60, 1000)
	fog.position.y = twister.height_m * 0.5 - 20.0
	_fog_material = ShaderMaterial.new()
	_fog_material.shader = preload("res://Weather/twister_fog.gdshader")
	_fog_material.set_shader_parameter("box_size", fog.size)
	_fog_material.set_shader_parameter("height_m", twister.height_m)
	fog.material = _fog_material
	add_child(fog)
	_audio = AudioStreamPlayer3D.new()
	_audio.name = "TwisterRoar"
	_audio.stream = preload("res://Audio/RuntimeAudio.gd").loop_stream(preload("res://Audio/wind woosh loop.wav"))
	_audio.unit_size = 200.0
	_audio.max_distance = 3000.0
	_audio.max_db = -8.0
	_audio.pitch_scale = 0.7
	add_child(_audio)

func _multimesh(count: int) -> MultiMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	return mm

func _make_orbiting_particles(count: int, debris: bool) -> void:
	var model := MultiMeshInstance3D.new()
	model.name = "Debris" if debris else "SpirallingDust"
	model.multimesh = _multimesh(count)
	model.custom_aabb = AABB(Vector3(-550, -50, -550), Vector3(1100, _twister.height_m + 150, 1100))
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := RandomNumberGenerator.new()
	rng.seed = 321 if debris else 789
	for i in count:
		model.multimesh.set_instance_transform(i, Transform3D.IDENTITY)
		model.multimesh.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	var material := ShaderMaterial.new()
	material.shader = preload("res://Weather/twister_particles.gdshader")
	material.set_shader_parameter("debris", debris)
	model.material_override = material
	_materials.append(material)
	add_child(model)

func _process(delta: float) -> void:
	if not is_instance_valid(_twister):
		return
	var strength: float = _twister.strength if _twister.enabled else 0.0
	visible = strength > 0.001
	_tint = _tint.lerp(DustEffect._sanitize_dust_color(DustEffect._shared_dust_color), minf(delta, 1.0))
	for material in _materials:
		material.set_shader_parameter("elapsed", _twister.elapsed_s)
		material.set_shader_parameter("height_m", _twister.height_m)
		material.set_shader_parameter("strength", strength)
		material.set_shader_parameter("dust_color", _tint)
	_fog_material.set_shader_parameter("elapsed", _twister.elapsed_s)
	_fog_material.set_shader_parameter("strength", strength)
	_fog_material.set_shader_parameter("dust_color", _tint)
	_ground_material.albedo_color = Color(_tint, 0.30 * strength)
	_ground_timer -= delta
	if visible and _ground_timer <= 0.0:
		_ground_timer = 0.1
		_update_ground()
	var camera := get_viewport().get_camera_3d()
	var near := false
	var enclosed := false
	if camera != null:
		_audio.position.y = clampf(camera.global_position.y - global_position.y, 10.0, _twister.height_m * 0.7)
		near = camera.global_position.distance_to(_audio.global_position) < _audio.max_distance
		var manager := get_tree().get_first_node_in_group("audio_manager_3d")
		if manager != null:
			enclosed = manager.is_cockpit_camera_active() or manager.is_bridge_camera_active()
		_fog_material.set_shader_parameter("clear_center", to_local(camera.global_position))
	_fog_material.set_shader_parameter("clear_radius", 5.0 if enclosed else 0.0)
	if near and visible:
		_audio.volume_db = linear_to_db(maxf(strength, 0.0001)) - (19.0 if enclosed else 8.0)
		if not _audio.playing:
			_audio.play()
	else:
		_audio.stop()

func _update_ground() -> void:
	for i in 64:
		var phase := fmod(float(i) * 0.618034 + _twister.elapsed_s * 0.06, 1.0)
		var angle: float = float(i) * 2.39996 + _twister.elapsed_s * 0.6
		var radius := 60.0 + phase * 190.0
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		pos.y = _twister.ground_height(global_position + pos) - global_position.y + 8.0 + phase * 24.0
		# Grow and dissipate before wrapping the orbit back to the inner ring.
		var scale_m := sin(phase * PI) * (38.0 + sin(float(i) * 7.13) * 10.0)
		_ground.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(scale_m, scale_m * 0.65, scale_m)), pos))

func _funnel_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 48:
		for col in 64:
			for corner in [Vector2(0, 0), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]:
				var uv := Vector2((col + corner.x) / 64.0, (row + corner.y) / 48.0)
				st.set_uv(uv)
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(cos(uv.x * TAU), uv.y, sin(uv.x * TAU)))
	return st.commit()
