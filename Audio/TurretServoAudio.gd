extends Node3D
const AUDIO = preload("res://Audio/RuntimeAudio.gd")
const SERVO = preload("res://Audio/mechanisms/electric_servo.ogg")
var _player: AudioStreamPlayer3D
var _yaw: Node3D
var _pitch: Node3D
var _previous_yaw: Quaternion
var _previous_pitch: Quaternion
var _elapsed: float = 0.0

func _ready() -> void:
	_yaw = get_parent()._get_yaw_mount()
	_pitch = get_parent().barrel_mount
	if not is_instance_valid(_pitch):
		set_physics_process(false)
		return
	_previous_yaw = _yaw.quaternion
	_previous_pitch = _pitch.quaternion
	_player = AudioStreamPlayer3D.new()
	_player.stream = AUDIO.loop_stream(SERVO)
	_player.max_distance = 35.0
	_player.unit_size = 3.0
	_player.volume_db = -80.0
	_player.add_to_group("3d_audio")
	add_child(_player)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.10:
		return
	if not is_instance_valid(_yaw) or not is_instance_valid(_pitch):
		_player.stop()
		set_physics_process(false)
		return
	var rate := maxf(_previous_yaw.angle_to(_yaw.quaternion), _previous_pitch.angle_to(_pitch.quaternion)) / _elapsed
	_previous_yaw = _yaw.quaternion
	_previous_pitch = _pitch.quaternion
	_elapsed = 0.0
	var moving := rate > 0.025 and AUDIO.listener_near(self, 35.0)
	_player.volume_db = lerpf(_player.volume_db, -19.0 if moving else -80.0, 0.6)
	_player.pitch_scale = lerpf(0.85, 1.15, clampf(rate / 2.0, 0.0, 1.0))
	if moving and not _player.playing:
		_player.play()
	elif not moving and _player.volume_db < -65.0:
		_player.stop()
