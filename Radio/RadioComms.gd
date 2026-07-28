extends Node

const RADIO_TEST_STREAM_PATH := "res://Audio/Citadel voice test.mp3"
const CITADEL_AUDIO_DIR := "res://Audio"
const CITADEL_AUDIO_PREFIX := "Citadel - "
const CITADEL_FLIGHT_NAME_ALIASES := ["Archer", "Bulldog", "Crimson", "Dingo"]
const PILOT_AUDIO_PREFIXES := ["Ukrainian - ", "British male - ", "Filipino - ", "Arabic female - ", "German female - ", "Scottish female - ", "Brazilian male - ", "French Canadian female - ", "Nigerian male - "]
const RADIO_BUS_NAME := "Radio"
const RADIO_STATIC_MIX_RATE := 22050

## RadioComms — autoload singleton.
##
## Displays military-style radio transmissions in a scrolling HUD log and
## optionally speaks them via the OS text-to-speech engine.
##
## Usage:
##   RadioComms.transmit("Citadel", "Bulldog flight", "Bandits bearing two-seven-zero. Engage.")
##   RadioComms.transmit_delayed("Bulldog lead", "Citadel", "Copy. Wilco.", 1.5)

# ── Configuration ──────────────────────────────────────────────────────────────

@export var use_tts: bool = false          ## Enable OS text-to-speech
@export var tts_volume: int = 80           ## 0–100
@export var tts_pitch: float = 1.0
@export var tts_rate: float = 1.05        ## Slightly clipped = radio effect
@export var message_linger_s: float = 9.0 ## How long each line stays visible
@export var max_visible: int = 7          ## Maximum lines shown at once
@export var radio_test_hotkey_enabled: bool = false
@export var radio_static_pre_roll_s: float = 0.08
@export var radio_static_post_roll_s: float = 0.20
@export var radio_voice_gain_db: float = -2.5
@export var radio_highpass_cutoff_hz: float = 800.0
@export var radio_lowpass_cutoff_hz: float = 2800.0
@export var radio_filter_resonance: float = 1.4
@export var radio_static_noise_gain: float = 0.034
@export var radio_static_crackle_gain: float = 0.18
@export var radio_crackle_chance_per_frame: float = 0.014
@export var radio_squelch_burst_s: float = 0.055
@export var radio_squelch_burst_gain: float = 0.55
@export var radio_dropout_chance_per_frame: float = 0.002
@export var radio_dropout_min_s: float = 0.02
@export var radio_dropout_max_s: float = 0.055
@export var radio_dropout_volume_db: float = -12.0
@export var radio_pitch_jitter: float = 0.006
@export var radio_voice_flutter_update_s: float = 0.16
@export var use_citadel_voice_clips: bool = true
@export var use_pilot_voice_clips: bool = true
@export var radio_voice_queue_max_age_s: float = 4.0
@export var radio_bark_repeat_cooldown_s: float = 10.0
@export var lock_pilot_voice_to_callsign: bool = true

# ── Signals ────────────────────────────────────────────────────────────────────

## Emitted for every transmission. Connect to add subtitles, logging, etc.
signal transmitted(sender: String, recipient: String, body: String)

# ── Private state ──────────────────────────────────────────────────────────────

var _messages: Array = []  # Array of { sender, recipient, body, expire_at }
var _canvas: CanvasLayer
var _panel: Panel
var _log: RichTextLabel
var _status_label: Label
var _tts_queue: Array[String] = []
var _tts_busy: bool = false
var _radio_voice_player: AudioStreamPlayer
var _radio_static_player: AudioStreamPlayer
var _radio_static_playback: AudioStreamGeneratorPlayback
var _radio_test_stream: AudioStream
var _citadel_voice_streams: Dictionary = {}
var _pilot_voice_streams: Dictionary = {}
var _pilot_voice_prefixes_available: Dictionary = {}
var _pilot_sender_voice_prefixes: Dictionary = {}
var _citadel_voice_queue: Array = []
var _radio_rng := RandomNumberGenerator.new()
var _radio_static_until_s: float = 0.0
var _radio_static_mix: float = 0.0
var _radio_crackle_frames_left: int = 0
var _radio_crackle_level: float = 0.0
var _radio_squelch_frames_left: int = 0
var _radio_squelch_total_frames: int = 0
var _radio_squelch_gain: float = 0.0
var _radio_request_serial: int = 0
var _radio_dropout_until_s: float = 0.0
var _radio_voice_flutter_timer_s: float = 0.0
var _radio_voice_volume_offset_db: float = 0.0
var _radio_voice_pitch_offset: float = 0.0
var _recent_radio_bark_times: Dictionary = {}

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_display()
	_radio_rng.randomize()
	_setup_radio_audio()
	_build_citadel_voice_library()
	_build_pilot_voice_library()

func _process(delta: float) -> void:
	_expire_messages()
	_pin_to_bottom()
	_refresh_status()
	if use_tts:
		_drain_tts_queue()
	_update_radio_static(delta)

func _input(event: InputEvent) -> void:
	return
	if not radio_test_hotkey_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_V:
		play_citadel_test()

# ── Public API ─────────────────────────────────────────────────────────────────

## Send a radio transmission immediately.
func transmit(sender: String, recipient: String, body: String) -> void:
	_enqueue(sender, recipient, body)
	_queue_radio_voice_clip(sender, recipient, body)
	transmitted.emit(sender, recipient, body)
	print("[Radio] %s → %s: %s" % [sender, recipient, body])

