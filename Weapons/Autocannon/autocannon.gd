extends Weapon
class_name Autocannon

const HELI_TEST_UNLIMITED_AMMO_META := "heli_test_unlimited_ammo"

const PROJECTILE_SPEED_CAP_SETTING_KEYS: Array = [
	"physics/jolt_3d/simulation/limits/max_linear_velocity",
	"physics/jolt_physics_3d/simulation/limits/max_linear_velocity",
	"physics/jolt_3d/limits/max_linear_velocity",
	"physics/jolt_physics_3d/limits/max_linear_velocity",
	"physics/3d/max_linear_velocity",
]

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
const LMG_SHOT_STREAMS = [
	preload("res://Audio/guns/gun_lmg_1.wav"),
	preload("res://Audio/guns/gun_lmg_2.wav"),
	preload("res://Audio/guns/gun_lmg_3.wav"),
	preload("res://Audio/guns/gun_lmg_4.wav"),
	preload("res://Audio/guns/gun_lmg_5.wav"),
	preload("res://Audio/guns/gun_lmg_6.wav"),
	preload("res://Audio/guns/gun_lmg_7.wav"),
	preload("res://Audio/guns/gun_lmg_8.wav"),
	preload("res://Audio/guns/gun_lmg_9.wav"),
]
const AUTOCANNON_SHOT_STREAMS = [
	preload("res://Audio/guns/autocannon_1.wav"),
	preload("res://Audio/guns/autocannon_2.wav"),
	preload("res://Audio/guns/autocannon_3.wav"),
	preload("res://Audio/guns/autocannon_4.wav"),
]

@export var gun_profile: GunProfile
@export var bullet_projectile_scene: PackedScene
@export var rounds_per_minute: float = 600.0  # Rate of fire
@export var muzzle_velocity: float = 500.0   # Bullet speed
@export var spread_angle: float = 1.0         # Degrees of inaccuracy
@export var recoil_force: float = 1000.0
@export var damage_per_shot: float = 20.0
@export var max_range_m: float = 900.0
@export var cockpit_judder_shake_intensity: float = 0.4
@export var cockpit_judder_shake_duration_s: float = 0.06
@export var cannon_sound: AudioStream
@export var use_lmg_sound_set: bool = false
@export var use_autocannon_sound_set: bool = false
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
var _projectile_speed_cap_cached: bool = false
var _projectile_speed_cap_mps: float = INF
var _bullet_spawn_point: Node3D = null
var _tuning_shot_callback: Callable = Callable()
var _tuning_report_callback: Callable = Callable()
var _tuning_trial_id: int = -1
var _tuning_target: Node3D = null

func _ready():
	_apply_gun_profile()
	delete_when_empty = false  # Don't auto-remove when empty
	ammo_count = 1000  # Large gun ammo pool for sustained air combat
	hardpoint = get_parent() as Hardpoint
	automatic_fire = true
	weapon_category = "Guns"
	if weapon_name.is_empty() or weapon_name == "Generic Weapon":
		weapon_name = "Autocannon"
	if bullet_projectile_scene == null:
		bullet_projectile_scene = load("res://Projectiles/Bullet/bullet.tscn")
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

func _has_unlimited_test_ammo() -> bool:
	var aircraft: RigidBody3D = hardpoint.aircraft if hardpoint else null
	return is_instance_valid(aircraft) and bool(aircraft.get_meta(HELI_TEST_UNLIMITED_AMMO_META, false))

func can_fire() -> bool:
	return _has_unlimited_test_ammo() or ammo_count > 0

func set_tuning_context(
		shot_callback: Callable = Callable(),
		report_callback: Callable = Callable(),
		trial_id: int = -1,
		target: Node3D = null
) -> void:
	_tuning_shot_callback = shot_callback
	_tuning_report_callback = report_callback
	_tuning_trial_id = trial_id
	_tuning_target = target

func fire() -> bool:
	if not can_fire() or fire_timer > 0:
		return false

	var seconds_per_round := 60.0 / rounds_per_minute
	fire_timer = seconds_per_round

	_play_cannon_sound()

	var bullet = bullet_projectile_scene.instantiate()
	var spawn_transform: Transform3D = _get_bullet_spawn_transform()
	bullet.transform = spawn_transform

	var spread := Vector3(
		randf_range(-spread_angle, spread_angle),
		randf_range(-spread_angle, spread_angle),
		0
	)
	bullet.rotate_object_local(Vector3.RIGHT, deg_to_rad(spread.x))
	bullet.rotate_object_local(Vector3.UP, deg_to_rad(spread.y))
	_configure_projectile_instance(bullet)
	var projectile_transform: Transform3D = bullet.transform
	get_tree().current_scene.add_child(bullet)
	bullet.global_transform = projectile_transform

	var aircraft = hardpoint.aircraft if hardpoint else null
	var muzzle_vel = bullet.global_transform.basis.z.normalized() * muzzle_velocity
	_configure_tuning_bullet_metadata(bullet)
	if _tuning_shot_callback.is_valid():
		_tuning_shot_callback.call(_tuning_trial_id, bullet)
	bullet.fire(muzzle_vel, aircraft)

	if hardpoint:
		hardpoint.apply_recoil_force(get_recoil_force(), false)
	_apply_cockpit_judder(aircraft)

	if not _has_unlimited_test_ammo():
		ammo_count -= 1
	return true

