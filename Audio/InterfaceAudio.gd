extends Node
## One bounded UI voice, no hover noise or per-frame input polling.
const CLICK = preload("res://Audio/UI/click.wav")
const CONFIRM = preload("res://Audio/UI/confirm.wav")
const CANCEL = preload("res://Audio/UI/cancel.wav")
var _player: AudioStreamPlayer
var _last_ms: int = -1000
var sound_events: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.volume_db = -8.0
	_player.max_polyphony = 3
	add_child(_player)
	get_tree().node_added.connect(_watch_button)
	call_deferred("_scan", get_tree().root)

func _scan(node: Node) -> void:
	_watch_button(node)
	for child in node.get_children():
		_scan(child)

func _watch_button(node: Node) -> void:
	if node is BaseButton:
		var callback := _pressed.bind(node)
		if not node.pressed.is_connected(callback):
			node.pressed.connect(callback)

func _pressed(button: BaseButton) -> void:
	# A pressed handler may already have hidden the panel before this listener runs.
	if button.disabled or button.get_meta("silent_ui", false):
		return
	play_feedback(StringName(button.get_meta("audio_cue", "click")))

func play_feedback(cue: StringName = &"click") -> void:
	var now := Time.get_ticks_msec()
	if now - _last_ms < 45:
		return
	_last_ms = now
	_player.stream = CONFIRM if cue == &"confirm" else CANCEL if cue == &"cancel" else CLICK
	_player.play()
	sound_events += 1
