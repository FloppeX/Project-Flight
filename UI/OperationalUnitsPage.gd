class_name OperationalUnitsPage
extends Control

## Live carrier-console board shared by the Active Flights and Active Platoons
## pages.  The operations managers remain authoritative; this page only
## translates their current mission and member state into compact UI labels.

enum UnitKind {
	FLIGHTS,
	PLATOONS,
}

const HEADLINE_FONT: FontFile = preload("res://UI/Fonts/ArchivoNarrow-Variable.ttf")
const DATA_FONT: FontFile = preload("res://UI/Fonts/JetBrainsMono-Variable.ttf")
const TECHNICAL_INDEX_CATALOG: Script = preload("res://UI/TechnicalIndexCatalog.gd")

const TEXT_COLOR := Color("e5e2e1")
const STATUS_COLOR := Color("c4c7c7")
const BORDER_COLOR := Color("434747")
const CYAN_COLOR := Color("76c7c7")
const AMBER_COLOR := Color("ffb000")
const RED_COLOR := Color("e26d5a")
const DIM_COLOR := Color("7d8282")
const PAGE_BG := Color("0e0e0e")
const PANEL_BG := Color("141313")
const PANEL_ALT_BG := Color("1c1b1b")
const REFRESH_INTERVAL_S := 0.35
const AIR_STATE_NAMES: Array[String] = [
	"IDLE",
	"LAUNCHING",
	"CLIMBING",
	"TRANSIT",
	"SEARCH",
	"ATTACK_POSITIONING",
	"ATTACK_INBOUND",
	"ATTACK_DIVE",
	"ATTACK_BREAK_OFF",
	"DOGFIGHT",
	"ENGAGE",
	"RTB",
	"RECOVERY_MARSHAL",
	"RECOVERY_HOLD",
	"RECOVERY_APPROACH",
	"APPROACH",
	"LANDING",
	"MISSED_APPROACH",
	"PRE_LANDING",
]

var unit_kind: UnitKind = UnitKind.FLIGHTS

var _title_label: Label
var _subtitle_label: Label
var _summary_label: Label
var _unit_list: VBoxContainer
var _detail_title: Label
var _detail_status: Label
var _detail_meta: Label
var _member_list: VBoxContainer
var _empty_label: Label
var _filter_buttons: Dictionary = {}
var _flight_rows: VBoxContainer
var _portrait_texture_cache: Dictionary = {}

var _selected_unit: String = ""
var _filter_mode: String = "ALL"
var _refresh_timer_s: float = 0.0
var _last_signature: String = ""
var _tracked_member_records: Dictionary = {}
var _destroyed_members: Dictionary = {}
var _last_live_counts: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_refresh(true)


func _process(delta: float) -> void:
	_refresh_timer_s -= delta
	if _refresh_timer_s <= 0.0:
		# Keep a low-rate watch while the page is hidden so a destroyed member is
		# still present when the player next opens the operations board.
		_refresh_timer_s = REFRESH_INTERVAL_S if visible else 1.0
		_refresh(false)


func set_console_visible(value: bool) -> void:
	visible = value
	set_process(true)
	if value:
		_refresh_timer_s = REFRESH_INTERVAL_S
		_refresh(true)


func get_debug_snapshot() -> Dictionary:
	var units := _collect_units()
	return {
		"kind": "flights" if unit_kind == UnitKind.FLIGHTS else "platoons",
		"layout": "all_flights" if unit_kind == UnitKind.FLIGHTS else "master_detail",
		"unit_count": units.size(),
		"selected_unit": _selected_unit,
		"units": units,
	}


static func map_air_activity(state_name: String, evading: bool = false, destroyed: bool = false) -> String:
	if destroyed:
		return "DESTROYED"
	if evading or state_name == "ATTACK_BREAK_OFF":
		return "EVADING"
	match state_name:
		"DOGFIGHT", "ENGAGE", "ATTACK_POSITIONING", "ATTACK_INBOUND", "ATTACK_DIVE":
			return "ATTACKING"
		"RTB":
			return "RETURNING"
		"RECOVERY_MARSHAL", "RECOVERY_HOLD", "RECOVERY_APPROACH", "PRE_LANDING", "APPROACH", "LANDING", "MISSED_APPROACH":
			return "RECOVERING"
		"LAUNCHING":
			return "LAUNCHING"
		"CLIMBING", "TRANSIT":
			return "EN ROUTE"
		"SEARCH":
			return "PATROLLING"
		"IDLE", "INACTIVE":
			return "READY"
		_:
			return "ACTIVE"


static func map_ground_activity(
	objective_name: String,
	has_target: bool = false,
	moving: bool = false,
	deploying: bool = false,
	returning: bool = false,
	destroyed: bool = false
) -> String:
	if destroyed:
		return "DESTROYED"
	if returning or objective_name == "RETURN_TO_BASE":
		return "RETURNING"
	if deploying:
		return "DEPLOYING"
	if has_target:
		return "ATTACKING"
	if moving:
		return "MOVING"
	match objective_name:
		"PROTECT_NODE", "PROTECT_POSITION":
			return "GUARDING"
		"ESCORT_CARRIER":
			return "ESCORTING"
		"ATTACK_NODE", "ATTACK_POSITION", "PURSUE_ENEMIES":
			return "ADVANCING"
		_:
			return "HOLDING"


