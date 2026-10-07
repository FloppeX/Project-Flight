extends Node3D
## Finite seep cycles, danger, checkpoints and player collection intent.
var failures: Array[String] = []
var field: Node

class Collector extends Node3D:
	const CAPACITY := 160.0
	const EXTRACTION_RATE := 12.0
	var cargo := {"corium": 0.0, "plasteel": 0.0}
	var collecting := true
	var is_dying := false
	var deploy_mode := false
	var retrieve_mode := false
	var velocity := Vector3.ZERO
	var collection_target := Vector3.ZERO
	var points: Array[Vector3] = []
	var damage_taken := 0.0
	var current_health := 100.0
	func can_extract() -> bool: return collecting
	func arm_folded() -> bool: return true
	func cargo_total() -> float: return float(cargo.corium) + float(cargo.plasteel)
	func load_cargo(material: String, amount: float) -> float:
		var accepted := clampf(amount, 0.0, CAPACITY - cargo_total())
		cargo[material] += accepted
		return accepted
	func set_patrol_waypoints(at: Array[Vector3]) -> void: points = at.duplicate()
	func take_damage(amount: float) -> void: damage_taken += amount

class Bay extends Node:
	signal vehicle_deployed(unit)
	signal vehicle_retrieved(unit)
	signal vehicle_spawned(unit)
	var stored_harvesters := 1
	var deploy_calls := 0
	func deploy_harvester() -> bool:
		deploy_calls += 1
		return false
	func can_retrieve_vehicles() -> bool: return false

class Carrier extends Node3D:
	var vehicle_bay: Node
	func is_initial_placement_complete() -> bool: return true

func _ready() -> void: _run.call_deferred()

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("CORIUM_RESOURCE_FAIL: " + label)

