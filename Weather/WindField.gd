extends Node3D
## World-space air velocity in m/s. Vectors point where the air travels.
@export var enabled := true
@export var prevailing_velocity_mps := Vector3(4.0, 0.0, 2.0)
@export var gust_amplitude_mps := Vector3(3.0, 1.5, 3.0)
@export var turbulence_amplitude_mps := Vector3(1.5, 1.0, 1.5)
@export var gust_length_m := 600.0
@export var gust_period_s := 12.0
@export var turbulence_length_m := 35.0
@export var turbulence_period_s := 3.0
@export var noise_seed := 7319
var elapsed_s := 0.0
var _origin_offset := Vector3.ZERO
var _advection_offset := Vector3.ZERO
var _noise := FastNoiseLite.new()
var _dust_front: Node3D
var _twisters: Array[Node] = []

func _ready() -> void:
	add_to_group("atmospheric_wind")
	add_to_group("origin_shifter")
	process_physics_priority = -100
	_noise.seed = noise_seed
	_noise.frequency = 1.0
	_noise.fractal_type = FastNoiseLite.FRACTAL_NONE

func _physics_process(delta: float) -> void:
	elapsed_s += delta
	# Integrate the moving air parcel. Multiplying the current wind by total
	# elapsed time would jump the noise field whenever weather changes direction.
	_advection_offset += prevailing_velocity_mps * delta
	_dust_front = get_tree().get_first_node_in_group("dust_front") as Node3D
	_twisters = get_tree().get_nodes_in_group("twister")

func apply_origin_shift(offset: Vector3) -> void:
	# World objects subtract this offset; retain the same parcel of air.
	_origin_offset += offset

func get_velocity_at(world_position: Vector3) -> Vector3:
	if not enabled:
		return Vector3.ZERO
	var advected := world_position + _origin_offset - _advection_offset
	var gust := _sample(advected / maxf(gust_length_m, 1.0), elapsed_s / maxf(gust_period_s, 0.1))
	var turbulence := _sample(advected / maxf(turbulence_length_m, 1.0) + Vector3(57, 19, 83), elapsed_s / maxf(turbulence_period_s, 0.1))
	var storm_wind := Vector3.ZERO
	if is_instance_valid(_dust_front):
		storm_wind = _dust_front.get_wind_at(world_position)
	for twister in _twisters:
		if is_instance_valid(twister):
			storm_wind += twister.get_wind_at(world_position)
	return prevailing_velocity_mps + gust * gust_amplitude_mps + turbulence * turbulence_amplitude_mps + storm_wind

func _sample(position: Vector3, time: float) -> Vector3:
	var p := position + Vector3(0.0, time, time * 0.37)
	return Vector3(_noise.get_noise_3dv(p), _noise.get_noise_3dv(p + Vector3(137, 271, 53)), _noise.get_noise_3dv(p + Vector3(419, 73, 191)))
