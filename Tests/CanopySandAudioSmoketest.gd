extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func sample_rms(capture: AudioEffectCapture) -> float:
	capture.clear_buffer()
	await create_timer(0.25).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	var square_sum := 0.0
	for sample in samples:
		square_sum += sample.length_squared()
	return sqrt(square_sum / maxf(samples.size() * 2.0, 1.0))

func _run() -> void:
	await process_frame
	var front := load("res://Weather/DustFront.gd").new() as Node3D
	front.automatic_start = false
	root.add_child(front)
	front.set_physics_process(false)
	var visuals := front.get_child(0)
	visuals.set_process(false)
	var previous_speed := 0.0
	for level in range(1, 6):
		var speed: float = visuals._configure_grain_motion(Vector3(0, 0, -100), level, 1.0, true)
		check(speed > previous_speed and speed > 100.0, "Grains accelerate with severity at constant aircraft speed")
		var rendered_speed: float = visuals._particle_material.initial_velocity_max * visuals._particles.speed_scale
		check(rendered_speed >= speed, "Particle playback preserves the faster motion")
		previous_speed = speed
	var canopy := visuals.get_node("CanopySandImpacts")
	check(canopy._ticks.bus == "Master" and canopy._rattle.bus == "Master", "Canopy impacts bypass exterior muffling")
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, "SandTest")
	AudioServer.set_bus_send(bus, "Master")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, capture)
	canopy._ticks.bus = "SandTest"
	canopy._rattle.bus = "SandTest"
	canopy.update_exposure(true, 1.0, 1, 100.0, 2.0)
	var light := await sample_rms(capture)
	canopy.update_exposure(true, 1.0, 5, 250.0, 2.0)
	var extreme := await sample_rms(capture)
	check(light > 0.0001 and extreme > light * 1.5, "Canopy audio reaches mixer and grows with storm intensity")
	canopy.update_exposure(false, 1.0, 5, 250.0, 0.016)
	await create_timer(0.1).timeout
	var outside := await sample_rms(capture)
	check(outside < 0.00001, "Exterior view silences canopy impacts")
	canopy.update_exposure(true, 1.0, 5, 250.0, 2.0)
	canopy.update_exposure(true, 0.0, 5, 250.0, 2.0)
	check(not canopy._ticks.playing and not canopy._rattle.playing, "Leaving dust stops both grain layers")
	AudioServer.remove_bus(bus)
	front.queue_free()
	await process_frame
	print("CANOPY_SAND_AUDIO_OK light_rms=", light, " extreme_rms=", extreme, " exterior_rms=", outside, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
