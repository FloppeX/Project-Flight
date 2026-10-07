extends Node3D
class CarrierFixture:
	extends Node3D
	var vehicle_bay: Node
class BayFixture:
	extends Node
	var stored_harvesters := 1

func _ready() -> void: _run.call_deferred()
func _run() -> void:
	for singleton in get_tree().root.get_children():
		if singleton != self: singleton.process_mode = Node.PROCESS_MODE_DISABLED
	var carrier := CarrierFixture.new()
	add_child(carrier)
	carrier.add_to_group("carrier")
	carrier.vehicle_bay = BayFixture.new()
	carrier.add_child(carrier.vehicle_bay)
	var stores := preload("res://LandCarrier/CarrierManager.gd").new()
	carrier.add_child(stores)
	stores.get_harvester_ops().set_process(false)
	var field := POIManager.get_resource_field()
	field.reset()
	field.add_corium_seep("Starter seep", Vector3(550, 0, 0), 480.0, true)
	field.add_corium_seep("North survey", Vector3(0, 0, -2400), 640.0, true, false)
	field.add_corium_seep("South survey", Vector3(0, 0, 3300), 640.0, true)
	field.add_corium_seep("Hidden reserve", Vector3(12000, 0, 0), 1120.0)
	var salvage_id: int = field.add_ruin_source(0, 0, Vector3(900, 0, 0), Vector3(917, 0, 0), 0.3)
	field.get_source(salvage_id).discovered = true
	CarrierConsole.show_page("ground_bay", true)
	var page: Node = CarrierConsole.get("_ground_page")
	var panel: Node = page.find_child("HarvesterPanel", true, false)
	panel._refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	assert("1760" in panel._planning.text and "3 known" in panel._planning.text)
	assert("~3 loads" in panel._source_info.text)
	assert("240 remaining" in panel._salvage_planning.text)
	await _capture("known")
	for index in range(panel._sources.item_count):
		if panel._sources.get_item_id(index) == salvage_id: panel._sources.select(index)
	panel._refresh()
	assert("PLASTEEL SALVAGE" in panel._source_info.text and "~2 loads" in panel._source_info.text)
	await _capture("salvage")
	for source in field.sources:
		if source.discovered:
			source.materials.corium = 0.0
			source.reserve_corium = 0.0
			source.materials.plasteel = 0.0
	field._advance_seeps(1.0)
	panel._refresh()
	await get_tree().process_frame
	assert("Scout new terrain" in panel._planning.text and panel._collect.disabled)
	await _capture("depleted")
	print("CORIUM_PLANNING_RENDER_PASS known_reserves+finite_wording+no_hidden_intel+depleted_guidance")
	get_tree().quit()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://captures/corium_planning_%s.png" % label
	get_viewport().get_texture().get_image().save_png(path)
	print("CORIUM_PLANNING_FRAME ", path)
