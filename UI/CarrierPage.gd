class_name CarrierPage
extends Control

const DAMAGE := preload("res://LandCarrier/CarrierDamageControl.gd")
const WIREFRAME := preload("res://UI/CarrierWireframeView.gd")
const FONT := preload("res://UI/Fonts/JetBrainsMono-Variable.ttf")
const GREEN := Color("6ddd98")
const ORANGE := Color("ffb454")
const RED := Color("ff626d")
const TEXT := Color("e4ecee")
const DIM := Color("85999e")
const ORDER := ["hull", "flight", "catapults", "hangar", "elevators", "island", "vehicle_bay", "reactor", "replicator", "habitation", "defenses", "drive", "stores"]
const CONSEQUENCES := {
	"hull": "Lost at zero integrity. Structural repairs require a stopped carrier and 15 seconds without a hit. Armor subtracts 20 per external attack; internal fires bypass armor.",
	"flight": "Offline or isolated: new launches and landing clearances held. Operations already underway finish safely.",
	"catapults": "Offline or isolated: new launches held. Recovery remains available if the flight deck is operational.",
	"hangar": "Offline or isolated: new hangar retrievals held. Transfers already underway finish safely.",
	"elevators": "Offline or isolated: new hangar retrievals held. Lifts already moving finish their transfer.",
	"drive": "Degraded: half speed and turning authority. Offline or isolated: carrier stops. Navigation orders remain queued.",
	"island": "Degraded: half carrier radar radius. Offline or isolated: carrier sensor contacts unavailable. Aircraft reports and command controls remain usable.",
	"vehicle_bay": "Offline or isolated: new platoon deployments held. Existing ground units remain operational.",
	"defenses": "Tracked per installed mount. Degraded mounts aim and fire at reduced cadence; offline or isolated mounts stop engaging. DefenseOps reallocates targets.",
	"reactor": "Condition and fires tracked. Detailed power allocation and reactor failures are not modeled in this first slice.",
	"replicator": "Condition and fires tracked. Fabrication and replacement-component production remain planned systems.",
	"habitation": "Condition and fires tracked. Crew injuries, medical staffing and specialist repair skills are not modeled yet.",
	"stores": "Plasteel funds permanent repairs. Condition and fires tracked; secondary supply losses are not modeled yet.",
}
var _control: Node
var _wireframe_view: Control
var _selected_system_id := "hull"
var _detail_id := "hull"
var _buttons: Dictionary = {}
var _integrity: Label
var _bar: ProgressBar
var _alert: Label
var _title: Label
var _state: Label
var _consequence: Label
var _readout: Label
var _response: Label
var _crew: Label
var _stores: Label
var _priority: Button
var _isolate: Button
var _repairs: Button
var _reserve: Button
var _urgent: Button
var _mounts: OptionButton
var _mount_ids: Array[String] = []
var _elapsed := 0.0

func _ready() -> void:
	_build_ui()
	_refresh()
	_apply_selection_to_schematic()

func bind_damage_control(control: Node) -> void:
	_control = control
	_refresh()

func set_console_visible(value: bool) -> void:
	visible = value
	_wireframe_view.call("set_console_visible", value)
	if value:
		_refresh()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_elapsed += delta
	if _elapsed >= 0.25:
		_elapsed = 0.0
		_refresh()

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0b1115")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	column.add_child(_label("CARRIER  /  DAMAGE CONTROL", 24, TEXT))
	_alert = _label("Awaiting carrier telemetry", 13, DIM)
	column.add_child(_alert)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	column.add_child(content)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.0
	left.add_theme_constant_override("separation", 8)
	content.add_child(left)
	_integrity = _label("STRUCTURAL INTEGRITY  — / 2000", 20, TEXT)
	left.add_child(_integrity)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size.y = 12
	_bar.show_percentage = false
	left.add_child(_bar)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.custom_minimum_size.y = 250
	frame.add_theme_stylebox_override("panel", _style(Color("090d0d"), Color("28393f")))
	left.add_child(frame)
	_wireframe_view = WIREFRAME.new()
	_wireframe_view.name = "CarrierWireframeView"
	_wireframe_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wireframe_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(_wireframe_view)
	left.add_child(_label("GREEN Operational   ORANGE Degraded   RED Offline / Fire / Isolated\nDrag to orbit • Scroll to zoom • Select a section below", 11, DIM))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	left.add_child(grid)
	for id in ORDER:
		var button := _button(str(DAMAGE.LABELS.get(id, "Structure")))
		button.custom_minimum_size = Vector2(100, 42)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_system.bind(id))
		grid.add_child(button)
		_buttons[id] = button
	_stores = _label("", 12, TEXT)
	left.add_child(_stores)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 380
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	scroll.add_child(right)
	_title = _label("", 23, TEXT)
	right.add_child(_title)
	_state = _label("", 16, TEXT)
	right.add_child(_state)
	_mounts = OptionButton.new()
	_mounts.item_selected.connect(_select_mount)
	right.add_child(_mounts)
	_consequence = _label("", 13, DIM)
	right.add_child(_consequence)
	_readout = _label("", 13, TEXT)
	right.add_child(_readout)
	_response = _label("", 13, ORANGE)
	right.add_child(_response)
	_urgent = _button("PRIORITIZE REPAIR")
	_urgent.pressed.connect(_request_urgent)
	right.add_child(_urgent)
	_isolate = _button("ISOLATE SYSTEM")
	_isolate.pressed.connect(_toggle_isolation)
	right.add_child(_isolate)
	right.add_child(_label("EMERGENCY RESPONSE", 16, TEXT))
	_crew = _label("", 12, TEXT)
	right.add_child(_crew)
	_priority = _button("PRIORITY: SURVIVAL")
	_priority.pressed.connect(_cycle_repair_priority)
	right.add_child(_priority)
	_reserve = _button("REPAIR RESERVE: 100 PL")
	_reserve.pressed.connect(_cycle_reserve)
	right.add_child(_reserve)
	_repairs = _button("REPAIRS: AUTO")
	_repairs.pressed.connect(_toggle_repairs)
	right.add_child(_repairs)
	right.add_child(_label("Fire suppression always takes priority and uses no plasteel. Limited emergency patches are free; full repairs consume material above your reserve.", 11, DIM))

