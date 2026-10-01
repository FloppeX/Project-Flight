extends Node

class Pilot:
	extends HelicopterPilot
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _process(_delta: float) -> void: pass
	func _get_ground_height_at_position(_point: Vector3) -> float: return 0.0
	func _get_landing_surface_y() -> float: return 0.0

class Gear:
	extends Node
	var gear_has_contact: Array[bool] = [false, false, false, false]
	var gear_compressions: Array[float] = [0.0, 0.0, 0.0, 0.0]
	func get_gear_count() -> int: return 4

class Controls:
	extends Node
	var pitch_input := 0.0
	var roll_input := 0.0
	var yaw_input := 0.0

var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("HELI_SURFACE_FAIL " + label)

func _run() -> void:
	var body := RigidBody3D.new()
	add_child(body)
	body.position.y = 1.5
	var pilot := Pilot.new()
	body.add_child(pilot)
	pilot.aircraft = body
	pilot.state = HelicopterPilot.State.LANDING
	pilot._physics_delta = 0.5
	var gear := Gear.new()
	gear.name = "LandingGear"
	body.add_child(gear)
	var controls := Controls.new()
	body.add_child(controls)
	pilot.helicopter_flight = controls
	for i in 6:
		check(not pilot._update_terrain_landing_settled_touchdown(true, 1.5, Vector3.ZERO), "hover cannot land")
	gear.gear_has_contact = [true, true, false, false]
	for i in 6:
		check(not pilot._update_terrain_landing_settled_touchdown(true, 1.5, Vector3.ZERO), "one skid cannot land")
	gear.gear_has_contact.fill(true)
	body.rotation.z = deg_to_rad(25.0)
	check(not pilot._update_terrain_landing_settled_touchdown(true, 1.5, Vector3.ZERO), "tipping cannot land")
	body.rotation = Vector3.ZERO
	body.angular_velocity = Vector3(0.3, 0, 0)
	check(not pilot._update_terrain_landing_settled_touchdown(true, 1.5, Vector3.ZERO), "rotating cannot land")
	body.angular_velocity = Vector3.ZERO
	check(not pilot._update_terrain_landing_settled_touchdown(true, 1.5, Vector3(2, 0, 0)), "sliding cannot land")
	check(not pilot._update_terrain_landing_settled_touchdown(true, 1.5, Vector3(0, -2, 0)), "hard contact cannot land")
	for i in 2:
		check(not pilot._update_terrain_landing_settled_touchdown(true, 1.5, Vector3.ZERO), "requires dwell")
	gear.gear_has_contact.fill(false)
	check(not pilot._update_terrain_landing_settled_touchdown(true, 1.5, Vector3.ZERO), "bounce resets dwell")
	gear.gear_has_contact.fill(true)
	for i in 2:
		check(not pilot._update_terrain_landing_settled_touchdown(true, 1.5, Vector3.ZERO), "dwell restarts")
	check(pilot._update_terrain_landing_settled_touchdown(true, 1.5, Vector3.ZERO), "stable supported landing completes")
	body.linear_velocity = Vector3(0.5, 0, 0.5)
	pilot._set_helicopter_input(1, 1, 1)
	check(controls.pitch_input > 0 and controls.roll_input < 0, "contact steering damps velocity")
	check(absf(controls.pitch_input) <= 0.06 and absf(controls.roll_input) <= 0.06 and controls.yaw_input == 0, "contact limits")
	pilot._physics_delta = 1.0
	pilot._apply_collective(1.0)
	check(pilot._collective_cmd <= pilot._get_collective_trim() * 0.5 + 0.001, "stable support unloads rotor")
	check(body.has_meta("helicopter_touchdown_brake_frame"), "stable support requests brakes")
	pilot.state = HelicopterPilot.State.TAKEOFF
	pilot._apply_collective(1.0)
	check(not body.has_meta("helicopter_touchdown_brake_frame"), "departure releases touchdown brakes")
	pilot._prime_takeoff_reference()
	check(pilot._get_takeoff_speed_limit() == 0.0, "contact prevents departure acceleration")
	pilot._set_helicopter_input(1, 1, 1)
	check(Vector3(controls.pitch_input, controls.roll_input, controls.yaw_input) == Vector3.ZERO, "vertical lift neutral controls")
	gear.gear_has_contact.fill(false)
	body.position.y += 3
	check(pilot._get_takeoff_speed_limit() == 0.0, "low liftoff holds vertical")
	body.position.y += 4
	check(pilot._get_takeoff_speed_limit() > 0.0, "clearance releases departure")
	pilot._set_helicopter_input(0.5, -0.5, 0.5)
	check(controls.pitch_input == 0.5 and controls.roll_input == -0.5, "airborne authority restored")
	pilot.debug_enabled = false
	pilot._record_surface_trace(0.5)
	check(not pilot._flight_log.is_empty() and "contacts=" in pilot._flight_log.back()[1], "quiet telemetry without debug")
	print("HELICOPTER_SURFACE_SAFETY_%s checks=touchdown_dwell,contact,attitude,speed,steering,liftoff,telemetry" % ("PASS" if failures == 0 else "FAIL"))
	body.free()
	get_tree().quit(0 if failures == 0 else 1)
