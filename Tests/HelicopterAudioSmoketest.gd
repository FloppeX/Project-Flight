extends Node


const HELICOPTER_SCENES := [
	"res://Aircraft/Aircraft_9.tscn",
	"res://Aircraft/Aircraft_10.tscn",
	"res://Aircraft/Aircraft_11.tscn",
	"res://Aircraft/Aircraft_12.tscn",
	"res://Aircraft/Aircraft_13.tscn",
	"res://Aircraft/Aircraft_15.tscn",
]

const EXPECTED_PROFILES := {9: "b", 10: "f", 11: "a", 12: "c", 13: "d", 15: "g"}
const EXPECTED_PILOT_VOICES := 9
const EXPECTED_INTERIOR_LOWPASS_HZ := 1000.0
const EXPECTED_INTERIOR_SECONDARY_LOWPASS_HZ := 550.0
const EXPECTED_INTERIOR_HIGHPASS_HZ := 60.0
const EXPECTED_INTERIOR_REDUCTION_DB := -7.0
const EXPECTED_INTERIOR_PANNING := 0.1

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# Capture occurs on a child bus, so the test need not play through speakers.
	AudioServer.set_bus_mute(0, true)
	get_viewport().audio_listener_enable_3d = true
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 3, 5)
	camera.current = true
	_validate_audio_folders()
	_validate_radio_voice_discovery()
	for scene_path in HELICOPTER_SCENES:
		await _validate_helicopter(scene_path)
	_finish()


func _validate_audio_folders() -> void:
	for required_directory in [
		"res://Audio/cockpit",
		"res://Audio/engine/fixed_wing",
		"res://Audio/engine/helicopter",
		"res://Audio/impacts",
		"res://Audio/Voices/Pilots",
		"res://Audio/Voices/Citadel",
		"res://Audio/Voices/SourcePacks",
	]:
		_expect(DirAccess.dir_exists_absolute(required_directory), "missing audio directory %s" % required_directory)

	var audio_root := DirAccess.open("res://Audio")
	_expect(audio_root != null, "Audio root could not be opened")
	if audio_root == null:
		return
	for file_name in audio_root.get_files():
		var extension := file_name.get_extension().to_lower()
		# The weather system intentionally keeps this existing source at Audio root.
		_expect(
			(extension != "wav" and extension != "ogg" and extension != "mp3") or file_name == "wind woosh loop.wav",
			"loose audio asset remains at Audio root: %s" % file_name
		)

	for representative_asset in [
		"res://Audio/cockpit/wind_sound_cockpit.wav",
		"res://Audio/engine/fixed_wing/airplane_propeller 1.wav",
		"res://Audio/engine/fixed_wing/prop startup 3.wav",
		"res://Audio/impacts/bullet_impact_dirt_01.wav",
		"res://Audio/impacts/bullet_impact_metal_heavy_01.wav",
		"res://Audio/explosion/explosion_large_01.wav",
		"res://Audio/guns/Heavy machine gun.wav",
		"res://Audio/rockets/rocket.wav",
	]:
		_expect(load(representative_asset) is AudioStream, "organized audio asset did not load: %s" % representative_asset)


func _validate_radio_voice_discovery() -> void:
	var radio_comms := get_node_or_null("/root/RadioComms")
	_expect(radio_comms != null, "RadioComms autoload was unavailable")
	if radio_comms == null:
		return
	radio_comms.call("_build_citadel_voice_library")
	radio_comms.call("_build_pilot_voice_library")
	var citadel_streams: Dictionary = radio_comms.get("_citadel_voice_streams")
	var pilot_streams: Dictionary = radio_comms.get("_pilot_voice_streams")
	var pilot_prefixes: Dictionary = radio_comms.get("_pilot_voice_prefixes_available")
	_expect(citadel_streams.size() >= 25, "Citadel voice library did not find the organized clips")
	_expect(not pilot_streams.is_empty(), "pilot voice library did not find the organized clips")
	_expect(
		pilot_prefixes.size() == EXPECTED_PILOT_VOICES,
		"pilot voice library found %d of %d voice sets" % [pilot_prefixes.size(), EXPECTED_PILOT_VOICES]
	)