## Send a radio transmission after a delay (seconds). Good for acknowledgements.
func transmit_delayed(sender: String, recipient: String, body: String, delay_s: float) -> void:
	var t := get_tree().create_timer(delay_s)
	t.timeout.connect(func(): transmit(sender, recipient, body))

func play_citadel_test() -> void:
	if _radio_test_stream == null:
		_radio_test_stream = load(RADIO_TEST_STREAM_PATH)
	if _radio_test_stream == null or _radio_voice_player == null:
		push_warning("Radio test stream is unavailable: %s" % RADIO_TEST_STREAM_PATH)
		return

	_radio_request_serial += 1
	var request_serial := _radio_request_serial
	_radio_voice_player.stop()
	_start_radio_static_for(radio_static_pre_roll_s + _estimate_radio_test_length() + radio_static_post_roll_s)
	_trigger_radio_squelch_burst()

	var pre_roll_timer := get_tree().create_timer(radio_static_pre_roll_s)
	pre_roll_timer.timeout.connect(func() -> void:
		if request_serial != _radio_request_serial:
			return
		_radio_voice_player.stream = _radio_test_stream
		_radio_voice_player.pitch_scale = 1.0
		_radio_voice_player.play()
	)

# ── Standard phrase helpers ────────────────────────────────────────────────────
## Call these from AirOpsManager / Flight to get consistent phrasing.

func say_cap_order(flight_name: String, _altitude_m: float) -> void:
	var bodies := [
		"%s flight, maintain combat air patrol. Engage any bandits." % flight_name,
		"%s flight, hold CAP station. Weapons free on bandits." % flight_name,
		"%s flight, combat air patrol. Clear the skies." % flight_name,
	]
	transmit("Citadel", "%s flight" % flight_name, _pick(bodies))
	transmit_delayed("%s lead" % flight_name, "Citadel", _pick([
		"Copy. Orbiting. Keeping watch.",
		"Roger. On station. Sky is quiet.",
		"Wilco. Climbing to altitude. Watch your spacing.",
	]), randf_range(1.2, 2.5))

func say_cas_order(flight_name: String) -> void:
	var bodies := [
		"%s flight, execute ground attack. Cleared hot on enemy armor." % flight_name,
		"%s flight, weapons free on ground targets. Watch your altitude." % flight_name,
		"%s flight, engage ground targets. Cleared hot. Keep it tight." % flight_name,
	]
	transmit("Citadel", "%s flight" % flight_name, _pick(bodies))
	transmit_delayed("%s lead" % flight_name, "Citadel", _pick([
		"Copy. Breaking off. Blyad, let's go get them.",
		"Roger. Cleared hot. I see my line.",
		"Understood. Tally. Stay sharp out there.",
	]), randf_range(1.0, 2.2))

func say_rtb_order(flight_name: String) -> void:
	var bodies := [
		"%s flight, return to base. Good hunting." % flight_name,
		"%s flight, return to base. The deck is ready." % flight_name,
		"%s flight, break off and return to base. Nice work." % flight_name,
	]
	transmit("Citadel", "%s flight" % flight_name, _pick(bodies))
	transmit_delayed("%s lead" % flight_name, "Citadel", _pick([
		"Copy. Turning for home.",
		"Roger. Flight, on me. Time to find the boat.",
		"Wilco. Close it up. Good work today. Good work.",
	]), randf_range(1.0, 2.0))

func say_target_assignment(lead_callsign: String, wingman_callsign: String,
		lead_target: String, wingman_target: String) -> void:
	## Flight-internal: lead distributes targets to a wingman.
	var bodies := [
		"I'll take the %s. You take the %s." % [lead_target, wingman_target],
		"On the %s. %s, take the %s." % [lead_target, wingman_callsign, wingman_target],
		"%s, break right. Engage the %s. I'm on the %s." % [wingman_callsign, wingman_target, lead_target],
	]
	transmit(lead_callsign, wingman_callsign, _pick(bodies))

func say_splash(callsign: String) -> void:
	var bodies := [
		"Splash one.",
		"Got him. Blyad, good kill.",
		"He's down. Chort vozmy.",
		"Confirmed kill. Yes. Yes.",
	]
	transmit(callsign, "Citadel", _pick(bodies))

func say_bingo(callsign: String) -> void:
	transmit(callsign, "Citadel", _pick([
		"Bingo fuel. RTB. Hold my spot.",
		"Running dry. Heading back. Cover my slot.",
	]))

func say_taking_fire(callsign: String) -> void:
	var bodies := [
		"Taking hits. Blyad. Breaking off, breaking off.",
		"I'm taking fire. Chort.",
		"Ground fire. Yob tvoyu mat. Taking evasive.",
		"Hit. I'm hit. Disengaging. Assessing damage.",
	]
	transmit(callsign, "Citadel", _pick(bodies))

# ── Internal: message management ──────────────────────────────────────────────

func _build_citadel_voice_library() -> void:
	_citadel_voice_streams.clear()
	var dir := DirAccess.open(CITADEL_AUDIO_DIR)
	if dir == null:
		push_warning("Citadel voice directory is unavailable: %s" % CITADEL_AUDIO_DIR)
		return

	for file_name in dir.get_files():
		if not file_name.begins_with(CITADEL_AUDIO_PREFIX):
			continue
		var extension := file_name.get_extension().to_lower()
		if extension != "wav" and extension != "ogg" and extension != "mp3":
			continue
		var base_name := file_name.get_basename()
		var phrase := base_name.substr(CITADEL_AUDIO_PREFIX.length())
		var key := _normalize_citadel_phrase(phrase)
		var stream := load(CITADEL_AUDIO_DIR.path_join(file_name)) as AudioStream
		if stream != null and not key.is_empty():
			_citadel_voice_streams[key] = stream

