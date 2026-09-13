extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var actor := Node3D.new()
	root.add_child(actor)
	var feet := preload("res://Audio/OfficerFootsteps.gd").new()
	actor.add_child(feet)
	feet.set_physics_process(false)
	for i in 60:
		feet.advance_distance(Vector3.ZERO)
	assert(feet.step_events == 0, "Stationary actors must not step")
	feet.advance_distance(Vector3(0, 0.3, 0))
	assert(feet.step_events == 0, "Lift travel must not step")
	for i in range(1, 16):
		feet.advance_distance(Vector3(i * 0.1, 0.3, 0))
	assert(feet.step_events == 2, "Cadence follows actual distance")
	feet.advance_distance(Vector3(100, 0, 0))
	assert(feet.step_events == 2, "Teleport must not step")
	var last := feet._last_index
	feet.advance_distance(Vector3(100.8, 0, 0))
	assert(feet._last_index != last, "Adjacent steps use different clips")
	actor.position += Vector3(500, 0, 500)
	feet.advance_distance(Vector3(100.8, 0, 0))
	assert(feet.step_events == 3, "Carrier/world movement must not create steps")

	var aircraft := RigidBody3D.new()
	root.add_child(aircraft)
	var manager := preload("res://Audio/AudioManager3D.gd").new()
	manager.aircraft = aircraft
	manager.cabin_systems_player = AudioStreamPlayer.new()
	manager.cabin_systems_player.stream = preload("res://Audio/RuntimeAudio.gd").loop_stream(manager.cabin_systems_sound)
	root.add_child(manager.cabin_systems_player)
	assert(manager.cabin_systems_player.stream.loop, "Cabin stream loops")
	manager._update_cabin_systems(1.0, true)
	assert(manager.cabin_systems_player.playing, "Cabin plays in cockpit")
	manager._update_cabin_systems(1.0, false)
	assert(not manager.cabin_systems_player.playing, "Cabin stops outside cockpit")
	manager._ejected_pilot_audio_active = true
	manager._update_cabin_systems(1.0, true)
	assert(not manager.cabin_systems_player.playing, "No cabin audio after ejection")
	manager._ejected_pilot_audio_active = false
	manager._aircraft_audio_destroyed = true
	manager._update_cabin_systems(1.0, true)
	assert(not manager.cabin_systems_player.playing, "No cabin audio after destruction")
	manager.cabin_systems_player.queue_free()
	manager.free()

	var ui := root.get_node("InterfaceAudio")
	var button := Button.new()
	root.add_child(button)
	await process_frame
	ui._last_ms = -1000
	var events: int = ui.sound_events
	button.disabled = true
	button.pressed.emit()
	assert(ui.sound_events == events, "Disabled UI is silent")
	button.disabled = false
	button.pressed.emit()
	assert(ui.sound_events == events + 1, "UI activation plays once")
	button.pressed.emit()
	assert(ui.sound_events == events + 1, "UI burst is throttled")
	button.set_meta("silent_ui", true)
	ui._last_ms = -1000
	button.pressed.emit()
	assert(ui.sound_events == events + 1, "UI can opt out")

	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var turret := preload("res://Weapons/Turrets/turret.gd").new()
	turret.barrel_mount = Node3D.new()
	turret.add_child(turret.barrel_mount)
	root.add_child(turret)
	var servo := turret.get_node("TurretServoAudio")
	servo.set_physics_process(false)
	servo._physics_process(0.11)
	assert(not servo._player.playing, "Stationary turret is silent")
	turret.rotation.y += 0.2
	servo._physics_process(0.11)
	assert(servo._player.playing, "Turret slew starts electric servo")
	for i in 8:
		servo._physics_process(0.11)
	assert(not servo._player.playing, "Servo stops once aiming stops")
	camera.position = Vector3(1000, 0, 0)
	turret.rotation.y += 0.2
	servo._physics_process(0.11)
	assert(not servo._player.playing, "Distant servo does not decode audio")
	turret.queue_free()
	camera.queue_free()
	actor.queue_free()
	aircraft.queue_free()
	button.queue_free()
	await process_frame
	print("ENVIRONMENT_AUDIO_SMOKE PASS")
	quit()
