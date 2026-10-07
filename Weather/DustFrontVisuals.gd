extends Node3D
## Fixed cost: three silhouette shells, one fog volume, nearby dust and one
## camera-local patch of particles on the approaching wall.

var _front: Node3D
var _fog: FogVolume
var _fog_material: ShaderMaterial
var _materials: Array[ShaderMaterial] = []
var _particles: GPUParticles3D
var _particle_material: ParticleProcessMaterial
var _wall_particles: GPUParticles3D
var _wall_particle_material: ParticleProcessMaterial
var _wall_particle_draw_material: StandardMaterial3D
var _audio: AudioStreamPlayer
var _canopy_audio: Node
var _particle_draw_material: ShaderMaterial
var _tint := Color(0.78, 0.46, 0.26)
var _tint_sample_timer := 0.0
var _last_camera_id := 0
var _last_camera_position := Vector3.ZERO

func setup(front: Node3D) -> void:
	_front = front
	var dimensions := Vector3(front.half_width_m, front.height_m, front.half_depth_m)
	var mesh := _make_wall_mesh(dimensions)
	for shell in [1.0, 0.95, 0.89]:
		var wall := MeshInstance3D.new()
		wall.name = "DistantDustWall"
		wall.mesh = mesh
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = preload("res://Weather/dust_front_wall.gdshader")
		material.set_shader_parameter("dimensions", dimensions)
		material.set_shader_parameter("shell", shell)
		material.set_shader_parameter("shell_opacity", 0.78 if shell == 1.0 else (0.48 if shell == 0.95 else 0.30))
		wall.material_override = material
		_materials.append(material)
		add_child(wall)
	_fog = FogVolume.new()
	_fog.name = "LocalStormFog"
	_fog.size = Vector3(dimensions.x * 2.15, dimensions.y * 1.3, dimensions.z * 2.15)
	_fog.position.y = dimensions.y * 0.5
	_fog_material = ShaderMaterial.new()
	_fog_material.shader = preload("res://Weather/dust_front_fog.gdshader")
	_fog_material.set_shader_parameter("dimensions", dimensions)
	_fog_material.set_shader_parameter("box_size", _fog.size)
	_fog.material = _fog_material
	add_child(_fog)
	_make_particles()
	_make_wall_particles()
	_audio = AudioStreamPlayer.new()
	_audio.name = "StormWind"
	_audio.stream = preload("res://Audio/RuntimeAudio.gd").loop_stream(preload("res://Audio/cockpit/wind_sound_cockpit.wav"))
	_audio.volume_db = -80.0
	add_child(_audio)
	_canopy_audio = preload("res://Weather/CanopySandAudio.gd").new()
	_canopy_audio.name = "CanopySandImpacts"
	add_child(_canopy_audio)
	refresh_shape()

func refresh_shape() -> void:
	var dimensions := Vector3(_front.half_width_m, _front.height_m, _front.half_depth_m)
	var mesh := _make_wall_mesh(dimensions)
	for child in get_children():
		if child is MeshInstance3D and child.name.begins_with("DistantDustWall"):
			child.mesh = mesh
			child.custom_aabb = AABB(Vector3(-dimensions.x * 1.4, -180.0, -dimensions.z * 1.4),
				Vector3(dimensions.x * 2.8, dimensions.y * 1.25 + 180.0, dimensions.z * 2.8))
	_fog.size = Vector3(dimensions.x * 2.85, dimensions.y * 1.5, dimensions.z * 2.85)
	_fog.position.y = dimensions.y * 0.5
	_fog_material.set_shader_parameter("dimensions", dimensions)
	_fog_material.set_shader_parameter("box_size", _fog.size)
	_fog_material.set_shader_parameter("outline", _front.outline)
	for material in _materials:
		material.set_shader_parameter("dimensions", dimensions)
		material.set_shader_parameter("outline", _front.outline)

