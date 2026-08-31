extends Node

class TestCarrier:
	extends LandCarrier
	var spawned_track_samples: Array[Transform3D] = []
	func _ready() -> void:
		pass
	func _spawn_track_mark_for_tread(tread_transform: Transform3D) -> void:
		spawned_track_samples.append(tread_transform)

class LazyResourceCarrier:
	extends LandCarrier
	func _ready() -> void:
		pass

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var carrier := TestCarrier.new()
	carrier.track_mark_max_active = 2
	carrier.set_physics_process(false)
	get_tree().root.add_child(carrier)
	carrier.set_physics_process(false)
	carrier._ensure_track_mark_resources()

	_expect(carrier._track_mark_material is ShaderMaterial, "track marks do not use the fade shader")
	_expect(carrier._track_mark_multimesh != null, "track mark MultiMesh was not created")
	if carrier._track_mark_multimesh != null:
		_expect(carrier._track_mark_multimesh.use_custom_data, "track mark MultiMesh custom data is disabled")
	var fade_shader: Shader = carrier._track_mark_material.shader
	_expect(fade_shader.code.contains("INSTANCE_CUSTOM"), "fade shader does not read per-mark lifetime data")
	_expect(fade_shader.code.contains("ALPHA"), "fade shader does not write transparent opacity")
	_expect(fade_shader.code.contains("fresh_brightness"), "fade shader does not lighten newly created marks")
	_expect(fade_shader.code.contains("fresh_lift_fraction"), "fade shader does not limit the fresh color lift by age")
	_expect(not fade_shader.code.contains("unshaded"), "track marks do not receive the terrain's scene lighting")
	var fresh_brightness: Variant = carrier._track_mark_material.get_shader_parameter(&"fresh_brightness")
	_expect(
		is_equal_approx(float(fresh_brightness), carrier.track_mark_fresh_brightness),
		"fresh track brightness did not reach the shared material"
	)
	_expect(float(fresh_brightness) > 1.0, "new track marks still begin at the darker aged color")

	var sand_color := Color(0.88, 0.80, 0.42, 1.0)
	var deeper_sand := carrier._get_track_mark_color_from_ground(sand_color)
	_expect(deeper_sand.get_luminance() < sand_color.get_luminance(), "track color is not darker than its sampled ground")
	_expect(deeper_sand.get_luminance() > sand_color.get_luminance() * 0.75, "track color is still being crushed toward black")
	_expect(deeper_sand.r > deeper_sand.g and deeper_sand.g > deeper_sand.b, "track color did not preserve the sampled sand hue")

	carrier._track_mark_entries.append({
		"transform": Transform3D.IDENTITY,
		"age": 0.0,
		"lifetime": 30.0,
		"spawn_time": 4.0,
		"color": Color(0.08, 0.06, 0.03, 1.0),
	})
	carrier._track_mark_clock_s = 4.0
	carrier._sync_track_mark_multimesh(true)
	var entry: Dictionary = carrier._track_mark_entries[0]
	var slot := int(entry.get("slot", -1))
	_expect(slot >= 0, "track mark did not receive a stable MultiMesh slot")
	_expect(is_equal_approx(float(entry.get("spawn_time", -1.0)), 4.0), "track mark did not retain its spawn time")
	_expect(is_equal_approx(float(entry.get("lifetime", -1.0)), 30.0), "track mark did not retain its lifetime")

	carrier._update_track_mark_lifetimes(15.0)
	var shader_time: Variant = carrier._track_mark_material.get_shader_parameter(&"track_time_s")
	_expect(is_equal_approx(float(shader_time), 19.0), "track fade clock was not updated smoothly")
	_expect(carrier._track_mark_entries.size() == 1, "track mark was removed before its lifetime")

	carrier._update_track_mark_lifetimes(15.0)
	_expect(carrier._track_mark_entries.is_empty(), "expired track mark was not removed")
	if slot >= 0:
		_expect(carrier._track_mark_free_slots.has(slot), "expired track mark slot was not released")

	# Normal movement must initialize the pool itself. The intro carrier does not
	# perform an origin shift or explicit MultiMesh sync before it starts driving.
	var lazy_carrier := LazyResourceCarrier.new()
	lazy_carrier.track_mark_max_active = 4
	lazy_carrier.track_mark_spawn_spacing_m = 2.0
	lazy_carrier.track_mark_min_speed_mps = 0.1
	lazy_carrier.set_physics_process(false)
	get_tree().root.add_child(lazy_carrier)
	lazy_carrier.set_physics_process(false)
	var lazy_tread := Node3D.new()
	lazy_carrier.add_child(lazy_tread)
	lazy_carrier._tread_nodes = [lazy_tread]
	lazy_carrier._mark_initial_placement_completed()
	lazy_carrier._update_track_marks(1.0, lazy_carrier.global_transform)
	lazy_tread.global_position = Vector3(0.0, 0.0, 3.0)
	lazy_carrier._update_track_marks(1.0, lazy_carrier.global_transform)
	_expect(lazy_carrier._track_mark_multimesh != null, "normal movement did not lazily create the track mark pool")
	_expect(lazy_carrier._track_mark_entries.size() == 1, "normal movement discarded its first track mark")

	# A menu/nav handoff is a teleport. It must replace the old trail with a
	# short heading-aligned seed and fully settle the suspension in that frame.
	lazy_carrier._tread_local_xz = [Vector2.ZERO]
	lazy_carrier._tread_initial_rot_y = [0.0]
	lazy_carrier.global_position = Vector3(1000.0, 40.0, 1000.0)
	lazy_carrier.settle_after_nonphysical_placement(6.0)
	var post_teleport_y := lazy_carrier.global_position.y
	lazy_carrier._update_tread_visuals(1.0 / 60.0, lazy_carrier.global_transform)
	_expect(
		absf(lazy_carrier.global_position.y - post_teleport_y) <= 0.05,
		"non-physical placement left the carrier body visibly settling"
	)
	for teleported_entry in lazy_carrier._track_mark_entries:
		var teleported_mark_transform := teleported_entry.get("transform", Transform3D.IDENTITY) as Transform3D
		_expect(
			teleported_mark_transform.origin.distance_to(lazy_carrier.global_position) < 100.0,
			"non-physical placement retained a cross-map trail segment"
		)

	# Each tread needs its own distance history: a shared carrier-centre distance
	# leaves holes on the outside track during turns.
	carrier.track_mark_spawn_spacing_m = 2.0
	carrier.track_mark_min_speed_mps = 0.1
	var test_tread := Node3D.new()
	carrier.add_child(test_tread)
	carrier._tread_nodes = [test_tread]
	var samples_before_startup_placement := carrier.spawned_track_samples.size()
	carrier._initial_placement_completed = false
	carrier._update_track_marks(1.0, carrier.global_transform)
	test_tread.global_position = Vector3(5000.0, 0.0, 5000.0)
	carrier._mark_initial_placement_completed()
	carrier._update_track_marks(1.0, carrier.global_transform)
	_expect(
		carrier.spawned_track_samples.size() == samples_before_startup_placement,
		"startup placement teleport emitted a cross-map track trail"
	)
	_expect(
		carrier._track_mark_tread_states.has(test_tread.get_instance_id()),
		"first post-placement frame did not seed tread history at the final position"
	)
	carrier._track_mark_tread_states.clear()
	test_tread.global_position = Vector3.ZERO
	carrier._update_track_marks_for_tread(test_tread, 1.0, true)
	test_tread.global_position = Vector3(0.0, 0.0, 5.0)
	carrier._update_track_marks_for_tread(test_tread, 1.0, true)
	_expect(carrier.spawned_track_samples.size() == 2, "tread travel did not emit evenly spaced track samples")
	if carrier.spawned_track_samples.size() == 2:
		_expect(is_equal_approx(carrier.spawned_track_samples[0].origin.z, 2.0), "first tread sample was not interpolated at its own spacing")
		_expect(is_equal_approx(carrier.spawned_track_samples[1].origin.z, 4.0), "second tread sample was not interpolated at its own spacing")
	var samples_before_origin_shift := carrier.spawned_track_samples.size()
	carrier.apply_origin_shift(Vector3(1000.0, 0.0, 0.0))
	test_tread.global_position -= Vector3(1000.0, 0.0, 0.0)
	carrier._update_track_marks_for_tread(test_tread, 1.0, true)
	_expect(carrier.spawned_track_samples.size() == samples_before_origin_shift, "floating-origin shift was mistaken for tread travel")

	# Reaching the cap must recycle the oldest slot immediately instead of
	# pausing trail creation until that mark's lifetime expires.
	var first_slot: int = carrier._acquire_track_mark_slot()
	carrier._track_mark_entries.append({"slot": first_slot, "age": 0.0, "lifetime": 30.0})
	var second_slot: int = carrier._acquire_track_mark_slot()
	carrier._track_mark_entries.append({"slot": second_slot, "age": 0.0, "lifetime": 30.0})
	var recycled_slot: int = carrier._acquire_track_mark_slot()
	_expect(recycled_slot == first_slot, "full track buffer did not recycle its oldest stable slot")
	_expect(carrier._track_mark_entries.size() == 1, "oldest capped track mark was not evicted")

	if _failures.is_empty():
		print("[LandCarrierTrackMarkFadeSmoketest] PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("[LandCarrierTrackMarkFadeSmoketest] " + failure)
		get_tree().quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