func _refresh() -> void:
	if not is_instance_valid(_control):
		_control = get_tree().get_first_node_in_group("carrier_damage_control")
	var connected := is_instance_valid(_control)
	for button in [_urgent, _isolate, _priority, _reserve, _repairs]:
		button.disabled = not connected or (connected and bool(_control.get("lost")))
	if not connected:
		_alert.text = "NO LIVE CARRIER — damage-control commands unavailable"
		_integrity.text = "STRUCTURAL INTEGRITY  — / —"
		_bar.value = 0
		_title.text = "Carrier offline"
		_state.text = "NO TELEMETRY"
		_consequence.text = ""
		_readout.text = ""
		_response.text = ""
		_crew.text = "Teams unavailable"
		_stores.text = "STORES TELEMETRY UNAVAILABLE"
		_mounts.hide()
		_wireframe_view.call("set_region_statuses", {})
		return
	var hp: float = _control.get("structure")
	var maximum: float = _control.get("max_structure")
	_integrity.text = "STRUCTURAL INTEGRITY  %d / %d  ·  ARMOR %d" % [ceili(hp), maximum, _control.get("armor")]
	_integrity.modulate = GREEN if hp >= maximum * 0.75 else ORANGE if hp > maximum * 0.3 else RED
	_bar.max_value = maximum
	_bar.value = hp
	_bar.modulate = _integrity.modulate
	_alert.text = str(_control.get("last_event"))
	var fire_count := 0
	for s in (_control.get("systems") as Dictionary).values():
		if float(s.fire) > 0.0:
			fire_count += 1
	if fire_count > 0 and not _control.get("lost"):
		_alert.text = "%d ACTIVE FIRE(S) — emergency crews responding. Select a red section for containment controls." % fire_count
	_alert.modulate = RED if _control.get("lost") else TEXT
	var region_states: Dictionary = {}
	for id in ORDER:
		var current_status: String = _control.call("status", id)
		var s: Dictionary = _control.call("system_snapshot", id)
		var button: Button = _buttons[id]
		button.text = "%s\n%s %d%%" % [str(s.label).to_upper(), current_status, ceili(s.condition)]
		button.add_theme_color_override("font_color", _color(current_status))
		button.add_theme_stylebox_override("normal", _style(Color("1c2b30") if id == _selected_system_id else Color("111b20"), _color(current_status) if id == _selected_system_id else Color("28393f")))
		if id != "hull":
			region_states["flight_deck" if id == "flight" else id] = current_status
	var systems: Dictionary = _control.get("systems")
	for id in systems:
		if str(id).begins_with("mount:"):
			region_states[id] = _control.call("status", id)
	_wireframe_view.call("set_region_statuses", region_states)
	_update_mounts(systems)
	var detail: Dictionary = _control.call("system_snapshot", _detail_id)
	if detail.is_empty():
		_detail_id = _selected_system_id
		detail = _control.call("system_snapshot", _detail_id)
	var current_status: String = _control.call("status", _detail_id)
	_title.text = str(detail.label).to_upper()
	_state.text = "%s  ·  %d%%" % [current_status, ceili(detail.condition)]
	_state.modulate = _color(current_status)
	_consequence.text = CONSEQUENCES[_selected_system_id]
	var missing := maximum - hp if _detail_id == "hull" else 100.0 - float(detail.condition)
	_readout.text = "Fire intensity: %d%%\nFull restoration: up to %d plasteel\n%s" % [ceili(detail.fire), ceili(missing * (2.0 if _detail_id == "hull" else 1.0)), "Isolated — manually return to service" if detail.isolated else "Operations held by damage/fire" if current_status in ["FIRE", "OFFLINE", "LOST"] else "Connected to operations"]
	_response.text = _control.call("repair_note", _detail_id)
	_urgent.text = "CLEAR URGENT PRIORITY" if _control.get("urgent") == _detail_id else "PRIORITIZE REPAIR"
	_isolate.visible = _detail_id != "hull"
	_isolate.text = "RETURN TO SERVICE" if detail.isolated else "ISOLATE SYSTEM"
	_isolate.disabled = bool(_control.get("lost")) or (detail.isolated and float(detail.fire) > 0)
	_crew.text = ""
	for team in _control.get("teams"):
		var job: Dictionary = _control.call("system_snapshot", str(team.job))
		_crew.text += "%s — %s\n%s\n" % [team.name, job.get("label", "Available"), team.task]
	_priority.text = "PRIORITY: " + str(_control.get("doctrine"))
	_reserve.text = "REPAIR RESERVE: %d PL" % _control.get("repair_reserve")
	_repairs.text = "REPAIRS: AUTO" if _control.get("repairs_enabled") else "REPAIRS: PAUSED"
	var manager := _control.get_parent().get_node_or_null("CarrierManager")
	_stores.text = "PLASTEEL %d  ·  RESERVED %d  ·  CORIUM %d" % [manager.get("plasteel_units"), _control.get("repair_reserve"), manager.get("corium_units")] if manager != null else "STORES TELEMETRY UNAVAILABLE"
	_apply_selection_to_schematic()

