extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var carrier := (load("res://LandCarrier/LandCarrier2.tscn") as PackedScene).instantiate() as Node3D
	scene.add_child(carrier)
	await process_frame
	await process_frame
	var deck := carrier.get_node("FlightDeckManager")
	var aircraft_scene := load("res://Aircraft/Aircraft_5.tscn") as PackedScene
	var lane: Dictionary = deck.call("_get_parallel_launch_lanes")[1]
	var job := lane.duplicate()
	job["aircraft_data"] = deck.call(
		"_make_stored_aircraft_entry_unassigned", "Aircraft_5", aircraft_scene, aircraft_scene.resource_path)
	job["aircraft"] = null
	job["tractors"] = []
	job["phase"] = "retrieving"
	job["launch_complete"] = false
	job["cleanup_complete"] = false
	deck.set("_parallel_launch_jobs", {int(job["lane_id"]): job})
	deck.call_deferred("_run_parallel_launch_job", job, 0)
	var aircraft: RigidBody3D = null
	var last_pos := Vector3.INF
	var still_frames := 0
	var orphan_injected := false
	var original_aircraft_id := 0
	for frame in 1800:
		await physics_frame
		var live_job: Dictionary = (deck.get("_parallel_launch_jobs") as Dictionary).get(int(job["lane_id"]), job)
		if is_instance_valid(live_job.get("aircraft")):
			aircraft = live_job.get("aircraft") as RigidBody3D
		if not is_instance_valid(aircraft):
			continue
		if original_aircraft_id == 0:
			original_aircraft_id = aircraft.get_instance_id()
		if str(live_job.get("phase", "")) == "towing" and not orphan_injected \
		and carrier.to_local(aircraft.global_position).z > -8.0:
			# Simulate an interrupted tow, leaving the aircraft and tractors
			# partway off the raised elevator without an active mover.
			live_job["tow_generation"] = int(live_job["tow_generation"]) + 1
			live_job["tow_heartbeat_frame"] = Engine.get_physics_frames() - 480
			orphan_injected = true
			print("AIRCRAFT5_TOW_ORPHAN_INJECTED frame=%d pos=%s" % [frame, aircraft.global_position])
		if orphan_injected and str(live_job.get("phase", "")) in ["handoff", "launching", "launched"] \
		and aircraft.get_instance_id() == original_aircraft_id:
			print("AIRCRAFT5_RETRIEVAL_TOW_PASS frame=%d pos=%s" % [frame, aircraft.global_position])
			quit(0)
			return
		if aircraft.global_position.distance_to(last_pos) < 0.002:
			still_frames += 1
		else:
			still_frames = 0
		last_pos = aircraft.global_position
		if still_frames == 180 or (frame > 0 and frame % 300 == 0):
			print("AIRCRAFT5_RETRIEVAL_TOW_PROGRESS frame=%d state=%d pos=%s still=%d bots=%s" % [
				frame, deck.current_state, aircraft.global_position, still_frames,
				deck.tractor_bots.map(func(bot): return "%s:%s:%s" % [bot.name, bot.global_position, bot.is_active]),
			])
	push_error("AIRCRAFT5_RETRIEVAL_TOW_FAIL state=%d pos=%s still=%d" % [
		deck.current_state, aircraft.global_position if is_instance_valid(aircraft) else Vector3.INF, still_frames])
	quit(1)
