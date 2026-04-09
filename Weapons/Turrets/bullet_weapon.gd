extends Weapon
class_name BulletWeapon

const HEAVY_AUTO_SHOT_STREAMS = [
	preload("res://Audio/guns/gun_machinegun_auto_heavy_shot_01.wav"),
	preload("res://Audio/guns/gun_machinegun_auto_heavy_shot_02.wav"),
	preload("res://Audio/guns/gun_machinegun_auto_heavy_shot_03.wav"),
	preload("res://Audio/guns/gun_machinegun_auto_heavy_shot_04.wav"),
	preload("res://Audio/guns/gun_machinegun_auto_heavy_shot_05.wav"),
	preload("res://Audio/guns/gun_machinegun_auto_heavy_shot_06.wav"),
	preload("res://Audio/guns/gun_machinegun_auto_heavy_shot_07.wav"),
	preload("res://Audio/guns/gun_machinegun_auto_heavy_shot_08.wav"),
]

@export var bullet_scene: PackedScene
@export var bullet_speed: float = 900.0
@export var fire_rate: float = 2.5 # Shots per second
@export var damage_per_shot: float = 20.0
@export var infinite_ammo: bool = true
@export var use_heavy_auto_sound_set: bool = true
@export var sfx_pool_size: int = 4
@export var pitch_variation: float = 0.03
@export var volume_variation_db: float = 1.5

var _sfx_players: Array[AudioStreamPlayer3D] = []
var _sfx_player_index: int = 0
var _last_shot_sound_index: int = -1

func _ready() -> void:
	if not bullet_scene:
		bullet_scene = load("res://Projectiles/Bullet/bullet.tscn")
	_setup_shot_audio()

func fire() -> bool:
	if not can_fire():
		return false
	var now_s: float = Time.get_ticks_msec() / 1000.0
	var cooldown_s: float = 1.0 / maxf(fire_rate, 0.01)
	var next_fire_time_s: float = float(get_meta("next_fire_time_s", 0.0))
	if now_s < float(next_fire_time_s):
		return false

	set_meta("next_fire_time_s", now_s + cooldown_s)

	# Turret weapons default to sustained fire instead of running dry after a short exchange.
	super.fire()
	if infinite_ammo:
		ammo_count += 1

	var spawn_transform = global_transform
	var firing_entity: Node3D = self
	var parent = get_parent()

	while parent:
		if parent is Turret:
			var turret_parent: Turret = parent as Turret
			spawn_transform = turret_parent.get_next_firing_transform()
			firing_entity = _resolve_firing_entity_from_turret(turret_parent)
			break
		elif parent is Node3D and parent.has_method("get_team"):
			firing_entity = parent as Node3D
			break
		parent = parent.get_parent()

	_spawn_bullet(spawn_transform, firing_entity)
	_play_shot_sound(spawn_transform.origin)
	return true

func _resolve_firing_entity_from_turret(turret_node: Turret) -> Node3D:
	if turret_node == null or not is_instance_valid(turret_node):
		return self

	var controller_node: Node = turret_node.get_parent()
	if controller_node and is_instance_valid(controller_node):
		var host_candidate: Variant = controller_node.get("host_actor")
		if host_candidate is Node3D and is_instance_valid(host_candidate) and (host_candidate as Node3D).has_method("get_team"):
			return host_candidate as Node3D

	var ancestor: Node = turret_node
	while ancestor:
		if ancestor is Node3D and ancestor.has_method("get_team"):
			return ancestor as Node3D
		ancestor = ancestor.get_parent()

	return turret_node

func can_fire() -> bool:
	if infinite_ammo:
		return true
	return super.can_fire()

func _spawn_bullet(spawn_transform: Transform3D, firing_entity: Node3D) -> void:
	if not bullet_scene:
		return

	var bullet = bullet_scene.instantiate()

	var root = get_tree().current_scene
	if not root:
		push_warning("BulletWeapon: No current scene found.")
		return

	bullet.transform = spawn_transform
	root.add_child(bullet)
	bullet.global_position += bullet.global_transform.basis.z * 2.5

	var direction = spawn_transform.basis.z.normalized()
	var velocity = direction * bullet_speed

	if bullet.has_method("fire"):
		bullet.fire(velocity, firing_entity)

	if bullet is RigidBody3D and bullet.linear_velocity.length() > 1.0:
		var vel_dir: Vector3 = bullet.linear_velocity.normalized()
		var up := Vector3.UP
		var right := up.cross(vel_dir).normalized()
		if right.length_squared() > 0.0001:
			up = vel_dir.cross(right).normalized()
			bullet.global_transform.basis = Basis(right, up, vel_dir)

	if "damage_amount" in bullet:
		bullet.damage_amount = damage_per_shot

func _setup_shot_audio() -> void:
	var sound_bank: Array = _get_shot_sound_bank()
	if sound_bank.is_empty():
		return

	for i in range(max(sfx_pool_size, 1)):
		var player := AudioStreamPlayer3D.new()
		add_child(player)
		player.max_distance = 1000.0
		player.unit_size = 18.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		player.add_to_group("3d_audio")
		_sfx_players.push_back(player)

func _play_shot_sound(world_pos: Vector3) -> void:
	if _sfx_players.is_empty():
		return

	var stream: AudioStream = _pick_random_shot_sound()
	if stream == null:
		return

	var player: AudioStreamPlayer3D = _sfx_players[_sfx_player_index]
	_sfx_player_index = (_sfx_player_index + 1) % _sfx_players.size()
	player.stream = stream
	player.global_position = world_pos
	player.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	player.volume_db = randf_range(-volume_variation_db, volume_variation_db)
	player.play()

func _get_shot_sound_bank() -> Array:
	if use_heavy_auto_sound_set:
		return HEAVY_AUTO_SHOT_STREAMS
	return []

func _pick_random_shot_sound() -> AudioStream:
	var sound_bank: Array = _get_shot_sound_bank()
	if sound_bank.is_empty():
		return null

	var index: int = randi_range(0, sound_bank.size() - 1)
	if sound_bank.size() > 1 and index == _last_shot_sound_index:
		index = (index + 1 + (randi() % (sound_bank.size() - 1))) % sound_bank.size()
	_last_shot_sound_index = index
	return sound_bank[index] as AudioStream