func _queue_citadel_voice_clip(sender: String, recipient: String, body: String) -> void:
	if not use_citadel_voice_clips:
		return
	if sender != "Citadel":
		return
	var stream := _find_citadel_voice_stream(recipient, body)
	if stream == null:
		return
	_enqueue_radio_voice_stream(stream, _radio_bark_cooldown_key(sender, body))
	_play_next_citadel_voice_clip()

func _build_pilot_voice_library() -> void:
	_pilot_voice_streams.clear()
	_pilot_voice_prefixes_available.clear()
	_pilot_sender_voice_prefixes.clear()
	var dir := DirAccess.open(CITADEL_AUDIO_DIR)
	if dir == null:
		push_warning("Pilot voice directory is unavailable: %s" % CITADEL_AUDIO_DIR)
		return

	for file_name in dir.get_files():
		var voice_prefix := _pilot_voice_prefix_for_file(file_name)
		if voice_prefix == "":
			continue
		var extension := file_name.get_extension().to_lower()
		if extension != "wav" and extension != "ogg" and extension != "mp3":
			continue
		var base_name := file_name.get_basename()
		var phrase := base_name.substr(voice_prefix.length())
		var key := _canonical_pilot_voice_key(phrase)
		var stream := load(CITADEL_AUDIO_DIR.path_join(file_name)) as AudioStream
		if stream != null and not key.is_empty():
			if not _pilot_voice_streams.has(key):
				_pilot_voice_streams[key] = {}
			var streams_by_prefix: Dictionary = _pilot_voice_streams[key]
			if not streams_by_prefix.has(voice_prefix):
				streams_by_prefix[voice_prefix] = []
			(streams_by_prefix[voice_prefix] as Array).append(stream)
			_pilot_voice_prefixes_available[voice_prefix] = true

func _queue_radio_voice_clip(sender: String, recipient: String, body: String) -> void:
	var stream: AudioStream = null
	if sender == "Citadel" and use_citadel_voice_clips:
		stream = _find_citadel_voice_stream(recipient, body)
	elif use_pilot_voice_clips:
		stream = _find_pilot_voice_stream(sender, body)
	if stream == null:
		return
	_enqueue_radio_voice_stream(stream, _radio_bark_cooldown_key(sender, body))
	_play_next_citadel_voice_clip()

func _find_citadel_voice_stream(recipient: String, body: String) -> AudioStream:
	var key := _normalize_citadel_phrase(body)
	if _citadel_voice_streams.has(key):
		return _citadel_voice_streams[key] as AudioStream

	var flight_suffix := " flight"
	if recipient.ends_with(flight_suffix):
		var flight_name := recipient.substr(0, recipient.length() - flight_suffix.length())
		if not flight_name.is_empty():
			key = _normalize_citadel_phrase(body.replace(flight_name, "Archer"))
			if _citadel_voice_streams.has(key):
				return _citadel_voice_streams[key] as AudioStream

	for flight_name in CITADEL_FLIGHT_NAME_ALIASES:
		if flight_name == "Archer":
			continue
		if body.contains(flight_name):
			key = _normalize_citadel_phrase(body.replace(flight_name, "Archer"))
			if _citadel_voice_streams.has(key):
				return _citadel_voice_streams[key] as AudioStream

	return null

func _find_pilot_voice_stream(sender: String, body: String) -> AudioStream:
	if not _is_pilot_sender(sender):
		return null

	var direct_key := _normalize_pilot_phrase(body)
	if _pilot_voice_streams.has(direct_key):
		return _pick_pilot_voice_stream(sender, direct_key)

	var alias_key := _pilot_voice_alias_key(body)
	if alias_key != "" and _pilot_voice_streams.has(alias_key):
		return _pick_pilot_voice_stream(sender, alias_key)

	return null

func _pick_pilot_voice_stream(sender: String, key: String) -> AudioStream:
	var streams_by_prefix: Dictionary = _pilot_voice_streams.get(key, {})
	if streams_by_prefix.is_empty():
		return null
	if lock_pilot_voice_to_callsign:
		var voice_prefix := _get_pilot_voice_prefix_for_sender(sender)
		if streams_by_prefix.has(voice_prefix):
			var locked_streams: Array = streams_by_prefix[voice_prefix]
			if not locked_streams.is_empty():
				return locked_streams[randi() % locked_streams.size()] as AudioStream
		if voice_prefix != "":
			return null

	for prefix in PILOT_AUDIO_PREFIXES:
		if streams_by_prefix.has(prefix):
			var streams_for_prefix: Array = streams_by_prefix[prefix]
			if not streams_for_prefix.is_empty():
				return streams_for_prefix[randi() % streams_for_prefix.size()] as AudioStream

	var fallback_prefixes := streams_by_prefix.keys()
	if fallback_prefixes.is_empty():
		return null
	var streams: Array = streams_by_prefix[fallback_prefixes[0]]
	if streams.is_empty():
		return null
	return streams[randi() % streams.size()] as AudioStream

