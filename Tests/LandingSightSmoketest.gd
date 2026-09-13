extends SceneTree

const FIXED_WING_SCENES: PackedStringArray = [
	"res://Aircraft/Aircraft_1.tscn",
	"res://Aircraft/Aircraft_2.tscn",
	"res://Aircraft/Aircraft_5.tscn",
	"res://Aircraft/Aircraft_7.tscn",
	"res://Aircraft/Aircraft_8.tscn",
	"res://Aircraft/Aircraft_14.tscn",
]
const LANDING_SIGHT_MODEL: Script = preload("res://AI/LandingSight.gd")


class CarrierDouble:
	extends Node3D

	var deck_velocity := Vector3(5.0, 0.0, 0.0)
	var yaw_rate_rad_s: float = 0.0

	func get_deck_reference_velocity_vector() -> Vector3:
		return deck_velocity

	func get_yaw_rate_rad_s() -> float:
		return yaw_rate_rad_s


class WireDouble:
	extends Node3D

	var wire_number: int = 2
	var half_span_m: float = 10.0
	var vertical_tolerance_m: float = 0.8
	var lateral_margin_m: float = 1.0

	func get_wire_center() -> Vector3:
		return global_position

	func get_wire_number() -> int:
		return wire_number

	func get_capture_half_span_m() -> float:
		return half_span_m

	func get_swept_hook_vertical_tolerance_m() -> float:
		return vertical_tolerance_m

	func get_swept_hook_lateral_margin_m() -> float:
		return lateral_margin_m


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "LandingSightSmoketest"
	root.add_child(scene)
	current_scene = scene

	var carrier := CarrierDouble.new()
	carrier.name = "LandingSightCarrier"
	carrier.add_to_group("carrier")
	scene.add_child(carrier)

	var approach_markers: Array[Node3D] = []
	for index in range(5):
		var marker := Marker3D.new()
		marker.name = "approach_%d" % index
		marker.position = Vector3(0.0, 0.0, -1200.0 + float(index) * 300.0)
		carrier.add_child(marker)
		approach_markers.append(marker)

	var wire := WireDouble.new()
	wire.name = "ArrestingCable2"
	wire.position = Vector3.ZERO
	wire.add_to_group("arresting_cable")
	carrier.add_child(wire)

	var aircraft := RigidBody3D.new()
	aircraft.name = "LandingSightAircraft"
	aircraft.position = Vector3(4.0, 100.0, -1004.0)
	# Match carrier lateral motion. The sight should therefore retain a 4m
	# lateral prediction rather than projecting roughly 100m of false drift.
	aircraft.linear_velocity = Vector3(5.0, -4.861111, 50.0)
	aircraft.angular_velocity = Vector3.ZERO
	scene.add_child(aircraft)

	var left_gear := _make_wheel_collider("LeftGearCollider", Vector3(-2.0, -2.0, 0.0))
	var right_gear := _make_wheel_collider("RightGearCollider", Vector3(2.0, -2.0, 0.0))
	aircraft.add_child(left_gear)
	aircraft.add_child(right_gear)

	var hook_root := Node3D.new()
	hook_root.name = "TailHook"
	hook_root.position = Vector3(0.0, -2.0, -4.0)
	aircraft.add_child(hook_root)
	var hook_area := Area3D.new()
	hook_area.name = "HookArea"
	hook_area.add_to_group("tailhook")
	hook_root.add_child(hook_area)

	var pilot := Node.new()
	pilot.name = "AIPilot"
	pilot.set_script(load("res://AI/AIPilot.gd") as Script)
	aircraft.add_child(pilot)
	pilot.set("aircraft", aircraft)
	pilot.set("_approach_wp", approach_markers)
	pilot.set("current_state", 15) # AIPilot.State.LANDING
	pilot.set("pitch_input", 0.23)
	pilot.set("roll_input", -0.17)
	pilot.set("yaw_input", 0.11)
	pilot.set("throttle_input", 0.64)
	# Keep this case in explicit shadow mode so it can prove that observation by
	# itself never mutates controls. Logged recovery scenarios exercise the
	# default enabled guidance path.
	pilot.set("landing_sight_guidance_enabled", false)

	pilot.call("_update_landing_sight", 0.1)
	var solution: Dictionary = pilot.call("get_landing_sight_snapshot")
	if not bool(solution.get("valid", false)) or not bool(solution.get("shadow_only", false)):
		return _fail("landing sight did not publish a shadow solution")
	var target: Dictionary = solution.get("target_wire", {})
	if not bool(target.get("valid", false)) or int(target.get("wire_number", 0)) != 2:
		return _fail("landing sight did not solve the selected wire")
	if absf(float(target.get("lateral_m", INF)) - 4.0) > 0.05:
		return _fail("moving-deck compensation produced wrong lateral miss: %.2fm" % float(target.get("lateral_m", INF)))
	if absf(float(target.get("vertical_m", INF))) > 0.05:
		return _fail("tailhook did not project through wire height: %.2fm" % float(target.get("vertical_m", INF)))
	if not bool(target.get("predicted_capture", false)) \
			or int(solution.get("predicted_capture_wire_number", 0)) != 2:
		return _fail("capture-sized hook crossing was not recognized")
	if not bool(solution.get("contact_sink_within_limit", false)) \
			or int(solution.get("predicted_viable_wire_number", 0)) != 2:
		return _fail("survivable wire crossing was not recognized as viable")
	if not bool((solution.get("hook_deck_projection", {}) as Dictionary).get("valid", false)) \
			or not bool((solution.get("main_gear_deck_projection", {}) as Dictionary).get("valid", false)):
		return _fail("hook or main-gear deck footprint was unavailable")
	if absf(float(solution.get("track_error_deg", INF))) > 0.05:
		return _fail("carrier-relative track error ignored matched deck motion")
	if not is_equal_approx(float(pilot.get("pitch_input")), 0.23) \
			or not is_equal_approx(float(pilot.get("roll_input")), -0.17) \
			or not is_equal_approx(float(pilot.get("yaw_input")), 0.11) \
			or not is_equal_approx(float(pilot.get("throttle_input")), 0.64):
		return _fail("shadow sight changed a flight-control input")
	if not pilot.has_method("_update_landing_sight_debug_visuals") \
			or not pilot.has_method("_clear_landing_sight_debug_visuals"):
		return _fail("landing sight debug visualization API is missing")
	if not aircraft.has_meta("landing_sight_shadow_solution"):
		return _fail("aircraft did not expose its landing sight snapshot")

	# Enable the cue output with a test-only early blend point. Computing active
	# cues must still be side-effect free; _state_landing is the sole consumer.
	pilot.set("landing_sight_guidance_enabled", true)
	pilot.set("landing_sight_guidance_start_remaining_m", 1300.0)
	pilot.set("landing_sight_guidance_full_remaining_m", 1100.0)
	pilot.set("landing_sight_guidance_terminal_lateral_power", 2.0)
	pilot.call("_update_landing_sight", 0.1)
	var guided_solution: Dictionary = pilot.call("get_landing_sight_snapshot")
	if bool(guided_solution.get("shadow_only", true)) \
			or not bool(guided_solution.get("guidance_valid", false)) \
			or float(guided_solution.get("guidance_weight", 0.0)) < 0.99 \
			or not is_finite(float(guided_solution.get("suggested_fpa_rad", NAN))) \
			or not is_finite(float(guided_solution.get("suggested_fpv_yaw_error_rad", NAN))):
		return _fail("active landing sight did not publish finite final-control cues")
	if absf(float(guided_solution.get("current_lateral_error_m", INF)) - 4.0) > 0.05 \
			or absf(float(guided_solution.get("current_right_speed_mps", INF))) > 0.05 \
			or float(guided_solution.get("suggested_right_speed_mps", 0.0)) >= -0.1:
		return _fail("terminal lateral cue did not turn position error into an unloading intercept")
	var legacy_lateral_speed := float(LANDING_SIGHT_MODEL.terminal_lateral_speed_mps(40.0, 4.0, 1.0, 50.0))
	var terminal_lateral_speed := float(LANDING_SIGHT_MODEL.terminal_lateral_speed_mps(40.0, 4.0, 2.0, 50.0))
	var stopping_limited_speed := float(LANDING_SIGHT_MODEL.terminal_lateral_speed_mps(90.0, 3.0, 2.0, 50.0, 4.0))
	if not is_equal_approx(legacy_lateral_speed, -10.0) \
			or not is_equal_approx(terminal_lateral_speed, -20.0) \
			or absf(stopping_limited_speed + sqrt(720.0)) > 0.001:
		return _fail("terminal lateral path power did not preserve legacy or powered behavior")
	if not is_equal_approx(float(pilot.get("pitch_input")), 0.23) \
			or not is_equal_approx(float(pilot.get("roll_input")), -0.17) \
			or not is_equal_approx(float(pilot.get("yaw_input")), 0.11) \
			or not is_equal_approx(float(pilot.get("throttle_input")), 0.64):
		return _fail("cue calculation changed a flight-control input outside final control")
	pilot.set("landing_sight_guidance_enabled", false)
	pilot.call("_update_landing_sight", 0.1)

	# Introduce a real left drift relative to the carrier. The per-wire prediction
	# should immediately expose that the previously catchable path now misses.
	aircraft.linear_velocity.x = 4.0
	pilot.call("_update_landing_sight", 0.1)
	var drift_solution: Dictionary = pilot.call("get_landing_sight_snapshot")
	var drift_target: Dictionary = drift_solution.get("target_wire", {})
	if float(drift_target.get("lateral_m", 0.0)) > -15.0 \
			or bool(drift_target.get("predicted_capture", true)):
		return _fail("wire-crossing projection did not reveal lateral drift")
	if float(drift_solution.get("target_lateral_error_rate_mps", 0.0)) >= 0.0:
		return _fail("landing sight trend did not report worsening left error")

	# Restore the lateral track, but make the same geometric wire crossing at an
	# impact sink rate that would be fatal. It should remain a projected crossing
	# while being rejected as a viable landing solution.
	aircraft.position.y = 400.0
	aircraft.linear_velocity = Vector3(5.0, -19.742063, 50.0)
	pilot.call("_update_landing_sight", 0.1)
	var steep_solution: Dictionary = pilot.call("get_landing_sight_snapshot")
	var steep_target: Dictionary = steep_solution.get("target_wire", {})
	if not bool(steep_target.get("predicted_capture", false)) \
			or int(steep_solution.get("predicted_capture_wire_number", 0)) != 2:
		return _fail("steep test trajectory no longer crossed the wire geometry")
	if bool(steep_solution.get("contact_sink_within_limit", true)) \
			or int(steep_solution.get("predicted_viable_wire_number", -1)) != 0 \
			or bool(steep_target.get("predicted_landing_viable", true)):
		return _fail("fatal sink rate was incorrectly accepted as landing-viable")
	if not _check_fixed_wing_sensor_geometry():
		return

	pilot.call("_clear_landing_sight_debug_visuals")
	aircraft.free()
	carrier.free()
	current_scene = null
	scene.free()
	await process_frame
	await process_frame
	await process_frame
	print("[LandingSightSmoketest] PASS shadow_only=true active_cues=true terminal_lateral=true controls_unchanged=true moving_deck=true hook+gear_footprints=true wire2_capture=true drift_miss=true fatal_sink_rejected=true debug_visual_api=true fleet_sensors=6")
	quit(0)


