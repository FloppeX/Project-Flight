extends "res://Tests/DualCatapultLaunchQueueSmoketest.gd"

var _tow_samples: Dictionary = {}
var _tow_initial_heights: Dictionary = {}
var _maximum_tow_drift := 0.0
var _capture_requested := false
var _review_camera: Camera3D

func _physics_process(_delta: float) -> void:
	var carrier := get_node_or_null("LandCarrier") as Node3D
	if carrier == null:
		for child in get_children():
			if child is Node3D and child.has_node("FlightDeckManager"):
				carrier = child
	if carrier == null:
		return
	# No terrain bootstrap in this isolated fixture: reveal the otherwise hidden
	# startup carrier so the rendered support check includes the actual deck.
	if DisplayServer.get_name() != "headless":
		carrier.show()
	var manager := carrier.get_node("FlightDeckManager") as FlightDeckManager
	var jobs: Dictionary = manager.get("_parallel_launch_jobs")
	for job: Dictionary in jobs.values():
		var aircraft_variant: Variant = job.get("aircraft")
		if not is_instance_valid(aircraft_variant):
			continue
		var aircraft := aircraft_variant as RigidBody3D
		if not aircraft.freeze or not bool(aircraft.get_meta("carrier_manual_transport", false)):
			continue
		var elevator: Node = job.get("elevator")
		if not manager.call("_is_elevator_physically_at_top_for", elevator):
			continue
		var id := aircraft.get_instance_id()
		var local_y := carrier.to_local(aircraft.global_position).y
		if not _tow_initial_heights.has(id):
			_tow_initial_heights[id] = local_y
		_tow_samples[id] = int(_tow_samples.get(id, 0)) + 1
		_maximum_tow_drift = maxf(_maximum_tow_drift, absf(local_y - float(_tow_initial_heights[id])))
		if DisplayServer.get_name() != "headless":
			if not is_instance_valid(_review_camera):
				_setup_review()
			_review_camera.global_position = aircraft.global_position + Vector3(19, 7, 22)
			_review_camera.look_at(aircraft.global_position)
			_review_camera.make_current()
			if int(_tow_samples[id]) >= 150 and not _capture_requested:
				_capture_requested = true
				_capture.call_deferred()

func notify_aircraft_launched(pilot: Node) -> void:
	_expect(_maximum_tow_drift < 0.025, "live dual launch changed loaded tow height by %.4fm" % _maximum_tow_drift)
	if _launched_count == 1:
		_expect(_tow_samples.size() == 2, "did not observe both supported tow lanes")
		for count in _tow_samples.values():
			_expect(int(count) >= 20, "insufficient continuous tow samples")
		print("DUAL_CATAPULT_WHEEL_SUPPORT samples=%s maximum_body_drift=%.4fm" % [_tow_samples.values(), _maximum_tow_drift])
	super.notify_aircraft_launched(pilot)

func _setup_review() -> void:
	_review_camera = Camera3D.new()
	_review_camera.fov = 48
	add_child(_review_camera)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.3, 0.35, 0.4)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.shadow_enabled = true
	add_child(light)

func _capture() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://captures/dual_catapult_wheel_support.png")