func _process(delta: float) -> void:
	if not is_instance_valid(_front):
		return
	_tint_sample_timer -= delta
	if _tint_sample_timer <= 0.0:
		_tint_sample_timer = 1.0
		_update_dust_tint()
	var strength: float = _front.strength if _front.enabled else 0.0
	visible = strength > 0.001
	_fog_material.set_shader_parameter("strength", strength)
	_fog_material.set_shader_parameter("elapsed", _front.elapsed_s)
	_fog_material.set_shader_parameter("extinction", _front.get_extinction())
	var severity: int = _front.get_severity()
	var particle_gain := lerpf(0.8, 1.6, float(severity - 1) / 4.0)
	# Tiny grains need more contrast to remain legible after antialiasing.
	_particle_draw_material.set_shader_parameter("opacity", 0.24 * particle_gain)
	_wall_particle_draw_material.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.06 * particle_gain * strength)
	for material in _materials:
		material.set_shader_parameter("strength", strength)
		material.set_shader_parameter("elapsed", _front.elapsed_s)
	var camera := get_viewport().get_camera_3d()
	var intensity := 0.0
	var inside := false
	var cockpit := false
	var grain_speed := 0.0
	if camera != null:
		intensity = _front.get_intensity_at(camera.global_position)
		for manager in get_tree().get_nodes_in_group("audio_manager_3d"):
			if manager.is_cockpit_camera_active():
				cockpit = true
				inside = true
				break
			if manager.is_bridge_camera_active():
				inside = true
				break
		_particles.global_position = camera.global_position
		_particles.global_basis = Basis.IDENTITY
		_update_wall_particles(camera, strength)
		var wind: Vector3 = _front.get_wind_at(camera.global_position) + _front.get_travel_velocity() * 0.4
		var field := get_tree().get_first_node_in_group("atmospheric_wind")
		if field != null:
			wind = field.get_velocity_at(camera.global_position)
		var airflow := wind - _get_camera_velocity(camera, delta)
		grain_speed = _configure_grain_motion(airflow, severity, intensity, cockpit)
	_canopy_audio.update_exposure(cockpit, intensity, severity, grain_speed, delta)
	_particle_draw_material.set_shader_parameter("cockpit_view", cockpit)
	_fog_material.set_shader_parameter("interior_clear_radius", (3.0 if cockpit else 5.0) if inside else 0.0)
	if camera != null:
		_fog_material.set_shader_parameter("interior_clear_center", _front.to_local(camera.global_position))
	_particles.amount_ratio = clampf(intensity * (0.4 + severity * 0.12), 0.0, 1.0)
	_particles.emitting = intensity > 0.08 and (not inside or cockpit)
	_particles.visible = (not inside or cockpit) and intensity > 0.02
	if camera == null:
		_wall_particles.emitting = false
		_wall_particles.visible = false
	var target_db := lerpf(-38.0, -15.0, intensity) - (14.0 if inside else 0.0) if intensity > 0.01 else -80.0
	_audio.volume_db = lerpf(_audio.volume_db, target_db, 1.0 - exp(-delta * 3.0))
	if intensity > 0.01 and not _audio.playing:
		_audio.play()
	elif intensity <= 0.01 and _audio.volume_db < -65.0:
		_audio.stop()

func _configure_grain_motion(airflow: Vector3, severity: int, intensity: float, cockpit: bool) -> float:
	# Exaggerate fine-grain advection visually without changing aircraft forces.
	var level := float(clampi(severity, 1, 5))
	var speed := maxf(airflow.length() * (3.75 + level * 0.75), 75.0 + level * 45.0)
	speed *= lerpf(0.6, 1.0, intensity)
	var direction := airflow.normalized() if airflow.length() > 0.1 else Vector3.RIGHT
	_particles.speed_scale = clampf(speed / 30.0, 1.0, 48.0)
	_particle_material.direction = direction
	_particle_material.initial_velocity_min = speed * 0.85 / _particles.speed_scale
	_particle_material.initial_velocity_max = speed * 1.15 / _particles.speed_scale
	_particle_material.scale_min = 0.01 if cockpit else 0.025
	_particle_material.scale_max = 0.025 if cockpit else 0.07
	_particle_draw_material.set_shader_parameter("flow_direction", direction)
	_particle_draw_material.set_shader_parameter("grain_stretch", clampf(speed / 100.0, 2.0, 5.0))
	return speed

func _get_camera_velocity(camera: Camera3D, delta: float) -> Vector3:
	var velocity := Vector3.ZERO
	var displacement := camera.global_position - _last_camera_position
	if camera.get_instance_id() == _last_camera_id and displacement.length() < 100.0:
		velocity = displacement / maxf(delta, 0.001)
	_last_camera_id = camera.get_instance_id()
	_last_camera_position = camera.global_position
	# Aircraft velocity survives camera switches and floating-origin shifts.
	var ancestor: Node = camera.get_parent()
	while ancestor != null:
		if ancestor is RigidBody3D:
			return (ancestor as RigidBody3D).linear_velocity
		ancestor = ancestor.get_parent()
	return velocity.limit_length(350.0)

