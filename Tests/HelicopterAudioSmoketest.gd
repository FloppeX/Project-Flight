extends Node


const HELICOPTER_SCENES := [
	"res://Aircraft/Aircraft_9.tscn",
	"res://Aircraft/Aircraft_10.tscn",
	"res://Aircraft/Aircraft_11.tscn",
	"res://Aircraft/Aircraft_12.tscn",
]

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
		_expect(
			extension != "wav" and extension != "ogg" and extension != "mp3",
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
		_validate_rotor_layers(rotor, scene_path)
	if audio_manager != null and rotor != null:
		_validate_cockpit_filter(audio_manager, rotor, helicopter, scene_path)
	if engine != null:
		_expect(engine.get("EngineSoundLoop") == null, "%s still has a competing Engine rotor loop" % scene_path)
		_expect(engine.get("EngineSoundStart") == null, "%s still has a fixed-wing engine-start sound" % scene_path)

	remove_child(helicopter)
	helicopter.free()
	await get_tree().process_frame


func _validate_rotor_layers(rotor: Node, scene_path: String) -> void:
	for property_name in ["rotor_audio_slow_stream", "rotor_audio_medium_stream", "rotor_audio_fast_stream"]:
		_expect(rotor.get(property_name) != null, "%s is missing %s" % [scene_path, property_name])

	var slow := rotor.get_node_or_null("RotorAudioSlow") as AudioStreamPlayer3D
	var medium := rotor.get_node_or_null("RotorAudioMedium") as AudioStreamPlayer3D
	var fast := rotor.get_node_or_null("RotorAudioFast") as AudioStreamPlayer3D
	_expect(slow != null and medium != null and fast != null, "%s did not create all three rotor audio players" % scene_path)
	if slow == null or medium == null or fast == null:
		return
	for player in [slow, medium, fast]:
		_expect(player.is_in_group("3d_audio"), "%s rotor layer is not routed as 3D aircraft audio" % scene_path)

	rotor.set("_power", 0.10)
	rotor.call("_update_rotor_audio")
	_expect(slow.playing and not medium.playing and not fast.playing, "%s slow rotor state did not select the slow recording" % scene_path)
	rotor.set("_power", 0.55)
	rotor.call("_update_rotor_audio")
	_expect(not slow.playing and medium.playing and not fast.playing, "%s medium rotor state did not select the medium recording" % scene_path)
	rotor.set("_power", 1.0)
	rotor.call("_update_rotor_audio")
	_expect(not slow.playing and not medium.playing and fast.playing, "%s fast rotor state did not select the fast recording" % scene_path)

	rotor.call("set_aircraft_audio_budget_enabled", false)
	rotor.call("_update_rotor_audio")
	_expect(not slow.playing and not medium.playing and not fast.playing, "%s rotor audio ignored the AI audio budget" % scene_path)
	rotor.call("set_aircraft_audio_budget_enabled", true)


func _validate_cockpit_filter(audio_manager: Node, rotor: Node, helicopter: Node, scene_path: String) -> void:
	_expect(is_equal_approx(float(audio_manager.get("interior_lowpass_cutoff")), EXPECTED_INTERIOR_LOWPASS_HZ), "%s has a different cockpit low-pass" % scene_path)
	_expect(is_equal_approx(float(audio_manager.get("interior_secondary_lowpass_cutoff")), EXPECTED_INTERIOR_SECONDARY_LOWPASS_HZ), "%s has a different secondary cockpit low-pass" % scene_path)
	_expect(is_equal_approx(float(audio_manager.get("interior_highpass_cutoff")), EXPECTED_INTERIOR_HIGHPASS_HZ), "%s has a different cockpit high-pass" % scene_path)
	_expect(is_equal_approx(float(audio_manager.get("interior_volume_reduction")), EXPECTED_INTERIOR_REDUCTION_DB), "%s has a different cockpit volume reduction" % scene_path)
	_expect(is_equal_approx(float(audio_manager.get("interior_panning_strength")), EXPECTED_INTERIOR_PANNING), "%s has different cockpit panning" % scene_path)

	audio_manager.call("switch_aircraft_audio_sources", helicopter, "Interior")
	for player_name in ["RotorAudioSlow", "RotorAudioMedium", "RotorAudioFast"]:
		var player := rotor.get_node_or_null(player_name) as AudioStreamPlayer3D
		if player != null:
			_expect(player.bus == "Interior", "%s %s did not enter the cockpit-filter bus" % [scene_path, player_name])
			_expect(is_equal_approx(player.panning_strength, EXPECTED_INTERIOR_PANNING), "%s %s did not receive cockpit panning" % [scene_path, player_name])


func _finish() -> void:
	if _failures.is_empty():
		print("[HelicopterAudioSmoketest] PASS helicopters=4 rotor_layers=3 cockpit_filter=shared voice_sets=9 audio_root=clean")
		get_tree().quit(0)
		return
	print("[HelicopterAudioSmoketest] %d failure(s)" % _failures.size())
	get_tree().quit(1)


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("[HelicopterAudioSmoketest] FAIL: %s" % description)
