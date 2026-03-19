extends Node

const RADIO_TEST_STREAM_PATH := "res://Audio/Citadel voice test.mp3"
const RADIO_BUS_NAME := "Radio"

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
@export var radio_test_hotkey_enabled: bool = true
@export var radio_static_pre_roll_s: float = 0.08
@export var radio_static_post_roll_s: float = 0.20
@export var radio_voice_gain_db: float = -2.5
@export var radio_highpass_cutoff_hz: float = 900.0
@export var radio_lowpass_cutoff_hz: float = 1850.0
@export var radio_filter_resonance: float = 1.2
@export var radio_static_noise_gain: float = 0.022
@export var radio_static_crackle_gain: float = 0.18
@export var radio_crackle_chance_per_frame: float = 0.014
@export var radio_dropout_chance_per_frame: float = 0.01
@export var radio_dropout_min_s: float = 0.02
@export var radio_dropout_max_s: float = 0.09
@export var radio_dropout_volume_db: float = -22.0
@export var radio_pitch_jitter: float = 0.035

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
var _radio_rng := RandomNumberGenerator.new()
var _radio_static_until_s: float = 0.0
var _radio_static_mix: float = 0.0
var _radio_crackle_frames_left: int = 0
var _radio_crackle_level: float = 0.0
var _radio_request_serial: int = 0
var _radio_dropout_until_s: float = 0.0

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_display()
	_radio_rng.randomize()
	_setup_radio_audio()

func _process(delta: float) -> void:
	_expire_messages()
	_pin_to_bottom()
	_refresh_status()
	if use_tts:
		_drain_tts_queue()
	_update_radio_static(delta)

func _input(event: InputEvent) -> void:
	if not radio_test_hotkey_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_V:
		play_citadel_test()

# ── Public API ─────────────────────────────────────────────────────────────────

## Send a radio transmission immediately.
func transmit(sender: String, recipient: String, body: String) -> void:
	_enqueue(sender, recipient, body)
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

	var pre_roll_timer := get_tree().create_timer(radio_static_pre_roll_s)
	pre_roll_timer.timeout.connect(func() -> void:
		if request_serial != _radio_request_serial:
			return
		_radio_voice_player.stream = _radio_test_stream
		_radio_voice_player.play()
	)

# ── Standard phrase helpers ────────────────────────────────────────────────────
## Call these from AirOpsManager / Flight to get consistent phrasing.

func say_cap_order(flight_name: String, altitude_m: float) -> void:
	var angels := roundi(altitude_m / 300.0)  # rough feet/300 ≈ angels
	var bodies := [
		"Maintain combat air patrol. Angels %d. Engage any bandits." % angels,
		"Hold CAP station. Angels %d. Weapons free on bandits." % angels,
		"Combat air patrol. Angels %d. Clear the skies." % angels,
	]
	transmit("Citadel", "%s flight" % flight_name, _pick(bodies))
	transmit_delayed("%s lead" % flight_name, "Citadel", _pick([
		"Copy. Wilco.",
		"Roger. On station.",
		"Understood. Climbing to angels %d." % angels,
	]), randf_range(1.2, 2.5))

func say_cas_order(flight_name: String) -> void:
	var bodies := [
		"Ground attack. Cleared hot on enemy armor.",
		"Weapons free on ground targets. Watch your altitude.",
		"Engage ground targets. Cleared hot. Keep it tight.",
	]
	transmit("Citadel", "%s flight" % flight_name, _pick(bodies))
	transmit_delayed("%s lead" % flight_name, "Citadel", _pick([
		"Copy. Rolling in.",
		"Roger. Cleared hot.",
		"Understood. Selecting target.",
	]), randf_range(1.0, 2.2))

