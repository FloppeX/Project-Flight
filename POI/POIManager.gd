extends Node
## Autoload singleton. Spawns POIs on the terrain, tracks discovery by aircraft,
## triggers reveal when a friendly ground vehicle gets close, and shows the POI card.

const SPAWN_COUNT := 11
const MIN_POI_SEPARATION_M := 1500.0
const GROUND_REVEAL_RADIUS_M := 200.0
const POLL_INTERVAL_S := 0.5
const LOS_SAMPLE_STEP_M := 100.0
const LOS_TERRAIN_CLEARANCE_M := 4.0
const STARTING_DISCOVERED_POI_COUNT := 3
const STARTING_REVEAL_RETRY_COUNT := 12
const STARTING_REVEAL_RETRY_INTERVAL_S := 0.25

class POIInstance:
	var id: int = 0
	var world_pos: Vector3 = Vector3.ZERO
	var data: POIData = null
	var discovered: bool = false
	var revealed: bool = false

var _pois: Array[POIInstance] = []
var _rng := RandomNumberGenerator.new()
var _poll_timer: float = 0.0
var _active_card: Node = null
var reveals_disabled: bool = false
var _debug_card_index: int = 0
var _starting_reveal_done: bool = false
var _starting_reveal_attempts: int = 0

signal poi_discovered(poi_id: int)

# --- POI definitions (title, body, category, detection_radius, requires_los, [choices]) ---
const _DEFINITIONS: Array = [
	["Wrecked Scout Car", "The driver's log is still readable. Detailed notes on enemy patrol routes in the area.", POIData.Category.INTEL, 600.0, true, [], preload("res://Images/POI/poi wrecked scout car.png")],
	["Old Man in a Bunker", "He won't come with you. But he watched the raiders for months through a telescope. \"Their planes come from the northwest. Big base. Radar tower.\"", POIData.Category.INTEL, 700.0, true, [], preload("res://Images/POI/poi old man in a bunker.png")],
	["Collapsed Radio Tower", "The antenna is junk, but the transmitter still works. Your comms officer patches it into the carrier's network.", POIData.Category.INTEL, 800.0, true, [], preload("res://Images/POI/poi collapsed radio tower.png")],
	["Dying Prospector", "She's not going to make it. She knows it. Pushes a crumpled map into your scout's hands. \"Buried it... south of the three mesas. Couldn't carry it.\"", POIData.Category.RESOURCE_CACHE, 550.0, true, [], preload("res://Images/POI/poi dying prospector.png")],
	["Ammunition Stockpile", "Crates stacked floor to ceiling in a concrete bunker. Half of it is corroded. The other half will fly just fine.", POIData.Category.RESOURCE_CACHE, 700.0, true, [], preload("res://Images/POI/poi ammunition stockpile.png")],
	["Wandering Mechanic", "Sunburned, dehydrated, but his hands are steady. Says he kept a whole motor pool running before his settlement fell.", POIData.Category.SETTLEMENT, 650.0, true, ["Offer 1 Water", "Offer 2 Water"], preload("res://Images/POI/poi wandering mechanic.png")],
	["Weathered Shrine", "Someone built this. Recently. Candles, wire sculptures, a faded photo of the sky before the dust came. Nothing useful. Your crew stands quiet for a moment.", POIData.Category.SETTLEMENT, 500.0, false, [], preload("res://Images/POI/poi shrine.png")],
	["Minefield", "Your scout spots the half-buried casings just in time. Or almost in time.", POIData.Category.HAZARD, 600.0, true, ["Navigate Carefully", "Push Through", "Mark and Avoid"], preload("res://Images/POI/poi minefield.png")],
	["Raider Prisoner", "Chained to a pipe in a burned-out building. He's been here a while.", POIData.Category.SETTLEMENT, 750.0, true, ["Free Him", "Interrogate", "Leave Him"], preload("res://Images/POI/poi raider prisoner.png")],
	["Abandoned Settlement", "Decaying machinery litters the ground. Whoever stayed here left in a hurry.", POIData.Category.RESOURCE_CACHE, 700.0, true, [], preload("res://Images/POI/poi abandoned settlement.png")],
	["Raider Corpse", "The fool died clutching a chunk of corium to his chest. It melted his bones.", POIData.Category.RESOURCE_CACHE, 600.0, true, [], preload("res://Images/POI/poi raider corpse.png")],
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("origin_shifter")
	_rng.randomize()
	call_deferred("_wait_for_terrain")

func _wait_for_terrain() -> void:
	if not TerrainNavGrid.is_ready():
		await get_tree().create_timer(1.0, false).timeout
		_wait_for_terrain()
		return
	_place_pois()

func _place_pois() -> void:
	var attempts := 0
	while _pois.size() < SPAWN_COUNT and attempts < SPAWN_COUNT * 30:
		attempts += 1
		var pos: Vector3 = TerrainNavGrid.get_random_passable_position(_rng)
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
		inst.data = _make_data(inst.id)
		_pois.append(inst)
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
		if not poi.discovered or poi.revealed:
			continue
		for gv in get_tree().get_nodes_in_group("ground_vehicles"):
			if not (gv is Node3D) or not is_instance_valid(gv):
				continue
			if gv.has_method("get_team") and int(gv.call("get_team")) != 1:
				continue
			var gv_pos: Vector3 = (gv as Node3D).global_position
			var flat_dist: float = Vector2(gv_pos.x - poi.world_pos.x, gv_pos.z - poi.world_pos.z).length()
			if flat_dist < GROUND_REVEAL_RADIUS_M:
				_reveal_poi(poi)
				return  # one reveal at a time

func _reveal_poi(poi: POIInstance) -> void:
	if reveals_disabled:
		return
	poi.revealed = true
	var card := POICard.new()
	card.setup(poi.data)
	card.confirmed.connect(_on_card_confirmed)
	get_tree().root.add_child(card)
	_active_card = card
	get_tree().paused = true

func _on_card_confirmed(_choice_idx: int) -> void:
	if is_instance_valid(_active_card):
		_active_card.queue_free()
	_active_card = null
	get_tree().paused = false

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
	card.confirmed.connect(_on_card_confirmed)
	get_tree().root.add_child(card)
	_active_card = card
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

func apply_origin_shift(offset: Vector3) -> void:
	for poi: POIInstance in _pois:
		poi.world_pos -= offset
