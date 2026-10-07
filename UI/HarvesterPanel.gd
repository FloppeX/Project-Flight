extends PanelContainer
var _status: Label
var _notice: Label
var _source_info: Label
var _planning: Label
var _salvage_planning: Label
var _sources: OptionButton
var _collect: Button
var _recall: Button
var _repeat: CheckButton
var _timer := 0.0
var _signature := ""
var _source_selection_explicit := false

func _ops() -> Node:
	var manager := get_tree().get_first_node_in_group("carrier_manager")
	return manager.get_harvester_ops() if manager != null else null

func _ready() -> void:
	name = "HarvesterPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1c211f")
	style.border_color = Color("655436")
	style.set_border_width_all(1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	add_child(column)
	_status = Label.new()
	_status.add_theme_font_override("font", preload("res://UI/Fonts/JetBrainsMono-Variable.ttf"))
	_status.add_theme_font_size_override("font_size", 13)
	_status.modulate = Color("ffc561")
	_status.tooltip_text = "The harvester has a shielded intake and sealed cargo tank for safe corium collection."
	column.add_child(_status)
	var map_orders := Button.new()
	map_orders.text = "TACTICAL MAP ORDERS"
	map_orders.tooltip_text = "Select the harvester on the tactical map: move, harvest, harvest when possible, or return to base."
	map_orders.pressed.connect(func() -> void: WorldMapOverlay.select_harvester())
	column.add_child(map_orders)
	_planning = Label.new()
	_planning.add_theme_font_size_override("font_size", 12)
	_planning.modulate = Color("b9c7c2")
	_planning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_planning)
	_salvage_planning = Label.new()
	_salvage_planning.add_theme_font_size_override("font_size", 12)
	_salvage_planning.modulate = Color("b9c7c2")
	_salvage_planning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_salvage_planning)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	_sources = OptionButton.new()
	_sources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sources.custom_minimum_size = Vector2(310, 36)
	_sources.fit_to_longest_item = false
	_sources.clip_text = true
	_sources.item_selected.connect(func(_index: int) -> void:
		_source_selection_explicit = true
		_refresh()
	)
	row.add_child(_sources)
	_repeat = CheckButton.new()
	_repeat.text = "Repeat trips"
	_repeat.button_pressed = true
	_repeat.tooltip_text = "Keep collecting the finite reserve until exhausted. Partial loads return during dormancy; spent corium never replenishes. Recall at any time to move on."
	row.add_child(_repeat)
	_collect = Button.new()
	_collect.text = "COLLECT"
	_collect.custom_minimum_size.x = 110
	_collect.pressed.connect(_order)
	row.add_child(_collect)
	_recall = Button.new()
	_recall.text = "RECALL"
	_recall.custom_minimum_size.x = 100
	_recall.pressed.connect(func() -> void:
		var ops := _ops()
		if ops != null: ops.recall()
	)
	row.add_child(_recall)
	_source_info = Label.new()
	_source_info.add_theme_font_size_override("font_size", 12)
	_source_info.modulate = Color("ffc561")
	_source_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_source_info)
	_notice = Label.new()
	_notice.add_theme_font_size_override("font_size", 12)
	_notice.modulate = Color("b9c7c2")
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_notice)
	_refresh()

func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.5
		_refresh()

func _order() -> void:
	var ops := _ops()
	if ops == null or _sources.selected < 0:
		return
	var reason: String = ops.collect(_sources.get_item_id(_sources.selected), _repeat.button_pressed)
	if not reason.is_empty():
		ops.notice = reason
	_refresh()