func _get_pilot_voice_prefix_for_sender(sender: String) -> String:
	var sender_key := sender.strip_edges().to_lower()
	if sender_key.is_empty():
		return ""
	if _pilot_sender_voice_prefixes.has(sender_key):
		return str(_pilot_sender_voice_prefixes[sender_key])
	var available_prefixes := _get_available_pilot_voice_prefixes()
	if available_prefixes.is_empty():
		return ""
	if PilotRoster != null and is_instance_valid(PilotRoster) and PilotRoster.has_method("get_voice_prefix_for_callsign"):
		var roster_prefix := str(PilotRoster.get_voice_prefix_for_callsign(sender_key))
		if available_prefixes.has(roster_prefix):
			_pilot_sender_voice_prefixes[sender_key] = roster_prefix
			return roster_prefix
	var assigned_prefix := ""
	if not available_prefixes.has(assigned_prefix):
		assigned_prefix = available_prefixes[_stable_sender_index(sender_key, available_prefixes.size())]
	_pilot_sender_voice_prefixes[sender_key] = assigned_prefix
	return assigned_prefix

func _get_available_pilot_voice_prefixes() -> Array[String]:
	var result: Array[String] = []
	for prefix in PILOT_AUDIO_PREFIXES:
		if bool(_pilot_voice_prefixes_available.get(prefix, false)):
			result.append(prefix)
	return result

func _stable_sender_index(sender_key: String, modulo: int) -> int:
	if modulo <= 0:
		return 0
	var hash_value: int = 0
	for byte in sender_key.to_utf8_buffer():
		hash_value = int((hash_value * 31 + int(byte)) % 2147483647)
	return hash_value % modulo

func _pilot_voice_prefix_for_file(file_name: String) -> String:
	var lower_name := file_name.to_lower()
	for prefix in PILOT_AUDIO_PREFIXES:
		if lower_name.begins_with(prefix.to_lower()):
			return file_name.substr(0, prefix.length())
	return ""

func _is_pilot_sender(sender: String) -> bool:
	if sender == "Citadel":
		return false
	var sender_lc := sender.to_lower()
	return sender_lc.ends_with(" lead") \
		or sender_lc.contains(" two") \
		or sender_lc.contains(" three") \
		or sender_lc.contains(" four") \
		or sender_lc.contains(" flight")

func _normalize_citadel_phrase(phrase: String) -> String:
	var text := phrase.to_lower()
	for punctuation in [".", ",", "!", "?", ":", ";", "-", "_", "'", "\""]:
		text = text.replace(punctuation, " ")
	text = text.replace("rtb", "return to base")

	var input_tokens := text.split(" ", false)
	var output_tokens := PackedStringArray()
	var i := 0
	while i < input_tokens.size():
		var token := input_tokens[i]
		if token == "angels" and i + 1 < input_tokens.size() and input_tokens[i + 1].is_valid_int():
			i += 2
			continue
		if (token == "cap" or token == "cas" or token == "intercept") \
				and i + 1 < input_tokens.size() and input_tokens[i + 1] == "mission":
			i += 1
			continue
		if i + 1 < input_tokens.size() and input_tokens[i + 1] == "flight":
			output_tokens.append("archer")
		else:
			output_tokens.append(token)
		i += 1
	return " ".join(output_tokens)

func _normalize_pilot_phrase(phrase: String) -> String:
	var text := phrase.to_lower()
	for punctuation in [".", ",", "!", "?", ":", ";", "-", "_", "'", "\"", "[", "]", "—", "–"]:
		text = text.replace(punctuation, " ")
	text = text.replace("rtb", "returning to base")

	var input_tokens := text.split(" ", false)
	var output_tokens := PackedStringArray()
	for token in input_tokens:
		if token.is_empty():
			continue
		output_tokens.append(token)
	return " ".join(output_tokens)

func _canonical_pilot_voice_key(phrase: String) -> String:
	var key := _normalize_pilot_phrase(phrase)

	match key:
		"roger on station nothing up ere":
			return _normalize_pilot_phrase("Roger. On station. Sky is quiet.")
		"wilco climbing to altitude watch your spacing yeah":
			return _normalize_pilot_phrase("Wilco. Climbing to altitude. Watch your spacing.")
		"copy breaking off let s ave it":
			return _normalize_pilot_phrase("Copy. Breaking off. Blyad, let's go get them.")
		"roger cleared hot i see my line yeah":
			return _normalize_pilot_phrase("Roger. Cleared hot. I see my line.")
		"copy turning for ome":
			return _normalize_pilot_phrase("Copy. Turning for home.")
		"roger flight on me time to find the boat innit":
			return _normalize_pilot_phrase("Roger. Flight, on me. Time to find the boat.")
		"wilco close it up good work today proper good work":
			return _normalize_pilot_phrase("Wilco. Close it up. Good work today. Good work.")
		"copy going after em bloody hell let s go":
			return _normalize_pilot_phrase("Copy. Going after them. Bozhe miy, here we go.")
		"copy back on patrol sorted":
			return _normalize_pilot_phrase("Copy. Back on patrol.")
		"wilco flight get down low watch for ground fire yeah":
			return _normalize_pilot_phrase("Wilco. Flight. Push it low. Watch for ground fire.")
		"off the deck gear up climbing to station":
			return _normalize_pilot_phrase("Off the deck. Gear up, climbing to station.")
		"airborne coming around what s the picture":
			return _normalize_pilot_phrase("Airborne. Coming around. What is the picture?")
		"up and away flight close on me yeah":
			return _normalize_pilot_phrase("Up and away. Blyad. Flight, form on my wing.")
		"target acquired going in cover my six":
			return _normalize_pilot_phrase("Target acquired. I'm going in. Cover my six.")
		"two tally target s mine":
			return _normalize_pilot_phrase("Two, tally. Target is mine.")
		"copy lead pickle s ot":
			return _normalize_pilot_phrase("Copy lead. Pickle is hot.")
		"splash one get in":
			return _normalize_pilot_phrase("Splash one. Slava Ukraini.")
		"got im bloody hell good kill":
			return _normalize_pilot_phrase("Got him. Blyad, good kill.")
		"e s down yeah":
			return _normalize_pilot_phrase("He's down. Chort vozmy.")
		"confirmed kill ave that":
			return _normalize_pilot_phrase("Confirmed kill. Yes. Yes.")
		"bingo fuel returning to base old my spot":
			return _normalize_pilot_phrase("Bingo fuel. RTB. Hold my spot.")
		"running dry eading back cover my slot cheers":
			return _normalize_pilot_phrase("Running dry. Heading back. Cover my slot.")
		"taking its bollocks breaking off breaking off":
			return _normalize_pilot_phrase("Taking hits. Blyad. Breaking off, breaking off.")
		"i m taking fire sod it":
			return _normalize_pilot_phrase("I'm taking fire. Chort.")
		"ground fire bloody hell taking evasive":
			return _normalize_pilot_phrase("Ground fire. Yob tvoyu mat. Taking evasive.")
		"i m it falling back checking systems":
			return _normalize_pilot_phrase("Hit. I'm hit. Disengaging. Assessing damage.")

	return key

