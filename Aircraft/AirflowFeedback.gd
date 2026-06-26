extends Node
class_name AirflowFeedback

@export var warning_audio_stream: AudioStream = preload("res://Audio/stall buffet sound.wav")
@export var audio_bus: String = "Interior"
@export var silence_volume_db: float = -80.0
@export var max_volume_db: float = -8.0
@export var pitch_min: float = 0.82
@export var pitch_max: float = 1.22
@export var fade_speed: float = 8.0

@export var aoa_warning_start_deg: float = 14.0
@export var aoa_warning_full_deg: float = 32.0
@export var slip_warning_start_mps: float = 14.0
@export var slip_warning_full_mps: float = 38.0
@export var stall_warning_margin_start_mps: float = 16.0
@export var stall_warning_margin_full_mps: float = 0.0
@export var slip_warning_weight: float = 0.65

@export var camera_warning_start: float = 0.18
@export var camera_warning_full: float = 0.9
@export var vibration_warning_start: float = 0.28
@export var vibration_update_interval_s: float = 0.12
@export var vibration_duration_s: float = 0.18
@export var vibration_weak_max: float = 0.35
@export var vibration_strong_max: float = 0.65

var aircraft: RigidBody3D = null
var warning_intensity: float = 0.0
var _audio_player: AudioStreamPlayer = null
var _vibration_timer_s: float = 0.0
var _last_active: bool = false


func setup(host_aircraft: RigidBody3D) -> void:
	aircraft = host_aircraft
	_ensure_audio_player()


func update_airflow_feedback(
		delta: float,
		active: bool,
		aoa_deg: float,
		stall_severity: float,
		forward_speed_mps: float,
		lateral_speed_mps: float,
		effective_stall_speed_mps: float
) -> void:
	var target_intensity := 0.0
	if active:
		var aoa_warning := _smoothstep(aoa_warning_start_deg, aoa_warning_full_deg, absf(aoa_deg))
		var slip_warning := _smoothstep(slip_warning_start_mps, slip_warning_full_mps, lateral_speed_mps) * slip_warning_weight
		var stall_warning := _smoothstep(
			effective_stall_speed_mps + stall_warning_margin_start_mps,
			effective_stall_speed_mps + stall_warning_margin_full_mps,
			forward_speed_mps
		)
		target_intensity = maxf(maxf(aoa_warning, stall_warning), maxf(slip_warning, stall_severity))

	var blend := clampf(delta * fade_speed, 0.0, 1.0)
	warning_intensity = lerpf(warning_intensity, clampf(target_intensity, 0.0, 1.0), blend)

	_update_audio(delta, active)
	_update_camera_feedback()
	_update_vibration(delta, active)

	if _last_active and not active:
		_stop_vibration()
	_last_active = active


func _ensure_audio_player() -> void:
	if _audio_player != null or warning_audio_stream == null:
		return
	if warning_audio_stream is AudioStreamWAV:
		(warning_audio_stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif warning_audio_stream is AudioStreamOggVorbis:
		(warning_audio_stream as AudioStreamOggVorbis).loop = true
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "AirflowBuffetAudio"
	_audio_player.stream = warning_audio_stream
	_audio_player.volume_db = silence_volume_db
	_audio_player.pitch_scale = pitch_min
	_audio_player.bus = _resolve_audio_bus()
	add_child(_audio_player)


func _update_audio(delta: float, active: bool) -> void:
	_ensure_audio_player()
	if _audio_player == null:
		return
	_audio_player.bus = _resolve_audio_bus()

	var audible := active and warning_intensity > 0.01
	var target_volume := silence_volume_db
	var target_pitch := pitch_min
	if audible:
		var audio_t := _smoothstep(0.08, 1.0, warning_intensity)
		target_volume = lerpf(silence_volume_db, max_volume_db, audio_t)
		target_pitch = lerpf(pitch_min, pitch_max, audio_t)

	var blend := clampf(delta * fade_speed, 0.0, 1.0)
	_audio_player.volume_db = lerpf(_audio_player.volume_db, target_volume, blend)
	_audio_player.pitch_scale = lerpf(_audio_player.pitch_scale, target_pitch, blend)

	if audible:
		if not _audio_player.playing:
			_audio_player.play()
	elif _audio_player.playing and _audio_player.volume_db <= silence_volume_db + 1.0:
		_audio_player.stop()


func _update_camera_feedback() -> void:
	var camera_intensity := _smoothstep(camera_warning_start, camera_warning_full, warning_intensity)
	var camera_controller := _find_camera_controller()
	if camera_controller == null:
		return
	var cockpit_script: Variant = camera_controller.get("cockpit_script") if "cockpit_script" in camera_controller else null
	if cockpit_script is Node and cockpit_script.has_method("set_airflow_buffet_intensity"):
		cockpit_script.call("set_airflow_buffet_intensity", camera_intensity)


func _update_vibration(delta: float, active: bool) -> void:
	_vibration_timer_s -= delta
	if not active or warning_intensity < vibration_warning_start:
		if _last_active:
			_stop_vibration()
		return
	if _vibration_timer_s > 0.0:
		return
	_vibration_timer_s = maxf(vibration_update_interval_s, 0.03)

	var vibration_t := _smoothstep(vibration_warning_start, 1.0, warning_intensity)
	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.018)
	var weak := clampf(vibration_weak_max * vibration_t * pulse, 0.0, 1.0)
	var strong := clampf(vibration_strong_max * vibration_t * pulse, 0.0, 1.0)
	for device_id in Input.get_connected_joypads():
		Input.start_joy_vibration(int(device_id), weak, strong, vibration_duration_s)


func _stop_vibration() -> void:
	for device_id in Input.get_connected_joypads():
		Input.stop_joy_vibration(int(device_id))


func _find_camera_controller() -> Node:
	if aircraft == null or not is_instance_valid(aircraft):
		return null
	var direct := aircraft.get_node_or_null("CameraController")
	if direct != null:
		return direct
	return aircraft.find_child("CameraController", true, false)


func _resolve_audio_bus() -> String:
	return audio_bus if AudioServer.get_bus_index(audio_bus) >= 0 else "Master"


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 1.0 if value >= edge1 else 0.0
	var t := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
