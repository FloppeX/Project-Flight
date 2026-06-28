@tool
extends EditorPlugin

const PREVIEW_SCRIPT := preload("res://HUD/Instruments/InstrumentPanelLayoutPreview.gd")

var dock: VBoxContainer
var preview: Control
var status_label: Label


func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "Instrument Panel Layout"

	var toolbar := HBoxContainer.new()
	dock.add_child(toolbar)

	var load_button := Button.new()
	load_button.text = "Load Selected"
	load_button.tooltip_text = "Load module_layout from the selected InstrumentPanel node."
	load_button.pressed.connect(_load_selected_layout)
	toolbar.add_child(load_button)

	var apply_button := Button.new()
	apply_button.text = "Apply"
	apply_button.tooltip_text = "Apply the preview layout to the selected InstrumentPanel node."
	apply_button.pressed.connect(_apply_to_selected_panel)
	toolbar.add_child(apply_button)

	var copy_button := Button.new()
	copy_button.text = "Copy"
	copy_button.tooltip_text = "Copy module_layout assignment text to the clipboard."
	copy_button.pressed.connect(_copy_layout)
	toolbar.add_child(copy_button)

	status_label = Label.new()
	status_label.text = "Select an InstrumentPanel node, then Load Selected."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(status_label)

	preview = PREVIEW_SCRIPT.new()
	preview.custom_minimum_size = Vector2(560, 270)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.add_child(preview)

	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree() -> void:
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()
	dock = null
	preview = null
	status_label = null


func _load_selected_layout() -> void:
	var panel := _selected_panel()
	if panel == null:
		_set_status("Select an InstrumentPanel node with a module_layout property first.")
		return
	var layout: Variant = panel.get("module_layout")
	if layout is Array and not (layout as Array).is_empty():
		preview.set_module_layout(layout)
		_set_status("Loaded layout from %s." % panel.name)
	else:
		_set_status("%s has no explicit layout; using preview default." % panel.name)


func _apply_to_selected_panel() -> void:
	var panel := _selected_panel()
	if panel == null:
		_set_status("Select an InstrumentPanel node before applying.")
		return
	panel.set("module_layout", preview.get_module_layout_copy())
	var editor_interface := get_editor_interface()
	if editor_interface != null and editor_interface.has_method("mark_scene_as_unsaved"):
		editor_interface.call("mark_scene_as_unsaved")
	_set_status("Applied layout to %s." % panel.name)


func _copy_layout() -> void:
	preview.copy_layout_to_clipboard()
	_set_status("Copied module_layout to clipboard.")


func _selected_panel() -> Node:
	var selection := get_editor_interface().get_selection()
	if selection == null:
		return null
	for node in selection.get_selected_nodes():
		if node != null and _node_has_property(node, "module_layout"):
			return node
	return null


func _node_has_property(node: Node, property_name: String) -> bool:
	for property in node.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message
	print("[InstrumentPanelLayoutEditor] %s" % message)