func _make_wall_mesh(dimensions: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 16:
		for column in 96:
			var corners: Array[Vector3] = []
			for ij in [Vector2(column, row), Vector2(column + 1, row), Vector2(column, row + 1), Vector2(column + 1, row + 1)]:
				var angle: float = ij.x / 96.0 * TAU
				var y: float = ij.y / 16.0
				var r: float = sqrt(maxf(0.0, 1.0 - pow(y, 8.0))) * _front.SHAPE.edge(angle, _front.outline)
				corners.append(Vector3(cos(angle) * dimensions.x * r, y * dimensions.y, sin(angle) * dimensions.z * r))
			for idx in [0, 2, 1, 1, 2, 3]:
				surface.add_vertex(corners[idx])
	surface.generate_normals()
	return surface.commit()

func _make_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "NearbyBlowingDust"
	_particles.amount = 320
	_particles.lifetime = 1.8
	_particles.preprocess = 1.8
	_particles.local_coords = true
	_particles.visibility_aabb = AABB(Vector3(-130, -70, -130), Vector3(260, 140, 260))
	_particle_material = ParticleProcessMaterial.new()
	_particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	_particle_material.emission_sphere_radius = 25.0
	_particle_material.gravity = Vector3.ZERO
	_particle_material.spread = 6.0
	_particle_material.scale_min = 0.025
	_particle_material.scale_max = 0.07
	_particles.process_material = _particle_material
	var mesh := SphereMesh.new()
	mesh.radial_segments = 4
	mesh.rings = 2
	var material := ShaderMaterial.new()
	material.shader = preload("res://Weather/dust_nearby.gdshader")
	material.set_shader_parameter("dust_color", _tint)
	mesh.material = material
	_particle_draw_material = material
	_particles.draw_pass_1 = mesh
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_particles.emitting = false
	add_child(_particles)

func _make_wall_particles() -> void:
	_wall_particles = GPUParticles3D.new()
	_wall_particles.name = "ApproachingWallDust"
	_wall_particles.amount = 2200
	_wall_particles.lifetime = 2.8
	_wall_particles.preprocess = 2.8
	# Existing particles stay in world space as the camera follows the moving front.
	_wall_particles.local_coords = false
	_wall_particles.visibility_aabb = AABB(Vector3(-1900, -940, -250), Vector3(3800, 1880, 500))
	_wall_particle_material = ParticleProcessMaterial.new()
	_wall_particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_wall_particle_material.emission_box_extents = Vector3(1700.0, 830.0, 90.0)
	_wall_particle_material.direction = Vector3(0.0, 0.12, 1.0)
	_wall_particle_material.spread = 32.0
	_wall_particle_material.initial_velocity_min = 10.0
	_wall_particle_material.initial_velocity_max = 24.0
	_wall_particle_material.gravity = Vector3.ZERO
	_wall_particle_material.scale_min = 0.65
	_wall_particle_material.scale_max = 1.35
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.17, Color.WHITE)
	fade.add_point(0.72, Color.WHITE)
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	_wall_particle_material.color_ramp = fade_texture
	_wall_particles.process_material = _wall_particle_material
	var mesh := SphereMesh.new()
	mesh.radius = 4.5
	mesh.height = 9.0
	mesh.radial_segments = 4
	mesh.rings = 2
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.06)
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	_wall_particle_draw_material = material
	_wall_particles.draw_pass_1 = mesh
	_wall_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall_particles.emitting = false
	add_child(_wall_particles)

func _update_wall_particles(camera: Camera3D, strength: float) -> void:
	_wall_particles.speed_scale = 0.8 + 0.55 * float(_front.get_severity())
	var p: Vector3 = _front.to_local(camera.global_position)
	var width: float = _front.half_width_m
	var depth: float = _front.half_depth_m
	var height: float = _front.height_m
	var angle := atan2(p.z / depth, p.x / width)
	var lobe: float = _front.SHAPE.edge(angle, _front.outline)
	var tangent: Vector3 = (_front.get_local_edge(angle - 0.01) - _front.get_local_edge(angle + 0.01)).normalized()
	var outward := tangent.cross(Vector3.UP).normalized()
	var half_particle_height := minf(830.0, height * 0.36)
	var wall_point := Vector3(cos(angle) * width * lobe,
		clampf(p.y, half_particle_height + 40.0, height - half_particle_height - 40.0), sin(angle) * depth * lobe)
	var wall_distance := (p - wall_point).dot(outward)
	var outside := Vector2(p.x / width, p.z / depth).length() > lobe
	var active := strength > 0.05 and outside and wall_distance < 3500.0 and p.y < height * 1.15
	_wall_particles.emitting = active
	_wall_particles.visible = active
	if active:
		# A tangent strip follows the broad leading edge; narrow it on tighter side arcs.
		var curvature_radius := pow(width * width * sin(angle) * sin(angle)
			+ depth * depth * cos(angle) * cos(angle), 1.5) / (width * depth)
		var half_span := clampf(sqrt(2.0 * curvature_radius * 100.0), 450.0, 1700.0)
		if absf(_wall_particle_material.emission_box_extents.x - half_span) > 20.0 \
				or absf(_wall_particle_material.emission_box_extents.y - half_particle_height) > 1.0:
			_wall_particle_material.emission_box_extents = Vector3(half_span, half_particle_height, 90.0)
		_wall_particles.global_transform = Transform3D(_front.global_basis * Basis(tangent, Vector3.UP, outward),
			_front.to_global(wall_point - outward * 40.0))

func _update_dust_tint() -> void:
	# Match the wheel dust's shared, terrain-sampled palette.
	var target := DustEffect._sanitize_dust_color(DustEffect._shared_dust_color)
	_tint = _tint.lerp(target, 0.2)
	var shader_tint := Color(_tint.r, _tint.g, _tint.b, 1.0)
	_fog_material.set_shader_parameter("dust_color", shader_tint)
	for material in _materials:
		material.set_shader_parameter("dust_color", shader_tint)
	_particle_draw_material.set_shader_parameter("dust_color", shader_tint)
