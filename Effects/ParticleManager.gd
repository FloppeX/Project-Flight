extends Node

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")

# Global particle manager - handles all types of particles independently of their creators
@export var particle_update_interval_s: float = 1.0 / 30.0
@export var particle_max_update_delta_s: float = 0.1
@export_group("Managed Effect Pool")
@export var managed_effects_enabled: bool = true
@export var max_active_managed_effects: int = 512
@export var max_active_smoke: int = 384
@export var max_active_flashes: int = 96
@export var max_active_debris: int = 160
@export var max_active_blast_waves: int = 24
@export var max_pooled_per_kind: int = 192
@export var prewarm_explosion_flashes: int = 6
@export var prewarm_explosion_debris: int = 16
@export var prewarm_blast_waves: int = 2
@export var full_effect_distance_m: float = 650.0
@export var max_effect_distance_m: float = 1800.0
@export var distant_effect_stride: int = 2
@export var max_explosion_sounds_per_second: int = 10
@export var max_active_explosion_audio_players: int = 8
@export var max_pooled_explosion_audio_players: int = 8
@export var prewarm_explosion_audio_players: int = 2

var particles: Array = []
var _particle_update_accumulator_s: float = 0.0
var _managed_pools: Dictionary = {}
var _active_managed: Dictionary = {}
var _active_managed_counts: Dictionary = {}
var _shared_meshes: Dictionary = {}
var _managed_visual_sequence: int = 0
var _recent_explosion_sound_times_ms: Array[int] = []
var _active_explosion_audio: Dictionary = {}
var _explosion_audio_pool: Array[AudioStreamPlayer3D] = []
var managed_spawn_requests: int = 0
var managed_spawn_accepted: int = 0
var managed_spawn_rejected: int = 0
var managed_meshes_created: int = 0
var managed_meshes_reused: int = 0

func _ready():
	# Make this an autoload singleton
	set_process(false)
	_prewarm_managed_pool("explosion_flash", prewarm_explosion_flashes)
	_prewarm_managed_pool("debris_box", prewarm_explosion_debris)
	_prewarm_managed_pool("blast_wave", prewarm_blast_waves)
	for i in range(mini(maxi(prewarm_explosion_audio_players, 0), maxi(max_pooled_explosion_audio_players, 0))):
		var player: AudioStreamPlayer3D = _create_explosion_audio_player()
		player.visible = false
		_explosion_audio_pool.append(player)

func _process(delta):
	var _profiler_start: int = FrameProfiler.begin("ParticleManager.process")
	if particles.is_empty():
		_particle_update_accumulator_s = 0.0
		set_process(false)
		FrameProfiler.end("ParticleManager.process", _profiler_start)
		return

	_particle_update_accumulator_s += delta
	var update_interval := maxf(particle_update_interval_s, 0.001)
	if _particle_update_accumulator_s < update_interval:
		FrameProfiler.end("ParticleManager.process", _profiler_start)
		return

	var particle_delta := minf(_particle_update_accumulator_s, maxf(particle_max_update_delta_s, update_interval))
	_particle_update_accumulator_s = 0.0

	# Update all particles globally
	for i in range(particles.size() - 1, -1, -1):
		var particle = particles[i]
		if not is_instance_valid(particle.mesh_instance):
			var stale_id: int = int(particle.get("managed_instance_id", 0))
			if stale_id != 0:
				_forget_managed_instance(stale_id)
			particles.remove_at(i)
			continue
			
		particle.life_time += particle_delta
		
		# Apply particle behaviors based on type
		match particle.type:
			"smoke":
				_update_smoke_particle(particle, particle_delta)
			"explosion":
				_update_explosion_particle(particle, particle_delta)
			"spark":
				_update_spark_particle(particle, particle_delta)
			"outward_dust":
				_update_outward_dust_particle(particle, particle_delta)
			"explosion_flash":
				_update_explosion_flash(particle, particle_delta)
			"blast_wave":
				_update_blast_wave(particle, particle_delta)
			_:
				_update_default_particle(particle, particle_delta)
		
		# Remove expired particles
		if particle.life_time >= particle.max_life:
			if "on_finish" in particle and particle.on_finish is Callable and (particle.on_finish as Callable).is_valid():
				(particle.on_finish as Callable).call(particle.mesh_instance)
			else:
				particle.mesh_instance.queue_free()
			particles.remove_at(i)
	FrameProfiler.end("ParticleManager.process", _profiler_start)