func _pilot_voice_alias_key(body: String) -> String:
	var key := _normalize_pilot_phrase(body)

	if key.begins_with("understood climbing"):
		return _normalize_pilot_phrase("Wilco. Climbing to altitude. Watch your spacing.")
	if key == "copy wilco":
		return _normalize_pilot_phrase("Copy. Orbiting. Keeping watch.")
	if key == "roger on station":
		return _normalize_pilot_phrase("Roger. On station. Sky is quiet.")

	if key == "copy rolling in":
		return _normalize_pilot_phrase("Copy. Breaking off. Blyad, let's go get them.")
	if key == "roger cleared hot":
		return _normalize_pilot_phrase("Roger. Cleared hot. I see my line.")
	if key == "understood selecting target":
		return _normalize_pilot_phrase("Understood. Tally. Stay sharp out there.")

	if key == "copy rtb" or key == "roger heading home":
		return _normalize_pilot_phrase("Copy. Turning for home.")
	if key == "wilco flight form up":
		return _normalize_pilot_phrase("Wilco. Close it up. Good work today. Good work.")

	if key == "copy going to intercept":
		return _normalize_pilot_phrase("Copy. Going after them. Bozhe miy, here we go.")
	if key == "roger tally engaging":
		return _normalize_pilot_phrase("Tally. I'm in. Engaging.")
	if key == "wilco flight weapons free":
		return _normalize_pilot_phrase("Wilco. Flight. Weapons free. Call your targets.")

	if key == "copy resuming cap":
		return _normalize_pilot_phrase("Copy. Back on patrol.")
	if key == "roger back on patrol":
		return _normalize_pilot_phrase("Roger. Back on station. Stay sharp.")
	if key == "wilco flight form up back on the clock":
		return _normalize_pilot_phrase("Wilco. Flight, form up. Back on the clock.")

	if key == "roger selecting targets":
		return _normalize_pilot_phrase("Roger. Got targets. Flight, sort yourselves out.")
	if key == "wilco flight going for the deck":
		return _normalize_pilot_phrase("Wilco. Flight. Push it low. Watch for ground fire.")

	if key == "airborne climbing to station":
		return _normalize_pilot_phrase("Airborne. Coming around. What is the picture?")
	if key == "off the deck coming around":
		return _normalize_pilot_phrase("Off the deck. Gear up, climbing to station.")
	if key == "up and away":
		return _normalize_pilot_phrase("Up and away. Blyad. Flight, form on my wing.")

	if key.begins_with("target acquired rolling in"):
		return _normalize_pilot_phrase("Target acquired. I'm going in. Cover my six.")
	if key.begins_with("lead s on"):
		return _normalize_pilot_phrase("Lead's in on target. Committing.")
	if key.begins_with("engaging"):
		return _normalize_pilot_phrase("Tally. Rolling in hot. Flight, find your marks.")
	if key.begins_with("two tally"):
		return _normalize_pilot_phrase("Two, tally. Target is mine.")
	if key.contains("engaging the"):
		return _normalize_pilot_phrase("In on target. Engaging.")
	if key.begins_with("copy i ve got"):
		return _normalize_pilot_phrase("Copy lead. Pickle is hot.")

	if key == "splash one":
		return _normalize_pilot_phrase("Splash one. Slava Ukraini.")
	if key == "target destroyed searching":
		return _normalize_pilot_phrase("He's down. Chort vozmy.")
	if key == "kill continuing attack":
		return _normalize_pilot_phrase("Got him. Blyad, good kill.")

	if key == "bingo fuel returning to base":
		return _normalize_pilot_phrase("Bingo fuel. RTB. Hold my spot.")
	if key == "taking hits breaking off":
		return _normalize_pilot_phrase("Taking hits. Blyad. Breaking off, breaking off.")
	if key == "taking fire evading":
		return _normalize_pilot_phrase("Ground fire. Yob tvoyu mat. Taking evasive.")
	if key == "hit disengaging":
		return _normalize_pilot_phrase("Hit. I'm hit. Disengaging. Assessing damage.")

	return ""

