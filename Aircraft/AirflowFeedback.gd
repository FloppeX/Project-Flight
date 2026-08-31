extends Node
class_name AirflowFeedback

@export var warning_audio_stream: AudioStream = preload("res://Audio/cockpit/stall buffet sound.wav")
# These are non-spatial sensations heard by the pilot through the airframe. The
# Interior bus is reserved for heavily muffling exterior 3D sources and its
# cockpit low-pass chain removes most of the air-rush recording's useful band.
# Match AudioManager3D's cockpit-native loop by bypassing that filter.
@export var audio_bus: String = "Master"
@export var silence_volume_db: float = -80.0
@export var min_volume_db: float = -42.0
@export var max_volume_db: float = -8.0
@export var pitch_min: float = 0.82
@export var pitch_max: float = 1.22
@export var fade_speed: float = 8.0

@export_group("Base Airflow")
@export var wind_audio_stream: AudioStream = preload("res://Audio/cockpit/wind_sound_cockpit.wav")
@export var wind_start_speed_mps: float = 25.0
@export var wind_full_vne_ratio: float = 0.95
@export var wind_min_volume_db: float = -45.0
@export var wind_max_volume_db: float = -16.0
@export var wind_pitch_min: float = 0.78
@export var wind_pitch_max: float = 1.18
@export_group("")

@export_group("Maneuver Drag")
@export var drag_audio_stream: AudioStream = preload("res://Audio/cockpit/air rush sound.wav")
@export var drag_start_accel_mps2: float = 0.6
@export var drag_full_accel_mps2: float = 8.0
@export var drag_min_volume_db: float = -42.0
@export var drag_max_volume_db: float = -6.0
@export var drag_pitch_min: float = 0.80
@export var drag_pitch_max: float = 1.24
@export var drag_camera_weight: float = 0.38
@export var drag_vibration_start: float = 0.25
@export var drag_vibration_weak_max: float = 0.24
@export_group("")

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
var wind_intensity: float = 0.0
var drag_intensity: float = 0.0
var departure_intensity: float = 0.0
var _audio_player: AudioStreamPlayer = null
var _wind_audio_player: AudioStreamPlayer = null
var _drag_audio_player: AudioStreamPlayer = null
var _vibration_timer_s: float = 0.0
var _last_active: bool = false


func setup(host_aircraft: RigidBody3D) -> void:
	aircraft = host_aircraft


