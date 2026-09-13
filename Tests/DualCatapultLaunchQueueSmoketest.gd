extends Node

const CARRIER_SCENE := preload("res://LandCarrier/LandCarrier2.tscn")

var _failures: PackedStringArray = []
var _launched_count := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var carrier := CARRIER_SCENE.instantiate() as Node3D
	add_child(carrier)
	await get_tree().process_frame
	await get_tree().process_frame
	var manager := carrier.get_node("FlightDeckManager") as FlightDeckManager
	var stored_before := manager.stored_aircraft.size()
	var accepted := manager.queue_ai_flight(2, self)
	var jobs_variant: Variant = manager.get("_parallel_launch_jobs")
	var jobs: Dictionary = jobs_variant if jobs_variant is Dictionary else {}

	_expect(accepted == 2, "two-aircraft sortie was not accepted")
	_expect(jobs.size() == 2, "scheduler did not reserve both launch lanes")
	_expect(int(manager.get("_ai_launch_queue")) == 0, "reserved aircraft remained in the scalar queue")
	_expect(manager.stored_aircraft.size() == stored_before - 2, "two launch jobs did not reserve exactly two hangar aircraft")
	_expect(manager.current_state == FlightDeckManager.DeckState.RETRIEVING_FROM_HANGAR, "parallel retrieval did not own the deck state")

	var elevators: Dictionary = {}
	var catapults: Dictionary = {}
	for job_variant in jobs.values():
		var job := job_variant as Dictionary
		var job_elevator := job.get("elevator") as Node
		var job_catapult := job.get("catapult") as Node
		_expect(is_instance_valid(job_elevator), "launch job has no elevator")
		_expect(is_instance_valid(job_catapult), "launch job has no catapult")
		if is_instance_valid(job_elevator):
			elevators[job_elevator.get_instance_id()] = true
		if is_instance_valid(job_catapult):
			catapults[job_catapult.get_instance_id()] = true
	_expect(elevators.size() == 2, "both jobs shared one elevator")
	_expect(catapults.size() == 2, "both jobs shared one catapult")

	# Let both deferred jobs enter their physical retrieval. They should coexist,
	# not merely reserve two slots and then serialize behind a scalar deck state.
	var wait_frames := 0
	var live_job_aircraft := 0
	var rising_elevators := 0
	while wait_frames < 180:
		wait_frames += 1
		live_job_aircraft = 0
		rising_elevators = 0
		jobs = manager.get("_parallel_launch_jobs") as Dictionary
		for job_variant in jobs.values():
			var job := job_variant as Dictionary
			var aircraft_variant: Variant = job.get("aircraft")
			if is_instance_valid(aircraft_variant):
				live_job_aircraft += 1
			var job_elevator := job.get("elevator") as Node
			if is_instance_valid(job_elevator) \
			and float(job_elevator.call("get_platform_local_y")) > -9.45:
				rising_elevators += 1
		if live_job_aircraft == 2 and rising_elevators == 2:
			break
		await get_tree().physics_frame
	_expect(live_job_aircraft == 2, "two aircraft were not alive in the retrieval lanes together")
	_expect(rising_elevators == 2, "both elevators did not rise concurrently")

	var launch_wait_frames := 0
	while _launched_count < 2 and launch_wait_frames < 1200:
		launch_wait_frames += 1
		await get_tree().physics_frame
	_expect(_launched_count == 2, "both catapults did not complete their launch")
	var cleanup_wait_frames := 0
	while not (manager.get("_parallel_launch_jobs") as Dictionary).is_empty() \
	and cleanup_wait_frames < 360:
		cleanup_wait_frames += 1
		await get_tree().physics_frame
	_expect((manager.get("_parallel_launch_jobs") as Dictionary).is_empty(), "completed launch lanes remained reserved")
	_expect(manager.get("_pending_flight_ops") == null, "completed two-aircraft sortie retained its FlightOps owner")
	if _failures.is_empty():
		print("DUAL_CATAPULT_LAUNCH_QUEUE_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[DualCatapultLaunchQueueSmoketest] %s" % failure)
	get_tree().quit(1)


func notify_aircraft_launched(_pilot: Node) -> void:
	_launched_count += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
