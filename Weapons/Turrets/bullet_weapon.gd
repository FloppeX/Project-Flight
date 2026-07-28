extends Weapon
class_name BulletWeapon

const PROJECTILE_SPEED_CAP_SETTING_KEYS: Array = [
	"physics/jolt_3d/simulation/limits/max_linear_velocity",
	"physics/jolt_physics_3d/simulation/limits/max_linear_velocity",
	"physics/jolt_3d/limits/max_linear_velocity",
	"physics/jolt_physics_3d/limits/max_linear_velocity",
	"physics/3d/max_linear_velocity",
]

const DEBUG_TARGET_META_KEY: StringName = &"debug_target_node"
const DEBUG_REPORT_CALLBACK_META_KEY: StringName = &"debug_report_callback"
const DEBUG_NOMINAL_FLIGHT_TIME_META_KEY: StringName = &"debug_nominal_flight_time_s"

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
@export var bullet_scene: PackedScene
@export var bullet_speed: float = 500.0
@export var muzzle_velocity: float = 500.0
@export var fire_rate: float = 2.5 # Shots per second
@export var damage_per_shot: float = 20.0
@export var spread_angle: float = 1.0
@export var recoil_force: float = 1000.0
@export var max_range_m: float = 500.0
@export var infinite_ammo: bool = true
@export var turret_fire_rate_multiplier: float = 0.5
@export var host_recoil_enabled: bool = false
@export var host_recoil_impulse_scale: float = 0.001
@export var host_recoil_speed_cap_mps: float = 4.0
@export var use_lmg_sound_set: bool = false
@export var use_autocannon_sound_set: bool = false
@export var use_heavy_auto_sound_set: bool = true
@export var sfx_pool_size: int = 4
@export var pitch_variation: float = 0.03
@export var volume_variation_db: float = 1.5

var _sfx_players: Array[AudioStreamPlayer3D] = []
var _sfx_player_index: int = 0
var _last_shot_sound_index: int = -1
var last_fired_projectile: Node = null
var _projectile_speed_cap_cached: bool = false
var _projectile_speed_cap_mps: float = INF
var _bullet_spawn_point: Node3D = null

func _ready() -> void:
	_apply_gun_profile()
	automatic_fire = true
	muzzle_velocity = maxf(bullet_speed, 50.0)
	if weapon_name.is_empty() or weapon_name == "Generic Weapon":
		weapon_name = "Turret Gun"
	if not bullet_scene:
		bullet_scene = load("res://Projectiles/Bullet/bullet.tscn")
	_setup_shot_audio()
	if _is_mounted_in_turret():
		fire_rate *= maxf(turret_fire_rate_multiplier, 0.0)


func _is_mounted_in_turret() -> bool:
	var node: Node = get_parent()
	while node:
		if node is Turret:
			return true
		node = node.get_parent()
	return false

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

	spawn_transform = _get_bullet_spawn_transform(spawn_transform)
	_spawn_bullet(spawn_transform, firing_entity)
	var mounted_hardpoint: Hardpoint = _find_parent_hardpoint()
	if mounted_hardpoint != null and is_instance_valid(mounted_hardpoint):
		mounted_hardpoint.apply_recoil_force(recoil_force, false)
	else:
		_apply_host_recoil(spawn_transform, firing_entity)
	_play_shot_sound(spawn_transform.origin)
	return true

func _apply_host_recoil(spawn_transform: Transform3D, firing_entity: Node3D) -> void:
	if not host_recoil_enabled:
		return
	if firing_entity == null or not is_instance_valid(firing_entity):
		return
	var recoil_direction: Vector3 = -spawn_transform.basis.z.normalized()
	if recoil_direction.length_squared() <= 0.0001:
		return
	var recoil_impulse: Vector3 = recoil_direction * recoil_force * maxf(host_recoil_impulse_scale, 0.0)
	if firing_entity is RigidBody3D:
		(firing_entity as RigidBody3D).apply_central_impulse(recoil_impulse)
	elif firing_entity is CharacterBody3D:
		var character_body := firing_entity as CharacterBody3D
		var planar_impulse := Vector3(recoil_impulse.x, 0.0, recoil_impulse.z)
		if planar_impulse.length_squared() <= 0.0001:
			return
		character_body.velocity += planar_impulse.limit_length(maxf(host_recoil_speed_cap_mps, 0.0))

func _get_bullet_spawn_transform(fallback_transform: Transform3D) -> Transform3D:
	var spawn_point := _get_bullet_spawn_point()
	if spawn_point != null and is_instance_valid(spawn_point):
		return spawn_point.global_transform
	return fallback_transform