func _validate_helicopter(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	_expect(packed != null, "could not load %s" % scene_path)
	if packed == null:
		return
	var helicopter := packed.instantiate() as RigidBody3D
	_expect(helicopter != null, "could not instantiate %s" % scene_path)
	if helicopter == null:
		return
	helicopter.process_mode = Node.PROCESS_MODE_DISABLED
	helicopter.freeze = true
	helicopter.collision_layer = 0
	helicopter.collision_mask = 0
	add_child(helicopter)
	await get_tree().process_frame

	var rotor := helicopter.get_node_or_null("RotorAssembly")
	var audio_manager := helicopter.get_node_or_null("AudioManager3D")
	var engine := helicopter.get_node_or_null("Engine")
	_expect(rotor != null, "%s has no RotorAssembly" % scene_path)
	_expect(audio_manager != null, "%s has no AudioManager3D" % scene_path)
	_expect(engine != null, "%s has no Engine" % scene_path)
	if rotor != null:
		await _validate_rotor_layers(rotor, scene_path)
	if audio_manager != null and rotor != null:
		_validate_cockpit_filter(audio_manager, rotor, helicopter, scene_path)
	if engine != null:
		_expect(engine.get("EngineSoundLoop") == null, "%s still has a competing Engine rotor loop" % scene_path)
		_expect(engine.get("EngineSoundStart") == null, "%s still has a fixed-wing engine-start sound" % scene_path)

	remove_child(helicopter)
	helicopter.free()
	await get_tree().process_frame


func _validate_rotor_layers(rotor: Node, scene_path: String) -> void:
	var streams: Array = rotor.get("rotor_audio_streams")
	var players: Array = rotor.get("_rotor_audio_bank_players")
	_expect(streams.size() == 5 and players.size() == 5, "%s needs all five speed recordings" % scene_path)
	if streams.size() != 5 or players.size() != 5:
		return
	var index := scene_path.get_file().trim_prefix("Aircraft_").trim_suffix(".tscn").to_int()
	for speed in range(5):
		var player := players[speed] as AudioStreamPlayer3D
		_expect(player != null, "%s missing speed player" % scene_path)
		if player == null:
			return
		_expect(streams[speed].resource_path == "res://Audio/engine/helicopter/profiles/%s/rotor_%d.ogg" % [EXPECTED_PROFILES[index], speed], "%s wrong profile/speed source" % scene_path)
		_expect(player.stream is AudioStreamOggVorbis and player.stream.loop, "%s speed layer must loop" % scene_path)
		_expect(player.stream != streams[speed], "Runtime loop setup must not mutate shared imported sources")
		_expect(player.is_in_group("3d_audio"), "%s layer bypasses aircraft routing" % scene_path)
		# Frozen test aircraft still need their audio players processed by the mixer.
		player.process_mode = Node.PROCESS_MODE_ALWAYS

	# Ascending and descending RPM: every speed and every transition is exercised.
	for step in [0, 1, 2, 3, 4, 5, 6, 7, 8, 7, 6, 5, 4, 3, 2, 1, 0]:
		var rpm: float = 0.05 + 0.95 * float(step) / 8.0
		rotor.set("_power", rpm)
		rotor.call("_update_rotor_audio")
		var active := 0
		for player in players:
			if player.playing:
				active += 1
		_expect(active == (1 if step % 2 == 0 else 2), "%s RPM %.3f selected the wrong number of layers" % [scene_path, rpm])
		if step % 2 == 0:
			_expect(players[step / 2].playing, "%s wrong speed layer selected" % scene_path)

	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, "RotorProbe")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, capture)
	for player in players:
		player.bus = "RotorProbe"
	var levels: Array[float] = []
	for rpm in [0.05, 0.40, 0.76, 1.0]:
		rotor.set("_power", rpm)
		rotor.call("_update_rotor_audio")
		var rms := await _capture_rms(capture)
		levels.append(rms)
		_expect(rms > 0.00001, "%s rotor at %.2f RPM did not reach mixer" % [scene_path, rpm])
	_expect(levels[3] > levels[0] * 1.2, "%s full-speed rotor lost its load envelope" % scene_path)
	players[4].seek(players[4].stream.get_length() - 0.06)
	_expect(await _capture_rms(capture) > 0.00001 and players[4].playing, "%s loop stopped at the recording boundary" % scene_path)
	rotor.call("set_aircraft_audio_budget_enabled", false)
	_expect(await _capture_rms(capture) < 0.000001, "%s suppressed rotor is still audible" % scene_path)
	rotor.call("set_aircraft_audio_budget_enabled", true)
	rotor.call("_update_rotor_audio")
	_expect(await _capture_rms(capture) > 0.00001, "%s rotor did not resume after budget restore" % scene_path)
	rotor.set("_power", 0.0)
	rotor.call("_update_rotor_audio")
	_expect(await _capture_rms(capture) < 0.000001, "%s stopped rotor still audible" % scene_path)
	for player in players:
		_expect(not player.playing, "%s stopped rotor still decoding" % scene_path)
		player.bus = "Master"
	AudioServer.remove_bus(bus)
	print("HELICOPTER_MIXER profile=", EXPECTED_PROFILES[index], " rms=", levels)


