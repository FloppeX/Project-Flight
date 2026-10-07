extends SceneTree

const CATALOG := preload("res://UI/TechnicalIndexCatalog.gd")
const VIEW := preload("res://UI/TechnicalIndexView.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.get_node("SaveGameManager").set("autosave_enabled", false)
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	var entry: Dictionary = {}
	for candidate in CATALOG.entries_for("GROUND VEHICLES"):
		if candidate.scene == "res://GroundVehicle/Harvester.tscn": entry = candidate
	if entry.is_empty():
		push_error("HARVESTER_INDEX_FAIL missing catalog entry")
		quit(1)
		return
	var view := VIEW.new()
	root.add_child(view)
	view.open()
	view._show_category("GROUND VEHICLES")
	view._select_entry(entry)
	await process_frame
	var model: Node = view.get_node("RotatablePreview/EquipmentViewport/PreviewPivot/ModelRoot")
	var bounds: Dictionary = view._calculate_preview_bounds()
	var ok: bool = bool(bounds.get("found", false)) and model.find_child("AuthoredHull", true, false) != null \
		and model.find_child("AuthoredExtractorHead", true, false) != null \
		and view._name_label.text == "RESOURCE HARVESTER" \
		and view._description_label.text.contains("160 units")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		ok = root.get_texture().get_image().save_png("res://captures/harvester_technical_index.png") == OK and ok
	print("HARVESTER_INDEX_", "PASS" if ok else "FAIL", " bounds=", bounds)
	view.free()
	quit(0 if ok else 1)
