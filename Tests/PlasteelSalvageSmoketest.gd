extends SceneTree

var failures: Array[String] = []
var world: Node3D
var field: Node

class Collector extends Node3D:
	const CAPACITY := 160.0
	var cargo := {"corium": 0.0, "plasteel": 0.0}
	func cargo_total() -> float: return float(cargo.corium) + float(cargo.plasteel)
	func can_extract() -> bool: return true
	func load_cargo(material: String, amount: float) -> float:
		var accepted := minf(amount, CAPACITY - cargo_total())
		cargo[material] += accepted
		return accepted

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PLASTEEL_SALVAGE_FAIL: " + message)

func _run() -> void:
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	world = Node3D.new()
	world.scene_file_path = "res://Main_Scene.tscn"
	root.add_child(world)
	current_scene = world
	field = root.get_node("POIManager").get_resource_field()
	field.reset()
	root.get_node("GameSession").finish_loaded_game()
	root.get_node("TerrainNavGrid")._is_baked = false
	root.get_node("TerrainNavGrid")._query_is_baked = false
	root.get_node("NavGraph")._is_ready = false
	await _test_building()
	await _test_live_scene("res://Buildings/building_barracks.tscn", 180.0)
	await _test_live_scene("res://Buildings/building_wind_turbine.tscn", 220.0)
	await _test_live_scene("res://Buildings/gun_emplacement.tscn", 65.0)
	await _test_persistent_ruin("res://Buildings/building_enemy_outpost.tscn", 300.0)
	await _test_persistent_ruin("res://Buildings/building_enemy_vehicle_bay.tscn", 220.0)
	_test_guards()
	await process_frame
	if failures.is_empty():
		print("PLASTEEL_SALVAGE_SMOKETEST_OK buildings turbine emplacement outpost bay finite-cargo save-restore guards")
		quit(0)
	else:
		quit(1)

func _test_building() -> void:
	print("PLASTEEL_CASE generic building")
	var building: Node3D = load("res://Buildings/Building.gd").new()
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = Vector3(40, 14, 24)
	shape.material = StandardMaterial3D.new()
	mesh.mesh = shape
	building.add_child(mesh)
	world.add_child(building)
	building.set("_explosion_scene", null)
	var before: int = field.sources.size()
	building.call("take_damage", 1000.0)
	check(field.sources.size() == before + 1, "building destruction creates one salvage site")
	building.call("_destroy")
	check(field.sources.size() == before + 1, "repeated building destruction does not duplicate materials")
	var source: Dictionary = field.sources.back()
	check(float(source.materials.plasteel) == 180.0 and float(source.materials.corium) == 0.0, "building ruin yields plasteel only")
	var local: Vector3 = building.to_local(source.position)
	check(absf(local.x) > 20.0 or absf(local.z) > 12.0, "salvage collection marker sits outside the authored building footprint")
	# Loading finite salvage follows the existing cargo contract and survives a checkpoint.
	source.discovered = true
	var collector := Collector.new()
	world.add_child(collector)
	collector.global_position = source.position
	field.extract(int(source.id), 500.0, collector)
	check(float(collector.cargo.plasteel) == 160.0 and float(source.materials.plasteel) == 20.0, "extraction respects harvester capacity and remaining wreck material")
	var saved: Dictionary = root.get_node("SaveGameManager")._decode_json_value(JSON.parse_string(JSON.stringify(root.get_node("SaveGameManager")._encode_json_value(field.capture_save_state()))))
	var source_id := int(source.id)
	field.restore_save_state(saved)
	check(float(field.get_source(source_id).materials.plasteel) == 20.0, "checkpoint retains partially harvested salvage")
	collector.free()
	await process_frame

func _test_live_scene(path: String, expected: float) -> void:
	print("PLASTEEL_CASE ", path)
	var unit := load(path).instantiate() as Node3D
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	if "is_dummy" in unit: unit.set("is_dummy", true)
	world.add_child(unit)
	unit.set("_explosion_scene", null)
	var before: int = field.sources.size()
	unit.call("take_damage", 10000.0)
	check(field.sources.size() == before + 1, "%s creates one wreck salvage site" % path)
	unit.call("_destroy")
	check(field.sources.size() == before + 1, "%s guards repeated destruction" % path)
	check(float(field.sources.back().materials.plasteel) == expected, "%s gives its configured plasteel yield" % path)
	await process_frame

func _test_persistent_ruin(path: String, expected: float) -> void:
	print("PLASTEEL_CASE persistent ", path)
	var unit := load(path).instantiate() as Node3D
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(unit)
	unit.set("_explosion_scene", null)
	var before: int = field.sources.size()
	unit.call("take_damage", 10000.0)
	check(field.sources.size() == before + 1 and float(field.sources.back().materials.plasteel) == expected, "%s creates finite ruin salvage on live destruction" % path)
	var saved: Dictionary = unit.call("capture_save_state")
	unit.call("_destroy")
	check(field.sources.size() == before + 1, "%s guards repeated live destruction" % path)
	var restored := load(path).instantiate() as Node3D
	restored.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(restored)
	restored.call("restore_save_state", saved)
	check(field.sources.size() == before + 1, "%s checkpoint rebuilds ruin without granting salvage again" % path)
	check(bool(restored.get("is_destroyed")), "%s remains ruined after restoring" % path)
	unit.queue_free()
	restored.queue_free()
	await process_frame

func _test_guards() -> void:
	var building: Node3D = load("res://Buildings/Building.gd").new()
	world.add_child(building)
	var before: int = field.sources.size()
	building.add_to_group("runway_surface")
	load("res://Buildings/Building.gd").register_plasteel_salvage(building, "Tarmac", 180.0)
	check(field.sources.size() == before, "destroyed tarmac is not a plasteel ruin")
	building.remove_from_group("runway_surface")
	building.set_meta("suppress_enemy_ops_on_destroy", true)
	load("res://Buildings/Building.gd").register_plasteel_salvage(building, "Load-time reconstruction", 180.0)
	check(field.sources.size() == before, "suppressed reconstruction cannot manufacture salvage")
	building.remove_meta("suppress_enemy_ops_on_destroy")
	world.scene_file_path = "res://Tests/Fixture.tscn"
	load("res://Buildings/Building.gd").register_plasteel_salvage(building, "Test-only wreck", 180.0)
	check(field.sources.size() == before, "resource sources are limited to the campaign world")
	world.scene_file_path = "res://Main_Scene.tscn"
	building.queue_free()
