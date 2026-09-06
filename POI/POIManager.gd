extends Node
## Autoload singleton. Spawns POIs on campaign terrain, tracks aircraft discovery,
## turns ground investigation into pending command decisions, and resolves cards.

const SPAWN_COUNT := 11
const MIN_POI_SEPARATION_M := 1500.0
const GROUND_REVEAL_RADIUS_M := 200.0
const POLL_INTERVAL_S := 0.5
const LOS_SAMPLE_STEP_M := 100.0
const LOS_TERRAIN_CLEARANCE_M := 4.0
const STARTING_DISCOVERED_POI_COUNT := 3
const STARTING_REVEAL_RETRY_COUNT := 12
const STARTING_REVEAL_RETRY_INTERVAL_S := 0.25
const CAMPAIGN_SCENE_PATH := "res://Main_Scene.tscn"
const WRECKED_SCOUT_CAR_EFFECT := "reveal_nearest_enemy_base"
const WRECKED_SCOUT_CAR_REVEAL_RADIUS_M := 5000.0
const WRECKED_SCOUT_CAR_WORLD_SCENE: PackedScene = preload("res://POI/World/WreckedScoutCarSite.tscn")
const ABANDONED_OUTPOST_EFFECT := "reveal_nearby_poi_sites"
const ABANDONED_OUTPOST_REVEAL_COUNT := 2
const ABANDONED_OUTPOST_SITE_RADIUS_M := 350.0
const ABANDONED_OUTPOST_WORLD_SCENE: PackedScene = preload("res://POI/World/AbandonedOutpostSite.tscn")
const POI_DECISION_NOTICE_SCRIPT: Script = preload("res://UI/POIDecisionNotice.gd")

class POIInstance:
	var id: int = 0
	var world_pos: Vector3 = Vector3.ZERO
	var data: POIData = null
	var discovered: bool = false
	var revealed: bool = false
	var awaiting_orders: bool = false
	var resolved_choice: int = -2
	var outcome_world_pos: Vector3 = Vector3.INF
	var world_node: Node3D = null

var _pois: Array[POIInstance] = []
var _rng := RandomNumberGenerator.new()
var _poll_timer: float = 0.0
var _active_card: Node = null
var _active_poi_id: int = -1
var _decision_notice: CanvasLayer = null
var _was_paused_before_card: bool = false
var _placement_generation: int = 0
var reveals_disabled: bool = false
var _debug_card_index: int = 0
var _starting_reveal_done: bool = false
var _starting_reveal_attempts: int = 0

signal poi_discovered(poi_id: int)
signal poi_awaiting_orders(poi_id: int)
signal poi_resolved(poi_id: int, effect_id: String)

