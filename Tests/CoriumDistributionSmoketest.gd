extends Node
## Fixed allocation, failed placement retries, depletion and checkpoint continuity.
class FieldFixture:
	extends "res://POI/ResourceField.gd"
	var allow_region := false
	func _validated_seed_position(at: Vector3, slot: int) -> Vector3:
		return at if slot < 2 or allow_region else Vector3.INF
	func _spawn_visual(_source: Dictionary) -> void: pass

class TerrainField:
	extends "res://POI/ResourceField.gd"
	func _spawn_visual(_source: Dictionary) -> void: pass

var failures: Array[String] = []
var root: Window:
	get: return get_tree().root
func _ready() -> void: _run.call_deferred()
func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("CORIUM_DISTRIBUTION_FAIL: " + label)

func _roundtrip(state: Dictionary) -> Dictionary:
	return SaveGameManager._decode_json_value(JSON.parse_string(JSON.stringify(SaveGameManager._encode_json_value(state))))

func _run() -> void:
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	TerrainNavGrid._is_baked = false
	TerrainNavGrid._query_is_baked = false
	var field := FieldFixture.new()
	root.add_child(field)
	field.set_process(false)
	var start := Vector3(300, 0, -200)
	for poll in range(20): field._seed_terrain(start)
	check(field.sources.size() == 2 and not field.seeded, "two starter successes do not abandon missing regional opportunities")
	var checkpoint := _roundtrip(field.capture_save_state())
	var restored := FieldFixture.new()
	root.add_child(restored)
	restored.set_process(false)
	restored.restore_save_state(checkpoint)
	check(restored._seed_attempts == field._seed_attempts and restored._seed_origin == start, "save retains failed candidate history and original campaign anchor")
	field.allow_region = true
	restored.allow_region = true
	for poll in range(80):
		field._seed_terrain(start)
		restored._seed_terrain(start + Vector3(9000, 0, 9000))
	check(field.seeded and field.sources.size() == 9, "all eight finite deposits plus starter salvage are placed")
	for original in field.sources:
		var resumed: Dictionary = restored.get_source(int(original.id))
		check(not resumed.is_empty() and (original.position as Vector3).is_equal_approx(resumed.position) and original.seed_slot == resumed.seed_slot and field.remaining(original) == restored.remaining(resumed), "moving the carrier or reloading does not reroll placement: " + str(original.id))
	var total := 0.0
	var counts := [0, 0, 0, 0]
	for source in field.sources:
		if source.kind != "corium": continue
		total += field.remaining(source)
		var distance: float = source.position.distance_to(start)
		if distance <= 1100.01: counts[0] += 1
		elif distance >= 1999.99 and distance <= 4000.01: counts[1] += 1
		elif distance >= 5999.99 and distance <= 10000.01: counts[2] += 1
		elif distance >= 11999.99 and distance <= 18000.01: counts[3] += 1
	check(counts == [1, 2, 2, 3] and total == 6720.0, "scarce sites span four distances with varied finite yields")
	var overview := field.corium_overview(start)
	check(overview.sites == 3 and overview.remaining == 1760.0, "starter surveys show two alternatives without leaking distant hidden reserves")
	# Exhausted slots are tombstones: long waits, travel and JSON reloads cannot
	# create replacements. Remaining abandoned sites retain their exact stocks.
	var exhausted: Dictionary = field.sources[0]
	exhausted.materials.corium = 0.0
	exhausted.reserve_corium = 0.0
	field._advance_seeps(3600.0)
	var after := _roundtrip(field.capture_save_state())
	after.seeded = false # A pending placement pass must count exhausted slots too.
	restored.restore_save_state(after)
	for poll in range(100): restored._seed_terrain(Vector3(18000, 0, 18000))
	restored._advance_seeps(3600.0)
	var depleted: Dictionary = restored.get_source(int(exhausted.id))
	check(restored.sources.size() == 9 and restored.remaining(depleted) == 0.0 and depleted.seep_phase == "exhausted", "depleted sites remain permanently exhausted after travel, waiting and reload")
	check(restored.corium_overview(start).remaining == 1280.0 and restored.corium_overview(start).exhausted == 1, "planning totals exclude exhausted sites and retain unharvested alternatives")
	var next := restored._seed_candidate(6, 99)
	var offset := Vector3(4500, 0, -2200)
	restored.apply_origin_shift(offset)
	check(restored._seed_candidate(6, 99).is_equal_approx(next - offset), "origin shifts move pending candidates with existing geography")
	# A completed legacy map is kept intact, even if old placement found few sites.
	restored.restore_save_state({"seeded": true, "sources": [exhausted.duplicate(true)]})
	restored._seed_terrain(start)
	check(restored.sources.size() == 1 and restored.remaining(restored.sources[0]) == 0.0, "legacy completed maps do not receive retroactive replacement deposits")
	field.free()
	restored.free()
	if "--terrain" in OS.get_cmdline_user_args():
		await _test_terrain()
	print("CORIUM_DISTRIBUTION_%s %s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_terrain() -> void:
	var terrain := preload("res://Environment/LowPolyTerrain.gd").new()
	terrain.generate_on_ready = false
	terrain.seed = 22551
	terrain.plateau_height_m = 500.0
	terrain.base_height_offset_m = 220.0
	root.add_child(terrain)
	terrain.set_process(false)
	TerrainNavGrid.disk_cache_enabled = false
	if TerrainNavGrid.bake_complete.is_connected(NavGraph._init_graph):
		TerrainNavGrid.bake_complete.disconnect(NavGraph._init_graph)
	TerrainNavGrid._reset_bake_state()
	if TerrainNavGrid.bake_complete.is_connected(NavGraph._init_graph):
		TerrainNavGrid.bake_complete.disconnect(NavGraph._init_graph)
	TerrainNavGrid._try_start_bake()
	var bake_started := Time.get_ticks_msec()
	var last_stage := ""
	while not TerrainNavGrid.is_ready():
		if Time.get_ticks_msec() - bake_started > 600000:
			check(false, "terrain bake completed within ten minutes")
			terrain.free()
			return
		TerrainNavGrid._bake_rows()
		var stage := TerrainNavGrid.get_bake_stage_label()
		if stage != last_stage:
			print("CORIUM_TERRAIN ", stage)
			last_stage = stage
		await get_tree().process_frame
	print("CORIUM_TERRAIN grid ready")
	NavGraph._reset_graph()
	await NavGraph._build(true)
	await NavGraph._build_spatial_index(true)
	NavGraph._is_ready = true
	print("CORIUM_TERRAIN graph ready")
	var origin := Vector3.INF
	for index in range(NavGraph._nodes.size()):
		var at: Vector3 = NavGraph._nodes[index]
		if NavGraph._node_cl[index] >= 80.0 and TerrainNavGrid.is_low_clear_position(at.x, at.z, 10.0) and at.length_squared() < origin.length_squared():
			origin = at
	check(origin != Vector3.INF, "real terrain has a carrier-width starting anchor")
	if origin != Vector3.INF:
		var field := TerrainField.new()
		root.add_child(field)
		field.set_process(false)
		var peak_ms := 0.0
		for poll in range(600):
			var before := Time.get_ticks_usec()
			field._seed_terrain(origin)
			peak_ms = maxf(peak_ms, (Time.get_ticks_usec() - before) / 1000.0)
			if field.seeded: break
			await get_tree().process_frame
		check(field.seeded and field.sources.size() == 9, "real campaign terrain supports all eight reachable finite deposits")
		print("CORIUM_TERRAIN sites=%d origin=%s attempts=%s peak_poll_ms=%.1f" % [field.sources.size(), origin, field._seed_attempts, peak_ms])
		for frame in range(1800):
			field._seed_salvage(origin)
			if field._salvage_seeded: break
			await get_tree().process_frame
		check(field._salvage_seeded and field.sources.size() == 21, "real campaign terrain supports twelve reachable scattered ruins beside the eight deposits and starter ruin")
		print("PLASTEEL_TERRAIN sources=%d attempts=%s" % [field.sources.size(), field._salvage_attempts])
		field.free()
	terrain.free()