func _update_smoke_particle(particle: Dictionary, delta: float):
	var life_progress: float = particle.life_time / particle.max_life

	# Rise upward
	if "rise_speed" in particle:
		particle.mesh_instance.global_position.y += particle.rise_speed * delta
		# Slow down rise over time
		particle.rise_speed *= (1.0 - delta * 0.3)

	# Expand uniformly over time
	if "expand" in particle and particle.expand:
		var expand_factor: float = 1.0 + life_progress * 1.2
		particle.mesh_instance.scale = particle.initial_scale * expand_factor
	else:
		var scale_factor = 1.0 - life_progress * 0.9
		particle.mesh_instance.scale = particle.initial_scale * scale_factor

	# Slow rotation
	if "yaw_speed" in particle:
		particle.mesh_instance.rotation.y += particle.yaw_speed * delta

	# Fade out — scale from initial alpha, not 1.0


	if particle.mesh_instance.material_override:
		if not "initial_alpha" in particle:
			particle.initial_alpha = particle.mesh_instance.material_override.albedo_color.a
		var fade: float = 1.0 - life_progress * life_progress  # Quadratic fade
		particle.mesh_instance.material_override.albedo_color.a = particle.initial_alpha * fade

func _update_explosion_particle(particle: Dictionary, delta: float):
	# Scale up quickly then fade
	var life_progress = particle.life_time / particle.max_life
	var scale_factor = 1.0 + life_progress * 2.0  # Grow to 3x size
	particle.mesh_instance.scale = particle.initial_scale * scale_factor

	# Fade out
	if particle.mesh_instance.material_override:
		var alpha = 1.0 - life_progress
		particle.mesh_instance.material_override.albedo_color.a = alpha

func _update_spark_particle(particle: Dictionary, delta: float):
	# Move with velocity and fade
	if "velocity" in particle:
		particle.mesh_instance.global_position += particle.velocity * delta
		# Apply gravity
		particle.velocity.y -= 9.8 * delta
	
	# Fade out
	var life_progress = particle.life_time / particle.max_life
	if particle.mesh_instance.material_override:
		var alpha = 1.0 - life_progress
		particle.mesh_instance.material_override.albedo_color.a = alpha

func _update_outward_dust_particle(particle: Dictionary, delta: float):
	var life_progress: float = particle.life_time / particle.max_life

	if "outward_velocity" in particle:
		particle.mesh_instance.global_position += particle.outward_velocity * delta
		# Air friction slows outward spread over time
		particle.outward_velocity *= (1.0 - delta * 1.5)

	if "rise_speed" in particle:
		particle.mesh_instance.global_position.y += particle.rise_speed * delta
		# Slow down rise over time
		particle.rise_speed *= (1.0 - delta * 0.5)

	if "expand" in particle and particle.expand:
		var expand_factor: float = 1.0 + life_progress * 2.0
		particle.mesh_instance.scale = particle.initial_scale * expand_factor

	if "yaw_speed" in particle:
		particle.mesh_instance.rotation.y += particle.yaw_speed * delta

	if particle.mesh_instance.material_override:
		if not "initial_alpha" in particle:
			particle.initial_alpha = particle.mesh_instance.material_override.albedo_color.a
		# Quadratic fade so it lingers slightly then fades
		var fade: float = 1.0 - (life_progress * life_progress)
		particle.mesh_instance.material_override.albedo_color.a = particle.initial_alpha * fade

func _update_default_particle(particle: Dictionary, delta: float):
	# Basic fade out
	var life_progress = particle.life_time / particle.max_life
	if particle.mesh_instance.material_override:
		var alpha = 1.0 - life_progress
		particle.mesh_instance.material_override.albedo_color.a = alpha

func _update_explosion_flash(particle: Dictionary, delta: float) -> void:
	var life_progress: float = clampf(particle.life_time / maxf(particle.max_life, 0.001), 0.0, 1.0)
	var growth: float = clampf(life_progress / 0.4, 0.0, 1.0)
	var target_scale: Vector3 = particle.get("target_scale", particle.initial_scale)
	particle.mesh_instance.scale = particle.initial_scale.lerp(target_scale, growth)
	particle.mesh_instance.rotation += particle.get("rotation_speed", Vector3.ZERO) * delta
	var material := particle.mesh_instance.material_override as StandardMaterial3D
	if material:
		var fade: float = 1.0 - life_progress * life_progress
		material.albedo_color.a = float(particle.get("initial_alpha", 0.8)) * fade
		material.emission_energy_multiplier = float(particle.get("initial_emission_energy", 6.0)) * fade