# --- POI definitions (title, body, category, detection_radius, requires_los, [choices]) ---
const _DEFINITIONS: Array = [
	["Wrecked Scout Car", "The driver's log is still readable. Detailed notes on enemy patrol routes in the area.", POIData.Category.INTEL, 600.0, true, ["Recover Patrol Log"], preload("res://Images/POI/poi wrecked scout car.png"), WRECKED_SCOUT_CAR_EFFECT, WRECKED_SCOUT_CAR_WORLD_SCENE],
	["Old Man in a Bunker", "He won't come with you. But he watched the raiders for months through a telescope. \"Their planes come from the northwest. Big base. Radar tower.\"", POIData.Category.INTEL, 700.0, true, [], preload("res://Images/POI/poi old man in a bunker.png")],
	["Collapsed Radio Tower", "The antenna is junk, but the transmitter still works. Your comms officer patches it into the carrier's network.", POIData.Category.INTEL, 800.0, true, [], preload("res://Images/POI/poi collapsed radio tower.png")],
	["Dying Prospector", "She's not going to make it. She knows it. Pushes a crumpled map into your scout's hands. \"Buried it... south of the three mesas. Couldn't carry it.\"", POIData.Category.RESOURCE_CACHE, 550.0, true, [], preload("res://Images/POI/poi dying prospector.png")],
	["Ammunition Stockpile", "Crates stacked floor to ceiling in a concrete bunker. Half of it is corroded. The other half will fly just fine.", POIData.Category.RESOURCE_CACHE, 700.0, true, [], preload("res://Images/POI/poi ammunition stockpile.png")],
	["Wandering Mechanic", "Sunburned, dehydrated, but his hands are steady. Says he kept a whole motor pool running before his settlement fell.", POIData.Category.SETTLEMENT, 650.0, true, ["Offer 1 Water", "Offer 2 Water"], preload("res://Images/POI/poi wandering mechanic.png")],
	["Weathered Shrine", "Someone built this. Recently. Candles, wire sculptures, a faded photo of the sky before the dust came. Nothing useful. Your crew stands quiet for a moment.", POIData.Category.SETTLEMENT, 500.0, false, [], preload("res://Images/POI/poi shrine.png")],
	["Minefield", "Your scout spots the half-buried casings just in time. Or almost in time.", POIData.Category.HAZARD, 600.0, true, ["Navigate Carefully", "Push Through", "Mark and Avoid"], preload("res://Images/POI/poi minefield.png")],
	["Raider Prisoner", "Chained to a pipe in a burned-out building. He's been here a while.", POIData.Category.SETTLEMENT, 750.0, true, ["Free Him", "Interrogate", "Leave Him"], preload("res://Images/POI/poi raider prisoner.png")],
	["Abandoned Outpost", "A ruined frontier station. Its survey room still holds marked charts of nearby sites that never made it onto our tactical map.", POIData.Category.INTEL, 700.0, true, ["Recover Survey Records"], preload("res://Images/POI/poi abandoned settlement.png"), ABANDONED_OUTPOST_EFFECT, ABANDONED_OUTPOST_WORLD_SCENE],
	["Raider Corpse", "The fool died clutching a chunk of corium to his chest. It melted his bones.", POIData.Category.RESOURCE_CACHE, 600.0, true, [], preload("res://Images/POI/poi raider corpse.png")],
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("origin_shifter")
	_rng.randomize()
	call_deferred("_wait_for_terrain", _placement_generation)

func _wait_for_terrain(generation: int) -> void:
	if generation != _placement_generation:
		return
	# TerrainNavGrid also bakes the animated main-menu terrain. POI state and its
	# physical site belong only to the campaign scene, never to that preview.
	if get_tree().current_scene == null \
	or get_tree().current_scene.scene_file_path != CAMPAIGN_SCENE_PATH \
	or not TerrainNavGrid.is_ready():
		await get_tree().create_timer(1.0, false).timeout
		_wait_for_terrain(generation)
		return
	if _pois.is_empty():
		_place_pois()

func _place_pois() -> void:
	var pending := _get_pending_save_state()
	if not pending.is_empty():
		restore_save_state(pending)
		return
	var attempts := 0
	while _pois.size() < SPAWN_COUNT and attempts < SPAWN_COUNT * 30:
		attempts += 1
		var data := _make_data(_pois.size())
		var needs_building_footprint := data.effect_id == ABANDONED_OUTPOST_EFFECT
		var pos: Vector3 = TerrainNavGrid.get_random_passable_position(
			_rng,
			6.0 if needs_building_footprint else 15.0,
			500 if needs_building_footprint else 2000,
			6.0 if needs_building_footprint else 0.0,
			2.5 if needs_building_footprint else 15.0
		)
		if pos == Vector3.ZERO:
			continue
		var ok := true
		for existing: POIInstance in _pois:
			if existing.world_pos.distance_to(pos) < MIN_POI_SEPARATION_M:
				ok = false
				break
		if not ok:
			continue
		var inst := POIInstance.new()
		inst.id = _pois.size()
		inst.world_pos = pos
		inst.data = data
		_pois.append(inst)
		_spawn_world_site(inst)
	call_deferred("_reveal_starting_pois")

func _make_data(index: int) -> POIData:
	var def: Array = _DEFINITIONS[index % _DEFINITIONS.size()]
	var d := POIData.new()
	d.id = "poi_%d" % index
	d.title = def[0]
	d.body = def[1]
	d.category = def[2]
	d.detection_radius_m = def[3]
	d.requires_line_of_sight = def[4]
	if def.size() > 5 and def[5] is Array:
		for s in def[5]:
			d.choices.append(str(s))
	if def.size() > 6 and def[6] is Texture2D:
		d.image = def[6]
	if def.size() > 7:
		d.effect_id = str(def[7])
	if def.size() > 8 and def[8] is PackedScene:
		d.world_scene = def[8]
	return d

func _process(delta: float) -> void:
	if _active_card != null:
		return
	_poll_timer -= delta
	if _poll_timer > 0.0:
		return
	_poll_timer = POLL_INTERVAL_S
	_check_aircraft_discovery()
	_check_ground_reveal()

func _check_aircraft_discovery() -> void:
	for poi: POIInstance in _pois:
		if poi.discovered:
			continue
		for ac in get_tree().get_nodes_in_group("aircraft"):
			if not (ac is Node3D) or not is_instance_valid(ac):
				continue
			if not (ac as Node3D).is_in_group("friendlies"):
				continue
			var ac_pos: Vector3 = (ac as Node3D).global_position
			var dist: float = ac_pos.distance_to(poi.world_pos)
			if dist > poi.data.detection_radius_m:
				continue
			# Check line of sight if required
			if poi.data.requires_line_of_sight:
				if not _has_terrain_line_of_sight(ac_pos, poi.world_pos):
					continue
			# Discovered!
			poi.discovered = true
			poi_discovered.emit(poi.id)
			break

func _reveal_starting_pois() -> void:
	if _starting_reveal_done:
		return
	if _pois.is_empty():
		return
	var origin_node := _get_starting_reveal_origin_node()
	if origin_node == null:
		_starting_reveal_attempts += 1
		if _starting_reveal_attempts <= STARTING_REVEAL_RETRY_COUNT:
			await get_tree().create_timer(STARTING_REVEAL_RETRY_INTERVAL_S, false).timeout
			_reveal_starting_pois()
		return

	var origin: Vector3 = origin_node.global_position
	var revealed_count: int = 0
	while revealed_count < STARTING_DISCOVERED_POI_COUNT:
		var nearest: POIInstance = null
		var nearest_dist_sq: float = INF
		for poi: POIInstance in _pois:
			if poi.discovered:
				continue
			var dx: float = poi.world_pos.x - origin.x
			var dz: float = poi.world_pos.z - origin.z
			var dist_sq: float = dx * dx + dz * dz
			if dist_sq < nearest_dist_sq:
				nearest_dist_sq = dist_sq
				nearest = poi
		if nearest == null:
			break
		nearest.discovered = true
		poi_discovered.emit(nearest.id)
		revealed_count += 1

	_starting_reveal_done = true

func _get_starting_reveal_origin_node() -> Node3D:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier and is_instance_valid(carrier):
		return carrier
	for ac in get_tree().get_nodes_in_group("aircraft"):
		if ac is Node3D and is_instance_valid(ac) and (ac as Node3D).is_in_group("friendlies"):
			return ac as Node3D
	return null

func _has_terrain_line_of_sight(observer_pos: Vector3, target_pos: Vector3) -> bool:
	var from_pos := observer_pos + Vector3.UP * 2.0  # observer eye height
	var to_pos := target_pos + Vector3.UP * 1.5      # target top
	var planar_dist := Vector2(to_pos.x - from_pos.x, to_pos.z - from_pos.z).length()
	if planar_dist <= 1.0:
		return true
	var steps: int = maxi(int(ceil(planar_dist / maxf(LOS_SAMPLE_STEP_M, 10.0))), 1)
	for step_idx in range(1, steps):
		var t: float = float(step_idx) / float(steps)
		var sample_pos := from_pos.lerp(to_pos, t)
		var terrain_y := TerrainNavGrid.sample_height(sample_pos.x, sample_pos.z)
		if terrain_y > TerrainNavGrid.IMPASSABLE * 0.5 and terrain_y + LOS_TERRAIN_CLEARANCE_M > sample_pos.y:
			return false
	return true

func _check_ground_reveal() -> void:
	for poi: POIInstance in _pois:
		if not poi.discovered or poi.revealed or poi.awaiting_orders:
			continue
		for gv in get_tree().get_nodes_in_group("ground_vehicles"):
			if not (gv is Node3D) or not is_instance_valid(gv):
				continue
			if gv.has_method("get_team") and int(gv.call("get_team")) != 1:
				continue
			var gv_pos: Vector3 = (gv as Node3D).global_position
			var flat_dist: float = Vector2(gv_pos.x - poi.world_pos.x, gv_pos.z - poi.world_pos.z).length()
			if flat_dist < GROUND_REVEAL_RADIUS_M:
				_mark_poi_awaiting_orders(poi)
				return  # one field report at a time


func _mark_poi_awaiting_orders(poi: POIInstance) -> void:
	if reveals_disabled:
		return
	if poi.revealed or poi.awaiting_orders:
		return
	poi.awaiting_orders = true
	poi_awaiting_orders.emit(poi.id)
	_refresh_decision_notice()
	if RadioComms != null and RadioComms.has_method("transmit"):
		RadioComms.transmit(
			"Field team",
			"Citadel",
			"%s secured. Awaiting orders." % poi.data.title
		)
	if CombatLog != null and CombatLog.has_method("event"):
		CombatLog.event("INTEL", "%s awaiting command decision" % poi.data.title)


func open_pending_decision(poi_id: int) -> bool:
	if _active_card != null or reveals_disabled:
		return false
	var poi := _find_poi(poi_id)
	if poi == null or poi.revealed or not poi.awaiting_orders:
		return false
	var card := POICard.new()
	card.setup(poi.data)
	card.confirmed.connect(_on_card_confirmed.bind(poi.id))
	card.dismissed.connect(_on_card_dismissed.bind(poi.id))
	get_tree().root.add_child(card)
	_active_card = card
	_active_poi_id = poi.id
	_set_decision_notice_visible(false)
	_was_paused_before_card = get_tree().paused
	get_tree().paused = true
	return true


func _on_card_confirmed(choice_idx: int, poi_id: int) -> void:
	if poi_id != _active_poi_id:
		return
	var poi := _find_poi(poi_id)
	if poi == null or not _apply_poi_effect(poi, choice_idx):
		_close_active_card()
		_refresh_decision_notice()
		return
	poi.awaiting_orders = false
	poi.revealed = true
	poi.resolved_choice = choice_idx
	poi_resolved.emit(poi.id, poi.data.effect_id)
	_close_active_card()
	_refresh_decision_notice()


func _on_card_dismissed(poi_id: int) -> void:
	if poi_id != _active_poi_id:
		return
	_close_active_card()
	_refresh_decision_notice()


func _close_active_card() -> void:
	var had_active_card := is_instance_valid(_active_card)
	if is_instance_valid(_active_card):
		_active_card.queue_free()
	_active_card = null
	_active_poi_id = -1
	if had_active_card:
		get_tree().paused = _was_paused_before_card
	_was_paused_before_card = false


func _apply_poi_effect(poi: POIInstance, _choice_idx: int) -> bool:
	if poi.data.effect_id.is_empty():
		return true
	match poi.data.effect_id:
		WRECKED_SCOUT_CAR_EFFECT:
			return _reveal_nearest_enemy_base(poi)
		ABANDONED_OUTPOST_EFFECT:
			return _reveal_nearby_poi_sites(poi)
		_:
			push_warning("[POIManager] Unknown POI effect: %s" % poi.data.effect_id)
			return false


func _reveal_nearest_enemy_base(poi: POIInstance) -> bool:
	if MapFogOfWar == null or not MapFogOfWar.is_initialized():
		push_warning("[POIManager] Cannot resolve patrol log before map intelligence is ready")
		return false
	var nearest_base: Node3D = null
	var nearest_dist_sq := INF
	for base_variant in get_tree().get_nodes_in_group("enemy_bases"):
		if not (base_variant is Node3D) or not is_instance_valid(base_variant):
			continue
		var base := base_variant as Node3D
		var dx := base.global_position.x - poi.world_pos.x
		var dz := base.global_position.z - poi.world_pos.z
		var dist_sq := dx * dx + dz * dz
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest_base = base
	if nearest_base == null:
		push_warning("[POIManager] Patrol log found no active enemy base to reveal")
		return false
	poi.outcome_world_pos = nearest_base.global_position
	MapFogOfWar.reveal_circle(nearest_base.global_position, WRECKED_SCOUT_CAR_REVEAL_RADIUS_M)
	if RadioComms != null and RadioComms.has_method("transmit"):
		RadioComms.transmit(
			"Intelligence",
			"Citadel",
			"Patrol log decoded. Enemy base located; five-kilometre sector added to the tactical map."
		)
	if CombatLog != null and CombatLog.has_method("event"):
		CombatLog.event("INTEL", "Wrecked scout car revealed enemy base at %s" % str(nearest_base.global_position))
	return true


func _reveal_nearby_poi_sites(source_poi: POIInstance) -> bool:
	if MapFogOfWar == null or not MapFogOfWar.is_initialized():
		push_warning("[POIManager] Cannot resolve survey records before map intelligence is ready")
		return false
	var revealed_count := 0
	var first_revealed_pos := Vector3.INF
	while revealed_count < ABANDONED_OUTPOST_REVEAL_COUNT:
		var nearest: POIInstance = null
		var nearest_dist_sq := INF
		for candidate: POIInstance in _pois:
			if candidate.id == source_poi.id or candidate.discovered or candidate.revealed:
				continue
			var dx := candidate.world_pos.x - source_poi.world_pos.x
			var dz := candidate.world_pos.z - source_poi.world_pos.z
			var dist_sq := dx * dx + dz * dz
			if dist_sq < nearest_dist_sq:
				nearest_dist_sq = dist_sq
				nearest = candidate
		if nearest == null:
			break
		nearest.discovered = true
		poi_discovered.emit(nearest.id)
		MapFogOfWar.reveal_circle(nearest.world_pos, ABANDONED_OUTPOST_SITE_RADIUS_M)
		if first_revealed_pos == Vector3.INF:
			first_revealed_pos = nearest.world_pos
		revealed_count += 1
	if first_revealed_pos != Vector3.INF:
		source_poi.outcome_world_pos = first_revealed_pos
	if RadioComms != null and RadioComms.has_method("transmit"):
		RadioComms.transmit(
			"Intelligence",
			"Citadel",
			"Outpost survey records recovered. %d nearby field site%s added to the tactical map." % [
				revealed_count,
				"" if revealed_count == 1 else "s",
			]
		)
	if CombatLog != null and CombatLog.has_method("event"):
		CombatLog.event("INTEL", "Abandoned outpost revealed %d nearby POI site(s)" % revealed_count)
	return true


func _find_poi(poi_id: int) -> POIInstance:
	for poi: POIInstance in _pois:
		if poi.id == poi_id:
			return poi
	return null


func _spawn_world_site(poi: POIInstance) -> void:
	if poi.data == null or poi.data.world_scene == null or get_tree().current_scene == null:
		return
	if is_instance_valid(poi.world_node):
		return
	var site := poi.data.world_scene.instantiate() as Node3D
	if site == null:
		push_warning("[POIManager] World scene for %s did not instantiate as Node3D" % poi.data.title)
		return
	get_tree().current_scene.add_child(site)
	site.global_position = poi.world_pos
	site.set_meta("poi_id", poi.id)
	site.set_meta("poi_title", poi.data.title)
	poi.world_node = site


func _clear_world_sites() -> void:
	for poi: POIInstance in _pois:
		if is_instance_valid(poi.world_node):
			poi.world_node.queue_free()
		poi.world_node = null


func _refresh_decision_notice() -> void:
	var pending := get_awaiting_order_markers()
	if pending.is_empty() or _active_card != null:
		_set_decision_notice_visible(false)
		return
	var marker: Dictionary = pending[0]
	if not is_instance_valid(_decision_notice):
		_decision_notice = POI_DECISION_NOTICE_SCRIPT.new() as CanvasLayer
		if _decision_notice == null:
			return
		_decision_notice.name = "POIDecisionNotice"
		_decision_notice.connect("review_requested", Callable(self, "open_pending_decision"))
		add_child(_decision_notice)
	_decision_notice.call("setup", int(marker.get("id", -1)), str(marker.get("title", "Field Site")), pending.size())
	_set_decision_notice_visible(true)


func _set_decision_notice_visible(is_visible: bool) -> void:
	if is_instance_valid(_decision_notice):
		_decision_notice.visible = is_visible

func _input(event: InputEvent) -> void:
	return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode == KEY_P:
		if _active_card == null:
			_show_debug_card()
		get_viewport().set_input_as_handled()

func _show_debug_card() -> void:
	var data := _make_data(_debug_card_index)
	_debug_card_index = (_debug_card_index + 1) % _DEFINITIONS.size()
	var card := POICard.new()
	card.setup(data)
	card.confirmed.connect(func(_choice_idx: int) -> void: _close_active_card())
	card.dismissed.connect(_close_active_card)
	get_tree().root.add_child(card)
	_active_card = card
	_active_poi_id = -1
	_was_paused_before_card = get_tree().paused
	get_tree().paused = true

## Returns world positions of all discovered (but not necessarily revealed) POIs.
func get_discovered_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for poi: POIInstance in _pois:
		if poi.discovered:
			result.append(poi.world_pos)
	return result

## Returns discovered POIs with display state for maps.
func get_discovered_map_markers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for poi: POIInstance in _pois:
		if poi.discovered:
			result.append({
				"position": poi.world_pos,
				"revealed": poi.revealed,
				"awaiting_orders": poi.awaiting_orders,
				"id": poi.id,
			})
	return result

## Returns POIs that are discovered but not yet consumed/revealed.
func get_active_discovered_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for poi: POIInstance in _pois:
		if poi.discovered and not poi.revealed:
			result.append(poi.world_pos)
	return result


func get_awaiting_order_markers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for poi: POIInstance in _pois:
		if poi.awaiting_orders and not poi.revealed:
			result.append({
				"id": poi.id,
				"position": poi.world_pos,
				"title": poi.data.title,
			})
	return result


func has_awaiting_orders() -> bool:
	for poi: POIInstance in _pois:
		if poi.awaiting_orders and not poi.revealed:
			return true
	return false


func has_active_decision() -> bool:
	return _active_card != null and is_instance_valid(_active_card)


func capture_save_state() -> Dictionary:
	var entries: Array[Dictionary] = []
	for poi: POIInstance in _pois:
		var entry: Dictionary = {
			"id": poi.id,
			"world_pos": poi.world_pos,
			"discovered": poi.discovered,
			"revealed": poi.revealed,
			"awaiting_orders": poi.awaiting_orders,
			"resolved_choice": poi.resolved_choice,
		}
		if poi.outcome_world_pos != Vector3.INF:
			entry["outcome_world_pos"] = poi.outcome_world_pos
		entries.append(entry)
	return {
		"pois": entries,
		"starting_reveal_done": _starting_reveal_done,
	}


func restore_save_state(state: Dictionary) -> bool:
	var entries_variant: Variant = state.get("pois", [])
	if not (entries_variant is Array):
		return false
	_clear_world_sites()
	_pois.clear()
	for entry_variant in entries_variant:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		var inst := POIInstance.new()
		inst.id = int(entry.get("id", _pois.size()))
		inst.world_pos = entry.get("world_pos", Vector3.ZERO) as Vector3
		inst.data = _make_data(inst.id)
		inst.discovered = bool(entry.get("discovered", false))
		inst.revealed = bool(entry.get("revealed", false))
		inst.awaiting_orders = bool(entry.get("awaiting_orders", false)) and not inst.revealed
		inst.resolved_choice = int(entry.get("resolved_choice", -2))
		var outcome_variant: Variant = entry.get("outcome_world_pos", Vector3.INF)
		inst.outcome_world_pos = outcome_variant as Vector3 if outcome_variant is Vector3 else Vector3.INF
		_pois.append(inst)
		_spawn_world_site(inst)
	_starting_reveal_done = bool(state.get("starting_reveal_done", true))
	_starting_reveal_attempts = 0
	call_deferred("_refresh_decision_notice")
	return not _pois.is_empty()


func start_new_campaign() -> void:
	_placement_generation += 1
	_close_active_card()
	_clear_world_sites()
	_pois.clear()
	_starting_reveal_done = false
	_starting_reveal_attempts = 0
	_poll_timer = 0.0
	_set_decision_notice_visible(false)
	# The new scene rebakes TerrainNavGrid. Wait for that fresh geometry instead
	# of placing sites against the previous campaign's still-live grid.
	call_deferred("_wait_for_fresh_campaign_terrain", _placement_generation)


func _wait_for_fresh_campaign_terrain(generation: int) -> void:
	while generation == _placement_generation and (
		get_tree().current_scene == null
		or get_tree().current_scene.scene_file_path != CAMPAIGN_SCENE_PATH
	):
		await get_tree().process_frame
	if generation != _placement_generation:
		return
	# MainMenu resets the autoload grid before entering Main_Scene. Deferring one
	# more frame ensures scene setup has had a chance to bind the new terrain.
	await get_tree().process_frame
	_wait_for_terrain(generation)


func _get_pending_save_state() -> Dictionary:
	if GameSession == null or not GameSession.has_pending_save_state():
		return {}
	var campaign := GameSession.peek_pending_campaign_state()
	var state_variant: Variant = campaign.get("pois", {})
	return state_variant as Dictionary if state_variant is Dictionary else {}

func apply_origin_shift(offset: Vector3) -> void:
	for poi: POIInstance in _pois:
		poi.world_pos -= offset
		if poi.outcome_world_pos != Vector3.INF:
			poi.outcome_world_pos -= offset
