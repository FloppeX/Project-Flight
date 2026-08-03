extends Node

# Impact presentation is intentionally bounded. Damage and hit resolution happen
# before these methods are called and are never sampled or discarded here.
@export var max_active_decals: int = 160
@export var max_pooled_decals: int = 160
@export var max_active_debris: int = 96
@export var max_debris_pool: int = 96
@export var full_effect_distance_m: float = 500.0
@export var max_effect_distance_m: float = 1200.0
@export var distant_effect_stride: int = 2
@export var max_impact_sounds_per_second: int = 24
@export var max_active_impact_audio_players: int = 12
@export var max_pooled_impact_audio_players: int = 12
@export var decal_service_interval_s: float = 0.25

var _decals: Array[Dictionary] = []
var _active_debris: Dictionary = {}
var _debris_pool: Array[MeshInstance3D] = []
var _decal_pool: Array[Decal] = []
var _visual_sequence: int = 0
var _recent_sound_times_ms: Array[int] = []
var _active_audio_players: Dictionary = {}
var _audio_player_pool: Array[AudioStreamPlayer3D] = []
var _unit_box_mesh: BoxMesh
var _decal_service_accum_s: float = 0.0

func _ready() -> void:
	_unit_box_mesh = BoxMesh.new()
	_unit_box_mesh.size = Vector3.ONE
	set_process(true)

func _process(delta: float) -> void:
	_decal_service_accum_s += delta
	if _decal_service_accum_s < maxf(decal_service_interval_s, 0.01):
		return
	var service_delta_s: float = _decal_service_accum_s
	_decal_service_accum_s = 0.0
	for i in range(_decals.size() - 1, -1, -1):
		var entry: Dictionary = _decals[i]
		var node_variant: Variant = entry.get("node", null)
		if typeof(node_variant) != TYPE_OBJECT or not is_instance_valid(node_variant):
			_decals.remove_at(i)
			continue
		var remaining_s: float = float(entry.get("remaining_s", -1.0))
		if remaining_s > 0.0:
			remaining_s -= service_delta_s
			entry["remaining_s"] = remaining_s
			_decals[i] = entry
		if remaining_s != -1.0 and remaining_s <= 0.0:
			_discard_decal(node_variant as Decal)
			_decals.remove_at(i)
	_enforce_decal_cap()

func should_spawn_visual(world_position: Vector3) -> bool:
	_visual_sequence += 1
	var viewport := get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport else null
	if camera == null or not is_instance_valid(camera):
		return true
	var distance_m: float = camera.global_position.distance_to(world_position)
	if max_effect_distance_m > 0.0 and distance_m > max_effect_distance_m:
		return false
	if not camera.is_position_in_frustum(world_position):
		return false
	if distance_m > full_effect_distance_m and distant_effect_stride > 1:
		return (_visual_sequence % distant_effect_stride) == 0
	return true

func register_decal(decal: Decal, lifetime_s: float) -> void:
	if decal == null or not is_instance_valid(decal):
		return
	_decals.append({"node": decal, "remaining_s": lifetime_s if lifetime_s > 0.0 else -1.0})
	_enforce_decal_cap()

func acquire_decal(parent_node: Node) -> Decal:
	var decal: Decal = null
	while not _decal_pool.is_empty() and decal == null:
		var candidate: Decal = _decal_pool.pop_back()
		if is_instance_valid(candidate):
			decal = candidate
	if decal == null:
		decal = Decal.new()
		add_child(decal)
	if parent_node and is_instance_valid(parent_node):
		decal.reparent(parent_node, false)
	decal.visible = true
	decal.set_meta(&"_bullet_impact_poolable_decal", true)
	return decal

func spawn_debris(world_position: Vector3, size: Vector3, color: Color, metallic: float, roughness: float, velocity: Vector3, lifetime_s: float) -> bool:
	if _active_debris.size() >= max(max_active_debris, 0):
		return false
	if not should_spawn_visual(world_position):
		return false
	var debris: MeshInstance3D = _acquire_debris()
	var scene: Node = get_tree().current_scene
	if scene == null:
		_release_debris(debris)
		return false
	debris.reparent(scene, false)
	debris.global_position = world_position
	debris.scale = size
	debris.visible = true
	var material: StandardMaterial3D = debris.material_override as StandardMaterial3D
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	_active_debris[debris.get_instance_id()] = debris
	var particle_manager: Node = get_node_or_null("/root/ParticleManager")
	if particle_manager == null:
		_release_debris(debris)
		return false
	particle_manager.call("add_spark_particle", debris, lifetime_s, size, velocity, {"on_finish": Callable(self, "_release_debris")})
	return true