func _enqueue_radio_voice_stream(stream: AudioStream, cooldown_key: String = "") -> void:
	if stream == null:
		return
	var now_s := Time.get_ticks_msec() / 1000.0
	_prune_recent_radio_barks(now_s)
	if cooldown_key != "":
		if _is_radio_bark_on_cooldown(cooldown_key, now_s):
			return
		if _radio_voice_queue_has_bark(cooldown_key):
			return
	_citadel_voice_queue.append({
		stream = stream,
		cooldown_key = cooldown_key,
		expire_at = now_s + maxf(radio_voice_queue_max_age_s, 0.1),
	})
	_prune_expired_radio_voice_queue(now_s)

func _prune_expired_radio_voice_queue(now_s: float = -1.0) -> void:
	if now_s < 0.0:
		now_s = Time.get_ticks_msec() / 1000.0
	_citadel_voice_queue = _citadel_voice_queue.filter(func(entry): return _is_radio_voice_entry_valid(entry, now_s))

func _is_radio_voice_entry_valid(entry, now_s: float) -> bool:
	if typeof(entry) != TYPE_DICTIONARY:
		return false
	if not entry.has("stream") or not (entry.stream is AudioStream):
		return false
	return float(entry.get("expire_at", 0.0)) > now_s

func _radio_voice_queue_has_bark(cooldown_key: String) -> bool:
	if cooldown_key == "":
		return false
	for entry in _citadel_voice_queue:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("cooldown_key", "")) == cooldown_key:
			return true
	return false

func _is_radio_bark_on_cooldown(cooldown_key: String, now_s: float) -> bool:
	if radio_bark_repeat_cooldown_s <= 0.0:
		return false
	if not _recent_radio_bark_times.has(cooldown_key):
		return false
	var last_played_s := float(_recent_radio_bark_times[cooldown_key])
	return now_s - last_played_s < radio_bark_repeat_cooldown_s

func _mark_radio_bark_played(cooldown_key: String, now_s: float) -> void:
	if cooldown_key == "":
		return
	_recent_radio_bark_times[cooldown_key] = now_s
	_prune_recent_radio_barks(now_s)

func _prune_recent_radio_barks(now_s: float) -> void:
	var keep_for_s := maxf(radio_bark_repeat_cooldown_s, 0.0) + maxf(radio_voice_queue_max_age_s, 0.1)
	if keep_for_s <= 0.0:
		_recent_radio_bark_times.clear()
		return
	var stale_keys := []
	for key in _recent_radio_bark_times.keys():
		if now_s - float(_recent_radio_bark_times[key]) > keep_for_s:
			stale_keys.append(key)
	for key in stale_keys:
		_recent_radio_bark_times.erase(key)

func _radio_bark_cooldown_key(sender: String, body: String) -> String:
	if sender == "Citadel":
		return "citadel:" + _normalize_citadel_phrase(body)
	return "pilot:" + _normalize_pilot_phrase(body)

func _play_next_citadel_voice_clip() -> void:
	if _radio_voice_player == null:
		return
	if _radio_voice_player.playing:
		return
	_prune_expired_radio_voice_queue()
	if _citadel_voice_queue.is_empty():
		return

	var entry: Dictionary = _citadel_voice_queue.pop_front()
	var stream: AudioStream = entry.stream as AudioStream
	var cooldown_key := str(entry.get("cooldown_key", ""))
	var now_s := Time.get_ticks_msec() / 1000.0
	if _is_radio_bark_on_cooldown(cooldown_key, now_s):
		_play_next_citadel_voice_clip()
		return
	var stream_length := stream.get_length()
	if stream_length <= 0.0:
		stream_length = 2.5
	_start_radio_static_for(radio_static_pre_roll_s + stream_length + radio_static_post_roll_s)
	_trigger_radio_squelch_burst()

	var pre_roll_timer := get_tree().create_timer(radio_static_pre_roll_s)
	pre_roll_timer.timeout.connect(func() -> void:
		if not _is_radio_voice_entry_valid(entry, Time.get_ticks_msec() / 1000.0):
			_play_next_citadel_voice_clip()
			return
		if _radio_voice_player == null or _radio_voice_player.playing:
			_citadel_voice_queue.push_front(entry)
			return
		_radio_voice_player.stream = stream
		_radio_voice_player.pitch_scale = 1.0
		_mark_radio_bark_played(cooldown_key, Time.get_ticks_msec() / 1000.0)
		_radio_voice_player.play()
	)

func _enqueue(sender: String, recipient: String, body: String) -> void:
	_messages.append({
		sender    = sender,
		recipient = recipient,
		body      = body,
		expire_at = Time.get_ticks_msec() / 1000.0 + message_linger_s,
	})
	while _messages.size() > max_visible:
		_messages.pop_front()
	_refresh_log()
	if use_tts:
		_tts_queue.append("%s to %s. %s" % [sender, recipient, body])

func _expire_messages() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var before := _messages.size()
	_messages = _messages.filter(func(m): return m.expire_at > now)
	if _messages.size() != before:
		_refresh_log()

func _refresh_log() -> void:
	if not _log:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var lines := ""
	for msg in _messages:
		# Fade to 40% in the last 2 seconds
		var alpha := 1.0
		var time_left: float = float(msg.expire_at) - now
		if time_left < 2.0:
			alpha = lerpf(0.35, 1.0, time_left / 2.0)
		var hex := "%02x" % int(alpha * 255)
		lines += "[color=#%s88ff88][b]%s → %s.[/b][/color][color=#%scccccc] %s[/color]\n" % [
			hex, msg.sender.to_upper(), msg.recipient.to_upper(), hex, msg.body
		]
	_log.text = lines

