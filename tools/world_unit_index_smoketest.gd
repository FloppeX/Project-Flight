extends SceneTree

class TestFormation:
	extends Node
	var position: Vector3 = Vector3.ZERO
	var vehicle_count: int = 5
	var vstate: int = 0
	var _active_vehicles: Array[Node3D] = []


var _index: Node = null
var _spawned: Array[Node] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_index = root.get_node_or_null("WorldUnitIndex")
	if _index == null:
		_fail("WorldUnitIndex autoload missing")
		return

	# Tree additions are indexed on a deferred callback. A short-lived node can
	# disappear before that callback runs, so the callback must tolerate a dead ref.
	var short_lived_node := Node3D.new()
	var short_lived_ref: WeakRef = weakref(short_lived_node)
	short_lived_node.free()
	_index.call("_consider_node_ref", short_lived_ref)

	var friendly_near := _make_unit("FriendlyNear", Vector3(20.0, 0.0, 15.0), ["ground_vehicles", "friendlies"])
	var friendly_far := _make_unit("FriendlyFar", Vector3(1200.0, 0.0, 0.0), ["ground_vehicles", "friendlies"])
	var enemy_near := _make_unit("EnemyNear", Vector3(45.0, 0.0, 0.0), ["ground_vehicles", "enemies"])
	var aircraft_near := _make_unit("AircraftNear", Vector3(100.0, 60.0, 0.0), ["ai_aircraft", "enemies"])

	var nearby_ground: Array = _index.query_nodes_in_groups(Vector3.ZERO, 80.0, ["ground_vehicles"])
	if not nearby_ground.has(friendly_near) or not nearby_ground.has(enemy_near) or nearby_ground.has(friendly_far):
		_fail("nearby ground query returned the wrong set: %s stats=%s" % [_node_names(nearby_ground), _index.get_report_stats()])
		return

	var nearby_enemy: Array = _index.query_nodes_in_groups(Vector3.ZERO, 150.0, ["enemies"])
	if not nearby_enemy.has(enemy_near) or not nearby_enemy.has(aircraft_near) or nearby_enemy.has(friendly_near):
		_fail("enemy group query returned the wrong set")
		return

	var nearest_friendly: float = float(_index.nearest_friendly_distance(Vector3.ZERO, 500.0))
	if absf(nearest_friendly - friendly_near.global_position.length()) > 0.01:
		_fail("nearest friendly distance was incorrect: %.3f" % nearest_friendly)
		return

	_index.report_observation(friendly_near, enemy_near, true, 1.0)
	var observation: Dictionary = _index.get_cached_observation(friendly_near, enemy_near)
	if observation.is_empty() or not bool(observation.get("visible", false)):
		_fail("observation cache did not retain a visible contact")
		return

	var formation := TestFormation.new()
	formation.name = "TestFormation"
	formation.position = Vector3(30.0, 0.0, 0.0)
	root.add_child(formation)
	_spawned.append(formation)
	_index.register_formation(formation, "platoon", "TEST-P01")
	await process_frame
	var formations: Array = _index.get_formation_records()
	var found_formation := false
	for record_value in formations:
		var record: Dictionary = record_value
		if String(record.get("name", "")) == "TEST-P01":
			found_formation = int(record.get("count", -1)) == 5 and String(record.get("kind", "")) == "platoon"
			break
	if not found_formation:
		_fail("formation record was missing or incomplete")
		return
	if not bool(_index.should_materialize_formation(Vector3.ZERO, 100.0, 500.0)):
		_fail("nearby friendly did not trigger formation materialization relevance")
		return
	if bool(_index.should_dematerialize_formation(Vector3.ZERO, 500.0)):
		_fail("nearby friendly incorrectly triggered formation dematerialization")
		return

	var transient_member := Node3D.new()
	root.add_child(transient_member)
	formation._active_vehicles.append(transient_member)
	transient_member.queue_free()
	await process_frame
	await process_frame
	_index.call("_refresh_formation_records")

	friendly_near.global_position = Vector3(900.0, 0.0, 0.0)
	await create_timer(0.2).timeout
	var old_cell_query: Array = _index.query_nodes_in_groups(Vector3.ZERO, 80.0, ["ground_vehicles"])
	var new_cell_query: Array = _index.query_nodes_in_groups(Vector3(900.0, 0.0, 0.0), 80.0, ["ground_vehicles"])
	if old_cell_query.has(friendly_near) or not new_cell_query.has(friendly_near):
		_fail("moving unit did not change spatial cells")
		return
	if not bool(_index.should_dematerialize_formation(Vector3.ZERO, 500.0)):
		_fail("distant friendlies did not trigger formation dematerialization relevance")
		return

	var stats: Dictionary = _index.get_report_stats()
	print("[WorldUnitIndexSmoke] PASS units=%d cells=%d formations=%d queries=%d candidates=%d returned=%d" % [
		int(stats.get("units", 0)),
		int(stats.get("cells", 0)),
		int(stats.get("formations", 0)),
		int(stats.get("queries", 0)),
		int(stats.get("candidates", 0)),
		int(stats.get("returned", 0)),
	])
	_cleanup()
	quit(0)


func _make_unit(unit_name: String, world_position: Vector3, groups: Array[String]) -> Node3D:
	var unit := Node3D.new()
	unit.name = unit_name
	root.add_child(unit)
	for group_name in groups:
		unit.add_to_group(group_name)
	unit.global_position = world_position
	_index.register_unit(unit)
	_spawned.append(unit)
	return unit


func _fail(message: String) -> void:
	push_error("[WorldUnitIndexSmoke] FAIL: %s" % message)
	_cleanup()
	quit(1)


func _cleanup() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.queue_free()
	_spawned.clear()


func _node_names(nodes: Array) -> Array[String]:
	var names: Array[String] = []
	for node in nodes:
		if node is Node:
			names.append((node as Node).name)
	return names