func should_play_impact_sound(world_position: Vector3) -> bool:
	if not should_spawn_visual(world_position):
		return false
	var now_ms: int = Time.get_ticks_msec()
	while not _recent_sound_times_ms.is_empty() and now_ms - _recent_sound_times_ms[0] >= 1000:
		_recent_sound_times_ms.pop_front()
	if _recent_sound_times_ms.size() >= max(max_impact_sounds_per_second, 0):
		return false
	_recent_sound_times_ms.append(now_ms)
	return true

func play_impact_sound(stream: AudioStream, world_position: Vector3, volume_db: float = -5.0, pitch_scale: float = 1.0) -> bool:
	if stream == null or not should_play_impact_sound(world_position):
		return false
	if _active_audio_players.size() >= maxi(max_active_impact_audio_players, 0):
		return false
	var player: AudioStreamPlayer3D = _acquire_audio_player()
	player.global_position = world_position
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.visible = true
	_active_audio_players[player.get_instance_id()] = player
	player.play()
	return true

func _acquire_debris() -> MeshInstance3D:
	var debris: MeshInstance3D = null
	while not _debris_pool.is_empty() and debris == null:
		var candidate: MeshInstance3D = _debris_pool.pop_back()
		if is_instance_valid(candidate):
			debris = candidate
	if debris == null:
		debris = MeshInstance3D.new()
		debris.mesh = _unit_box_mesh
		var material := StandardMaterial3D.new()
		debris.material_override = material
		add_child(debris)
	return debris

func _acquire_audio_player() -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D = null
	while not _audio_player_pool.is_empty() and player == null:
		var candidate: AudioStreamPlayer3D = _audio_player_pool.pop_back()
		if is_instance_valid(candidate):
			player = candidate
	if player == null:
		player = AudioStreamPlayer3D.new()
		player.max_distance = 1400.0
		player.unit_size = 30.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.add_to_group("3d_audio")
		player.finished.connect(_release_audio_player.bind(player))
		add_child(player)
	return player

func _release_audio_player(player: AudioStreamPlayer3D) -> void:
	if player == null or not is_instance_valid(player):
		return
	_active_audio_players.erase(player.get_instance_id())
	player.stop()
	player.stream = null
	player.visible = false
	if player.get_parent() != self:
		player.reparent(self, false)
	if _audio_player_pool.size() < maxi(max_pooled_impact_audio_players, 0):
		_audio_player_pool.append(player)
	else:
		player.queue_free()

func _release_debris(debris: MeshInstance3D) -> void:
	if debris == null or not is_instance_valid(debris):
		return
	_active_debris.erase(debris.get_instance_id())
	debris.visible = false
	debris.scale = Vector3.ONE
	if debris.get_parent() != self:
		debris.reparent(self, false)
	if _debris_pool.size() < max(max_debris_pool, 0):
		_debris_pool.append(debris)
	else:
		debris.queue_free()

func _enforce_decal_cap() -> void:
	while _decals.size() > max(max_active_decals, 0):
		var oldest: Dictionary = _decals.pop_front()
		var node_variant: Variant = oldest.get("node", null)
		if typeof(node_variant) == TYPE_OBJECT and node_variant is Decal and is_instance_valid(node_variant):
			_discard_decal(node_variant as Decal)

func _discard_decal(decal: Decal) -> void:
	if decal == null or not is_instance_valid(decal):
		return
	if not bool(decal.get_meta(&"_bullet_impact_poolable_decal", false)) or _decal_pool.size() >= max(max_pooled_decals, 0):
		decal.queue_free()
		return
	decal.visible = false
	decal.texture_albedo = null
	decal.modulate = Color.WHITE
	decal.size = Vector3(10.0, 10.0, 10.0)
	decal.reparent(self, false)
	_decal_pool.append(decal)

func get_stats() -> Dictionary:
	return {
		"active_decals": _decals.size(),
		"active_debris": _active_debris.size(),
		"pooled_debris": _debris_pool.size(),
		"pooled_decals": _decal_pool.size(),
		"active_impact_audio": _active_audio_players.size(),
		"pooled_impact_audio": _audio_player_pool.size(),
	}