func _make_wheel_collider(node_name: String, local_position: Vector3) -> CollisionShape3D:
	var collider := CollisionShape3D.new()
	collider.name = node_name
	collider.position = local_position
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	collider.shape = shape
	return collider


func _check_fixed_wing_sensor_geometry() -> bool:
	for scene_path in FIXED_WING_SCENES:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			_fail("could not load %s" % scene_path)
			return false
		var fleet_aircraft := packed.instantiate() as RigidBody3D
		if fleet_aircraft == null:
			_fail("%s did not instantiate as RigidBody3D" % scene_path)
			return false
		var fleet_pilot := fleet_aircraft.get_node_or_null("AIPilot")
		if fleet_pilot == null:
			fleet_aircraft.free()
			_fail("%s has no AIPilot" % scene_path)
			return false
		var hook_root := fleet_aircraft.find_child("TailHook", true, false)
		var hook_sensor := hook_root.get_node_or_null("HookArea") if hook_root != null else null
		var left_gear := fleet_aircraft.find_child("LeftGearCollider", true, false) as CollisionShape3D
		var right_gear := fleet_aircraft.find_child("RightGearCollider", true, false) as CollisionShape3D
		if hook_sensor == null or left_gear == null or right_gear == null \
				or left_gear.shape == null or right_gear.shape == null:
			fleet_aircraft.free()
			_fail("%s lacks usable hook or main-gear sight geometry" % scene_path)
			return false
		fleet_aircraft.free()
	return true


func _fail(reason: String) -> void:
	push_error("[LandingSightSmoketest] FAIL %s" % reason)
	quit(1)