func _run() -> void:
	for child in get_tree().root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene = self
	GameSession.finish_loaded_game()
	TerrainNavGrid._is_baked = false
	TerrainNavGrid._query_is_baked = false
	NavGraph._is_ready = false
	field = POIManager.get_resource_field()
	field.reset()
	var id: int = field.add_corium_seep("Test seep", Vector3.ZERO, 800.0, true, true)
	var source: Dictionary = field.get_source(id)
	var collector := Collector.new()
	add_child(collector)
	check(field.remaining(source) == 800.0 and field.available(source) == 160.0, "initial surface stock belongs to a finite underground deposit")
	field.extract(id, 500.0, collector)
	check(collector.cargo.corium == 160.0 and field.remaining(source) == 640.0, "cargo capacity and total stock are conserved")
	field._advance_seeps(10.0)
	check(source.materials.corium == 80.0 and source.reserve_corium == 560.0 and field.remaining(source) == 640.0, "surface seep transfers material without creating it")
	field._advance_seeps(35.0)
	check(source.seep_phase == "dormant" and field.available(source) == 0.0 and field.remaining(source) == 640.0, "dormancy conceals surface material without depletion")
	collector.cargo = {"corium": 0.0, "plasteel": 0.0}
	field.extract(id, 160.0, collector)
	check(collector.cargo_total() == 0.0 and field.discovered_sources().size() == 1, "dormant seeps remain known but cannot be extracted")
	_test_mission_waiting(source, collector)
	_test_checkpoint(id)
	source = field.get_source(id)
	field._advance_seeps(float(source.phase_left))
	check(source.seep_phase == "seeping" and field.available(source) > 0.0, "the next active cycle reopens collection")
	_test_hazards(source, collector)
	# Empty the complete reservoir through the cargo interface, across cycles.
	var recovered := 160.0
	collector.collecting = true
	for trip in range(20):
		collector.cargo = {"corium": 0.0, "plasteel": 0.0}
		if source.seep_phase == "dormant": field._advance_seeps(float(source.phase_left))
		field._advance_seeps(20.0)
		field.extract(id, 160.0, collector)
		recovered += collector.cargo_total()
		if field.remaining(source) <= 0.01: break
	check(is_equal_approx(recovered, 800.0) and field.remaining(source) == 0.0 and source.seep_phase == "exhausted", "repeated collection exhausts exactly the finite reserve")
	field._advance_seeps(2000.0)
	check(field.remaining(source) == 0.0 and field.corium_exposure_at(Vector3.ZERO) == 0.0 and field.discovered_sources().is_empty(), "exhausted seeps never refill or harm units")
	_test_scene_origin_shift()
	_test_legacy_save()
	_test_salvage_dedup()
	await _test_pause_and_campaign_gates()
	print("CORIUM_RESOURCE_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_mission_waiting(source: Dictionary, collector: Collector) -> void:
	var carrier := Carrier.new()
	add_child(carrier)
	carrier.add_to_group("carrier")
	var bay := Bay.new()
	carrier.add_child(bay)
	carrier.vehicle_bay = bay
	var ops := load("res://LandCarrier/HarvesterOps.gd").new() as Node
	carrier.add_child(ops)
	ops.set_process(false)
	check(ops.collect(int(source.id), true).is_empty() and ops.phase == "waiting_stored", "repeat orders wait in bay during dormancy")
	ops._process(1.0)
	check(bay.deploy_calls == 0, "waiting does not launch a futile empty trip")
	ops.recall()
	check(ops.phase == "stored" and not ops.repeat_collection, "explicit recall cancels a waiting mission")
	ops.vehicle = collector
	ops.source_id = int(source.id)
	ops.phase = "harvesting"
	ops.repeat_collection = true
	collector.cargo = {"corium": 30.0, "plasteel": 0.0}
	ops._process(1.0)
	check(ops.phase == "folding" and ops.repeat_collection and collector.cargo_total() == 30.0, "partial loads return at dormancy without canceling repeat intent")
	collector.cargo = {"corium": 0.0, "plasteel": 0.0}
	ops.phase = "harvesting"
	collector.collecting = true
	ops._process(1.0)
	check(ops.phase == "waiting_seep" and not collector.collecting and collector.points.is_empty(), "empty collectors fold and wait stationary")
	var saved: Dictionary = ops.capture_save_state()
	check(saved.phase == "waiting_seep" and bool(saved.repeat), "waiting mission and repeat intent are checkpointed")
	ops.recall()
	check(ops.phase == "folding" and not ops.repeat_collection, "recall remains available while waiting at a seep")
	ops.vehicle = null
	carrier.free()

func _test_checkpoint(id: int) -> void:
	var before: Dictionary = field.get_source(id).duplicate(true)
	var encoded: Variant = SaveGameManager._encode_json_value(field.capture_save_state())
	var saved: Dictionary = SaveGameManager._decode_json_value(JSON.parse_string(JSON.stringify(encoded)))
	field.restore_save_state(saved)
	var source: Dictionary = field.get_source(id)
	check(source.seep_phase == before.seep_phase and source.phase_left == before.phase_left and source.materials == before.materials and source.reserve_corium == before.reserve_corium, "JSON campaign checkpoint preserves phase timer and both stocks")
	source["wreck_position"] = Vector3(20, 0, 40)
	field.apply_origin_shift(Vector3(100, 0, 200))
	check(source.position == Vector3(-100, 0, -200) and source.wreck_position == Vector3(-80, 0, -160), "origin shift keeps source and wreck provenance aligned")
	field.apply_origin_shift(Vector3(-100, 0, -200))

func _test_hazards(source: Dictionary, collector: Collector) -> void:
	collector.position = source.position
	collector.add_to_group("ground_vehicles")
	collector.add_to_group("friendlies")
	field._apply_corium_hazards(1.0)
	check(is_equal_approx(collector.damage_taken, field.CORIUM_DAMAGE_PER_S), "unshielded units take exposure damage once despite multiple groups")
	check(field.corium_exposure_at(source.position + Vector3(20, 0, 0)) == 0.0 and field.corium_exposure_at(source.position + Vector3(0, 20, 0)) == 0.0, "hazard is bounded near the ground and seep")
	var harvester := load("res://GroundVehicle/Harvester.tscn").instantiate() as Node3D
	add_child(harvester)
	harvester.set_physics_process(false)
	harvester.position = source.position
	var health: float = harvester.current_health
	field._apply_corium_hazards(2.0)
	check(harvester.current_health == health, "real harvester containment protects collection")
	source.seep_phase = "dormant"
	var before := collector.damage_taken
	field._apply_corium_hazards(1.0)
	check(collector.damage_taken == before, "dormant crust stops exposure damage")
	source.seep_phase = "seeping"
	collector.remove_from_group("ground_vehicles")
	collector.remove_from_group("friendlies")
	harvester.free()

func _test_legacy_save() -> void:
	field.restore_save_state({"seeded": true, "sources": [{"id": 7, "label": "Old deposit", "position": Vector3.ZERO, "kind": "corium", "materials": {"corium": 63.0, "plasteel": 0.0}, "initial": 800.0, "discovered": true}]})
	var source: Dictionary = field.get_source(7)
	check(field.remaining(source) == 63.0 and source.reserve_corium == 0.0 and source.seep_phase == "seeping", "legacy saves acquire cycles without free materials")

func _test_scene_origin_shift() -> void:
	var id: int = field.add_source("Ruined machinery", Vector3(1000, 0, 200), "ruin", {"plasteel": 40.0}, true)
	var source: Dictionary = field.get_source(id)
	var visual: Node3D = field.get("_visuals")[id]
	var nested: Node3D
	for child in visual.get_children():
		if child is Node3D and not child.scene_file_path.is_empty():
			nested = child
			break
	if nested == null:
		check(false, "resource origin-shift fixture includes an authored ruin")
		return
	var site := load("res://POI/World/AbandonedOutpostSite.tscn").instantiate() as Node3D
	add_child(site)
	site.position = Vector3(600, 0, 600)
	var root_before := visual.global_position
	var ruin_before := nested.global_position
	var site_before := site.global_position
	var offset := Vector3(100, 0, 200)
	FloatingOrigin.shift_origin(offset)
	check(visual.global_position == root_before - offset and source.position == visual.global_position, "resource marker and saved coordinates shift together exactly once")
	check(nested.global_position == ruin_before - offset and source.wreck_position == nested.global_position, "nested authored ruin shifts once with its marker and collision")
	check(site.global_position == site_before - offset, "ordinary authored POI site shifts once through the scene root")
	FloatingOrigin.shift_origin(-offset)
	site.free()

func _test_salvage_dedup() -> void:
	var id: int = field.add_salvage_source("Ruin", Vector3(200, 0, 0), 100.0, "test_ruin", true)
	var collector := Collector.new()
	add_child(collector)
	collector.position = field.get_source(id).position
	field.extract(id, 60.0, collector)
	field.add_salvage_source("Ruin", Vector3(200, 0, 0), 100.0, "test_ruin", true)
	check(field.get_source(id).materials.plasteel == 40.0, "repeated POI salvage registration does not replenish harvested material")
	var source: Dictionary = field.get_source(id)
	source["wreck_position"] = Vector3(188, 0, 0)
	var ops := load("res://LandCarrier/HarvesterOps.gd").new() as Node
	add_child(ops)
	ops.set_process(false)
	ops.vehicle = collector
	ops.source_id = id
	collector.position = Vector3(180, 0, 0)
	ops._travel_to_source()
	check(not collector.points.is_empty() and collector.points[0].x > source.position.x, "salvage approaches stay outside the surviving wreck")
	ops.vehicle = null
	ops.free()
	collector.free()

func _test_pause_and_campaign_gates() -> void:
	var source: Dictionary = field.get_source(7)
	var before: float = source.phase_left
	field._process(10.0)
	check(source.phase_left == before, "non-campaign scenes do not advance seeps")
	scene_file_path = "res://Main_Scene.tscn"
	var carrier := Carrier.new()
	add_child(carrier)
	carrier.add_to_group("carrier")
	TerrainNavGrid._is_baked = true
	TerrainNavGrid._cols = 1
	TerrainNavGrid._rows = 1
	TerrainNavGrid._heights = PackedFloat32Array([0.0])
	field.seeded = true
	field._poll = 100.0
	field.set_process(true)
	get_tree().paused = true
	await get_tree().create_timer(0.06, true).timeout
	check(source.phase_left == before, "paused world freezes seep timers and damage")
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	check(float(source.phase_left) < before, "campaign processing resumes after unpause")
	field.set_process(false)
	carrier.free()
