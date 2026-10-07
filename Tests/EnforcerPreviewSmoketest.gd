extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	for service in root.get_children(): service.process_mode = Node.PROCESS_MODE_DISABLED
	var view := preload("res://UI/TechnicalIndexView.gd").new()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.show()
	view._selected_category = "GROUND VEHICLES"
	view.current_mode = "tech_items"
	view._category_panel.hide()
	view._item_panel.show()
	var entry: Dictionary
	var base_entry: Dictionary
	for candidate in preload("res://UI/TechnicalIndexCatalog.gd").entries_for("GROUND VEHICLES"):
		if candidate.name == "KMV ENFORCER": entry = candidate
		if candidate.name == "KMV DEFENDER": base_entry = candidate
	if entry.is_empty() or base_entry.is_empty():
		push_error("ENFORCER_PREVIEW_FAIL missing vehicle catalog entry")
		quit(1)
		return
	view._select_entry(base_entry)
	var base_barrel := view._preview_model_root.find_child("PreviewBarrel10mm", true, false)
	var base_passed: bool = base_barrel != null and base_barrel.visible
	view._select_entry(entry)
	var barrel := view._preview_model_root.find_child("PreviewBarrel20mm", true, false)
	var passed: bool = base_passed and barrel != null and barrel.visible and not view._empty_preview_label.visible \
		and view._name_label.text == "KMV ENFORCER" and "20 mm" in view._description_label.text
	if DisplayServer.get_name() != "headless":
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures/vehicle_3")
		var save_error := root.get_texture().get_image().save_png("res://captures/vehicle_3/technical_index.png")
		passed = passed and save_error == OK
	print("ENFORCER_PREVIEW_%s" % ("PASS" if passed else "FAIL"))
	view.queue_free()
	await process_frame
	quit(0 if passed else 1)
