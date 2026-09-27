extends Node
## A bounded approximation of thousands of fine grains striking the canopy.
## Two independent stereo recordings avoid a short, synchronized repeating hit.

var _ticks: AudioStreamPlayer
var _rattle: AudioStreamPlayer

func _ready() -> void:
	_ticks = _make_player("GrainTicks", preload("res://Audio/cockpit/canopy_sand_ticks.wav"))
	_rattle = _make_player("GrainRattle", preload("res://Audio/cockpit/canopy_sand_rattle.wav"))

func _make_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = preload("res://Audio/RuntimeAudio.gd").loop_stream(stream)
	# Contact heard through the canopy is already an interior sound.
	player.bus = "Master"
	player.volume_db = -80.0
	add_child(player)
	return player

func update_exposure(cockpit: bool, intensity: float, severity: int, airflow_speed: float, delta: float) -> void:
	if not cockpit:
		# Camera switches/ejection must never leave canopy sounds in exterior views.
		for player in [_ticks, _rattle]:
			player.stop()
			player.volume_db = -80.0
		return
	var level := float(clampi(severity, 1, 5) - 1) / 4.0
	var flux := intensity * clampf(airflow_speed / 100.0, 0.35, 1.7)
	var exposure_db := linear_to_db(maxf(flux, 0.0001))
	var ticks_db := clampf(lerpf(-24.0, -11.0, level) + exposure_db, -80.0, -7.0)
	var rattle_db := clampf(lerpf(-40.0, -16.0, level) + exposure_db, -80.0, -10.0)
	var blend := 1.0 - exp(-delta * 5.0)
	_ticks.pitch_scale = lerpf(0.85, 1.35, level)
	_rattle.pitch_scale = lerpf(0.9, 1.2, level)
	_ticks.volume_db = lerpf(_ticks.volume_db, ticks_db, blend)
	_rattle.volume_db = lerpf(_rattle.volume_db, rattle_db, blend)
	for player in [_ticks, _rattle]:
		if intensity > 0.02 and not player.playing:
			player.play(randf() * player.stream.get_length())
		elif intensity <= 0.02 and player.volume_db < -65.0:
			player.stop()
