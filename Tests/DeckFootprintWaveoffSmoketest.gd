extends SceneTree

const Sight = preload("res://AI/LandingSight.gd")

class CollisionSetup:
	extends Node
	func get_hull_bounds_local() -> AABB:
		return AABB(Vector3(-25, -20, -75), Vector3(50, 20, 150))

class MovingCarrier:
	extends Node3D
	var deck_velocity := Vector3.ZERO
	var yaw_rate := 0.0
	func get_deck_reference_velocity_vector() -> Vector3:
		return deck_velocity
	func get_yaw_rate_rad_s() -> float:
		return yaw_rate

var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func path(x: float, drift: float, z: float = -50.0, speed: float = 35.0,
		wheels: Array = [Vector2(-1.8, 0), Vector2(1.8, 0)]) -> Dictionary:
	return Sight.deck_footprint_path(Rect2(-25, -75, 50, 150), Rect2(-6, -5, 12, 10),
		wheels, Vector2(x, z), Vector2(drift, speed), 1.0, 1.2, 22.0, 1.5)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	check(path(0, 0).safe, "centred approach has room to stop")
	check(path(17, 0).safe, "near-edge footprint still inside margin is permitted")
	check(not path(18.1, 0).safe, "logged offset leaves inadequate wing clearance")
	check(not path(13, 3.9).safe, "outward drift must be included through arrest")
	check(not path(-13, -3.9).safe, "opposite deck edge is symmetric")
	check(path(13, -3.9).safe, "inward drift into safe footprint is permitted")
	check(not path(0, 0, 20).safe, "insufficient longitudinal stopping room is unsafe")
	check(path(0, 0, 50, -35).safe, "reverse carrier-local approach direction works")
	var stern_overhang := path(0, 0, -106)
	check(stern_overhang.safe and stern_overhang.body_longitudinal_clearance_m < 0.0,
		"supported main wheels permit tail overhang at the stern")
	check(path(0, 0, 106, -35).safe, "stern overhang permission follows reverse approach too")
	var stern_miss := path(0, 0, -110)
	check(stern_miss.safe and stern_miss.entry_delay_s > 0.0
		and stern_miss.limiting.edge == "z_min" and stern_miss.limiting.phase == "deck_entry",
		"plane crossing before stern defers horizontal support to actual deck entry")
	check(not path(18.1, 0, -110).safe, "deferred stern entry does not waive side clearance")
	check(path(0, 0, 110, -35).entry_delay_s > 0.0, "deferred entry works in reverse approach direction")
	var bow_miss := path(0, 0, 20)
	check(bow_miss.limiting.edge == "z_max" and bow_miss.limiting.phase == "stop",
		"insufficient stopping room records the bow at stop")
	var side_miss := path(13, 3.9)
	check(side_miss.limiting.kind == "body" and side_miss.limiting.edge == "x_max",
		"outward wing drift still rejects on the correct side")
	check(not path(0, 0, -50, 35, [Vector2(-30, 0), Vector2(1.8, 0)]).safe,
		"both main wheels must be supported independently of body footprint")
	check(not path(0, 0, -50, 35, [Vector2.ZERO]).valid, "missing second main wheel is unknown")
	check(not path(NAN, 0).valid, "nonfinite position must not become a safe prediction")
	check(not path(0, 0, -50, 35, [Vector2(NAN, 0), Vector2.ZERO]).valid,
		"nonfinite wheel is unknown")

	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var carrier := MovingCarrier.new()
	carrier.add_to_group("carrier")
	scene.add_child(carrier)
	var setup := CollisionSetup.new()
	setup.name = "CollisionSetup"
	carrier.add_child(setup)
	var marker := Node3D.new()
	carrier.add_child(marker)
	for model in ["Aircraft_1", "Aircraft_2", "Aircraft_5"]:
		var craft := (load("res://Aircraft/%s.tscn" % model) as PackedScene).instantiate() as RigidBody3D
		craft.freeze = true
		scene.add_child(craft)
		await process_frame
		await process_frame
		var pilot := craft.get_node("AIPilot")
		pilot.set_physics_process(false)
		pilot.set("_approach_wp", [marker])
		for heading in [0.0, PI, 1.2]:
			carrier.position = Vector3(230, 522, -440)
			carrier.rotation.y = heading
			craft.global_basis = carrier.global_basis
			craft.global_position = carrier.to_global(Vector3(0, 12, -55))
			craft.linear_velocity = carrier.global_basis * Vector3(0, -3, 35)
			var gear: Dictionary = pilot.call("_get_landing_sight_main_gear_sensor", Vector3.UP)
			check(gear.get("contact_points", []).size() == 2, model + " provides both authored main wheels")
			var solution := {"valid": true, "main_gear_sensor": gear,
				"main_gear_deck_projection": {"valid": true, "time_s": 1.0},
				"predicted_viable_wire_number": 1, "predicted_capture_wire_number": 1,
				"sink_rate_at_contact_mps": -3.0,
				"wire_solutions": [{"valid": true, "wire_number": 1, "time_s": 1.2,
					"vertical_m": 0.0, "lateral_m": 0.0, "half_span_m": 24.0}]}
			var footprint: Dictionary = pilot.call("_landing_sight_deck_footprint", solution)
			check(footprint.get("valid", false) and footprint.get("safe", false),
				model + " actual centred geometry is supported at every heading")
			pilot.set("_landing_sight_solution", solution)
			check(not pilot.call("_update_landing_high_miss_waveoff", 0.016), model + " centred viable approach continues")
			craft.global_position = carrier.to_global(Vector3(0, 12, -105))
			solution["main_gear_sensor"] = pilot.call("_get_landing_sight_main_gear_sensor", Vector3.UP)
			var overhang: Dictionary = pilot.call("_landing_sight_deck_footprint", solution)
			check(overhang.get("safe", false) and float(overhang.get("body_longitudinal_clearance_m", INF)) < 0.0,
				model + " actual tail may overhang stern while main wheels are supported")
			pilot.set("_landing_sight_solution", solution)
			check(not pilot.call("_update_landing_high_miss_waveoff", 0.016), model + " supported stern entry continues")
			craft.global_position = carrier.to_global(Vector3(0, 12, -120))
			craft.linear_velocity = carrier.global_basis * Vector3(0, -8, 35)
			var low_solution: Dictionary = solution.duplicate(true)
			low_solution["main_gear_sensor"] = pilot.call("_get_landing_sight_main_gear_sensor", Vector3.UP)
			low_solution["main_gear_sensor"]["lowest_position"] = Vector3(0, float(pilot.call("_get_approach_deck_y")) + 8.0, 0)
			low_solution["predicted_viable_wire_number"] = 0
			low_solution["predicted_capture_wire_number"] = 0
			low_solution["sink_rate_at_contact_mps"] = -8.0
			low_solution["wire_solutions"][0]["time_s"] = 1.0
			low_solution["wire_solutions"][0]["vertical_m"] = -8.0
			var low_path: Dictionary = pilot.call("_landing_sight_deck_footprint", low_solution)
			check(low_path.get("safe", false) and float(low_path.get("entry_delay_s", 0)) > 0.0,
				model + " horizontal support defers an early plane crossing")
			pilot.set("_landing_sight_solution", low_solution)
			check(pilot.call("_update_landing_high_miss_waveoff", 0.016), model + " unreachable vertical undershoot still rejects")
			check(pilot.get("_landing_sight_solution").get("waveoff_reason") == "escape_deadline_no_reachable_wire",
				model + " vertical reachability owns the undershoot decision")
			craft.global_position = carrier.to_global(Vector3(0, 12, -55))
			craft.linear_velocity = carrier.global_basis * Vector3(0, -3, 35)
			solution["main_gear_sensor"] = gear
			carrier.deck_velocity = Vector3(8, 0, -5)
			carrier.yaw_rate = 0.02
			var deck_motion: Vector3 = pilot.call("_get_landing_sight_deck_velocity_at", craft.global_position)
			craft.linear_velocity += deck_motion
			var moving_footprint: Dictionary = pilot.call("_landing_sight_deck_footprint", solution)
			check(moving_footprint.get("safe", false) and absf(float(moving_footprint.get("clearance_m", INF))
				- float(footprint.clearance_m)) < 0.01, model + " translation and yaw point velocity are carrier-relative")
			carrier.deck_velocity = Vector3.ZERO
			carrier.yaw_rate = 0.0
			craft.global_position = carrier.to_global(Vector3(13, 12, -55))
			craft.linear_velocity = carrier.global_basis * Vector3(3.9, -3, 35)
			solution["main_gear_sensor"] = pilot.call("_get_landing_sight_main_gear_sensor", Vector3.UP)
			pilot.set("_landing_sight_solution", solution)
			check(pilot.call("_update_landing_high_miss_waveoff", 0.016), model + " unsafe drift overrides viable catch")
			var decision: Dictionary = pilot.get("_landing_sight_solution")
			check(decision.get("waveoff_reason") == "unsafe_deck_footprint", model + " records explicit footprint reason")
			solution["main_gear_deck_projection"]["time_s"] = 8.0
			pilot.set("_landing_sight_solution", solution)
			check(not pilot.call("_update_landing_high_miss_waveoff", 0.016), model + " distant prediction leaves room to correct")
			solution["main_gear_deck_projection"]["time_s"] = 1.0
			pilot.set("_landing_sight_solution", solution)
			craft.set_meta("arresting_engaged", true)
			check(not pilot.call("_update_landing_high_miss_waveoff", 0.016), model + " actual arrest prevents late waveoff")
			craft.set_meta("arresting_engaged", false)
		craft.free()
	scene.free()
	print("DECK_FOOTPRINT_WAVEOFF_SMOKETEST %s checks=%d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
