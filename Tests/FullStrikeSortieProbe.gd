extends "res://Tests/FullScenarioFiveAircraftRecovery.gd"
## One production Aircraft 5, normal launch/CAS/RTB, finite ammunition and fuel.
## A stationary non-firing target isolates mission execution from enemy fire.
class StrikeTarget extends StaticBody3D:
	var current_health := 500.0
	var damage_total := 0.0
	func get_team() -> int: return 2
	func take_damage(amount: float) -> void:
		damage_total += maxf(amount, 0.0)
		current_health = maxf(current_health - amount, 0.0)

var strike_target: StrikeTarget
var attack_states := {}

func _run() -> void:
	for manager_name in ["EnemyOpsManager", "EnemyBaseManager"]:
		var manager := root.get_node(manager_name)
		manager.set("_disabled_for_test", true)
		manager.set_process(false)
		manager.set_physics_process(false)
	await super._run()

func _run_diagnostic_override() -> bool:
	stage = "launching"
	route_ordered = _order_route()
	var queued: int = deck.queue_ai_flight(1, observer, "rocket_strike", "Aircraft_5")
	_event("SORTIE_ORDER", {"model": "Aircraft_5", "loadout": "rocket_strike", "queued": queued})
	if queued != 1:
		_finish("launch_order_rejected")
		return true
	var deadline := elapsed() + 600.0
	while records.is_empty() and elapsed() < deadline:
		_sample()
		await create_timer(1.0).timeout
	if records.is_empty():
		_finish("launch_timeout")
		return true
	strike_target = StrikeTarget.new()
	strike_target.name = "SortieTarget"
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(12, 8, 12)
	collider.shape = shape
	strike_target.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	strike_target.add_child(mesh)
	current_scene.add_child(strike_target)
	var point := carrier.global_position + carrier.global_basis.z * 3500.0
	point.y = current_scene.get_node("LowPolyTerrainPrototype").get_height(point) + 4.0
	strike_target.global_position = point
	strike_target.add_to_group("buildings")
	strike_target.add_to_group("enemies")
	var id: int = records.keys()[0]
	var craft: Variant = live[id].craft.get_ref()
	air_ops.report_contact(craft, strike_target)
	air_ops.order_cas(records[id].flight, point, 1500.0)
	stage = "strike"
	_event("STRIKE_ORDER", {"target": point, "flight": records[id].flight})
	deadline = elapsed() + 420.0
	while elapsed() < deadline and not records[id].destroyed and not records[id].unavailable:
		_sample()
		attack_states[records[id].state] = true
		if strike_target.damage_total > 0.0: break
		await create_timer(1.0).timeout
	_event("STRIKE_RESULT", {"damage": strike_target.damage_total, "states": attack_states.keys()})
	if records[id].destroyed or records[id].unavailable:
		_finish("aircraft_lost_during_strike")
		return true
	stage = "recovering"
	recall_at = elapsed()
	air_ops.order_rtb(records[id].flight)
	_event("RECALL_ALL", {"launched": records.size()})
	while elapsed() - recall_at < 900.0:
		_sample()
		if records[id].stowed or records[id].destroyed or records[id].unavailable: break
		await create_timer(1.0).timeout
	_finish("sortie_observation_complete")
	return true

func _finish(reason: String) -> void:
	if stage == "complete": return
	var damage := strike_target.damage_total if is_instance_valid(strike_target) else 0.0
	var passed: bool = records.size() == 1 and damage > 0.0 and records.values().all(
		func(record): return record.caught and record.stowed and not record.destroyed)
	_event("SORTIE_RESULT", {"passed": passed, "reason": reason, "target_damage": damage,
		"attack_states": attack_states.keys(), "aircraft": records.values()})
	print("FULL_STRIKE_SORTIE ", "PASS" if passed else "FAIL", " reason=", reason)
	super._finish(reason)
	quit(0 if passed else 1)
