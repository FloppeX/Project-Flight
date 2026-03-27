extends Weapon
class_name Autocannon

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

@export var bullet_projectile_scene: PackedScene
@export var rounds_per_minute: float = 400.0  # Rate of fire
@export var muzzle_velocity: float = 1200.0   # Bullet speed
@export var spread_angle: float = 1.0         # Degrees of inaccuracy
@export var recoil_force: float = 1000.0
@export var cannon_sound: AudioStream
@export var use_heavy_auto_sound_set: bool = true
@export var sfx_pool_size: int = 8
@export var pitch_variation: float = 0.05
@export var volume_variation: float = 0.5

var hardpoint: Hardpoint
var fire_timer: float = 0.0
var is_firing: bool = false
var sfx_cannon_players: Array[AudioStreamPlayer3D] = []
var _sfx_player_index: int = 0
var _last_shot_sound_index: int = -1

func _ready():
	delete_when_empty = false  # Don't auto-remove when empty
	ammo_count = 1000  # Large gun ammo pool for sustained air combat
	hardpoint = get_parent() as Hardpoint
	automatic_fire = true
	weapon_name = "Autocannon"
	_setup_cannon_audio()

func _process(delta):
	if fire_timer > 0:
		fire_timer -= delta

func start_firing():
	is_firing = true

func stop_firing():
	is_firing = false

func get_recoil_force() -> float:
	return recoil_force

func fire() -> bool:
	if not can_fire() or fire_timer > 0:
		return false

	var seconds_per_round := 60.0 / rounds_per_minute
	fire_timer = seconds_per_round

	_play_cannon_sound()

	var bullet = bullet_projectile_scene.instantiate()
	# Set transform BEFORE adding to tree so first-frame visuals don't flash at the origin
	bullet.position = global_position
	bullet.rotation = global_rotation
	get_tree().current_scene.add_child(bullet)

	var spread := Vector3(
		randf_range(-spread_angle, spread_angle),
		randf_range(-spread_angle, spread_angle),
		0
	)
	bullet.rotate_object_local(Vector3.RIGHT, deg_to_rad(spread.x))
	bullet.rotate_object_local(Vector3.UP, deg_to_rad(spread.y))

	var aircraft = hardpoint.aircraft
	var muzzle_vel = hardpoint.get_hardpoint_forward_direction() * muzzle_velocity
	bullet.fire(muzzle_vel, aircraft)

	hardpoint.apply_recoil_force(get_recoil_force())

	ammo_count -= 1
	return true

func _setup_cannon_audio() -> void:
	var sound_bank: Array = _get_shot_sound_bank()
	if sound_bank.is_empty():
		return

	for i in range(max(sfx_pool_size, 1)):
		var player := AudioStreamPlayer3D.new()
		add_child(player)
		player.max_distance = 1000.0
		player.unit_size = 25.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		player.add_to_group("3d_audio")
		sfx_cannon_players.push_back(player)

func _play_cannon_sound() -> void:
	if sfx_cannon_players.is_empty():
		return

	var stream: AudioStream = _pick_random_shot_sound()
	if stream == null:
		return

	var player: AudioStreamPlayer3D = sfx_cannon_players[_sfx_player_index]
	_sfx_player_index = (_sfx_player_index + 1) % sfx_cannon_players.size()
	player.stream = stream
	player.global_position = global_position
	player.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	player.volume_db = randf_range(-volume_variation, volume_variation)
	player.play()

func _get_shot_sound_bank() -> Array:
	if use_heavy_auto_sound_set and not HEAVY_AUTO_SHOT_STREAMS.is_empty():
		return HEAVY_AUTO_SHOT_STREAMS
	if cannon_sound:
		return [cannon_sound]
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