func _refresh() -> void:
	var ops := _ops()
	if ops == null:
		_status.text = "HARVESTER // CARRIER UNAVAILABLE"
		_collect.disabled = true
		_recall.disabled = true
		return
	var snapshot: Dictionary = ops.snapshot()
	_status.text = "HARVESTER // %s // %s // CARGO C %.0f + P %.0f / %d // BAY %d" % [str(snapshot.mission).replace("AUTO_HARVEST", "HARVEST WHEN POSSIBLE"), str(snapshot.phase).to_upper().replace("_", " "), float(snapshot.cargo.corium), float(snapshot.cargo.plasteel), int(snapshot.capacity), int(snapshot.stored)]
	_notice.text = "%s  •  %s" % [str(snapshot.notice), str(snapshot.source)]
	var field: Node = get_tree().root.get_node("POIManager").get_resource_field()
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	var origin := carrier.global_position if is_instance_valid(carrier) else Vector3.ZERO
	var overview: Dictionary = field.corium_overview(origin)
	if int(overview.sites) > 0:
		_planning.text = "FINITE CORIUM // %d known sites // %.0f remaining // nearest %.1f km. Depleted sites never refill." % [int(overview.sites), float(overview.remaining), float(overview.nearest_m) / 1000.0]
	else:
		_planning.text = "No known corium reserves remain. Scout new terrain; depleted deposits never refill."
	var salvage: Dictionary = field.plasteel_overview(origin)
	_salvage_planning.text = "PLASTEEL SALVAGE // %d known sites // %.0f remaining // nearest %.1f km" % [int(salvage.sites), float(salvage.remaining), float(salvage.nearest_m) / 1000.0] if int(salvage.sites) > 0 else "No known plasteel salvage. Scout for ruins and vehicle wrecks, or recover destroyed enemy buildings."
	var sources: Array = field.discovered_sources()
	var collection_origin: Vector3 = ops.vehicle.global_position if is_instance_valid(ops.vehicle) else origin
	var distance_reference := "harvester" if is_instance_valid(ops.vehicle) else "carrier"
	sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := _source_distance_m(a, collection_origin)
		var db := _source_distance_m(b, collection_origin)
		return int(a.id) < int(b.id) if is_equal_approx(da, db) else da < db
	)
	var selected_id := -1
	if _source_selection_explicit and _sources.selected >= 0:
		selected_id = _sources.get_item_id(_sources.selected)
	elif not str(snapshot.phase) in ["stored", "lost"]:
		selected_id = int(snapshot.source_id)
	# Default to the closest source until the player chooses one. Re-sorting
	# after discovery/movement must preserve an explicit selection or live order,
	# and must never move choices under the pointer while the popup is open.
	var ids: Array[int] = []
	for source in sources:
		ids.append(int(source.id))
	var signature := str(ids)
	if signature != _signature and not _sources.get_popup().visible:
		_signature = signature
		_sources.clear()
		for source in sources:
			_sources.add_item(str(source.label), int(source.id))
			if int(source.id) == selected_id:
				_sources.select(_sources.item_count - 1)
		if not selected_id in ids:
			_source_selection_explicit = false
		if sources.is_empty():
			_sources.add_item("No known deposits — scout the terrain", -1)
	if not _sources.get_popup().visible:
		for index in range(_sources.item_count):
			if _sources.get_item_id(index) == selected_id:
				_sources.select(index)
	for index in range(_sources.item_count):
		var source: Dictionary = field.get_source(_sources.get_item_id(index))
		if source.is_empty():
			continue
		var corium := str(source.get("kind", "")) == "corium"
		var distance_m := _source_distance_m(source, collection_origin)
		var distance_text := "%.0f m" % distance_m if distance_m < 1000.0 else "%.1f km" % (distance_m / 1000.0)
		var text := "%s   %s   C %.0f / P %.0f" % [str(source.label), distance_text, float(source.materials.corium), float(source.materials.plasteel)]
		if corium:
			text = "%s   %s   %s   surface %.0f / reserve %.0f" % [str(source.label), distance_text, str(source.get("seep_phase", "seeping")).to_upper(), float(source.materials.corium), float(source.get("reserve_corium", 0.0))]
		_sources.set_item_text(index, text)
		_sources.set_item_tooltip(index, "%s // %s from %s" % [field.source_status(source), distance_text, distance_reference])
	var selected: Dictionary = field.get_source(_sources.get_item_id(_sources.selected)) if _sources.selected >= 0 else {}
	if str(selected.get("kind", "")) == "corium":
		_source_info.text = "CORIUM // %s // SURFACE %.0f / UNDERGROUND %.0f // %.1f km from %s // ~%d loads left\nDormancy pauses extraction. Active seep hazard: %.0f m. The harvester's shielded intake and sealed cargo tank protect it during collection." % [field.source_status(selected), float(selected.materials.corium), float(selected.get("reserve_corium", 0.0)), _source_distance_m(selected, collection_origin) / 1000.0, distance_reference, ceili(field.remaining(selected) / float(snapshot.capacity)), float(selected.get("hazard_radius", 0.0))]
	elif not selected.is_empty():
		_source_info.text = "%s // C %.0f / P %.0f // %.1f km from %s // ~%d loads left\nCollect loose metal beside the wreck. Salvage is finite; cargo reaches stores only after the harvester returns." % [field.source_status(selected), float(selected.materials.corium), float(selected.materials.plasteel), _source_distance_m(selected, collection_origin) / 1000.0, distance_reference, ceili(field.remaining(selected) / float(snapshot.capacity))]
	else:
		_source_info.text = "Corium deposits are fixed and finite. Seeping and dormancy cycle until the reserve is exhausted. Recover plasteel from wrecks and ruins."
	_collect.disabled = sources.is_empty() or str(snapshot.phase) in ["deploying", "folding", "returning", "retrieving"] or (int(snapshot.stored) == 0 and not is_instance_valid(ops.vehicle))
	_recall.disabled = str(snapshot.phase) in ["stored", "lost"]

func _source_distance_m(source: Dictionary, origin: Vector3) -> float:
	var at: Vector3 = source.position
	return Vector2(at.x - origin.x, at.z - origin.z).length()