func _update_mounts(systems: Dictionary) -> void:
	_mounts.visible = _selected_system_id == "defenses"
	var ids: Array[String] = ["defenses"]
	for id in systems:
		if str(id).begins_with("mount:"):
			ids.append(id)
	if ids == _mount_ids:
		return
	_mount_ids = ids
	_mounts.clear()
	for id in ids:
		_mounts.add_item("All defenses" if id == "defenses" else str(systems[id].label))
	_mounts.select(maxi(ids.find(_detail_id), 0))

func _select_mount(index: int) -> void:
	_detail_id = _mount_ids[index]
	_refresh()

func _select_system(id: String) -> void:
	if not ORDER.has(id):
		return
	_selected_system_id = id
	_detail_id = id
	if _mounts != null and _mounts.item_count > 0:
		_mounts.select(0)
	_refresh()
	_apply_selection_to_schematic()

func _apply_selection_to_schematic() -> void:
	var region := "overview" if _selected_system_id == "hull" else "flight_deck" if _selected_system_id == "flight" else _selected_system_id
	_wireframe_view.call("set_highlighted_region", region, false)

func _request_urgent() -> void:
	if is_instance_valid(_control):
		_control.call("set_urgent", _detail_id)
		_refresh()

func _toggle_isolation() -> void:
	if is_instance_valid(_control):
		var s: Dictionary = _control.call("system_snapshot", _detail_id)
		_control.call("set_isolated", _detail_id, not bool(s.isolated))
		_refresh()

func _cycle_repair_priority() -> void:
	if is_instance_valid(_control):
		var index := DAMAGE.DOCTRINES.find(_control.get("doctrine"))
		_control.set("doctrine", DAMAGE.DOCTRINES[(index + 1) % DAMAGE.DOCTRINES.size()])
		_refresh()

func _cycle_reserve() -> void:
	if is_instance_valid(_control):
		var options := [0.0, 100.0, 250.0]
		_control.set("repair_reserve", options[(options.find(_control.get("repair_reserve")) + 1) % options.size()])
		_refresh()

func _toggle_repairs() -> void:
	if is_instance_valid(_control):
		_control.set("repairs_enabled", not bool(_control.get("repairs_enabled")))
		_refresh()

func get_debug_snapshot() -> Dictionary:
	return {"kind": "carrier", "mode": "live_damage_control", "mock_data": false, "telemetry_connected": is_instance_valid(_control), "selected_system": _selected_system_id, "system_count": ORDER.size(), "wireframe": _wireframe_view.call("get_debug_snapshot")}

func _color(current_status: String) -> Color:
	return GREEN if current_status == "OPERATIONAL" else ORANGE if current_status == "DEGRADED" else RED

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 36
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_stylebox_override("normal", _style(Color("111b20"), Color("28393f")))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, GREEN))
	return button

func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	return style
