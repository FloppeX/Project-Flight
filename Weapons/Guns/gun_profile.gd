extends Resource
class_name GunProfile

@export var profile_name: String = "Gun Profile"
@export var weapon_name: String = "Autocannon"
@export var rounds_per_minute: float = 600.0
@export var muzzle_velocity_mps: float = 500.0
@export var spread_angle_deg: float = 1.0
@export var recoil_force: float = 1000.0
@export var damage_per_shot: float = 10.0
@export var max_range_m: float = 800.0
@export var projectile_scene: PackedScene
@export var use_lmg_sound_set: bool = false
@export var use_autocannon_sound_set: bool = false
@export var use_heavy_auto_sound_set: bool = true
