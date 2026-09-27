extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var carrier := Node3D.new()
	carrier.name = "Carrier"
	carrier.add_to_group("carrier")
	stage.add_child(carrier)
	var commander := (load("res://LandCarrier/Commander.tscn") as PackedScene).instantiate()
	carrier.add_child(commander)
	await process_frame
	var camera := commander.get_node("Camera3D") as Camera3D
	camera.make_current()
	var controller := CameraController.new()
	controller.bridge_script = commander
	controller.bridge_camera = camera
	var aircraft := RigidBody3D.new()
	stage.add_child(aircraft)
	var manager := AudioManager3D.new()
	manager.aircraft = aircraft
	manager.camera_controller = controller
	aircraft.add_child(manager)
	manager.set_process(false)
	var footsteps := commander.get_node("OfficerFootsteps")._player as AudioStreamPlayer3D
	var local_sound := AudioStreamPlayer3D.new()
	local_sound.add_to_group("3d_audio")
	local_sound.add_to_group("carrier_local_audio")
	carrier.add_child(local_sound)
	var exterior_sound := AudioStreamPlayer3D.new()
	exterior_sound.add_to_group("3d_audio")
	stage.add_child(exterior_sound)
	manager._process(0.016)
	assert(manager.current_audio_bus == "Bridge", "Commander selected cockpit filtering")
	assert(footsteps.bus == "Master" and local_sound.bus == "Master",
		"Nearby carrier sounds were filtered as exterior noise")
	assert(exterior_sound.bus == "Bridge", "Exterior sound bypassed bridge damping")
	assert(manager.bridge_interior_player.bus == "Bridge", "Bridge ambience used the cockpit bus")
	manager.switch_to_interior_audio()
	manager._process(0.016)
	assert(manager.current_audio_bus == "Bridge" and footsteps.bus == "Master",
		"Returning from cockpit did not restore local sounds")
	var master_bus := AudioServer.get_bus_index("Master")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 0.5
	var capture_index := AudioServer.get_bus_effect_count(master_bus)
	AudioServer.add_bus_effect(master_bus, capture)
	capture = AudioServer.get_bus_effect(master_bus, capture_index) as AudioEffectCapture
	commander.set_process(false)
	var footstep_emitter := commander.get_node("OfficerFootsteps")
	footstep_emitter.set_physics_process(false)
	await create_timer(0.1).timeout
	capture.clear_buffer()
	footstep_emitter.advance_distance(commander.position + Vector3(0.8, 0.0, 0.0))
	await create_timer(0.2).timeout
	var peak := 0.0
	for sample in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	AudioServer.remove_bus_effect(master_bus, capture_index)
	assert(peak > 0.01, "Commander footsteps did not reach the output bus")
	print("COMMANDER_AUDIO_ROUTING_SMOKE PASS")
	stage.queue_free()
	controller.free()
	await process_frame
	quit(0)