func _update_blast_wave(particle: Dictionary, _delta: float) -> void:
	var life_progress: float = clampf(particle.life_time / maxf(particle.max_life, 0.001), 0.0, 1.0)
	var target_scale: Vector3 = particle.get("target_scale", Vector3.ONE)
	particle.mesh_instance.scale = particle.initial_scale.lerp(target_scale, minf(life_progress * 3.0, 1.0))
	var material := particle.mesh_instance.material_override as StandardMaterial3D
	if material:
		var fade: float = 1.0 - life_progress
		material.albedo_color.a = float(particle.get("initial_alpha", 0.8)) * fade
		material.emission_energy_multiplier = float(particle.get("initial_emission_energy", 8.0)) * fade

func add_particle(mesh_instance: MeshInstance3D, type: String, max_life: float, initial_scale: Vector3, extra_data: Dictionary = {}):
	var particle_data = {
		"mesh_instance": mesh_instance,
		"type": type,
		"life_time": 0.0,
		"max_life": max_life,
		"initial_scale": initial_scale
	}
	
	# Add extra data for specific particle types
	for key in extra_data:
		particle_data[key] = extra_data[key]
	
	particles.append(particle_data)
	set_process(true)

# Convenience functions for common particle types
func add_smoke_particle(mesh_instance: MeshInstance3D, max_life: float, initial_scale: Vector3):
	add_particle(mesh_instance, "smoke", max_life, initial_scale)

func add_rising_smoke(mesh_instance: MeshInstance3D, max_life: float, initial_scale: Vector3, rise_speed: float = 5.0, yaw_speed: float = 0.0, extra_data: Dictionary = {}):
	var smoke_data := {
		"rise_speed": rise_speed,
		"expand": true,
		"yaw_speed": yaw_speed,
	}
	for key in extra_data:
		smoke_data[key] = extra_data[key]
	add_particle(mesh_instance, "smoke", max_life, initial_scale, smoke_data)

func add_explosion_particle(mesh_instance: MeshInstance3D, max_life: float, initial_scale: Vector3):
	add_particle(mesh_instance, "explosion", max_life, initial_scale)

func add_spark_particle(mesh_instance: MeshInstance3D, max_life: float, initial_scale: Vector3, velocity: Vector3, extra_data: Dictionary = {}):
	var spark_data := {"velocity": velocity}
	for key in extra_data:
		spark_data[key] = extra_data[key]
	add_particle(mesh_instance, "spark", max_life, initial_scale, spark_data)

func add_outward_dust(mesh_instance: MeshInstance3D, max_life: float, initial_scale: Vector3, outward_velocity: Vector3, rise_speed: float = 1.0, yaw_speed: float = 0.0, extra_data: Dictionary = {}):
	var dust_data := {
		"outward_velocity": outward_velocity,
		"rise_speed": rise_speed,
		"expand": true,
		"yaw_speed": yaw_speed,
	}
	for key in extra_data:
		dust_data[key] = extra_data[key]
	add_particle(mesh_instance, "outward_dust", max_life, initial_scale, dust_data)

func spawn_managed_smoke(
	world_position: Vector3,
	world_size: Vector3,
	color: Color,
	max_life: float,
	rise_speed: float = 0.0,
	yaw_speed: float = 0.0,
	expand: bool = false,
	shape_kind: String = "box",
	emission_energy: float = 0.0,
	important: bool = false
) -> bool:
	var pool_kind: String = "smoke_sphere" if shape_kind == "sphere" else "smoke_box"
	if not _can_spawn_managed(pool_kind, world_position, important):
		return false
	var puff: MeshInstance3D = _activate_managed_mesh(pool_kind, world_position)
	if puff == null:
		return false
	puff.scale = world_size
	puff.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_configure_managed_material(puff, color, emission_energy, 1.0)
	var finish_callback: Callable = Callable(self, "_release_managed_mesh").bind(pool_kind)
	add_rising_smoke(puff, maxf(max_life, 0.05), puff.scale, rise_speed, yaw_speed, {
		"expand": expand,
		"initial_alpha": color.a,
		"managed_instance_id": puff.get_instance_id(),
		"on_finish": finish_callback,
	})
	return true