func _capture_rms(capture: AudioEffectCapture) -> float:
	await get_tree().create_timer(0.10).timeout
	capture.clear_buffer()
	await get_tree().create_timer(0.12).timeout
	# A newly created capture bus can miss its first mix during scene warmup.
	# Wait for actual samples; silence still fails the RMS assertion below.
	var deadline := Time.get_ticks_msec() + 1000
	while capture.get_frames_available() == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.02).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	_expect(not samples.is_empty(), "Audio capture has no mixer frames")
	var sum := 0.0
	for sample in samples:
		sum += sample.length_squared()
	return sqrt(sum / maxf(samples.size() * 2.0, 1.0))


func _validate_cockpit_filter(audio_manager: Node, rotor: Node, helicopter: Node, scene_path: String) -> void:
	_expect(is_equal_approx(float(audio_manager.get("interior_lowpass_cutoff")), EXPECTED_INTERIOR_LOWPASS_HZ), "%s has a different cockpit low-pass" % scene_path)
	_expect(is_equal_approx(float(audio_manager.get("interior_secondary_lowpass_cutoff")), EXPECTED_INTERIOR_SECONDARY_LOWPASS_HZ), "%s has a different secondary cockpit low-pass" % scene_path)
	_expect(is_equal_approx(float(audio_manager.get("interior_highpass_cutoff")), EXPECTED_INTERIOR_HIGHPASS_HZ), "%s has a different cockpit high-pass" % scene_path)
	_expect(is_equal_approx(float(audio_manager.get("interior_volume_reduction")), EXPECTED_INTERIOR_REDUCTION_DB), "%s has a different cockpit volume reduction" % scene_path)
	_expect(is_equal_approx(float(audio_manager.get("interior_panning_strength")), EXPECTED_INTERIOR_PANNING), "%s has different cockpit panning" % scene_path)

	audio_manager.call("switch_aircraft_audio_sources", helicopter, "Interior")
	for speed in range(5):
		var player_name := "RotorAudio%d" % speed
		var player := rotor.get_node_or_null(player_name) as AudioStreamPlayer3D
		if player != null:
			_expect(player.bus == "Interior", "%s %s did not enter the cockpit-filter bus" % [scene_path, player_name])
			_expect(is_equal_approx(player.panning_strength, EXPECTED_INTERIOR_PANNING), "%s %s did not receive cockpit panning" % [scene_path, player_name])


func _finish() -> void:
	if _failures.is_empty():
		print("[HelicopterAudioSmoketest] PASS helicopters=6 profiles=6 rotor_layers=5 mixer=audible loop_wrap=true budget_and_stop=silent cockpit_filter=shared voice_sets=9")
		get_tree().quit(0)
		return
	print("[HelicopterAudioSmoketest] %d failure(s)" % _failures.size())
	get_tree().quit(1)


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("[HelicopterAudioSmoketest] FAIL: %s" % description)