func say_rtb_order(flight_name: String) -> void:
	var bodies := [
		"RTB. Good hunting.",
		"Return to base. The deck is ready.",
		"Break off and RTB. Nice work.",
	]
	transmit("Citadel", "%s flight" % flight_name, _pick(bodies))
	transmit_delayed("%s lead" % flight_name, "Citadel", _pick([
		"Copy. RTB.",
		"Roger. Heading home.",
		"Wilco. Flight, form up.",
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
		"Target destroyed. Searching.",
		"Kill. Continuing attack.",
	]
	transmit(callsign, "Citadel", _pick(bodies))

func say_bingo(callsign: String) -> void:
	transmit(callsign, "Citadel", "Bingo fuel. Returning to base.")

func say_taking_fire(callsign: String) -> void:
	var bodies := [
		"Taking hits. Breaking off.",
		"Taking fire. Evading.",
		"Hit. Disengaging.",
	]
	transmit(callsign, "Citadel", _pick(bodies))

# ── Internal: message management ──────────────────────────────────────────────

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
	static_generator.mix_rate = 22050
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

	if AudioServer.get_bus_effect_count(bus_index) > 0:
		return

	var high_pass := AudioEffectHighPassFilter.new()
	high_pass.cutoff_hz = radio_highpass_cutoff_hz
	AudioServer.add_bus_effect(bus_index, high_pass)

	var low_pass := AudioEffectLowPassFilter.new()
	low_pass.cutoff_hz = radio_lowpass_cutoff_hz
	low_pass.resonance = radio_filter_resonance
	AudioServer.add_bus_effect(bus_index, low_pass)

	var gain := AudioEffectAmplify.new()
	gain.volume_db = -2.0
	AudioServer.add_bus_effect(bus_index, gain)

	var distortion := AudioEffectDistortion.new()
	distortion.mode = AudioEffectDistortion.MODE_CLIP
	distortion.drive = 0.22
	distortion.pre_gain = 1.5
	distortion.keep_hf_hz = 1200.0
	AudioServer.add_bus_effect(bus_index, distortion)

func _update_radio_static(delta: float) -> void:
	if _radio_static_playback == null and _radio_static_player != null:
		_radio_static_playback = _radio_static_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _radio_static_playback == null:
		return

	var now_s := Time.get_ticks_msec() / 1000.0
	var target_mix := 1.0 if now_s < _radio_static_until_s else 0.0
	_radio_static_mix = move_toward(_radio_static_mix, target_mix, delta * 10.0)
	_update_radio_voice_damage(now_s)

	var frames_available := _radio_static_playback.get_frames_available()
	for i in range(frames_available):
		var sample := _next_radio_static_sample()
		_radio_static_playback.push_frame(Vector2(sample, sample))

func _update_radio_voice_damage(now_s: float) -> void:
	if _radio_voice_player == null:
		return
	if not _radio_voice_player.playing:
		_radio_voice_player.volume_db = radio_voice_gain_db
		_radio_voice_player.pitch_scale = 1.0
		return

	if now_s >= _radio_dropout_until_s and _radio_rng.randf() < radio_dropout_chance_per_frame:
		_radio_dropout_until_s = now_s + _radio_rng.randf_range(radio_dropout_min_s, radio_dropout_max_s)

	if now_s < _radio_dropout_until_s:
		_radio_voice_player.volume_db = radio_dropout_volume_db
	else:
		_radio_voice_player.volume_db = radio_voice_gain_db + _radio_rng.randf_range(-1.5, 0.8)

	_radio_voice_player.pitch_scale = 1.0 + _radio_rng.randf_range(-radio_pitch_jitter, radio_pitch_jitter)

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

	return clampf(hiss + crackle, -1.0, 1.0)

func _start_radio_static_for(duration_s: float) -> void:
	var now_s := Time.get_ticks_msec() / 1000.0
	_radio_static_until_s = maxf(_radio_static_until_s, now_s + duration_s)

func _estimate_radio_test_length() -> float:
	if _radio_test_stream == null:
		return 3.0
	var length_s := _radio_test_stream.get_length()
	return length_s if length_s > 0.0 else 3.0

func _on_radio_voice_finished() -> void:
	_radio_dropout_until_s = 0.0
	_start_radio_static_for(radio_static_post_roll_s)

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
