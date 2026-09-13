extends SceneTree


class TestAircraft:
	extends RigidBody3D

	var current_health := 100.0
	var max_health := 100.0


class RaisedCircuitTerrain:
	extends Node

	func get_height(world_pos: Vector3) -> float:
		# A ridge under the lateral downwind/turn, while the carrier centreline
		# remains clear. The compact pattern should climb over it, not fall back to
		# the legacy multi-kilometre arrival.
		if world_pos.z < -1400.0 and absf(world_pos.x) > 250.0:
			return 300.0
		return -1000.0


class RaisedIngressTerrain:
	extends Node

	func get_height(world_pos: Vector3) -> float:
		# A short ridge crosses only the aircraft-to-downwind join. It should raise
		# that one endpoint without raising or rejecting the carrier circuit.
		if world_pos.x > 650.0 and world_pos.z > -600.0 and world_pos.z < -500.0:
			return 450.0
		return -1000.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var carrier := Node3D.new()
	carrier.name = "CompactRecoveryCarrier"
	carrier.add_to_group("carrier")
	root.add_child(carrier)
	var aircraft := TestAircraft.new()
	aircraft.name = "CompactRecoveryAircraft"
	aircraft.position = Vector3(700.0, 300.0, -800.0)
	aircraft.linear_velocity = Vector3(10.0, 0.0, 70.0)
	root.add_child(aircraft)
	var pilot := Node.new()
	aircraft.add_child(pilot)
	pilot.set_script(load("res://AI/AIPilot.gd") as Script)
	pilot.set("aircraft", aircraft)
	pilot.set("carrier_position", Vector3.ZERO)
	pilot.set("aircraft_heightmap_pathfinding_enabled", false)
	var frame := {
		"valid": true,
		"origin": Vector3.ZERO,
		"forward": Vector3.BACK,
		"right": Vector3.RIGHT,
		"deck_y": 0.0,
	}

	if not bool(pilot.call("_try_install_compact_recovery_route", frame)):
		return _fail(aircraft, "near aircraft did not receive compact recovery route")
	if str(pilot.get("_flight_plan_name")) != "recovery_approach":
		return _fail(aircraft, "compact route did not become the recovery approach")
	var active_plan: Variant = pilot.get("_active_flight_plan")
	if active_plan == null or str(active_plan.metadata.get("planner", "")) != "compact_pattern":
		return _fail(aircraft, "compact route metadata is missing")
	var legs: Array = pilot.get("_flight_plan_legs")
	if legs.size() != 4:
		return _fail(aircraft, "expected 4 compact legs, got %d" % legs.size())
	if str((legs[0] as Dictionary).get("role", "")) != "recovery_transit" \
			or str((legs[legs.size() - 1] as Dictionary).get("role", "")) != "recovery_lineup":
		return _fail(aircraft, "compact route lost its downwind-to-lineup role sequence")
	var arc_leg: Dictionary = legs[2] as Dictionary
	if str(arc_leg.get("route_primitive", "")) != "arc" \
			or not is_equal_approx(float(arc_leg.get("arc_sweep_rad", 0.0)), PI):
		return _fail(aircraft, "compact break is not one continuous 180-degree arc")
	if not is_equal_approx(absf(float(arc_leg.get("arc_turn_sign", 0.0))), 1.0):
		return _fail(aircraft, "compact break has no directed turn")
	var ingress_alt_m := float((legs[0] as Dictionary).get("carrier_alt_above_deck_m", NAN))
	var break_start_alt_m := float((legs[1] as Dictionary).get("carrier_alt_above_deck_m", NAN))
	var break_end_alt_m := float(arc_leg.get("carrier_alt_above_deck_m", NAN))
	if not is_finite(ingress_alt_m) or not is_finite(break_start_alt_m) \
			or not is_finite(break_end_alt_m):
		return _fail(aircraft, "compact descent profile has invalid altitudes")
	if break_start_alt_m >= ingress_alt_m - 20.0:
		return _fail(aircraft, "compact route still postpones descent until the break")
	var arc_descent_angle_deg := rad_to_deg(atan2(
		break_start_alt_m - break_end_alt_m,
		PI * float(arc_leg.get("turn_radius_m", 0.0))
	))
	var expected_pre_final_deg := float(pilot.get("landing_glideslope_deg")) \
		* float(pilot.get("recovery_compact_pre_final_slope_scale"))
	if absf(arc_descent_angle_deg - expected_pre_final_deg) > 0.25:
		return _fail(aircraft, "compact break descent is not continuous with glideslope: %.2fdeg" % arc_descent_angle_deg)

	var maximum_behind_m := 0.0
	var maximum_lateral_m := 0.0
	var route_length_m := 0.0
	var previous := aircraft.global_position
	for leg_value: Variant in legs:
		var leg := leg_value as Dictionary
		maximum_behind_m = maxf(maximum_behind_m, float(leg.get("carrier_behind_m", 0.0)))
		maximum_lateral_m = maxf(maximum_lateral_m, absf(float(leg.get("carrier_right_m", 0.0))))
		var point: Vector3 = leg.get("position", previous)
		if str(leg.get("route_primitive", "")) == "arc":
			route_length_m += float(leg.get("arc_sweep_rad", 0.0)) \
				* float(leg.get("turn_radius_m", 0.0))
			maximum_behind_m = maxf(
				maximum_behind_m,
				float(leg.get("carrier_arc_center_behind_m", 0.0)) \
					+ float(leg.get("turn_radius_m", 0.0))
			)
		else:
			route_length_m += Vector2(point.x - previous.x, point.z - previous.z).length()
		previous = point
	if maximum_behind_m > 3000.0:
		return _fail(aircraft, "compact route still extends %.0fm behind the carrier" % maximum_behind_m)
	if maximum_lateral_m > 925.0:
		return _fail(aircraft, "compact route exceeds its local lateral circuit")
	if route_length_m > 6500.0:
		return _fail(aircraft, "compact route is still too long: %.0fm" % route_length_m)
	if not is_equal_approx(float(pilot.call("_get_active_route_lookahead_distance_m")), 180.0):
		return _fail(aircraft, "compact route did not select short-turn lookahead")

	# Every point belongs to the moving carrier frame, including the abeam circuit.
	var first_before: Vector3 = (pilot.get("waypoints") as Array)[0]
	var arc_center_before: Vector2 = (pilot.get("_flight_plan_legs") as Array)[2].get(
		"arc_center_xz",
		Vector2.ZERO
	)
	var shifted_frame: Dictionary = frame.duplicate()
	shifted_frame["origin"] = Vector3(125.0, 0.0, -80.0)
	pilot.call("_update_recovery_carrier_relative_gates", shifted_frame)
	var first_after: Vector3 = (pilot.get("waypoints") as Array)[0]
	var arc_center_after: Vector2 = (pilot.get("_flight_plan_legs") as Array)[2].get(
		"arc_center_xz",
		Vector2.ZERO
	)
	if not Vector2(first_after.x - first_before.x, first_after.z - first_before.z) \
			.is_equal_approx(Vector2(125.0, -80.0)):
		return _fail(aircraft, "compact circuit did not move with the carrier: before=%s after=%s" % [
			str(first_before),
			str(first_after),
		])
	if not (arc_center_after - arc_center_before).is_equal_approx(Vector2(125.0, -80.0)):
		return _fail(aircraft, "compact turn center did not move with the carrier")

	# Nearby terrain should raise the same compact circuit instead of rejecting it
	# and restoring the old long approach.
	var raised_terrain := RaisedCircuitTerrain.new()
	root.add_child(raised_terrain)
	pilot.set("_terrain_height_callable", Callable(raised_terrain, "get_height"))
	aircraft.position = Vector3(700.0, 300.0, -800.0)
	pilot.call("_clear_flight_plan")
	pilot.set("_recovery_route_request_debugged", false)
	if not bool(pilot.call("_try_install_compact_recovery_route", frame)):
		return _fail(aircraft, "terrain ridge rejected the compact route instead of raising it")
	active_plan = pilot.get("_active_flight_plan")
	var terrain_raise_m: float = float(active_plan.metadata.get("terrain_raise_m", 0.0))
	var raised_circuit_m: float = terrain_raise_m
	if terrain_raise_m < 150.0 or terrain_raise_m > 230.0:
		return _fail(aircraft, "compact terrain raise was outside its bounded envelope: %.1fm" % terrain_raise_m)
	legs = pilot.get("_flight_plan_legs")
	if float((legs[1] as Dictionary).get("carrier_alt_above_deck_m", 0.0)) < 410.0:
		return _fail(aircraft, "raised compact downwind did not preserve terrain clearance")
	if not is_equal_approx(float(pilot.get("recovery_compact_turn_bank_limit_deg")), 50.0):
		return _fail(aircraft, "compact break lost its 450m-radius bank envelope")
	pilot.set("_terrain_height_callable", Callable())
	raised_terrain.free()

	# A ridge confined to the live ingress may need more climb than the compact
	# circuit's own raise ceiling. Those limits must remain independent.
	var ingress_terrain := RaisedIngressTerrain.new()
	root.add_child(ingress_terrain)
	pilot.set("_terrain_height_callable", Callable(ingress_terrain, "get_height"))
	aircraft.position = Vector3(700.0, 300.0, -800.0)
	pilot.call("_clear_flight_plan")
	pilot.set("_recovery_route_request_debugged", false)
	if not bool(pilot.call("_try_install_compact_recovery_route", frame)):
		return _fail(aircraft, "ingress ridge rejected a clear compact circuit")
	active_plan = pilot.get("_active_flight_plan")
	var ingress_raise_m: float = float(active_plan.metadata.get("ingress_raise_m", 0.0))
	terrain_raise_m = float(active_plan.metadata.get("terrain_raise_m", 0.0))
	if ingress_raise_m <= float(pilot.get("recovery_compact_pattern_max_raise_m")) \
			or ingress_raise_m > float(pilot.get("recovery_compact_ingress_max_raise_m")):
		return _fail(aircraft, "ingress climb did not use its independent bounded allowance: %.1fm" % ingress_raise_m)
	if terrain_raise_m > float(pilot.get("recovery_compact_preferred_side_max_raise_m")):
		return _fail(aircraft, "ingress-only ridge unnecessarily raised the compact circuit: %.1fm" % terrain_raise_m)
	pilot.set("_terrain_height_callable", Callable())
	ingress_terrain.free()

	# A distant aircraft should terrain-transit toward the local circuit, not toward
	# the old multi-kilometre centreline join.
	aircraft.position = Vector3(-500.0, 500.0, -6000.0)
	pilot.call("_clear_flight_plan")
	if not bool(pilot.call("_ensure_compact_recovery_rtb_plan")):
		return _fail(aircraft, "distant RTB did not select compact-circuit ingress")
	var rtb_waypoints: Array = pilot.get("waypoints")
	if rtb_waypoints.is_empty():
		return _fail(aircraft, "compact RTB ingress has no waypoint")
	var rtb_goal: Vector3 = rtb_waypoints[rtb_waypoints.size() - 1]
	var rtb_goal_range := Vector2(rtb_goal.x, rtb_goal.z).length()
	if rtb_goal_range > 1100.0:
		return _fail(aircraft, "RTB still targets a far-behind setup point: goal=%s range=%.0fm plan=%s" % [
			str(rtb_goal),
			rtb_goal_range,
			str(pilot.get("_flight_plan_name")),
		])
	# The asynchronous terrain route uses this same local endpoint. Its result must
	# not be compared to the legacy multi-kilometre centreline handoff contract.
	pilot.set("current_state", 11) # AIPilot.State.RTB
	var contract_failure: String = str(pilot.call("_route_result_contract_failure", {
		"plan_name": "rtb",
		"provenance": {
			"origin_shift_epoch": int(pilot.get("_origin_shift_epoch")),
			"request_final_goal": rtb_goal,
			"request_carrier_position": Vector3.ZERO,
		},
		"legs": [{"position": rtb_goal}],
	}))
	if not contract_failure.is_empty():
		return _fail(aircraft, "compact RTB terrain route failed its contract: %s" % contract_failure)

	# The default recovery policy should commit the imperfect but meaningful pose
	# observed in the Aircraft_2 logs, while still rejecting extreme/late entries.
	var press_assessment := {
		"valid": true,
		"lateral_m": 205.0,
		"vertical_m": 107.0,
		"track_yaw_error_deg": 12.0,
		"fpa_error_deg": 4.0,
		"bank_deg": 12.0,
		"carrier_relative_velocity": Vector3(0.0, -12.0, 68.0),
	}
	if not bool(pilot.call("_is_recovery_press_handoff", press_assessment, 1000.0)):
		return _fail(aircraft, "press mode rejected a recoverable high/offset approach")
	var extreme_press_assessment: Dictionary = press_assessment.duplicate()
	extreme_press_assessment["lateral_m"] = 300.0
	if bool(pilot.call("_is_recovery_press_handoff", extreme_press_assessment, 1000.0)):
		return _fail(aircraft, "press mode accepted an extreme lateral approach")
	extreme_press_assessment = press_assessment.duplicate()
	extreme_press_assessment["vertical_m"] = -35.0
	if bool(pilot.call("_is_recovery_press_handoff", extreme_press_assessment, 1000.0)):
		return _fail(aircraft, "press mode accepted a dangerously low approach")
	if bool(pilot.call("_is_recovery_press_handoff", press_assessment, 300.0)):
		return _fail(aircraft, "press mode accepted a new handoff inside the final cone gate")

	# Once the missed-approach budget is exhausted, the route owner must expose a
	# local hold exception instead of requesting another generic terrain arrival.
	pilot.set("_recovery_go_around_attempt_count", 3)
	pilot.set("_recovery_compact_retry_only", true)
	pilot.call("_enter_compact_recovery_hold", "smoketest", true)
	if int(pilot.get("current_state")) != 13 \
			or not bool(pilot.get("_recovery_retry_limit_reached")) \
			or not (pilot.get("waypoints") as Array).is_empty():
		return _fail(aircraft, "bounded bolter retry did not terminate in a route-free local hold")

	aircraft.free()
	carrier.free()
	print("[CompactCarrierRecoverySmoketest] PASS local_route=%.0fm max_behind=%.0fm max_lateral=%.0fm turn=180deg descent=%.1fdeg rollout=2000m terrain_raise=%.0fm ingress_raise=%.0fm moving_carrier=true distant_rtb_goal=%.0fm press=recoverable_errors_committed bolter_retry=bounded" % [
		route_length_m,
		maximum_behind_m,
		maximum_lateral_m,
		arc_descent_angle_deg,
		raised_circuit_m,
		ingress_raise_m,
		rtb_goal_range,
	])
	quit(0)


func _fail(aircraft: Node, reason: String) -> void:
	push_error("[CompactCarrierRecoverySmoketest] FAIL %s" % reason)
	if is_instance_valid(aircraft):
		aircraft.free()
	quit(1)