func _get_bullet_spawn_point() -> Node3D:
	if _bullet_spawn_point != null and is_instance_valid(_bullet_spawn_point):
		return _bullet_spawn_point
	var found := find_child("BulletSpawnPoint", true, false) as Node3D
	if found != null:
		_bullet_spawn_point = found
	return _bullet_spawn_point

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

func _find_parent_hardpoint() -> Hardpoint:
	var node: Node = get_parent()
	while node != null:
		if node is Hardpoint:
			return node as Hardpoint
		node = node.get_parent()
	return null

func can_fire() -> bool:
	if infinite_ammo:
		return true
	return super.can_fire()

func _spawn_bullet(spawn_transform: Transform3D, firing_entity: Node3D) -> void:
	if not bullet_scene:
		return

	var bullet = bullet_scene.instantiate()
	last_fired_projectile = null

	var root = get_tree().current_scene
	if not root:
		push_warning("BulletWeapon: No current scene found.")
		return

	bullet.transform = spawn_transform
	_configure_projectile_instance(bullet)
	root.add_child(bullet)
	last_fired_projectile = bullet
	bullet.global_position += bullet.global_transform.basis.z * 2.5

	# Propagate optional debug metadata from turret controller before bullet.fire()
	# runs, so projectile-side debug setup can pick up the assigned target/callback.
	var debug_target_variant: Variant = get_meta(DEBUG_TARGET_META_KEY, null)
	if typeof(debug_target_variant) == TYPE_OBJECT and debug_target_variant is Node3D and is_instance_valid(debug_target_variant):
		bullet.set_meta("debug_target_node", debug_target_variant)
	var debug_callback_variant: Variant = get_meta(DEBUG_REPORT_CALLBACK_META_KEY, Callable())
	if debug_callback_variant is Callable:
		var debug_callback: Callable = debug_callback_variant
		if debug_callback.is_valid():
			bullet.set_meta("debug_report_callback", debug_callback)
	var debug_nominal_flight_time_variant: Variant = get_meta(DEBUG_NOMINAL_FLIGHT_TIME_META_KEY, -1.0)
	if typeof(debug_nominal_flight_time_variant) in [TYPE_FLOAT, TYPE_INT]:
		bullet.set_meta("debug_nominal_flight_time_s", float(debug_nominal_flight_time_variant))
	bullet.set_meta("debug_nominal_bullet_speed_mps", bullet_speed)

	var direction: Vector3 = spawn_transform.basis.z.normalized()
	if spread_angle > 0.001:
		var pitch_offset_rad: float = deg_to_rad(randf_range(-spread_angle, spread_angle))
		var yaw_offset_rad: float = deg_to_rad(randf_range(-spread_angle, spread_angle))
		var yaw_basis: Basis = Basis(spawn_transform.basis.y.normalized(), yaw_offset_rad)
		var pitch_basis: Basis = Basis(spawn_transform.basis.x.normalized(), pitch_offset_rad)
		direction = (yaw_basis * pitch_basis * direction).normalized()
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

func _apply_gun_profile() -> void:
	if gun_profile == null:
		return
	if not gun_profile.weapon_name.is_empty():
		weapon_name = gun_profile.weapon_name
	muzzle_velocity = maxf(gun_profile.muzzle_velocity_mps, 50.0)
	bullet_speed = muzzle_velocity
	fire_rate = maxf(gun_profile.rounds_per_minute / 60.0, 0.01)
	spread_angle = maxf(gun_profile.spread_angle_deg, 0.0)
	recoil_force = maxf(gun_profile.recoil_force, 0.0)
	damage_per_shot = maxf(gun_profile.damage_per_shot, 0.0)
	max_range_m = maxf(gun_profile.max_range_m, 10.0)
	use_lmg_sound_set = gun_profile.use_lmg_sound_set
	use_autocannon_sound_set = gun_profile.use_autocannon_sound_set
	use_heavy_auto_sound_set = gun_profile.use_heavy_auto_sound_set
	if gun_profile.projectile_scene != null:
		bullet_scene = gun_profile.projectile_scene

func _configure_projectile_instance(projectile: Node) -> void:
	if projectile == null or not is_instance_valid(projectile):
		return
	if "damage_amount" in projectile:
		projectile.damage_amount = damage_per_shot
	if "damage" in projectile:
		projectile.damage = damage_per_shot
	if "lifetime" in projectile:
		projectile.lifetime = maxf(max_range_m / maxf(_get_effective_projectile_speed_mps(), 1.0), 0.05)

func _get_effective_projectile_speed_mps() -> float:
	var nominal_speed_mps: float = maxf(bullet_speed, 50.0)
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
	if use_lmg_sound_set:
		return LMG_SHOT_STREAMS
	if use_autocannon_sound_set:
		return AUTOCANNON_SHOT_STREAMS
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