func update_airflow_feedback(
		delta: float,
		active: bool,
		aoa_deg: float,
		stall_severity: float,
		total_speed_mps: float,
		forward_speed_mps: float,
		lateral_speed_mps: float,
		effective_stall_speed_mps: float,
		never_exceed_speed_mps: float,
		control_stress: float,
		advanced_flight_model: bool = true,
		dirty_drag_accel_mps2: float = 0.0,
		departure_severity: float = 0.0
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
		target_intensity = maxf(
			maxf(aoa_warning, stall_warning),
			maxf(maxf(slip_warning, stall_severity), control_stress)
		)

	var blend := clampf(delta * fade_speed, 0.0, 1.0)
	warning_intensity = lerpf(warning_intensity, clampf(target_intensity, 0.0, 1.0), blend)
	var target_wind := calculate_wind_intensity(total_speed_mps, never_exceed_speed_mps) \
		if active and advanced_flight_model else 0.0
	wind_intensity = lerpf(wind_intensity, target_wind, blend)
	var target_drag := calculate_drag_intensity(dirty_drag_accel_mps2) \
		if active and advanced_flight_model else 0.0
	drag_intensity = lerpf(drag_intensity, target_drag, blend)
	var target_departure := clampf(departure_severity, 0.0, 1.0) if active else 0.0
	departure_intensity = lerpf(departure_intensity, target_departure, blend)

	_update_audio(delta, active)
	_update_wind_audio(delta, active)
	_update_drag_audio(delta, active)
	_update_camera_feedback()
	_update_vibration(delta, active)

	if _last_active and not active:
		_stop_vibration()
	_last_active = active


func _ensure_audio_players() -> void:
	if _audio_player == null and warning_audio_stream != null:
		_set_stream_looping(warning_audio_stream)
		_audio_player = AudioStreamPlayer.new()
		_audio_player.name = "AirflowBuffetAudio"
		_audio_player.stream = warning_audio_stream
		_audio_player.volume_db = silence_volume_db
		_audio_player.pitch_scale = pitch_min
		_audio_player.bus = _resolve_audio_bus()
		add_child(_audio_player)
	if _wind_audio_player == null and wind_audio_stream != null:
		_set_stream_looping(wind_audio_stream)
		_wind_audio_player = AudioStreamPlayer.new()
		_wind_audio_player.name = "BaseAirflowAudio"
		_wind_audio_player.stream = wind_audio_stream
		_wind_audio_player.volume_db = silence_volume_db
		_wind_audio_player.pitch_scale = wind_pitch_min
		_wind_audio_player.bus = _resolve_audio_bus()
		add_child(_wind_audio_player)
	if _drag_audio_player == null and drag_audio_stream != null:
		_set_stream_looping(drag_audio_stream)
		_drag_audio_player = AudioStreamPlayer.new()
		_drag_audio_player.name = "ManeuverDragAudio"
		_drag_audio_player.stream = drag_audio_stream
		_drag_audio_player.volume_db = silence_volume_db
		_drag_audio_player.pitch_scale = drag_pitch_min
		_drag_audio_player.bus = _resolve_audio_bus()
		add_child(_drag_audio_player)


func _set_stream_looping(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true


func _update_audio(delta: float, active: bool) -> void:
	if _audio_player == null and not active:
		return
	_ensure_audio_players()
	if _audio_player == null:
		return
	_audio_player.bus = _resolve_audio_bus()

	var audible := active and warning_intensity > 0.01
	var target_volume := silence_volume_db
	var target_pitch := pitch_min
	if audible:
		var audio_t := _smoothstep(0.08, 1.0, warning_intensity)
		target_volume = lerpf(min_volume_db, max_volume_db, audio_t)
		target_pitch = lerpf(pitch_min, pitch_max, audio_t)

	var blend := clampf(delta * fade_speed, 0.0, 1.0)
	_audio_player.volume_db = lerpf(_audio_player.volume_db, target_volume, blend)
	_audio_player.pitch_scale = lerpf(_audio_player.pitch_scale, target_pitch, blend)

	if audible:
		if not _audio_player.playing:
			_audio_player.play()
	elif _audio_player.playing and _audio_player.volume_db <= silence_volume_db + 1.0:
		_audio_player.stop()


func _update_wind_audio(delta: float, active: bool) -> void:
	if _wind_audio_player == null and not active:
		return
	_ensure_audio_players()
	if _wind_audio_player == null:
		return
	_wind_audio_player.bus = _resolve_audio_bus()
	var audible := active and wind_intensity > 0.01
	var target_volume := silence_volume_db
	var target_pitch := wind_pitch_min
	if audible:
		target_volume = lerpf(wind_min_volume_db, wind_max_volume_db, wind_intensity)
		target_pitch = lerpf(wind_pitch_min, wind_pitch_max, wind_intensity)
	var blend := clampf(delta * fade_speed, 0.0, 1.0)
	_wind_audio_player.volume_db = lerpf(_wind_audio_player.volume_db, target_volume, blend)
	_wind_audio_player.pitch_scale = lerpf(_wind_audio_player.pitch_scale, target_pitch, blend)
	if audible:
		if not _wind_audio_player.playing:
			_wind_audio_player.play()
	elif _wind_audio_player.playing and _wind_audio_player.volume_db <= silence_volume_db + 1.0:
		_wind_audio_player.stop()


func _update_drag_audio(delta: float, active: bool) -> void:
	if _drag_audio_player == null and not active:
		return
	_ensure_audio_players()
	if _drag_audio_player == null:
		return
	_drag_audio_player.bus = _resolve_audio_bus()
	var audible := active and drag_intensity > 0.01
	var target_volume := silence_volume_db
	var target_pitch := drag_pitch_min
	if audible:
		var audio_t := _smoothstep(0.03, 1.0, drag_intensity)
		target_volume = lerpf(drag_min_volume_db, drag_max_volume_db, audio_t)
		target_pitch = lerpf(drag_pitch_min, drag_pitch_max, audio_t)
	var blend := clampf(delta * fade_speed, 0.0, 1.0)
	_drag_audio_player.volume_db = lerpf(_drag_audio_player.volume_db, target_volume, blend)
	_drag_audio_player.pitch_scale = lerpf(_drag_audio_player.pitch_scale, target_pitch, blend)
	if audible:
		if not _drag_audio_player.playing:
			_drag_audio_player.play()
	elif _drag_audio_player.playing and _drag_audio_player.volume_db <= silence_volume_db + 1.0:
		_drag_audio_player.stop()


func calculate_wind_intensity(speed_mps: float, never_exceed_speed_mps: float) -> float:
	var full_speed := maxf(
		never_exceed_speed_mps * maxf(wind_full_vne_ratio, 0.1),
		wind_start_speed_mps + 0.1
	)
	return _smoothstep(wind_start_speed_mps, full_speed, speed_mps)


func calculate_drag_intensity(dirty_drag_accel_mps2: float) -> float:
	return _smoothstep(
		drag_start_accel_mps2,
		maxf(drag_full_accel_mps2, drag_start_accel_mps2 + 0.01),
		dirty_drag_accel_mps2
	)


func _update_camera_feedback() -> void:
	# Maneuver drag contributes only a restrained pre-stall tremor. The sharper
	# buffet and departure signals remain authoritative as the wing separates.
	var feedback_source := maxf(
		maxf(warning_intensity, departure_intensity),
		drag_intensity * drag_camera_weight
	)
	var camera_intensity := _smoothstep(camera_warning_start, camera_warning_full, feedback_source)
	var camera_controller := _find_camera_controller()
	if camera_controller == null:
		return
	var cockpit_script: Variant = camera_controller.get("cockpit_script") if "cockpit_script" in camera_controller else null
	if cockpit_script is Node and cockpit_script.has_method("set_airflow_buffet_intensity"):
		cockpit_script.call("set_airflow_buffet_intensity", camera_intensity)


func _update_vibration(delta: float, active: bool) -> void:
	_vibration_timer_s -= delta
	var buffet_active := warning_intensity >= vibration_warning_start \
		or departure_intensity >= vibration_warning_start
	var drag_active := drag_intensity >= drag_vibration_start
	if not active or (not buffet_active and not drag_active):
		if _last_active:
			_stop_vibration()
		return
	if _vibration_timer_s > 0.0:
		return
	_vibration_timer_s = maxf(vibration_update_interval_s, 0.03)

	var buffet_t := _smoothstep(
		vibration_warning_start,
		1.0,
		maxf(warning_intensity, departure_intensity)
	)
	var drag_t := _smoothstep(drag_vibration_start, 1.0, drag_intensity)
	var time_ms := float(Time.get_ticks_msec())
	var pulse := 0.72 + 0.28 * sin(time_ms * 0.018)
	# A developed departure gets an uneven beat instead of the smooth maneuver hum.
	var departure_chop := lerpf(
		1.0,
		0.58 + 0.42 * absf(sin(time_ms * 0.011) * sin(time_ms * 0.027)),
		departure_intensity
	)
	var weak := clampf(
		maxf(drag_vibration_weak_max * drag_t, vibration_weak_max * buffet_t) * pulse,
		0.0,
		1.0
	)
	var strong := clampf(vibration_strong_max * buffet_t * pulse * departure_chop, 0.0, 1.0)
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
