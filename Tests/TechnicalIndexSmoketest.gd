extends SceneTree

const Catalog = preload("res://UI/TechnicalIndexCatalog.gd")
const TechnicalIndexView = preload("res://UI/TechnicalIndexView.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_menu_source := FileAccess.get_file_as_string("res://UI/MainMenu.gd")
	if not main_menu_source.contains("[\"TECHNICAL INDEX\", Callable(self, \"_show_technical_index\")]") \
			or not main_menu_source.contains("TechnicalIndexView.new()"):
		_fail("main menu did not expose the Technical Index route")
		return
	var expected_categories: Array[String] = [
		"LAND CARRIER",
		"AIRPLANES",
		"HELICOPTERS",
		"STRUCTURES",
		"WEAPONS",
	]
	if Catalog.categories() != expected_categories:
		_fail("category order did not match the requested Technical Index")
		return

	var scene_count := 0
	for category in expected_categories:
		var entries := Catalog.entries_for(category)
		if entries.is_empty():
			_fail("%s had no catalog entries" % category)
			return
		for entry in entries:
			var scene_path := String(entry.get("scene", ""))
			if not ResourceLoader.exists(scene_path):
				_fail("catalog scene was missing: %s" % scene_path)
				return
			var packed := load(scene_path) as PackedScene
			if packed == null:
				_fail("catalog scene could not be loaded: %s" % scene_path)
				return
			var instance := packed.instantiate()
			if not instance is Node3D:
				instance.free()
				_fail("catalog entry was not a 3D scene: %s" % scene_path)
				return
			instance.free()
			scene_count += 1

	var view := TechnicalIndexView.new() as Control
	root.add_child(view)
	view.call("open")
	if String(view.get("current_mode")) != "tech_categories":
		_fail("Technical Index did not open on its category list")
		return
	view.call("_show_category", "AIRPLANES")
	if String(view.get("current_mode")) != "tech_items":
		_fail("category selection did not open the equipment list")
		return
	var airplane_entries := Catalog.entries_for("AIRPLANES")
	view.call("_select_entry", airplane_entries[0])
	var selected_name := _find_label(view, String(airplane_entries[0].get("name", "")))
	if selected_name == null:
		_fail("selected equipment name was not rendered")
		return
	var pivot := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot") as Node3D
	if pivot == null:
		_fail("isolated rotatable preview world was unavailable")
		return
	var yaw_before := pivot.rotation.y
	view.call("rotate_preview", 0.2)
	if is_equal_approx(pivot.rotation.y, yaw_before):
		_fail("preview rotation input did not rotate the selected object")
		return

	print("[TechnicalIndexSmoketest] PASS categories=%d scenes=%d preview=rotatable" % [expected_categories.size(), scene_count])
	quit(0)


func _find_label(root_node: Node, text_value: String) -> Label:
	if root_node is Label and (root_node as Label).text == text_value:
		return root_node as Label
	for child in root_node.get_children():
		var found := _find_label(child as Node, text_value)
		if found != null:
			return found
	return null


func _fail(reason: String) -> void:
	push_error("[TechnicalIndexSmoketest] FAIL %s" % reason)
	quit(1)
