extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var viewport := root.get_viewport()
	viewport.audio_listener_enable_3d = false
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var commander := (load("res://LandCarrier/Commander.tscn") as PackedScene).instantiate() as CharacterBody3D
	stage.add_child(commander)
	await process_frame
	await process_frame
	var camera := commander.get_node("Camera3D") as Camera3D
	assert(camera.current, "Commander camera did not activate")
	if not viewport.audio_listener_enable_3d:
		push_error("Commander camera did not enable 3D sound")
		quit(1)
		return
	var footsteps := commander.get_node("OfficerFootsteps")
	footsteps.set_physics_process(false)
	footsteps.advance_distance(commander.position + Vector3(0.8, 0.0, 0.0))
	assert(footsteps.step_events == 1 and footsteps._player.playing,
		"Commander footsteps were not emitted")
	print("COMMANDER_SPATIAL_AUDIO_SMOKE PASS")
	stage.queue_free()
	await process_frame
	quit(0)
