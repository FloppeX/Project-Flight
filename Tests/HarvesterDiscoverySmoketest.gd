extends Node3D

class CarrierFixture:
	extends Node3D
	var placement_complete := false
	var vehicle_bay: Node
	func is_initial_placement_complete() -> bool: return placement_complete

class BayFixture:
	extends Node
	var stored_harvesters := 1

var failures: Array[String] = []

func _ready() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("HARVESTER_DISCOVERY_FAIL: " + message)

func _run() -> void:
	for service in get_tree().root.get_children():
		if service != self: service.process_mode = Node.PROCESS_MODE_DISABLED
	FloatingOrigin.enabled = false
	var carrier := CarrierFixture.new()
	carrier.position = Vector3(0, 0, 44000)
	add_child(carrier)
	carrier.add_to_group("carrier")
	carrier.vehicle_bay = BayFixture.new()
	carrier.add_child(carrier.vehicle_bay)
	_setup_grid()
	MapFogOfWar._initialize_from_navgrid()
	var field := POIManager.get_resource_field()
	field.reset()
	POIManager._pois.clear()
	# Two local sites, one just outside the limit, and three around the
	# throwaway scene position that used to be granted before placement.
	for distance in [600.0, 2500.0, 4500.0, 43500.0, 44000.0, 45000.0]:
		var poi := POIManager.POIInstance.new()
		poi.id = POIManager._pois.size()
		poi.data = POIManager._make_data(poi.id)
		poi.world_pos = Vector3(0, 0, distance)
		POIManager._pois.append(poi)
	POIManager._starting_reveal_done = false
	POIManager._reveal_starting_pois()
	check(POIManager.get_discovered_map_markers().is_empty(), "temporary carrier placement never grants knowledge")
	check(not POIManager._starting_reveal_done, "startup discovery waits for placement without expiring")
	carrier.position = Vector3.ZERO
	carrier.placement_complete = true
	POIManager._reveal_starting_pois()
	check(POIManager.get_discovered_map_markers().size() == 2, "only local sites are granted, even when fewer than three exist")
	check(not POIManager._pois[2].discovered and not POIManager._pois[5].discovered, "4.5 km and 45 km sites remain unknown")
	check(MapFogOfWar.is_world_explored(POIManager._pois[0].world_pos), "legitimate starting intel has an actionable map patch")
	# Simulate a continued campaign carrying exactly the old false discoveries.
	for poi in POIManager._pois: poi.discovered = poi.id >= 3
	var leaked: int = field.add_salvage_source("Distant outpost", Vector3(0, 0, 45000), 500.0, "poi_5", true)
	var legacy: Dictionary = POIManager.capture_save_state()
	legacy.erase("discovery_version")
	POIManager.restore_save_state(legacy)
	POIManager._repair_legacy_starting_reveals()
	check(POIManager.get_discovered_map_markers().is_empty(), "legacy unexplored starter grants are cleared")
	check(not field.get_source(leaked).discovered, "legacy salvage no longer leaks the unexplored outpost")
	# Genuine explored intelligence must survive the conservative migration.
	for poi in POIManager._pois: poi.discovered = poi.id >= 3
	MapFogOfWar.reveal_circle(POIManager._pois[3].world_pos, 350.0)
	POIManager._legacy_starting_reveal_check_pending = true
	POIManager._repair_legacy_starting_reveals()
	check(POIManager.get_discovered_map_markers().size() == 3, "migration preserves campaigns with real explored discoveries")
	field.reset()
	var far: int = field.add_salvage_source("Surveyed distant wreck", Vector3(0, 0, 45000), 500.0, "far", true)
	var near: int = field.add_salvage_source("Nearby ruin", Vector3(500, 0, 0), 240.0, "near", true)
	var hidden: int = field.add_salvage_source("Unscouted ruin", Vector3(50, 0, 0), 240.0, "hidden", false)
	var stores := preload("res://LandCarrier/CarrierManager.gd").new()
	carrier.add_child(stores)
	var ops := stores.get_harvester_ops()
	ops.set_process(false)
	var panel := preload("res://UI/HarvesterPanel.gd").new()
	add_child(panel)
	panel.set_process(false)
	check(panel._sources.get_item_id(0) == near and panel._sources.get_selected_id() == near, "nearest known site is first and selected, regardless of insertion order")
	check(panel._sources.item_count == 2 and not ops.collect(hidden).is_empty(), "hidden source cannot be selected or ordered directly")
	check("500 m" in panel._sources.get_item_text(0), "picker shows travel distance")
	panel._sources.select(1)
	panel._sources.item_selected.emit(1)
	var closer: int = field.add_salvage_source("New nearby wreck", Vector3(100, 0, 0), 80.0, "closer", true)
	panel._refresh()
	check(panel._sources.get_selected_id() == far, "new discoveries preserve explicit player selection")
	panel._source_selection_explicit = false
	ops.phase = "travelling"
	ops.source_id = near
	panel._refresh()
	check(panel._sources.get_selected_id() == near, "mission changes update selection even without list changes")
	# Deployed distances are measured from the vehicle, not the carrier.
	var collector := preload("res://GroundVehicle/Harvester.tscn").instantiate()
	add_child(collector)
	collector.set_physics_process(false)
	collector.position = Vector3(0, 0, 44900)
	ops.vehicle = collector
	panel._refresh()
	check(panel._sources.get_item_id(0) == far and panel._sources.get_selected_id() == near, "deployed picker sorts from harvester while preserving its mission")
	check("from harvester" in panel._sources.get_item_tooltip(0), "distance reference is explicit")
	# Invalid restored orders stop before queueing deployment; no new destination
	# or cargo credit is invented by correcting discovery.
	ops.vehicle = null
	ops.phase = "queued"
	ops.source_id = hidden
	ops._process(0.1)
	check(ops.phase == "stored" and ops.source_id == -1, "an unknown saved assignment cannot deploy")
	ops.source_id = closer
	ops.phase = "stored"
	panel._source_selection_explicit = false
	panel._signature = ""
	panel._refresh()
	check(panel._sources.get_selected_id() == closer, "without an active order the nearest source is the default")
	print("HARVESTER_DISCOVERY_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _setup_grid() -> void:
	TerrainNavGrid.cell_size_m = 500.0
	TerrainNavGrid._cols = 201
	TerrainNavGrid._rows = 201
	TerrainNavGrid._origin_x = -50000.0
	TerrainNavGrid._origin_z = -50000.0
	var heights := PackedFloat32Array()
	heights.resize(201 * 201)
	heights.fill(0.0)
	TerrainNavGrid._heights = heights
	TerrainNavGrid._is_baked = true
	TerrainNavGrid._query_is_baked = false
	NavGraph._is_ready = false