func _build_ui() -> void:
	if unit_kind == UnitKind.FLIGHTS:
		_build_flights_ui()
		return
	_build_platoons_ui()


func _build_flights_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = PAGE_BG
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var page_column := VBoxContainer.new()
	page_column.add_theme_constant_override("separation", 9)
	margin.add_child(page_column)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 58.0
	page_column.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 0)
	header.add_child(heading)
	_title_label = _make_label("ACTIVE FLIGHTS", 28, TEXT_COLOR)
	heading.add_child(_title_label)
	_subtitle_label = _make_label("ONE FLIGHT PER ROW // ONE LIVE CARD PER AIRCRAFT", 12, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	heading.add_child(_subtitle_label)
	_summary_label = _make_label("", 13, STATUS_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	_summary_label.custom_minimum_size.x = 380.0
	_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_summary_label)

	var rule := ColorRect.new()
	rule.color = BORDER_COLOR
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_column.add_child(rule)

	var guide := HBoxContainer.new()
	guide.custom_minimum_size.y = 24.0
	page_column.add_child(guide)
	var guide_left := _make_label("FLIGHT / MISSION", 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	guide_left.custom_minimum_size.x = 220.0
	guide.add_child(guide_left)
	var guide_cards := _make_label("AIRCRAFT TYPE  //  LOADOUT  //  PILOT  //  STATUS", 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	guide_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide.add_child(guide_cards)
	var live_label := _make_label("● LIVE", 10, CYAN_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	guide.add_child(live_label)

	var flight_scroll := ScrollContainer.new()
	flight_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	flight_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	flight_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page_column.add_child(flight_scroll)
	_flight_rows = VBoxContainer.new()
	_flight_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flight_rows.add_theme_constant_override("separation", 8)
	flight_scroll.add_child(_flight_rows)

	var footer := _make_label("AIRCRAFT CARDS UPDATE FROM LIVE PILOT, WEAPON, DAMAGE, AND FLIGHT DATA", 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	page_column.add_child(footer)


func _build_platoons_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = PAGE_BG
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var page_column := VBoxContainer.new()
	page_column.add_theme_constant_override("separation", 10)
	margin.add_child(page_column)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 66.0
	page_column.add_child(header)

	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 0)
	header.add_child(heading)
	_title_label = _make_label("", 28, TEXT_COLOR)
	heading.add_child(_title_label)
	_subtitle_label = _make_label("", 12, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	heading.add_child(_subtitle_label)
	_summary_label = _make_label("", 13, STATUS_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	_summary_label.custom_minimum_size.x = 330.0
	_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_summary_label)

	var rule := ColorRect.new()
	rule.color = BORDER_COLOR
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_column.add_child(rule)

	var filters := HBoxContainer.new()
	filters.custom_minimum_size.y = 34.0
	filters.add_theme_constant_override("separation", 6)
	page_column.add_child(filters)
	var filter_caption := _make_label("DISPLAY", 11, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	filter_caption.custom_minimum_size = Vector2(70.0, 30.0)
	filter_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	filters.add_child(filter_caption)
	for filter_name in ["ALL", "ACTIVE", "READY"]:
		var button := _make_filter_button(filter_name)
		button.pressed.connect(_on_filter_pressed.bind(filter_name))
		filters.add_child(button)
		_filter_buttons[filter_name] = button
	var filter_spacer := Control.new()
	filter_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(filter_spacer)
	var live_label := _make_label("● LIVE OPERATIONS DATA", 11, CYAN_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	live_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	filters.add_child(live_label)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 380
	split.add_theme_constant_override("separation", 12)
	page_column.add_child(split)

	var roster_panel := Panel.new()
	roster_panel.custom_minimum_size.x = 330.0
	roster_panel.add_theme_stylebox_override("panel", _make_style(PANEL_BG, BORDER_COLOR, 1, 12.0))
	split.add_child(roster_panel)
	var roster_margin := _make_margin(14)
	roster_panel.add_child(roster_margin)
	var roster_column := VBoxContainer.new()
	roster_column.add_theme_constant_override("separation", 8)
	roster_margin.add_child(roster_column)
	var roster_title := _make_label("FLIGHT GROUPS" if unit_kind == UnitKind.FLIGHTS else "GROUND PLATOONS", 14, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	roster_column.add_child(roster_title)
	var roster_scroll := ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_column.add_child(roster_scroll)
	_unit_list = VBoxContainer.new()
	_unit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_list.add_theme_constant_override("separation", 6)
	roster_scroll.add_child(_unit_list)

	var details_panel := Panel.new()
	details_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_panel.add_theme_stylebox_override("panel", _make_style(PANEL_ALT_BG, BORDER_COLOR, 1, 16.0))
	split.add_child(details_panel)
	var details_margin := _make_margin(18)
	details_panel.add_child(details_margin)
	var details_column := VBoxContainer.new()
	details_column.add_theme_constant_override("separation", 8)
	details_margin.add_child(details_column)
	var details_header := HBoxContainer.new()
	details_column.add_child(details_header)
	_detail_title = _make_label("SELECT A UNIT", 24, TEXT_COLOR)
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_header.add_child(_detail_title)
	_detail_status = _make_label("READY", 13, STATUS_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	_detail_status.custom_minimum_size.x = 150.0
	_detail_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	details_header.add_child(_detail_status)
	_detail_meta = _make_label("", 12, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	details_column.add_child(_detail_meta)
	var details_rule := ColorRect.new()
	details_rule.color = BORDER_COLOR
	details_rule.custom_minimum_size.y = 1.0
	details_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details_column.add_child(details_rule)
	var member_caption := _make_label("AIRCRAFT / PILOTS" if unit_kind == UnitKind.FLIGHTS else "VEHICLES", 11, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	details_column.add_child(member_caption)
	var member_scroll := ScrollContainer.new()
	member_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	member_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_column.add_child(member_scroll)
	_member_list = VBoxContainer.new()
	_member_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_member_list.add_theme_constant_override("separation", 7)
	member_scroll.add_child(_member_list)
	_empty_label = _make_label("", 15, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.custom_minimum_size.y = 120.0
	_member_list.add_child(_empty_label)

	var footer_text := "STATUS FOLLOWS EACH AIRCRAFT'S PILOT STATE // ASSIGNMENT CONTROLS CAN BE ADDED NEXT" if unit_kind == UnitKind.FLIGHTS else "STATUS FOLLOWS EACH VEHICLE'S OBJECTIVE, MOTION, AND COMBAT STATE // FORMATION CONTROLS CAN BE ADDED NEXT"
	var footer := _make_label(footer_text, 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	page_column.add_child(footer)

	_title_label.text = "ACTIVE FLIGHTS" if unit_kind == UnitKind.FLIGHTS else "ACTIVE PLATOONS"
	_subtitle_label.text = "AIRCRAFT, PILOTS, MISSION, AND CURRENT ACTIVITY" if unit_kind == UnitKind.FLIGHTS else "GROUND VEHICLES, OBJECTIVES, AND CURRENT ACTIVITY"
	_refresh_filter_styles()


func _refresh(force: bool) -> void:
	var units := _collect_units()
	var signature := _units_ui_signature(units)
	if unit_kind == UnitKind.PLATOONS:
		signature += "|" + _filter_mode + "|" + _selected_unit
	if not force and signature == _last_signature:
		return
	_last_signature = signature
	if unit_kind == UnitKind.FLIGHTS:
		_rebuild_flight_rows(units)
		_refresh_summary(units)
		return
	var visible_units: Array[Dictionary] = []
	for unit: Dictionary in units:
		if _unit_matches_filter(unit):
			visible_units.append(unit)
	if _selected_unit == "" or not _contains_unit(visible_units, _selected_unit):
		_selected_unit = str(visible_units[0].get("name", "")) if not visible_units.is_empty() else ""
	_rebuild_unit_list(visible_units)
	var selected := _find_unit(units, _selected_unit)
	_rebuild_details(selected)
	_refresh_summary(units)


func _units_ui_signature(units: Array[Dictionary]) -> String:
	# Deliberately omit positions and route points. Those change continuously but
	# are not rendered here; rebuilding the lists for them would disturb scrolling.
	var display_data: Array[Dictionary] = []
	for unit: Dictionary in units:
		display_data.append({
			"name": unit.get("name", ""),
			"mission": unit.get("mission", ""),
			"objective": unit.get("objective", ""),
			"role": unit.get("role", ""),
			"strength": unit.get("strength", 0),
			"queued": unit.get("queued", false),
			"deployed": unit.get("deployed", false),
			"activity": unit.get("activity", ""),
			"members": unit.get("members", []),
		})
	return var_to_str(display_data)


func _collect_units() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if unit_kind == UnitKind.FLIGHTS:
		var air_ops := get_node_or_null("/root/AirOpsManager")
		if air_ops == null:
			return result
		var flight_names_variant: Variant = air_ops.call("get_flight_names")
		var flight_names: Array = flight_names_variant if flight_names_variant is Array else []
		for unit_name_variant in flight_names:
			var unit_name := str(unit_name_variant)
			var summary: Dictionary = air_ops.call("get_flight_status", unit_name)
			var members: Array[Dictionary] = []
			var flight: Variant = air_ops.call("get_flight", unit_name)
			var live_member_ids: Dictionary = {}
			if flight != null:
				var member_nodes: Array = flight.call("get_members")
				_begin_live_roster(unit_name, member_nodes.size())
				for index in range(member_nodes.size()):
					var member: Node3D = member_nodes[index]
					var member_summary := _aircraft_member_summary(member, index)
					_track_member(member, unit_name, member_summary)
					live_member_ids[member.get_instance_id()] = true
					members.append(member_summary)
			_append_destroyed_members(unit_name, live_member_ids, members)
			summary["members"] = members
			summary["activity"] = _flight_activity(summary, members)
			result.append(summary)
	else:
		var ground_ops := get_node_or_null("/root/GroundOpsManager")
		if ground_ops == null:
			return result
		var platoon_names_variant: Variant = ground_ops.call("get_platoon_names")
		var platoon_names: Array = platoon_names_variant if platoon_names_variant is Array else []
		for unit_name_variant in platoon_names:
			var unit_name := str(unit_name_variant)
			var summary: Dictionary = ground_ops.call("get_platoon_status", unit_name)
			var members: Array[Dictionary] = []
			var platoon: Variant = ground_ops.call("get_platoon", unit_name)
			var live_member_ids: Dictionary = {}
			if platoon != null:
				var member_nodes: Array = platoon.call("get_members")
				_begin_live_roster(unit_name, member_nodes.size())
				for index in range(member_nodes.size()):
					var member: Node3D = member_nodes[index]
					var member_summary := _vehicle_member_summary(member, index, str(summary.get("objective", "NONE")))
					_track_member(member, unit_name, member_summary)
					live_member_ids[member.get_instance_id()] = true
					members.append(member_summary)
			_append_destroyed_members(unit_name, live_member_ids, members)
			summary["members"] = members
			summary["activity"] = _platoon_activity(summary, members)
			result.append(summary)
	return result


func _aircraft_member_summary(member: Node3D, index: int) -> Dictionary:
	var health := _health_summary(member)
	var pilot := member.find_child("AIPilot", true, false) if member and is_instance_valid(member) else null
	var state_name := "INACTIVE"
	var evading := false
	if pilot != null:
		var state_value: Variant = pilot.get("current_state")
		if typeof(state_value) == TYPE_INT and int(state_value) >= 0 and int(state_value) < AIR_STATE_NAMES.size():
			state_name = AIR_STATE_NAMES[int(state_value)]
		var evade_value: Variant = pilot.get("_defensive_evade_timer_s")
		evading = typeof(evade_value) in [TYPE_FLOAT, TYPE_INT] and float(evade_value) > 0.0
	var activity := map_air_activity(state_name, evading, bool(health.get("destroyed", false)))
	return {
		"source_id": member.get_instance_id(),
		"name": _aircraft_display_name(member, index),
		"pilot": _aircraft_display_name(member, index),
		"portrait_path": _aircraft_portrait_path(member),
		"type": _member_type_name(member, "AIRCRAFT"),
		"loadout": _aircraft_loadout_name(member),
		"slot": _flight_slot_name(index),
		"activity": activity,
		"health_percent": int(health.get("percent", 100)),
		"state": state_name,
	}


func _vehicle_member_summary(member: Node3D, index: int, objective_name: String) -> Dictionary:
	var health := _health_summary(member)
	var has_target := false
	if member.has_method("_has_combat_target"):
		has_target = bool(member.call("_has_combat_target"))
	elif "current_target" in member:
		var target: Variant = member.get("current_target")
		has_target = target != null and is_instance_valid(target)
	var moving := _member_speed_mps(member) > 0.75
	var deploying := bool(member.get("deploy_mode")) if "deploy_mode" in member else false
	var returning := bool(member.get("retrieve_mode")) if "retrieve_mode" in member else false
	var activity := map_ground_activity(
		objective_name,
		has_target,
		moving,
		deploying,
		returning,
		bool(health.get("destroyed", false))
	)
	return {
		"source_id": member.get_instance_id(),
		"name": "VEHICLE %02d" % (index + 1),
		"type": _member_type_name(member, "GROUND VEHICLE"),
		"slot": "UNIT %02d" % (index + 1),
		"activity": activity,
		"health_percent": int(health.get("percent", 100)),
	}


func _begin_live_roster(unit_name: String, live_count: int) -> void:
	var previous_live_count := int(_last_live_counts.get(unit_name, 0))
	if live_count > 0 and previous_live_count <= 0:
		# A new set of members after an empty group marks a new sortie/deployment.
		# Old loss rows no longer belong to the active lifecycle.
		_destroyed_members.erase(unit_name)
	_last_live_counts[unit_name] = live_count


func _track_member(member: Node3D, unit_name: String, member_summary: Dictionary) -> void:
	if member == null or not is_instance_valid(member):
		return
	var member_id := member.get_instance_id()
	_tracked_member_records[member_id] = {
		"unit_name": unit_name,
		"summary": member_summary.duplicate(true),
	}
	if not member.has_signal("destroyed"):
		return
	if unit_kind == UnitKind.FLIGHTS:
		var callback := Callable(self, "_on_tracked_aircraft_destroyed").bind(member_id, unit_name)
		if not member.is_connected("destroyed", callback):
			member.connect("destroyed", callback)
	else:
		var callback := Callable(self, "_on_tracked_vehicle_destroyed").bind(member_id, unit_name)
		if not member.is_connected("destroyed", callback):
			member.connect("destroyed", callback)


func _on_tracked_aircraft_destroyed(member_id: int, unit_name: String) -> void:
	_record_destroyed_member(member_id, unit_name)


func _on_tracked_vehicle_destroyed(_vehicle: Variant, member_id: int, unit_name: String) -> void:
	_record_destroyed_member(member_id, unit_name)


func _record_destroyed_member(member_id: int, unit_name: String) -> void:
	var tracked: Dictionary = _tracked_member_records.get(member_id, {})
	var member_summary: Dictionary = tracked.get("summary", {}).duplicate(true)
	if member_summary.is_empty():
		return
	member_summary["activity"] = "DESTROYED"
	member_summary["health_percent"] = 0
	member_summary["source_id"] = member_id
	var records_variant: Variant = _destroyed_members.get(unit_name, [])
	var records: Array = records_variant if records_variant is Array else []
	for existing_variant in records:
		var existing: Dictionary = existing_variant
		if int(existing.get("source_id", -1)) == member_id:
			return
	records.append(member_summary)
	_destroyed_members[unit_name] = records
	_last_signature = ""


func _append_destroyed_members(unit_name: String, live_member_ids: Dictionary, members: Array[Dictionary]) -> void:
	var records_variant: Variant = _destroyed_members.get(unit_name, [])
	if not records_variant is Array:
		return
	for record_variant in records_variant:
		var record: Dictionary = record_variant
		if live_member_ids.has(int(record.get("source_id", -1))):
			continue
		members.append(record.duplicate(true))


func _flight_activity(summary: Dictionary, members: Array[Dictionary]) -> String:
	if bool(summary.get("is_scrambling", false)):
		return "LAUNCHING"
	if members.is_empty():
		return "READY"
	if int(summary.get("strength", 0)) <= 0 and _members_have_activity(members, "DESTROYED"):
		return "DESTROYED"
	for priority in ["EVADING", "ATTACKING", "RECOVERING", "RETURNING", "LAUNCHING", "PATROLLING", "EN ROUTE"]:
		if _members_have_activity(members, priority):
			return priority
	if _members_have_activity(members, "DESTROYED"):
		return "DEGRADED"
	return "ACTIVE"


func _platoon_activity(summary: Dictionary, members: Array[Dictionary]) -> String:
	if bool(summary.get("queued", false)):
		return "DEPLOYING"
	if members.is_empty():
		return "READY"
	if int(summary.get("strength", 0)) <= 0 and _members_have_activity(members, "DESTROYED"):
		return "DESTROYED"
	for priority in ["ATTACKING", "RETURNING", "DEPLOYING", "MOVING", "ADVANCING", "GUARDING", "ESCORTING"]:
		if _members_have_activity(members, priority):
			return priority
	if _members_have_activity(members, "DESTROYED"):
		return "DEGRADED"
	return "HOLDING"


func _members_have_activity(members: Array[Dictionary], activity: String) -> bool:
	for member: Dictionary in members:
		if str(member.get("activity", "")) == activity:
			return true
	return false


func _rebuild_flight_rows(units: Array[Dictionary]) -> void:
	_clear_children(_flight_rows)
	if units.is_empty():
		var empty := _make_label("NO FLIGHT DATA AVAILABLE", 14, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
		empty.custom_minimum_size.y = 140.0
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_flight_rows.add_child(empty)
		return
	for unit: Dictionary in units:
		_add_flight_row(unit)


func _add_flight_row(unit: Dictionary) -> void:
	var activity := str(unit.get("activity", "READY"))
	var row_panel := Panel.new()
	row_panel.custom_minimum_size.y = 166.0
	row_panel.add_theme_stylebox_override("panel", _make_style(PANEL_BG, _status_color(activity), 1, 12.0))
	_flight_rows.add_child(row_panel)
	var row_margin := _make_margin(12)
	row_panel.add_child(row_margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row_margin.add_child(row)

	var flight_summary := VBoxContainer.new()
	flight_summary.custom_minimum_size.x = 198.0
	flight_summary.add_theme_constant_override("separation", 2)
	row.add_child(flight_summary)
	var flight_name := _make_label(str(unit.get("name", "FLIGHT")).to_upper(), 23, TEXT_COLOR)
	flight_summary.add_child(flight_name)
	var mission := str(unit.get("mission", "NONE")).replace("_", " ")
	var role := str(unit.get("role", "UNASSIGNED")).replace("_", " ")
	var mission_label := _make_label("MISSION  %s" % mission, 11, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	flight_summary.add_child(mission_label)
	var role_label := _make_label("ROLE     %s" % role, 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	flight_summary.add_child(role_label)
	var summary_spacer := Control.new()
	summary_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	flight_summary.add_child(summary_spacer)
	var flight_status := _make_label("● %s" % activity, 12, _status_color(activity), HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	flight_summary.add_child(flight_status)
	var strength := int(unit.get("strength", 0))
	var strength_label := _make_label("%d / 4 AIRCRAFT" % strength, 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	flight_summary.add_child(strength_label)

	var divider := ColorRect.new()
	divider.color = BORDER_COLOR
	divider.custom_minimum_size.x = 1.0
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(divider)

	var cards := HBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 8)
	row.add_child(cards)
	var members_variant: Variant = unit.get("members", [])
	var members: Array = members_variant if members_variant is Array else []
	if members.is_empty():
		var empty_card := Panel.new()
		empty_card.custom_minimum_size = Vector2(290.0, 138.0)
		empty_card.add_theme_stylebox_override("panel", _make_style(PANEL_ALT_BG, BORDER_COLOR, 1, 12.0))
		cards.add_child(empty_card)
		var empty_label := _make_label("NO AIRCRAFT ASSIGNED\nREADY FOR FORMATION", 12, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
		empty_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_card.add_child(empty_label)
		return
	for member_variant in members:
		_add_aircraft_card(cards, member_variant as Dictionary)


func _add_aircraft_card(cards: HBoxContainer, member: Dictionary) -> void:
	var activity := str(member.get("activity", "ACTIVE"))
	var card := Panel.new()
	card.custom_minimum_size = Vector2(285.0, 138.0)
	card.add_theme_stylebox_override("panel", _make_style(PANEL_ALT_BG, _status_color(activity), 1, 11.0))
	cards.add_child(card)
	var card_margin := _make_margin(10)
	card.add_child(card_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	card_margin.add_child(column)

	var type_label := _make_label(str(member.get("type", "AIRCRAFT")).to_upper(), 14, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	type_label.clip_text = true
	column.add_child(type_label)
	var identity_row := HBoxContainer.new()
	identity_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	identity_row.add_theme_constant_override("separation", 9)
	column.add_child(identity_row)
	_add_aircraft_portrait(identity_row, str(member.get("portrait_path", "")))
	var facts := VBoxContainer.new()
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.add_theme_constant_override("separation", 1)
	identity_row.add_child(facts)
	var pilot_caption := _make_label("PILOT", 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	facts.add_child(pilot_caption)
	var pilot_label := _make_label(str(member.get("pilot", "UNASSIGNED")).to_upper(), 11, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	pilot_label.clip_text = true
	pilot_label.tooltip_text = str(member.get("pilot", "UNASSIGNED"))
	facts.add_child(pilot_label)
	var loadout_caption := _make_label("LOADOUT", 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	facts.add_child(loadout_caption)
	var loadout_label := _make_label(str(member.get("loadout", "UNARMED")).to_upper(), 10, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	loadout_label.clip_text = true
	loadout_label.tooltip_text = str(member.get("loadout", "UNARMED"))
	facts.add_child(loadout_label)

	var status_row := HBoxContainer.new()
	column.add_child(status_row)
	var status_label := _make_label("● %s" % activity, 10, _status_color(activity), HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(status_label)
	var health := int(member.get("health_percent", 100))
	var condition_label := _make_label("COND %d%%" % health, 10, STATUS_COLOR if health >= 50 else AMBER_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	status_row.add_child(condition_label)


func _add_aircraft_portrait(parent: HBoxContainer, portrait_path: String) -> void:
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(56.0, 56.0)
	frame.add_theme_stylebox_override("panel", _make_style(PAGE_BG, CYAN_COLOR, 1))
	parent.add_child(frame)
	var texture := _get_portrait_texture(portrait_path)
	if texture != null:
		var portrait := TextureRect.new()
		portrait.position = Vector2(2.0, 2.0)
		portrait.size = Vector2(52.0, 52.0)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.texture = texture
		frame.add_child(portrait)
		return
	var placeholder := _make_label("—", 18, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
	placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame.add_child(placeholder)


func _get_portrait_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if _portrait_texture_cache.has(path):
		return _portrait_texture_cache[path] as Texture2D
	var texture := load(path) as Texture2D
	if texture != null:
		_portrait_texture_cache[path] = texture
	return texture


func _rebuild_unit_list(units: Array[Dictionary]) -> void:
	_clear_children(_unit_list)
	if units.is_empty():
		var noun := "FLIGHTS" if unit_kind == UnitKind.FLIGHTS else "PLATOONS"
		var empty := _make_label("NO %s MATCH THIS FILTER" % noun, 12, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
		empty.custom_minimum_size.y = 90.0
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_unit_list.add_child(empty)
		return
	for unit: Dictionary in units:
		var unit_name := str(unit.get("name", "UNIT"))
		var activity := str(unit.get("activity", "READY"))
		var strength := int(unit.get("strength", 0))
		var descriptor := str(unit.get("mission", "NONE")) if unit_kind == UnitKind.FLIGHTS else str(unit.get("objective", "NONE"))
		var noun := "AIRCRAFT" if unit_kind == UnitKind.FLIGHTS else "VEHICLES"
		var button := Button.new()
		button.text = "%s\n%s // %d %s // %s" % [unit_name.to_upper(), descriptor.replace("_", " "), strength, noun, activity]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 66.0
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", DATA_FONT)
		button.add_theme_font_size_override("font_size", 12)
		button.add_theme_color_override("font_color", TEXT_COLOR if unit_name == _selected_unit else STATUS_COLOR)
		button.add_theme_color_override("font_hover_color", TEXT_COLOR)
		var accent := _status_color(activity)
		button.add_theme_stylebox_override("normal", _make_style(Color("202525") if unit_name == _selected_unit else PANEL_ALT_BG, accent if unit_name == _selected_unit else BORDER_COLOR, 1, 9.0))
		button.add_theme_stylebox_override("hover", _make_style(Color("262929"), accent, 1, 9.0))
		button.add_theme_stylebox_override("pressed", _make_style(Color("202525"), accent, 2, 9.0))
		button.pressed.connect(_on_unit_pressed.bind(unit_name))
		_unit_list.add_child(button)


func _rebuild_details(unit: Dictionary) -> void:
	_clear_children(_member_list)
	if unit.is_empty():
		_detail_title.text = "NO UNIT SELECTED"
		_detail_status.text = "—"
		_detail_meta.text = "CHANGE THE DISPLAY FILTER TO SEE OTHER GROUPS"
		var no_selection := _make_label("NO UNIT MATCHES THE CURRENT FILTER", 14, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
		no_selection.custom_minimum_size.y = 120.0
		no_selection.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_member_list.add_child(no_selection)
		return
	var activity := str(unit.get("activity", "READY"))
	_detail_title.text = str(unit.get("name", "UNIT")).to_upper()
	_detail_status.text = "● %s" % activity
	_detail_status.add_theme_color_override("font_color", _status_color(activity))
	var strength := int(unit.get("strength", 0))
	if unit_kind == UnitKind.FLIGHTS:
		_detail_meta.text = "MISSION  %s     ROLE  %s     STRENGTH  %d / 4" % [
			str(unit.get("mission", "NONE")).replace("_", " "),
			str(unit.get("role", "UNASSIGNED")).replace("_", " "),
			strength,
		]
	else:
		var deployment := "QUEUED" if bool(unit.get("queued", false)) else ("DEPLOYED" if bool(unit.get("deployed", false)) else "IN BAY")
		_detail_meta.text = "OBJECTIVE  %s     LOCATION  %s     STRENGTH  %d" % [
			str(unit.get("objective", "NONE")).replace("_", " "),
			deployment,
			strength,
		]
	var members_variant: Variant = unit.get("members", [])
	var members: Array = members_variant if members_variant is Array else []
	if members.is_empty():
		var noun := "AIRCRAFT ASSIGNED" if unit_kind == UnitKind.FLIGHTS else "VEHICLES DEPLOYED"
		var empty := _make_label("READY / NO %s" % noun, 14, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
		empty.custom_minimum_size.y = 130.0
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_member_list.add_child(empty)
		return
	for member_variant in members:
		_add_member_row(member_variant as Dictionary)


func _add_member_row(member: Dictionary) -> void:
	var panel := Panel.new()
	panel.custom_minimum_size.y = 72.0
	panel.add_theme_stylebox_override("panel", _make_style(PANEL_BG, BORDER_COLOR, 1, 11.0))
	_member_list.add_child(panel)
	var margin := _make_margin(11)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 0)
	row.add_child(identity)
	var name_label := _make_label(str(member.get("name", "UNIT")).to_upper(), 15, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	identity.add_child(name_label)
	var type_label := _make_label("%s // %s" % [str(member.get("slot", "")), str(member.get("type", ""))], 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	identity.add_child(type_label)
	var health := int(member.get("health_percent", 100))
	var health_label := _make_label("COND %3d%%" % health, 11, STATUS_COLOR if health >= 50 else AMBER_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	health_label.custom_minimum_size.x = 90.0
	health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(health_label)
	var activity := str(member.get("activity", "ACTIVE"))
	var status_label := _make_label(activity, 11, _status_color(activity), HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
	status_label.custom_minimum_size = Vector2(128.0, 30.0)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_stylebox_override("normal", _make_style(Color(_status_color(activity), 0.08), _status_color(activity), 1, 8.0))
	row.add_child(status_label)


func _refresh_summary(units: Array[Dictionary]) -> void:
	var active_count := 0
	var ready_count := 0
	var member_count := 0
	for unit: Dictionary in units:
		var activity := str(unit.get("activity", "READY"))
		if activity == "READY":
			ready_count += 1
		else:
			active_count += 1
		member_count += int(unit.get("strength", 0))
	var noun := "AIRCRAFT" if unit_kind == UnitKind.FLIGHTS else "VEHICLES"
	_summary_label.text = "%02d ACTIVE  //  %02d READY  //  %02d %s" % [active_count, ready_count, member_count, noun]


func _health_summary(member: Node) -> Dictionary:
	var current := 1.0
	var maximum := 1.0
	if "current_health" in member:
		current = float(member.get("current_health"))
	if "max_health" in member:
		maximum = maxf(float(member.get("max_health")), 0.001)
	var destroyed := current <= 0.0
	if "is_dying" in member:
		destroyed = destroyed or bool(member.get("is_dying"))
	if "_has_exploded" in member:
		destroyed = destroyed or bool(member.get("_has_exploded"))
	return {
		"percent": clampi(int(round(current / maximum * 100.0)), 0, 100),
		"destroyed": destroyed,
	}


func _member_speed_mps(member: Node3D) -> float:
	for property_name in ["velocity", "linear_velocity"]:
		if property_name in member:
			var value: Variant = member.get(property_name)
			if value is Vector3:
				return Vector2(value.x, value.z).length()
	return 0.0


func _aircraft_display_name(member: Node3D, index: int) -> String:
	if member.has_meta("pilot_display_name"):
		return str(member.get_meta("pilot_display_name"))
	if member.has_meta("pilot_callsign"):
		return str(member.get_meta("pilot_callsign"))
	return "AIRCRAFT %02d" % (index + 1)


func _aircraft_portrait_path(member: Node3D) -> String:
	if not member.has_meta("pilot_identity"):
		return ""
	var identity_variant: Variant = member.get_meta("pilot_identity")
	if identity_variant is Dictionary:
		return str((identity_variant as Dictionary).get("portrait_path", ""))
	return ""


func _aircraft_loadout_name(member: Node3D) -> String:
	var weapon_counts: Dictionary = {}
	var ordered_names: Array[String] = []
	for node in _all_descendants(member):
		if not ("weapon_instance" in node) and not ("mounted_weapon" in node):
			continue
		var weapon_name := ""
		var weapon: Variant = node.get("weapon_instance") if "weapon_instance" in node else null
		if weapon != null and is_instance_valid(weapon):
			weapon_name = _weapon_display_name(weapon)
		if weapon_name.is_empty() and "mounted_weapon" in node:
			var mounted: Variant = node.get("mounted_weapon")
			if mounted is PackedScene:
				weapon_name = _weapon_name_from_path((mounted as PackedScene).resource_path)
		if weapon_name.is_empty():
			continue
		if not weapon_counts.has(weapon_name):
			weapon_counts[weapon_name] = 0
			ordered_names.append(weapon_name)
		weapon_counts[weapon_name] = int(weapon_counts[weapon_name]) + 1
	if ordered_names.is_empty():
		var profile := str(member.get_meta("resolved_ai_loadout_profile", "")).strip_edges()
		return profile.replace("_", " ").to_upper() if not profile.is_empty() else "UNARMED"
	var parts: PackedStringArray = []
	for weapon_name in ordered_names:
		var count := int(weapon_counts.get(weapon_name, 1))
		parts.append(("%dX " % count if count > 1 else "") + weapon_name)
	return " + ".join(parts)


func _weapon_display_name(weapon: Object) -> String:
	var result := ""
	if "weapon_name" in weapon:
		result = str(weapon.get("weapon_name")).strip_edges()
	if result.is_empty() or result == "Generic Weapon":
		var profile: Variant = weapon.get("gun_profile") if "gun_profile" in weapon else null
		if profile != null and profile.get("weapon_name") != null:
			result = str(profile.get("weapon_name")).strip_edges()
	if result.is_empty() or result == "Generic Weapon":
		var source_path := str(weapon.get("scene_file_path")) if "scene_file_path" in weapon else ""
		result = _weapon_name_from_path(source_path)
	return result.replace("_", " ").to_upper()


func _weapon_name_from_path(path: String) -> String:
	if path.is_empty():
		return ""
	var result := path.get_file().get_basename().replace("_hardpoint", "").replace("_", " ")
	return result.to_upper()


func _all_descendants(root_node: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = []
	for child in root_node.get_children():
		pending.append(child)
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result


func _member_type_name(member: Node, fallback: String) -> String:
	if member == null or not is_instance_valid(member):
		return fallback
	var source_path := member.scene_file_path
	if source_path != "":
		var catalog_name := _catalog_display_name(source_path)
		if not catalog_name.is_empty():
			return catalog_name.to_upper()
		return source_path.get_file().get_basename().replace("_", " ").to_upper()
	var node_name := str(member.name).replace("_", " ").to_upper()
	return node_name if node_name != "" else fallback


func _catalog_display_name(scene_path: String) -> String:
	for category_variant in TECHNICAL_INDEX_CATALOG.categories():
		var category := str(category_variant)
		for entry_variant in TECHNICAL_INDEX_CATALOG.entries_for(category):
			var entry: Dictionary = entry_variant
			if str(entry.get("scene", "")) == scene_path:
				return str(entry.get("name", ""))
	return ""


func _flight_slot_name(index: int) -> String:
	match index:
		0:
			return "LEAD"
		1:
			return "TWO"
		2:
			return "THREE"
		3:
			return "FOUR"
		_:
			return "SLOT %02d" % (index + 1)


func _unit_matches_filter(unit: Dictionary) -> bool:
	if _filter_mode == "ALL":
		return true
	var ready := str(unit.get("activity", "READY")) == "READY"
	return ready if _filter_mode == "READY" else not ready


func _contains_unit(units: Array[Dictionary], unit_name: String) -> bool:
	return not _find_unit(units, unit_name).is_empty()


func _find_unit(units: Array[Dictionary], unit_name: String) -> Dictionary:
	for unit: Dictionary in units:
		if str(unit.get("name", "")) == unit_name:
			return unit
	return {}


func _on_unit_pressed(unit_name: String) -> void:
	_selected_unit = unit_name
	_last_signature = ""
	_refresh(true)


func _on_filter_pressed(filter_name: String) -> void:
	_filter_mode = filter_name
	_last_signature = ""
	_refresh_filter_styles()
	_refresh(true)


func _refresh_filter_styles() -> void:
	for filter_name: String in _filter_buttons:
		var button := _filter_buttons[filter_name] as Button
		var active := filter_name == _filter_mode
		button.add_theme_stylebox_override("normal", _make_style(Color("202525") if active else PANEL_BG, CYAN_COLOR if active else BORDER_COLOR, 1, 7.0))
		button.add_theme_color_override("font_color", TEXT_COLOR if active else STATUS_COLOR)


func _make_filter_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(84.0, 30.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", DATA_FONT)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_stylebox_override("hover", _make_style(Color("262929"), CYAN_COLOR, 1, 7.0))
	button.add_theme_stylebox_override("pressed", _make_style(Color("202525"), CYAN_COLOR, 1, 7.0))
	return button


func _make_margin(amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", amount)
	margin.add_theme_constant_override("margin_top", amount)
	margin.add_theme_constant_override("margin_right", amount)
	margin.add_theme_constant_override("margin_bottom", amount)
	return margin


func _make_label(
	text_value: String,
	font_size: int,
	color: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	font: Font = HEADLINE_FONT
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = align
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_style(background: Color, border: Color, border_width: int, horizontal_padding: float = 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.content_margin_left = horizontal_padding
	style.content_margin_right = horizontal_padding
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	return style


func _status_color(activity: String) -> Color:
	match activity:
		"DESTROYED":
			return RED_COLOR
		"ATTACKING":
			return Color("f08a5d")
		"EVADING", "RETURNING", "RECOVERING", "DEPLOYING", "DEGRADED":
			return AMBER_COLOR
		"READY", "HOLDING":
			return STATUS_COLOR
		_:
			return CYAN_COLOR


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