func spawn_managed_debris(
	world_position: Vector3,
	size: Vector3,
	color: Color,
	velocity: Vector3,
	max_life: float,
	emission_energy: float = 0.0,
	important: bool = false
) -> bool:
	const POOL_KIND := "debris_box"
	if not _can_spawn_managed(POOL_KIND, world_position, important):
		return false
	var debris: MeshInstance3D = _activate_managed_mesh(POOL_KIND, world_position)
	if debris == null:
		return false
	debris.scale = size
	debris.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_configure_managed_material(debris, color, emission_energy, 0.9)
	var finish_callback: Callable = Callable(self, "_release_managed_mesh").bind(POOL_KIND)
	add_spark_particle(debris, maxf(max_life, 0.05), size, velocity, {
		"managed_instance_id": debris.get_instance_id(),
		"on_finish": finish_callback,
	})
	return true

func spawn_explosion_flash(
	world_position: Vector3,
	target_scale: Vector3,
	color: Color,
	emission_color: Color,
	duration: float,
	rotation_speed: Vector3,
	important: bool = false
) -> bool:
	const POOL_KIND := "explosion_flash"
	if not _can_spawn_managed(POOL_KIND, world_position, important):
		return false
	var flash: MeshInstance3D = _activate_managed_mesh(POOL_KIND, world_position)
	if flash == null:
		return false
	var initial_scale: Vector3 = target_scale * 0.1
	flash.scale = initial_scale
	flash.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_configure_managed_material(flash, color, 6.0, 0.3)
	var material := flash.material_override as StandardMaterial3D
	if material:
		material.emission = emission_color
	var finish_callback: Callable = Callable(self, "_release_managed_mesh").bind(POOL_KIND)
	add_particle(flash, "explosion_flash", maxf(duration, 0.05), initial_scale, {
		"target_scale": target_scale,
		"rotation_speed": rotation_speed,
		"initial_alpha": color.a,
		"initial_emission_energy": 6.0,
		"managed_instance_id": flash.get_instance_id(),
		"on_finish": finish_callback,
	})
	return true

func spawn_blast_wave(world_position: Vector3, radius_m: float, duration: float = 0.5, important: bool = false) -> bool:
	const POOL_KIND := "blast_wave"
	if not _can_spawn_managed(POOL_KIND, world_position, important):
		return false
	var ring: MeshInstance3D = _activate_managed_mesh(POOL_KIND, world_position)
	if ring == null:
		return false
	var initial_scale := Vector3.ONE * maxf(radius_m, 0.1) * 0.1
	var target_scale := Vector3(maxf(radius_m, 0.1), maxf(radius_m, 0.1) * 0.2, maxf(radius_m, 0.1))
	ring.scale = initial_scale
	_configure_managed_material(ring, Color(1.0, 0.5, 0.0, 0.8), 8.0, 0.2)
	var finish_callback: Callable = Callable(self, "_release_managed_mesh").bind(POOL_KIND)
	add_particle(ring, "blast_wave", maxf(duration, 0.05), initial_scale, {
		"target_scale": target_scale,
		"initial_alpha": 0.8,
		"initial_emission_energy": 8.0,
		"managed_instance_id": ring.get_instance_id(),
		"on_finish": finish_callback,
	})
	return true

func should_play_explosion_sound(world_position: Vector3) -> bool:
	var viewport := get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport else null
	if camera != null and is_instance_valid(camera) and max_effect_distance_m > 0.0:
		if camera.global_position.distance_to(world_position) > max_effect_distance_m * 1.5:
			return false
	var now_ms: int = Time.get_ticks_msec()
	while not _recent_explosion_sound_times_ms.is_empty() and now_ms - _recent_explosion_sound_times_ms[0] >= 1000:
		_recent_explosion_sound_times_ms.pop_front()
	if _recent_explosion_sound_times_ms.size() >= maxi(max_explosion_sounds_per_second, 0):
		return false
	_recent_explosion_sound_times_ms.append(now_ms)
	return true