func _configure_tuning_bullet_metadata(bullet: Node) -> void:
	if bullet == null or not is_instance_valid(bullet):
		return
	if _tuning_report_callback.is_valid():
		bullet.set_meta("debug_report_callback", _tuning_report_callback)
	if _tuning_target != null and is_instance_valid(_tuning_target):
		bullet.set_meta("debug_target_node", _tuning_target)
		var range_m: float = bullet.global_position.distance_to(_tuning_target.global_position)
		bullet.set_meta("debug_nominal_flight_time_s", range_m / maxf(muzzle_velocity, 50.0))
	bullet.set_meta("debug_nominal_bullet_speed_mps", muzzle_velocity)

func _get_bullet_spawn_transform() -> Transform3D:
	var spawn_point := _get_bullet_spawn_point()
	if spawn_point != null and is_instance_valid(spawn_point):
		return spawn_point.global_transform
	return global_transform

func _get_bullet_spawn_point() -> Node3D:
	if _bullet_spawn_point != null and is_instance_valid(_bullet_spawn_point):
		return _bullet_spawn_point
	var found := find_child("BulletSpawnPoint", true, false) as Node3D
	if found != null:
		_bullet_spawn_point = found
	return _bullet_spawn_point

func _apply_gun_profile() -> void:
	if gun_profile == null:
		return
	if not gun_profile.weapon_name.is_empty():
		weapon_name = gun_profile.weapon_name
	rounds_per_minute = maxf(gun_profile.rounds_per_minute, 1.0)
	muzzle_velocity = maxf(gun_profile.muzzle_velocity_mps, 50.0)
	spread_angle = maxf(gun_profile.spread_angle_deg, 0.0)
	recoil_force = maxf(gun_profile.recoil_force, 0.0)
	damage_per_shot = maxf(gun_profile.damage_per_shot, 0.0)
	max_range_m = maxf(gun_profile.max_range_m, 10.0)
	use_lmg_sound_set = gun_profile.use_lmg_sound_set
	use_autocannon_sound_set = gun_profile.use_autocannon_sound_set
	use_heavy_auto_sound_set = gun_profile.use_heavy_auto_sound_set
	if gun_profile.projectile_scene != null:
		bullet_projectile_scene = gun_profile.projectile_scene

func _configure_projectile_instance(projectile: Node) -> void:
	if projectile == null or not is_instance_valid(projectile):
		return
	if "damage_amount" in projectile:
		projectile.damage_amount = damage_per_shot
	if "damage" in projectile:
		projectile.damage = damage_per_shot
	if "lifetime" in projectile:
		var effective_speed_mps: float = _get_effective_projectile_speed_mps()
		projectile.lifetime = maxf(max_range_m / maxf(effective_speed_mps, 1.0), 0.05)

func _get_effective_projectile_speed_mps() -> float:
	var nominal_speed_mps: float = maxf(muzzle_velocity, 50.0)
	var speed_cap_mps: float = _get_projectile_linear_speed_cap_mps()
	if is_finite(speed_cap_mps):
		return maxf(minf(nominal_speed_mps, speed_cap_mps), 50.0)
	return nominal_speed_mps

func _get_projectile_linear_speed_cap_mps() -> float:
	if _projectile_speed_cap_cached:
		return _projectile_speed_cap_mps
	_projectile_speed_cap_cached = true
	_projectile_speed_cap_mps = INF
	for key_variant in PROJECTILE_SPEED_CAP_SETTING_KEYS:
		var key: String = str(key_variant)
		if not ProjectSettings.has_setting(key):
			continue
		var cap_variant: Variant = ProjectSettings.get_setting(key)
		if typeof(cap_variant) in [TYPE_FLOAT, TYPE_INT]:
			var cap_mps: float = float(cap_variant)
			if cap_mps > 0.0:
				_projectile_speed_cap_mps = cap_mps
				break
	return _projectile_speed_cap_mps

func _apply_cockpit_judder(aircraft_body: RigidBody3D) -> void:
	if aircraft_body == null or not is_instance_valid(aircraft_body):
		return
	if not aircraft_body.has_method("add_shake"):
		return
	var shake_amount: float = maxf(cockpit_judder_shake_intensity, 0.0) * randf_range(0.9, 1.1)
	aircraft_body.add_shake(shake_amount, maxf(cockpit_judder_shake_duration_s, 0.01))

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
	if use_lmg_sound_set and not LMG_SHOT_STREAMS.is_empty():
		return LMG_SHOT_STREAMS
	if use_autocannon_sound_set and not AUTOCANNON_SHOT_STREAMS.is_empty():
		return AUTOCANNON_SHOT_STREAMS
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
