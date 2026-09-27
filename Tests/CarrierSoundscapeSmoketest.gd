extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var carrier: Node3D = load("res://LandCarrier/LandCarrier2.tscn").instantiate()
	carrier.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(carrier)
	_disable_logic(carrier)
	carrier.process_mode = Node.PROCESS_MODE_INHERIT
	await physics_frame
	await physics_frame
	var commander := carrier.get_node("Commander")
	assert(commander.get_node("OfficerFootsteps")._player.is_in_group("carrier_local_audio"),
		"Commander steps are not routed as a local carrier sound")
	var forward_door := carrier.get_node("CarrierModel/ExteriorDoorForward")
	assert(forward_door._motion_audio.is_in_group("carrier_local_audio"),
		"Carrier door is not routed as a local sound")
	assert(commander._has_interior_ceiling(), "Bridge has interior ambience")
	var saved: Vector3 = commander.position
	commander.position = Vector3(0, 0.2, 30)
	assert(not commander._has_interior_ceiling(), "Open deck excludes room ambience")
	commander.position = saved
	commander._update_control_room_audio(1.0, true)
	assert(commander._control_room_audio_player.volume_db > -40.0, "Room audible inside")
	commander._update_control_room_audio(1.0, false)
	assert(commander._control_room_audio_player.volume_db < -70.0, "Room silent outside")
	var island_lift := carrier.get_node("CommanderWalkArea")
	var island_motor := island_lift._elevator_audio_player as AudioStreamPlayer3D
	assert(island_motor.is_in_group("carrier_local_audio"),
		"Island lift is not routed as a local sound")
	assert((island_motor.stream as AudioStreamWAV).loop_end > 0,
		"Island lift recording has a zero-length loop")
	assert(island_motor != null and not island_motor.playing, "Island lift motor starts silent")
	island_lift._begin_elevator_trip()
	island_lift._update_elevator_audio(0.1)
	assert(island_motor.playing and island_motor.volume_db > -22.0, "Island lift motor plays while travelling")
	await create_timer(0.15).timeout
	assert(island_motor.playing, "Island lift motor stopped immediately after starting")
	island_lift._elevator_moving = false
	for i in 12:
		island_lift._update_elevator_audio(0.1)
	assert(not island_motor.playing, "Island lift motor stops after arrival")
	var deck_motors: Array[AudioStreamPlayer3D] = []
	for lift_name in ["Elevator", "Elevator2"]:
		var lift := carrier.get_node(lift_name) as CarrierElevator
		var motor := lift._moving_audio_player as AudioStreamPlayer3D
		assert(motor != null, "%s has a positional motor" % lift_name)
		assert(motor.is_in_group("carrier_local_audio"), "%s is not routed as a local sound" % lift_name)
		assert((motor.stream as AudioStreamWAV).loop_end > 0,
			"%s recording has a zero-length loop" % lift_name)
		deck_motors.append(motor)
		var platform_y_before: float = lift._platform_local_y
		lift.move_platform_up()
		lift._physics_process(0.1)
		assert(absf(lift._platform_local_y - platform_y_before) < 0.001,
			"%s was expected to start with cover motion" % lift_name)
		assert(motor.volume_db > lift.moving_sound_silence_db + 1.0,
			"%s cover motion did not bring up its motor sound" % lift_name)
	await create_timer(0.15).timeout
	for motor in deck_motors:
		assert(motor.playing, "%s stopped immediately after starting" % motor.get_parent().get_parent().name)
	assert(deck_motors[0] != deck_motors[1], "Deck lifts share one motor player")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var tread: CarrierTread
	for node in carrier.find_children("*", "", true, false):
		if node is CarrierTread:
			tread = node
			break
	assert(tread != null)
	camera.global_position = tread.global_position + Vector3.UP * 3.0
	tread._update_rolling_audio(1.0, 0.0)
	assert(not tread._rolling_audio_player.playing, "Stopped tracks silent")
	tread._update_rolling_audio(1.0, 5.0)
	assert(tread._rolling_audio_player.playing, "Moving tracks audible nearby")
	assert(tread._rolling_audio_player.stream.loop, "Tread recording loops")
	tread._update_rolling_audio(1.0, 0.0)
	assert(not tread._rolling_audio_player.playing, "Track playback stops with movement")
	camera.global_position = tread.global_position + Vector3.UP * 1000.0
	tread._update_rolling_audio(1.0, 5.0)
	assert(not tread._rolling_audio_player.playing, "Distant tracks do not decode")
	print("CARRIER_SOUNDSCAPE_SMOKE PASS")
	carrier.queue_free()
	camera.queue_free()
	await process_frame
	quit()

func _disable_logic(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_disable_logic(child)
