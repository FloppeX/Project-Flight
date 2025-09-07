extends Weapon
class_name Autocannon

@export var bullet_projectile_scene: PackedScene
@export var rounds_per_minute: float = 400.0  # Rate of fire
@export var muzzle_velocity: float = 600.0    # Bullet speed
@export var spread_angle: float = 1.0         # Degrees of inaccuracy
@export var recoil_force: float = 1000.0
@export var cannon_sound: AudioStream
@export var pitch_variation: float = 0.05    # ±10%
@export var volume_variation: float = 0.5  # ±3dB

var hardpoint: Hardpoint
var fire_timer: float = 0.0
var is_firing: bool = false
var sfx_cannon: AudioStreamPlayer3D

func _ready():
	delete_when_empty = false  # Don't auto-remove when empty
	ammo_count = 200  # More ammo than bombs
	hardpoint = get_parent() as Hardpoint
	automatic_fire = true
	
		# Setup cannon sound
	if cannon_sound:
		sfx_cannon = AudioStreamPlayer3D.new()
		add_child(sfx_cannon)
		sfx_cannon.stream = cannon_sound
		sfx_cannon.volume_db = 0.0  # Adjust volume as needed
		sfx_cannon.max_distance = 1000.0     # Much larger range - 1km
		sfx_cannon.unit_size = 25.0          # Larger "size" of sound source  
		sfx_cannon.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		sfx_cannon.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		sfx_cannon.add_to_group("3d_audio")  # Add to group for audio management

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
	
	# Calculate fire delay based on RPM
	var seconds_per_round = 60.0 / rounds_per_minute
	fire_timer = seconds_per_round

	
	# Play cannon sound with variation
	if sfx_cannon:
		sfx_cannon.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
		sfx_cannon.volume_db = randf_range(-volume_variation, volume_variation)
		
		sfx_cannon.play()
	
	# Create bullet projectile
	var bullet = bullet_projectile_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position
	bullet.global_rotation = global_rotation
	
	# Add some spread for realism
	var spread = Vector3(
		randf_range(-spread_angle, spread_angle),
		randf_range(-spread_angle, spread_angle), 
		0
	)
	bullet.rotate_object_local(Vector3.RIGHT, deg_to_rad(spread.x))
	bullet.rotate_object_local(Vector3.UP, deg_to_rad(spread.y))
	
	# Use the new fire method from ProjectileNew/Bullet
	var aircraft = hardpoint.aircraft  # Access the aircraft directly
	var muzzle_vel = bullet.global_transform.basis.z * muzzle_velocity
	bullet.fire(muzzle_vel, aircraft)
	
	hardpoint.apply_recoil_force(get_recoil_force())
	
	ammo_count -= 1
	return true
