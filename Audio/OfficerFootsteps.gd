extends Node3D
## Carrier-local distance avoids steps from carrier motion, lifts or teleports.
const SOUNDS = [preload("res://Audio/footsteps/metal_01.wav"), preload("res://Audio/footsteps/metal_02.wav"),
	preload("res://Audio/footsteps/metal_03.wav"), preload("res://Audio/footsteps/metal_04.wav"),
	preload("res://Audio/footsteps/metal_05.wav"), preload("res://Audio/footsteps/metal_06.wav"),
	preload("res://Audio/footsteps/metal_07.wav"), preload("res://Audio/footsteps/metal_08.wav")]
@export var stride_m: float = 0.72
var _previous: Vector3
var _distance: float = 0.0
var _last_index: int = -1
var step_events: int = 0
var _player: AudioStreamPlayer3D

func _ready() -> void:
	_previous = get_parent().position
	_player = AudioStreamPlayer3D.new()
	_player.name = "BootsOnPlasteel"
	_player.unit_size = 2.5
	_player.max_distance = 18.0
	_player.volume_db = -8.0
	_player.max_polyphony = 2
	_player.add_to_group("3d_audio")
	_player.add_to_group("carrier_local_audio")
	add_child(_player)

func _physics_process(_delta: float) -> void:
	advance_distance(get_parent().position)

func advance_distance(current: Vector3) -> void:
	var delta := current - _previous
	_previous = current
	var movement := Vector2(delta.x, delta.z).length()
	if movement > 1.5 or absf(delta.y) > 0.5:
		_distance = 0.0
		return
	if movement < 0.001:
		return
	_distance += movement
	if _distance < stride_m:
		return
	_distance = fmod(_distance, stride_m)
	# Choose a different clip on every step; small variation avoids repetition.
	_last_index = (_last_index + 1 + randi_range(0, SOUNDS.size() - 2)) % SOUNDS.size()
	_player.stream = SOUNDS[_last_index]
	_player.pitch_scale = randf_range(0.96, 1.04)
	_player.play()
	step_events += 1