# ── Internal: TTS ──────────────────────────────────────────────────────────────

func _drain_tts_queue() -> void:
	if _tts_queue.is_empty():
		return
	if DisplayServer.tts_is_speaking():
		return
	var text: String = _tts_queue.pop_front()
	var voices := DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty():
		return
	DisplayServer.tts_speak(text, voices[0], tts_volume, tts_rate, tts_pitch)

func _setup_radio_audio() -> void:
	_ensure_radio_bus()
	_radio_test_stream = load(RADIO_TEST_STREAM_PATH)

	_radio_voice_player = AudioStreamPlayer.new()
	_radio_voice_player.bus = RADIO_BUS_NAME
	_radio_voice_player.volume_db = radio_voice_gain_db
	_radio_voice_player.finished.connect(_on_radio_voice_finished)
	add_child(_radio_voice_player)

	var static_generator := AudioStreamGenerator.new()
	static_generator.mix_rate = RADIO_STATIC_MIX_RATE
	static_generator.buffer_length = 0.12

	_radio_static_player = AudioStreamPlayer.new()
	_radio_static_player.bus = RADIO_BUS_NAME
	_radio_static_player.stream = static_generator
	_radio_static_player.volume_db = -9.0
	add_child(_radio_static_player)
	_radio_static_player.play()
	_radio_static_playback = _radio_static_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _ensure_radio_bus() -> void:
	var bus_index := AudioServer.get_bus_index(RADIO_BUS_NAME)
	if bus_index == -1:
		bus_index = AudioServer.get_bus_count()
		AudioServer.add_bus(bus_index)
		AudioServer.set_bus_name(bus_index, RADIO_BUS_NAME)
		AudioServer.set_bus_send(bus_index, "Master")

	# Always rebuild effects so export var changes take effect on restart.
	for i in range(AudioServer.get_bus_effect_count(bus_index) - 1, -1, -1):
		AudioServer.remove_bus_effect(bus_index, i)

	# HPF: cut bass/warmth below 350 Hz
	var high_pass := AudioEffectHighPassFilter.new()
	high_pass.cutoff_hz = radio_highpass_cutoff_hz
	AudioServer.add_bus_effect(bus_index, high_pass)

	# LPF: cut air/clarity above 3400 Hz
	var low_pass := AudioEffectLowPassFilter.new()
	low_pass.cutoff_hz = radio_lowpass_cutoff_hz
	low_pass.resonance = radio_filter_resonance
	AudioServer.add_bus_effect(bus_index, low_pass)

	# EQ boost: push midrange presence around 1.5 kHz
	var eq := AudioEffectEQ10.new()
	eq.set_band_gain_db(3, 4.5)   # ~800 Hz
	eq.set_band_gain_db(4, 5.5)   # ~1.6 kHz
	eq.set_band_gain_db(5, 3.0)   # ~3.2 kHz
	AudioServer.add_bus_effect(bus_index, eq)

	# Compressor: crush dynamics hard
	var compressor := AudioEffectCompressor.new()
	compressor.threshold = -24.0
	compressor.ratio = 12.0
	compressor.attack_us = 2000.0
	compressor.release_ms = 60.0
	compressor.gain = 10.0
	AudioServer.add_bus_effect(bus_index, compressor)

	# Hard clip / saturation: peaks break up, crushed and dirty
	var distortion := AudioEffectDistortion.new()
	distortion.mode = AudioEffectDistortion.MODE_CLIP
	distortion.drive = 0.65
	distortion.pre_gain = 8.0
	distortion.keep_hf_hz = 1800.0
	AudioServer.add_bus_effect(bus_index, distortion)

	# Limiter
	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = -2.0
	limiter.threshold_db = -6.0
	AudioServer.add_bus_effect(bus_index, limiter)

func _update_radio_static(delta: float) -> void:
	if _radio_static_playback == null and _radio_static_player != null:
		_radio_static_playback = _radio_static_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _radio_static_playback == null:
		return

	var now_s := Time.get_ticks_msec() / 1000.0
	var target_mix := 1.0 if now_s < _radio_static_until_s else 0.0
	_radio_static_mix = move_toward(_radio_static_mix, target_mix, delta * 10.0)
	_update_radio_voice_damage(delta, now_s)

	var frames_available := _radio_static_playback.get_frames_available()
	for i in range(frames_available):
		var sample := _next_radio_static_sample()
		_radio_static_playback.push_frame(Vector2(sample, sample))

func _update_radio_voice_damage(delta: float, now_s: float) -> void:
	if _radio_voice_player == null:
		return
	if not _radio_voice_player.playing:
		_radio_voice_player.volume_db = radio_voice_gain_db
		_radio_voice_player.pitch_scale = 1.0
		_radio_voice_flutter_timer_s = 0.0
		_radio_voice_volume_offset_db = 0.0
		_radio_voice_pitch_offset = 0.0
		return

	if now_s >= _radio_dropout_until_s and _radio_rng.randf() < radio_dropout_chance_per_frame:
		_radio_dropout_until_s = now_s + _radio_rng.randf_range(radio_dropout_min_s, radio_dropout_max_s)

	_radio_voice_flutter_timer_s -= delta
	if _radio_voice_flutter_timer_s <= 0.0:
		_radio_voice_flutter_timer_s = maxf(radio_voice_flutter_update_s, 0.04)
		_radio_voice_volume_offset_db = _radio_rng.randf_range(-0.45, 0.25)
		_radio_voice_pitch_offset = _radio_rng.randf_range(-radio_pitch_jitter, radio_pitch_jitter)

	if now_s < _radio_dropout_until_s:
		_radio_voice_player.volume_db = radio_dropout_volume_db
	else:
		_radio_voice_player.volume_db = radio_voice_gain_db + _radio_voice_volume_offset_db

	_radio_voice_player.pitch_scale = 1.0 + _radio_voice_pitch_offset

