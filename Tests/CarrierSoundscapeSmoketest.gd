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
	assert(commander._has_interior_ceiling(), "Bridge has interior ambience")
	var saved: Vector3 = commander.position
	commander.position = Vector3(0, 0.2, 30)
	assert(not commander._has_interior_ceiling(), "Open deck excludes room ambience")
	commander.position = saved
	commander._update_control_room_audio(1.0, true)
	assert(commander._control_room_audio_player.volume_db > -40.0, "Room audible inside")
	commander._update_control_room_audio(1.0, false)
	assert(commander._control_room_audio_player.volume_db < -70.0, "Room silent outside")
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