func play_explosion_sound(stream: AudioStream, world_position: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	if stream == null or not should_play_explosion_sound(world_position):
		return false
	if _active_explosion_audio.size() >= maxi(max_active_explosion_audio_players, 0):
		return false
	var player: AudioStreamPlayer3D = _acquire_explosion_audio_player()
	player.global_position = world_position
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.visible = true
	_active_explosion_audio[player.get_instance_id()] = player
	player.play()
	return true

func get_managed_effect_stats() -> Dictionary:
	var pooled_total: int = 0
	for pool_variant in _managed_pools.values():
		if pool_variant is Array:
			pooled_total += (pool_variant as Array).size()
	return {
		"active": _active_managed.size(),
		"active_by_kind": _active_managed_counts.duplicate(),
		"pooled": pooled_total,
		"active_explosion_audio": _active_explosion_audio.size(),
		"pooled_explosion_audio": _explosion_audio_pool.size(),
		"spawn_requests": managed_spawn_requests,
		"spawn_accepted": managed_spawn_accepted,
		"spawn_rejected": managed_spawn_rejected,
		"meshes_created": managed_meshes_created,
		"meshes_reused": managed_meshes_reused,
	}

func _acquire_explosion_audio_player() -> AudioStreamPlayer3D:
	while not _explosion_audio_pool.is_empty():
		var candidate: AudioStreamPlayer3D = _explosion_audio_pool.pop_back()
		if is_instance_valid(candidate):
			return candidate
	return _create_explosion_audio_player()

func _create_explosion_audio_player() -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.max_distance = 800.0
	player.unit_size = 50.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.add_to_group("3d_audio")
	player.finished.connect(_release_explosion_audio_player.bind(player))
	add_child(player)
	return player

func _release_explosion_audio_player(player: AudioStreamPlayer3D) -> void:
	if player == null or not is_instance_valid(player):
		return
	_active_explosion_audio.erase(player.get_instance_id())
	player.stop()
	player.stream = null
	player.visible = false
	if player.get_parent() != self:
		player.reparent(self, false)
	if _explosion_audio_pool.size() < maxi(max_pooled_explosion_audio_players, 0):
		_explosion_audio_pool.append(player)
	else:
		player.queue_free()

func _can_spawn_managed(pool_kind: String, world_position: Vector3, important: bool) -> bool:
	managed_spawn_requests += 1
	if not managed_effects_enabled:
		managed_spawn_rejected += 1
		return false
	if _active_managed.size() >= maxi(max_active_managed_effects, 0):
		managed_spawn_rejected += 1
		return false
	var category: String = _managed_category(pool_kind)
	var category_cap: int = _managed_category_cap(category)
	if int(_active_managed_counts.get(category, 0)) >= category_cap:
		managed_spawn_rejected += 1
		return false
	if not _should_spawn_managed_visual(world_position, important):
		managed_spawn_rejected += 1
		return false
	managed_spawn_accepted += 1
	return true

func _should_spawn_managed_visual(world_position: Vector3, important: bool) -> bool:
	_managed_visual_sequence += 1
	var viewport := get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport else null
	if camera == null or not is_instance_valid(camera):
		return true
	var distance_m: float = camera.global_position.distance_to(world_position)
	var allowed_distance_m: float = max_effect_distance_m * (1.5 if important else 1.0)
	if allowed_distance_m > 0.0 and distance_m > allowed_distance_m:
		return false
	if not camera.is_position_in_frustum(world_position):
		return false
	if not important and distance_m > full_effect_distance_m and distant_effect_stride > 1:
		return (_managed_visual_sequence % distant_effect_stride) == 0
	return true

func _activate_managed_mesh(pool_kind: String, world_position: Vector3) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = _acquire_managed_mesh(pool_kind)
	var scene_root: Node = get_tree().current_scene
	if mesh_instance == null or scene_root == null:
		return null
	mesh_instance.reparent(scene_root, false)
	mesh_instance.global_position = world_position
	mesh_instance.visible = true
	var instance_id: int = mesh_instance.get_instance_id()
	var category: String = _managed_category(pool_kind)
	_active_managed[instance_id] = {"node": mesh_instance, "pool_kind": pool_kind, "category": category}
	_active_managed_counts[category] = int(_active_managed_counts.get(category, 0)) + 1
	return mesh_instance

func _acquire_managed_mesh(pool_kind: String) -> MeshInstance3D:
	var pool_variant: Variant = _managed_pools.get(pool_kind, [])
	var pool: Array = pool_variant if pool_variant is Array else []
	while not pool.is_empty():
		var candidate_variant: Variant = pool.pop_back()
		if typeof(candidate_variant) == TYPE_OBJECT and candidate_variant is MeshInstance3D and is_instance_valid(candidate_variant):
			_managed_pools[pool_kind] = pool
			managed_meshes_reused += 1
			return candidate_variant as MeshInstance3D
	_managed_pools[pool_kind] = pool
	return _create_managed_mesh(pool_kind)

func _create_managed_mesh(pool_kind: String) -> MeshInstance3D:
	managed_meshes_created += 1
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _get_shared_mesh(pool_kind)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	add_child(mesh_instance)
	return mesh_instance

func _prewarm_managed_pool(pool_kind: String, requested_count: int) -> void:
	var count: int = mini(maxi(requested_count, 0), maxi(max_pooled_per_kind, 0))
	if count <= 0:
		return
	var pool_variant: Variant = _managed_pools.get(pool_kind, [])
	var pool: Array = pool_variant if pool_variant is Array else []
	while pool.size() < count:
		var mesh_instance: MeshInstance3D = _create_managed_mesh(pool_kind)
		mesh_instance.visible = false
		pool.append(mesh_instance)
	_managed_pools[pool_kind] = pool

func _get_shared_mesh(pool_kind: String) -> Mesh:
	var cached_variant: Variant = _shared_meshes.get(pool_kind, null)
	if cached_variant is Mesh:
		return cached_variant as Mesh
	var mesh: Mesh
	if pool_kind == "smoke_sphere":
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 6
		sphere.rings = 4
		mesh = sphere
	elif pool_kind == "blast_wave":
		var torus := TorusMesh.new()
		torus.inner_radius = 0.8
		torus.outer_radius = 1.0
		mesh = torus
	else:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mesh = box
	_shared_meshes[pool_kind] = mesh
	return mesh

func _configure_managed_material(mesh_instance: MeshInstance3D, color: Color, emission_energy: float, roughness: float) -> void:
	var material := mesh_instance.material_override as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
		mesh_instance.material_override = material
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = emission_energy > 0.0
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = maxf(emission_energy, 0.0)
	material.roughness = roughness

func _release_managed_mesh(mesh_instance: MeshInstance3D, pool_kind: String) -> void:
	if mesh_instance == null or not is_instance_valid(mesh_instance):
		return
	_forget_managed_instance(mesh_instance.get_instance_id())
	mesh_instance.visible = false
	mesh_instance.scale = Vector3.ONE
	mesh_instance.rotation = Vector3.ZERO
	if mesh_instance.get_parent() != self:
		mesh_instance.reparent(self, false)
	var pool_variant: Variant = _managed_pools.get(pool_kind, [])
	var pool: Array = pool_variant if pool_variant is Array else []
	if pool.size() < maxi(max_pooled_per_kind, 0):
		pool.append(mesh_instance)
		_managed_pools[pool_kind] = pool
	else:
		mesh_instance.queue_free()

func _forget_managed_instance(instance_id: int) -> void:
	var entry_variant: Variant = _active_managed.get(instance_id, null)
	if entry_variant is Dictionary:
		var category: String = str((entry_variant as Dictionary).get("category", "other"))
		_active_managed_counts[category] = maxi(int(_active_managed_counts.get(category, 1)) - 1, 0)
	_active_managed.erase(instance_id)

func _managed_category(pool_kind: String) -> String:
	if pool_kind.begins_with("smoke_"):
		return "smoke"
	if pool_kind == "explosion_flash":
		return "flash"
	if pool_kind == "debris_box":
		return "debris"
	if pool_kind == "blast_wave":
		return "blast_wave"
	return "other"

func _managed_category_cap(category: String) -> int:
	match category:
		"smoke":
			return maxi(max_active_smoke, 0)
		"flash":
			return maxi(max_active_flashes, 0)
		"debris":
			return maxi(max_active_debris, 0)
		"blast_wave":
			return maxi(max_active_blast_waves, 0)
		_:
			return maxi(max_active_managed_effects, 0)