func _next_radio_static_sample() -> float:
	var hiss := _radio_rng.randf_range(-1.0, 1.0) * radio_static_noise_gain * _radio_static_mix

	if _radio_crackle_frames_left <= 0 and _radio_static_mix > 0.02 and _radio_rng.randf() < radio_crackle_chance_per_frame:
		_radio_crackle_frames_left = _radio_rng.randi_range(6, 52)
		_radio_crackle_level = _radio_rng.randf_range(-1.0, 1.0) * radio_static_crackle_gain * _radio_static_mix

	var crackle := 0.0
	if _radio_crackle_frames_left > 0:
		var crackle_fade := clampf(float(_radio_crackle_frames_left) / 24.0, 0.0, 1.0)
		crackle = _radio_crackle_level * crackle_fade
		crackle += _radio_rng.randf_range(-1.0, 1.0) * (radio_static_crackle_gain * 0.35) * _radio_static_mix
		_radio_crackle_frames_left -= 1

	var squelch := 0.0
	if _radio_squelch_frames_left > 0:
		var elapsed_frames := _radio_squelch_total_frames - _radio_squelch_frames_left
		var t := float(elapsed_frames) / maxf(float(_radio_squelch_total_frames), 1.0)
		var attack := clampf(t / 0.18, 0.0, 1.0)
		var release := 1.0 - clampf((t - 0.45) / 0.55, 0.0, 1.0)
		var envelope := attack * release
		squelch = _radio_rng.randf_range(-1.0, 1.0) * _radio_squelch_gain * envelope
		_radio_squelch_frames_left -= 1

	return clampf(hiss + crackle + squelch, -1.0, 1.0)

func _start_radio_static_for(duration_s: float) -> void:
	var now_s := Time.get_ticks_msec() / 1000.0
	_radio_static_until_s = maxf(_radio_static_until_s, now_s + duration_s)

func _trigger_radio_squelch_burst(duration_s: float = -1.0, gain: float = -1.0) -> void:
	var burst_s := radio_squelch_burst_s if duration_s < 0.0 else duration_s
	if burst_s <= 0.0:
		return
	_radio_squelch_total_frames = maxi(1, ceili(float(RADIO_STATIC_MIX_RATE) * burst_s))
	_radio_squelch_frames_left = _radio_squelch_total_frames
	_radio_squelch_gain = maxf(radio_squelch_burst_gain if gain < 0.0 else gain, 0.0)

func _estimate_radio_test_length() -> float:
	if _radio_test_stream == null:
		return 3.0
	var length_s := _radio_test_stream.get_length()
	return length_s if length_s > 0.0 else 3.0

func _on_radio_voice_finished() -> void:
	_radio_dropout_until_s = 0.0
	_start_radio_static_for(radio_static_post_roll_s)
	_trigger_radio_squelch_burst(radio_squelch_burst_s * 0.8, radio_squelch_burst_gain * 0.75)
	if not _citadel_voice_queue.is_empty():
		var post_roll_timer := get_tree().create_timer(radio_static_post_roll_s)
		post_roll_timer.timeout.connect(_play_next_citadel_voice_clip)

# ── Internal: display construction ────────────────────────────────────────────

func _build_display() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 20  # above all game UI
	add_child(_canvas)

	# Plain Panel with a fixed size — PanelContainer resizes to content and
	# breaks anchor-based positioning inside a CanvasLayer.
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.size = Vector2(580, 228)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.05, 0.0, 0.72)
	style.border_color = Color(0.1, 0.6, 0.15, 0.6)
	style.set_border_width_all(1)
	style.set_content_margin_all(0)
	_panel.add_theme_stylebox_override("panel", style)
	_canvas.add_child(_panel)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_active = false
	_log.fit_content = false
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.position = Vector2(10, 8)
	_log.size = Vector2(560, 176)
	_log.add_theme_color_override("default_color", Color(0.2, 1.0, 0.3))
	_log.add_theme_font_size_override("normal_font_size", 13)
	_panel.add_child(_log)

	var divider := ColorRect.new()
	divider.color = Color(0.1, 0.6, 0.15, 0.4)
	divider.position = Vector2(10, 190)
	divider.size = Vector2(560, 1)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(divider)

	_status_label = Label.new()
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.position = Vector2(10, 196)
	_status_label.size = Vector2(560, 18)
	_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	_status_label.add_theme_font_size_override("font_size", 13)
	_panel.add_child(_status_label)

func _refresh_status() -> void:
	if not _status_label:
		return
	var parts: Array[String] = []
	if AirOpsManager == null:
		_status_label.text = ""
		return
	for f in AirOpsManager.flights:
		parts.append("%s: %d" % [f.flight_name.left(1), f.strength()])
	_status_label.text = "  ".join(parts)

func _pin_to_bottom() -> void:
	if not _panel:
		return
	var vp_size := get_tree().get_root().get_visible_rect().size
	_panel.position = Vector2(16.0, vp_size.y - _panel.size.y - 16.0)

# ── Utility ────────────────────────────────────────────────────────────────────

func _pick(options: Array) -> String:
	return options[randi() % options.size()]
