extends Node3D

const Escape = preload("res://AI/HelicopterEscape.gd")
class ProbePilot extends HelicopterPilot:
	func _get_ground_height_at_position(_point: Vector3) -> float: return 0.0
	func _get_heightmap_route_point(_a: Vector3, _b: Vector3) -> Vector3: return Vector3(0, 50, 500)
	func _sample_max_terrain_height_along_path(_a: Vector3, _b: Vector3) -> float: return 0.0
	func _apply_forward_terrain_hazard(_a: Vector3, _b: Vector3) -> bool: return false
	func _get_heightmap_upcoming_required_altitude(_a: Vector3, _b: float) -> float: return 50.0

var failures := 0
func _ready() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var flat := func(_p: Vector3) -> float: return 0.0
	var start := Vector3(0, 50, -400)
	var target := Vector3.ZERO
	var plan: Dictionary = Escape.choose(start, target, Vector3.BACK, 700, 24, flat)
	_check(not plan.is_empty() and not plan.covered, "flat terrain is exposed, not cover")
	_check(plan.position.z <= start.z and Escape.closest_range(start, plan.position, target) >= 120, "escape stays before target")
	_check(Escape.choose(start, target, Vector3.ZERO, 700, 24, flat).is_empty(), "degenerate heading rejected")
	_check(Escape.choose(start, target, Vector3.BACK, 700, 24, func(_p): return NAN).is_empty(), "unknown terrain rejected")
	_check(not Escape.segment_clear(start, Vector3(400, 50, -400), 24,
		func(p): return 80.0 if p.x > 150 and p.x < 250 else 0.0), "ridge across escape rejected")
	var ridge := func(p: Vector3) -> float:
		return 70.0 if p.x > 100 and p.x < 500 and p.z > -300 and p.z < -100 else 0.0
	plan = Escape.choose(start, target, Vector3.BACK, 700, 24, ridge)
	_check(not plan.is_empty() and plan.covered and plan.position.x > 0, "prefer shielded side without crossing its ridge")
	_check(Escape.closest_range(Vector3(0, 50, -400), Vector3(0, 50, 400), target) == 0.0, "overflight chord detected")
	var scene := Node3D.new()
	add_child(scene)
	var body := RigidBody3D.new()
	body.freeze = true
	scene.add_child(body)
	body.position = Vector3(0, 200, 0)
	var pilot := ProbePilot.new()
	pilot.combat_report_enabled = false
	pilot.crash_log_enabled = false
	body.add_child(pilot)
	pilot.aircraft = body
	pilot._atk_weapon_kind = "gun"
	_check(pilot._atk_run_entry_range_m() < 1300, "long-range lineup does not start firing timeout")
	body.linear_velocity = Vector3(0, 0, 20)
	var slow_breakoff := pilot._atk_turnaway_distance_m()
	body.linear_velocity = Vector3(0, 0, 50)
	_check(pilot._atk_turnaway_distance_m() > slow_breakoff, "fast pass reserves more turn-away distance")
	body.linear_velocity = Vector3.ZERO
	pilot.state = HelicopterPilot.State.LOW_LEVEL_TRANSIT
	pilot.mission_phase = HelicopterPilot.MissionPhase.OUTBOUND
	pilot._atk_state = HelicopterPilot.AtkState.RUN
	_check(pilot._atk_owns_terminal_guidance(), "run owns terminal guidance")
	pilot._atk_state = HelicopterPilot.AtkState.INGRESS
	pilot._atk_ingress_aligning = true
	_check(pilot._atk_owns_terminal_guidance(), "lineup owns terminal guidance")
	pilot._atk_ingress_aligning = false
	_check(not pilot._atk_owns_terminal_guidance(), "staging retains terrain route")
	pilot._atk_state = HelicopterPilot.AtkState.EGRESS
	_check(not pilot._atk_owns_terminal_guidance(), "egress retains terrain route")
	var foe := Node3D.new()
	scene.add_child(foe)
	var carrier := Node3D.new()
	scene.add_child(carrier)
	carrier.add_to_group("carrier")
	carrier.position = Vector3(-1000, 0, 0)
	pilot._commanded_attack_target = foe
	pilot._atk_target = foe
	_check(pilot.command_return_to_carrier_and_land(), "return accepted")
	_check(pilot._commanded_attack_target == null and pilot._atk_target == null, "return clears both attack owners")
	_check(pilot.mission_phase == HelicopterPilot.MissionPhase.INBOUND, "return owns mission")
	pilot.set_physics_process(false)
	carrier.remove_from_group("carrier")
	for command in ["command_hover", "command_land"]:
		pilot._commanded_attack_target = foe
		pilot._atk_target = foe
		pilot.call(command, Vector3(20, 50, 30))
		_check(pilot._commanded_attack_target == null and pilot._atk_target == null, command + " cancels attack")
	pilot.state = HelicopterPilot.State.LOW_LEVEL_TRANSIT
	pilot.mission_phase = HelicopterPilot.MissionPhase.OUTBOUND
	pilot._atk_state = HelicopterPilot.AtkState.SELECT
	pilot.use_heightmap_pathfinding = false
	pilot.destination = Vector3(0, 50, 1000)
	pilot._has_destination = true
	var altitudes: Array[float] = []
	for physics_delta in [1.0 / 60.0, 1.0 / 120.0]:
		pilot._physics_delta = physics_delta
		pilot._navigation_elapsed_s = 0.35
		pilot._transit_cruise_altitude_m = 200.0
		pilot._update_navigation_plan()
		altitudes.append(pilot._transit_cruise_altitude_m)
	_check(is_equal_approx(altitudes[0], altitudes[1]) and altitudes[0] < 195, "descent uses accumulated navigation time")
	print("HELI_SHOOT_SCOOT_SMOKE failures=%d" % failures)
	get_tree().quit(1 if failures else 0)
