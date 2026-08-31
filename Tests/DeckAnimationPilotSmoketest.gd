extends SceneTree

const DECK_PILOT_SCENE := "res://LandCarrier/DeckAnimationPilot.tscn"
const CARRIER_SCENE := "res://LandCarrier/LandCarrier2.tscn"
const EXPECTED_CLIPS: Array[StringName] = [
	&"idle_breathing", &"idle_neutral", &"walk", &"run", &"turn_left",
	&"turn_right", &"sit_1", &"sit_2", &"piloting", &"salute", &"wave",
	&"die", &"parachute",
]
const LOOPING_CLIPS: Array[StringName] = [
	&"idle_breathing", &"idle_neutral", &"walk", &"run", &"sit_1", &"sit_2",
	&"piloting", &"parachute",
]
const IN_PLACE_REVIEW_CLIPS: Array[StringName] = [
	&"walk", &"run", &"turn_left", &"turn_right",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_pilot := load(DECK_PILOT_SCENE) as PackedScene
	if packed_pilot == null:
		_fail("deck animation pilot scene did not load")
		return
	var deck_pilot := packed_pilot.instantiate() as Node3D
	if deck_pilot == null:
		_fail("deck animation pilot scene did not instantiate")
		return
	root.add_child(deck_pilot)
	await process_frame

	var animation_player := deck_pilot.get_node_or_null("Pilot/BakedAnimationPlayer") as AnimationPlayer
	if animation_player == null:
		_fail("baked AnimationPlayer was not found")
		return
	var clips: Array[StringName] = []
	clips.assign(deck_pilot.call("get_animation_names"))
	if clips != EXPECTED_CLIPS:
		_fail("unexpected animation sequence: %s" % str(clips))
		return
	if StringName(deck_pilot.call("get_current_animation")) != EXPECTED_CLIPS[0]:
		_fail("initial clip was not idle_breathing")
		return
	var fixed_transform := deck_pilot.transform
	var visible_pilot := deck_pilot.get_node_or_null("Pilot") as Node3D
	if visible_pilot == null:
		_fail("visible pilot root was not found")
		return
	var visible_pilot_base_transform := visible_pilot.transform

	for clip_index in range(EXPECTED_CLIPS.size()):
		var expected_clip := EXPECTED_CLIPS[clip_index]
		if clip_index > 0:
			_send_key(deck_pilot, KEY_A)
		if StringName(deck_pilot.call("get_current_animation")) != expected_clip:
			_fail("A did not select %s" % expected_clip)
			return
		if animation_player.current_animation != expected_clip or not animation_player.is_playing():
			_fail("%s was not playing" % expected_clip)
			return
		var animation := animation_player.get_animation(expected_clip)
		if animation == null:
			_fail("%s was unavailable in the deck review library" % expected_clip)
			return
		var should_loop := LOOPING_CLIPS.has(expected_clip)
		var does_loop := animation.loop_mode != Animation.LOOP_NONE
		if does_loop != should_loop:
			_fail("%s loop=%s, expected %s" % [expected_clip, does_loop, should_loop])
			return
		if IN_PLACE_REVIEW_CLIPS.has(expected_clip) \
				and not _has_stationary_horizontal_root(animation):
			_fail("%s retained horizontal root motion in the stationary review" % expected_clip)
			return
		if expected_clip in [&"turn_left", &"turn_right"]:
			animation_player.seek(animation.length * 0.5, true)
			animation_player.advance(0.0)
			deck_pilot.call("_process", 0.0)
			if not visible_pilot.position.is_equal_approx(visible_pilot_base_transform.origin):
				_fail("%s moved the visible pilot away from the review point" % expected_clip)
				return
			var preview_yaw := absf(rad_to_deg(visible_pilot.rotation.y))
			if preview_yaw < 40.0 or preview_yaw > 50.0:
				_fail("%s did not preview its matching body turn (yaw=%.1f)" % [
					expected_clip, preview_yaw,
				])
				return
		if not deck_pilot.transform.is_equal_approx(fixed_transform):
			_fail("deck pilot node moved while changing animations")
			return
	var death_animation := animation_player.get_animation(&"die")
	if death_animation == null or _horizontal_root_span(death_animation) < 0.1:
		_fail("death clip lost the internal forward root travel needed for a natural fall")
		return

	_send_key(deck_pilot, KEY_A)
	if StringName(deck_pilot.call("get_current_animation")) != EXPECTED_CLIPS[0]:
		_fail("animation sequence did not wrap to idle_breathing")
		return
	_send_key(deck_pilot, KEY_B)
	if StringName(deck_pilot.call("get_current_animation")) != EXPECTED_CLIPS[0]:
		_fail("a non-A key changed the animation")
		return

	var packed_carrier := load(CARRIER_SCENE) as PackedScene
	var carrier := packed_carrier.instantiate() as Node3D if packed_carrier != null else null
	if carrier == null:
		_fail("gameplay carrier scene did not instantiate")
		return
	var placed_pilot := carrier.get_node_or_null("DeckAnimationPilot") as Node3D
	if placed_pilot == null or not placed_pilot.is_in_group("deck_animation_pilot"):
		_fail("deck animation pilot was not placed on LandCarrier2")
		return
	if absf(placed_pilot.position.y - 0.03) > 0.001:
		_fail("deck animation pilot was not placed at deck height")
		return
	var main_menu_source := FileAccess.get_file_as_string("res://UI/MainMenu.gd")
	if not main_menu_source.contains("\"DeckAnimationPilot\""):
		_fail("decorative main-menu carrier does not remove the deck demonstrator")
		return

	print("[DeckAnimationPilotSmoketest] PASS clips=%d key=A fixed=%s deck_position=%s" % [
		clips.size(),
		str(deck_pilot.transform.is_equal_approx(fixed_transform)),
		str(placed_pilot.position),
	])
	carrier.free()
	deck_pilot.free()
	quit(0)


func _send_key(deck_pilot: Node3D, key: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = key
	event.keycode = key
	deck_pilot.call("_unhandled_key_input", event)


func _has_stationary_horizontal_root(animation: Animation) -> bool:
	var found_root_track := false
	for track_index in range(animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		if not String(animation.track_get_path(track_index)).ends_with(":root.x"):
			continue
		found_root_track = true
		var first := animation.track_get_key_value(track_index, 0) as Vector3
		for key_index in range(1, animation.track_get_key_count(track_index)):
			var value := animation.track_get_key_value(track_index, key_index) as Vector3
			if absf(value.x - first.x) > 0.00001 or absf(value.z - first.z) > 0.00001:
				return false
	return found_root_track


func _horizontal_root_span(animation: Animation) -> float:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for track_index in range(animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		if not String(animation.track_get_path(track_index)).ends_with(":root.x"):
			continue
		for key_index in range(animation.track_get_key_count(track_index)):
			var value := animation.track_get_key_value(track_index, key_index) as Vector3
			var horizontal := Vector2(value.x, value.z)
			minimum = minimum.min(horizontal)
			maximum = maximum.max(horizontal)
	if not is_finite(minimum.x):
		return 0.0
	return (maximum - minimum).length()


func _fail(reason: String) -> void:
	push_error("[DeckAnimationPilotSmoketest] FAIL %s" % reason)
	quit(1)
