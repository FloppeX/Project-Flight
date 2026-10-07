extends Node
## Finite physical sites. Material reaches carrier stores only through cargo unloading.
const SEEP_ACTIVE_S := 45.0
const SEEP_FLOW_RATE := 8.0
const CORIUM_HAZARD_RADIUS_M := 12.0
const CORIUM_DAMAGE_PER_S := 8.0
const CORIUM_VISUAL := preload("res://POI/World/CoriumSeepVisual.gd")
# One fixed campaign allocation, including the starter plasteel ruin in slot 1.
# Depleted slots still count; neither waiting nor moving creates replacements.
const SEED_SITE_COUNT := 9
const SEED_ATTEMPTS_PER_FRAME := 1
const SEED_YIELDS := [480.0, 0.0, 640.0, 640.0, 800.0, 800.0, 1120.0, 1120.0, 1120.0]
const SALVAGE_SITE_COUNT := 12
const SALVAGE_VARIANTS := [
	{"label": "Abandoned building", "scene": "res://POI/World/Ruin1Site.tscn", "radius": 10.0, "plasteel": 240.0},
	{"label": "Wrecked vehicle", "scene": "res://POI/World/WreckedScoutCarSite.tscn", "radius": 6.0, "plasteel": 80.0},
	{"label": "Ruined building", "scene": "res://POI/World/Ruin2Site.tscn", "radius": 18.0, "plasteel": 320.0},
]

var sources: Array[Dictionary] = []
var seeded := false
var _next_id := 1
var _poll := 0.0
var _hazard_poll := 0.0
var _visual_poll := 0.0
var _visuals: Dictionary = {}
var _seed_origin := Vector3.ZERO
var _seed_origin_set := false
var _seed_cursor := 0
var _seed_attempts: Array[int] = []
var _salvage_seeded := false
var _salvage_cursor := 0
var _salvage_attempts: Array[int] = []
var _seed_turn := false

func _ready() -> void:
	add_to_group("origin_shifter")
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(delta: float) -> void:
	if GameSession.has_pending_save_state():
		return
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://Main_Scene.tscn":
		return
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if not is_instance_valid(carrier) or not TerrainNavGrid.is_ready() or not carrier.is_initial_placement_complete():
		return
	if NavGraph.is_ready():
		_seed_turn = not _seed_turn
		if not seeded and (_seed_turn or _salvage_seeded):
			_seed_terrain(carrier.global_position)
		elif not _salvage_seeded:
			_seed_salvage(carrier.global_position)
	_advance_seeps(delta)
	_hazard_poll += delta
	if _hazard_poll >= 1.0:
		var exposure_s := _hazard_poll
		_hazard_poll = 0.0
		_apply_corium_hazards(exposure_s)
	_visual_poll -= delta
	if _visual_poll <= 0.0:
		_visual_poll = 0.25
		for source in sources:
			if not is_instance_valid(_visuals.get(int(source.id))):
				_spawn_visual(source)
			_update_visual(source)
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 2.0
	_sync_poi_salvage()
	for source in sources:
		if bool(source.discovered):
			continue
		for group in ["friendlies", "aircraft"]:
			for unit in get_tree().get_nodes_in_group(group):
				if not unit is Node3D or not _is_friendly_observer(unit):
					continue
				if unit.global_position.distance_to(source.position) < 700.0 and get_parent().call("_has_terrain_line_of_sight", unit.global_position + Vector3.UP * 4.0, source.position + Vector3.UP * 2.0):
					source.discovered = true
					MapFogOfWar.reveal_circle(source.position, 100.0)
					break
			if bool(source.discovered):
				break

func _is_friendly_observer(unit: Node) -> bool:
	return not unit.is_queued_for_deletion() and (unit.is_in_group("friendlies") or (unit.has_method("get_team") and int(unit.get_team()) == 1))

func _seed_terrain(origin: Vector3) -> void:
	if seeded:
		return
	if not _seed_origin_set:
		_seed_origin = origin
		_seed_origin_set = true
	if _seed_attempts.is_empty():
		_seed_attempts.resize(SEED_SITE_COUNT)
		_seed_attempts.fill(0)
	var occupied := {}
	for source in sources:
		if source.has("seed_slot"):
			var slot := int(source.seed_slot)
			if slot >= 0 and slot < SEED_SITE_COUNT:
				occupied[slot] = true
	# Resume missing slots across polls instead of abandoning the wider region
	# after two successes. Candidate history is saved and anchored to the start.
	for attempt in range(SEED_ATTEMPTS_PER_FRAME):
		var slot := _seed_cursor % SEED_SITE_COUNT
		_seed_cursor = (slot + 1) % SEED_SITE_COUNT
		if occupied.has(slot):
			continue
		var at := _seed_candidate(slot, _seed_attempts[slot])
		_seed_attempts[slot] += 1
		at = _validated_seed_position(at, slot)
		if at == Vector3.INF:
			continue
		var too_close := false
		for existing in sources:
			var separation := 1200.0 if slot >= 2 and str(existing.kind) == "corium" else 220.0
			if existing.position.distance_to(at) < separation:
				too_close = true
		if too_close:
			continue
		var source_id: int
		if slot == 1:
			source_id = add_source("Ruined machinery", at, "ruin", {"plasteel": 420.0}, true)
		else:
			var number := slot if slot > 1 else 1
			source_id = add_corium_seep("Corium seep %02d" % number, at, SEED_YIELDS[slot], slot <= 3, slot % 2 == 0)
		get_source(source_id)["seed_slot"] = slot
		occupied[slot] = true
		if occupied.size() == SEED_SITE_COUNT:
			break
	seeded = occupied.size() == SEED_SITE_COUNT

func _seed_candidate(slot: int, attempt: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = 847291 + slot * 104729 + attempt * 15485863
	var near := slot < 2
	var radius := rng.randf_range(350.0, 1100.0) if near else rng.randf_range(2000.0, 4000.0)
	if slot in [4, 5]:
		radius = rng.randf_range(6000.0, 10000.0)
	elif slot >= 6:
		radius = rng.randf_range(12000.0, 18000.0)
	# Paired alternatives occupy opposing sectors. Distant sites cover thirds
	# of the region; terrain retries can explore their whole sector.
	var angle := rng.randf() * TAU
	if slot in [2, 3, 4, 5]:
		angle = float(slot % 2) * PI + rng.randf_range(-PI * 0.4, PI * 0.4)
	elif slot >= 6:
		angle = float(slot - 6) * TAU / 3.0 + rng.randf_range(-PI / 3.0, PI / 3.0)
	# Near a map edge or blocked sector, retain distance/separation but allow
	# another direction. Otherwise an impossible sector would retry forever.
	if attempt >= 120:
		angle = rng.randf() * TAU
	return _seed_origin + Vector3(sin(angle), 0, cos(angle)) * radius

func _validated_seed_position(at: Vector3, slot: int) -> Vector3:
	if not TerrainNavGrid.is_low_clear_position(at.x, at.z, 10.0) or not TerrainNavGrid.is_stable_footprint(at.x, at.z, 7.0, 2.0, 2.5):
		return Vector3.INF
	if slot == 1:
		var ruin_at := at + Vector3(12, 0, -12)
		if not TerrainNavGrid.is_low_clear_position(ruin_at.x, ruin_at.z, 6.0) or not TerrainNavGrid.is_stable_footprint(ruin_at.x, ruin_at.z, 6.0, 2.0, 2.5):
			return Vector3.INF
	at.y = TerrainNavGrid.sample_height(at.x, at.z)
	# Every opportunity needs a ground route, including the distant alternatives.
	if not NavGraph.is_ready() or not NavGraph.can_anchor(at, 6.0) or NavGraph.find_path(_seed_origin, at, 6.0).is_empty():
		return Vector3.INF
	return at

func _seed_salvage(origin: Vector3) -> void:
	if _salvage_seeded:
		return
	if not _seed_origin_set:
		_seed_origin = origin
		_seed_origin_set = true
	if _salvage_attempts.is_empty():
		_salvage_attempts.resize(SALVAGE_SITE_COUNT)
		_salvage_attempts.fill(0)
	var occupied := {}
	for source in sources:
		if source.has("salvage_seed_slot"):
			occupied[int(source.salvage_seed_slot)] = true
	if occupied.size() >= SALVAGE_SITE_COUNT:
		_salvage_seeded = true
		return
	# One candidate per frame, alternating with any unfinished corium placement.
	var slot := _salvage_cursor
	_salvage_cursor = (slot + 1) % SALVAGE_SITE_COUNT
	if occupied.has(slot):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 973733 + slot * 104729 + _salvage_attempts[slot] * 15485863
	_salvage_attempts[slot] += 1
	var radius := rng.randf_range(1800.0, 7000.0) if slot < 6 else rng.randf_range(7000.0, 18000.0)
	var angle := rng.randf() * TAU
	var at := _seed_origin + Vector3(sin(angle), 0, cos(angle)) * radius
	for source in sources:
		if source.position.distance_to(at) < 650.0:
			return
	var variant := slot % SALVAGE_VARIANTS.size()
	var placement := _validated_salvage_position(at, variant)
	if placement.is_empty():
		return
	add_ruin_source(slot, variant, placement.collection, placement.wreck, rng.randf() * TAU)

func _validated_salvage_position(at: Vector3, variant: int) -> Dictionary:
	# The pile is outside a conservative circular footprint, for every yaw.
	var radius := float(SALVAGE_VARIANTS[variant].radius)
	var wreck_at := at + Vector3.RIGHT * (radius + 7.0)
	if not TerrainNavGrid.is_low_clear_position(wreck_at.x, wreck_at.z, 6.0) or not TerrainNavGrid.is_stable_footprint(wreck_at.x, wreck_at.z, radius, 2.0, 2.5):
		return {}
	at = _validated_seed_position(at, 2)
	if at == Vector3.INF:
		return {}
	wreck_at.y = TerrainNavGrid.sample_height(wreck_at.x, wreck_at.z)
	return {"collection": at, "wreck": wreck_at}

func add_ruin_source(slot: int, variant: int, collection_at: Vector3, wreck_at: Vector3, yaw: float) -> int:
	var key := "scattered_salvage_%d" % slot
	var existing := _source_for_key(key)
	if not existing.is_empty():
		return int(existing.id)
	var spec: Dictionary = SALVAGE_VARIANTS[variant]
	return add_source("%s %02d" % [spec.label, slot + 1], collection_at, "ruin", {"plasteel": spec.plasteel}, false,
		{"site_key": key, "salvage_seed_slot": slot, "ruin_variant": variant, "wreck_position": wreck_at, "wreck_yaw": yaw})

func _sync_poi_salvage() -> void:
	for poi in get_parent().get("_pois"):
		if poi.data == null or poi.data.world_scene == null:
			continue
		var key := "poi_%d" % poi.id
		var existing := _source_for_key(key)
		if not existing.is_empty():
			if poi.discovered:
				existing.discovered = true
			continue
		var at: Vector3 = poi.world_pos + Vector3(12, 0, 0)
		var ruin: bool = poi.data.effect_id == "reveal_nearby_poi_sites"
		var id := add_salvage_source("Outpost salvage" if ruin else "Scout car salvage", at, 500.0 if ruin else 100.0, key, poi.discovered)
		get_source(id)["wreck_position"] = poi.world_pos

func _source_for_key(key: String) -> Dictionary:
	if not key.is_empty():
		for source in sources:
			if str(source.get("site_key", "")) == key:
				return source
	return {}

func add_salvage_source(label: String, at: Vector3, amount: float, site_key: String, discovered := false) -> int:
	var existing := _source_for_key(site_key)
	if not existing.is_empty():
		existing.discovered = bool(existing.discovered) or discovered
		return int(existing.id)
	var id := add_source(label, _salvage_position(at), "salvage", {"plasteel": amount}, discovered)
	get_source(id)["site_key"] = site_key
	return id

func _salvage_position(origin: Vector3) -> Vector3:
	if not TerrainNavGrid.is_ready():
		return origin
	for radius in [0.0, 8.0, 14.0, 22.0, 32.0, 48.0]:
		for step in range(8):
			var angle := float(step) * TAU / 8.0
			var at: Vector3 = origin + Vector3(sin(angle), 0, cos(angle)) * float(radius)
			if not TerrainNavGrid.is_low_clear_position(at.x, at.z, 6.0) or not TerrainNavGrid.is_stable_footprint(at.x, at.z, 3.0, 2.0, 2.5):
				continue
			at.y = TerrainNavGrid.sample_height(at.x, at.z)
			if not NavGraph.is_ready() or NavGraph.can_anchor(at, 6.0):
				return at
	# Retain material if there is no accessible patch; missions report blocked approaches.
	return origin

func add_corium_seep(label: String, at: Vector3, total: float, discovered := false, active := true) -> int:
	var surface := minf(maxf(total, 0.0), 160.0)
	var id := add_source(label, at, "corium", {"corium": surface}, discovered)
	var source := get_source(id)
	source.reserve_corium = maxf(0.0, total - surface)
	source.surface_capacity = 160.0
	source.initial = maxf(0.0, total)
	source.seep_phase = "seeping" if active else "dormant"
	source.phase_left = SEEP_ACTIVE_S if active else _dormant_duration(id)
	_update_visual(source)
	return id

func add_source(label: String, at: Vector3, kind: String, materials: Dictionary, discovered := false, metadata: Dictionary = {}) -> int:
	if TerrainNavGrid.has_query_grid():
		var ground_y := TerrainNavGrid.sample_query_height(at.x, at.z)
		if ground_y > TerrainNavGrid.IMPASSABLE * 0.5:
			at.y = ground_y
	var source := {"id": _next_id, "label": label, "position": at, "kind": kind, "materials": {"corium": maxf(0.0, float(materials.get("corium", 0))), "plasteel": maxf(0.0, float(materials.get("plasteel", 0)))}, "discovered": discovered}
	source["initial"] = float(source.materials.corium) + float(source.materials.plasteel)
	source.merge(metadata)
	if kind == "corium":
		source.merge({"reserve_corium": 0.0, "surface_capacity": maxf(160.0, float(source.materials.corium)), "seep_phase": "seeping", "phase_left": SEEP_ACTIVE_S, "hazard_radius": CORIUM_HAZARD_RADIUS_M})
	_next_id += 1
	sources.append(source)
	_spawn_visual(source)
	return int(source.id)

func get_source(id: int) -> Dictionary:
	for source in sources:
		if int(source.id) == id:
			return source
	return {}

func remaining(source: Dictionary) -> float:
	if source.is_empty():
		return 0.0
	return float(source.materials.corium) + float(source.materials.plasteel) + float(source.get("reserve_corium", 0.0))

func available(source: Dictionary) -> float:
	if source.is_empty() or (str(source.kind) == "corium" and str(source.get("seep_phase", "seeping")) != "seeping"):
		return 0.0
	return float(source.materials.corium) + float(source.materials.plasteel)

func source_status(source: Dictionary) -> String:
	if remaining(source) <= 0.01:
		return "EXHAUSTED • permanently depleted" if str(source.get("kind", "")) == "corium" else "EXHAUSTED"
	if str(source.kind) != "corium":
		return "RECOVERABLE CARGO" if str(source.kind) == "cargo" else "PLASTEEL SALVAGE"
	if str(source.get("seep_phase", "seeping")) == "dormant":
		return "DORMANT • next seep in %d s" % ceili(float(source.get("phase_left", 0.0)))
	return "SEEPING • exposed corium hazard"

func discovered_sources() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source in sources:
		if bool(source.discovered) and remaining(source) > 0.01:
			result.append(source.duplicate(true))
	return result

func corium_overview(origin: Vector3) -> Dictionary:
	var result := {"sites": 0, "remaining": 0.0, "nearest_m": INF, "exhausted": 0}
	for source in sources:
		if not bool(source.discovered) or str(source.kind) != "corium":
			continue
		var stock := remaining(source)
		if stock <= 0.01:
			result.exhausted += 1
			continue
		result.sites += 1
		result.remaining += stock
		result.nearest_m = minf(float(result.nearest_m), origin.distance_to(source.position))
	return result

func plasteel_overview(origin: Vector3) -> Dictionary:
	var result := {"sites": 0, "remaining": 0.0, "nearest_m": INF}
	for source in sources:
		var stock := float(source.materials.plasteel)
		if not bool(source.discovered) or stock <= 0.01:
			continue
		result.sites += 1
		result.remaining += stock
		result.nearest_m = minf(float(result.nearest_m), origin.distance_to(source.position))
	return result

func _dormant_duration(id: int) -> float:
	return 55.0 + float((id * 17) % 36)

func _advance_seeps(delta: float) -> void:
	for source in sources:
		if str(source.kind) != "corium":
			continue
		if remaining(source) <= 0.01:
			source.seep_phase = "exhausted"
			source.phase_left = 0.0
			continue
		var time_left := maxf(0.0, delta)
		while time_left > 0.00001:
			var step := minf(time_left, maxf(0.0, float(source.phase_left)))
			if str(source.seep_phase) == "seeping":
				var seeped := minf(float(source.reserve_corium), minf(SEEP_FLOW_RATE * step, maxf(0.0, float(source.surface_capacity) - float(source.materials.corium))))
				source.reserve_corium -= seeped
				source.materials.corium += seeped
			source.phase_left -= step
			time_left -= step
			if float(source.phase_left) <= 0.00001:
				source.seep_phase = "dormant" if str(source.seep_phase) == "seeping" else "seeping"
				source.phase_left = _dormant_duration(int(source.id)) if str(source.seep_phase) == "dormant" else SEEP_ACTIVE_S

func corium_exposure_at(at: Vector3) -> float:
	var exposure := 0.0
	for source in sources:
		if str(source.kind) != "corium" or str(source.get("seep_phase", "seeping")) != "seeping" or remaining(source) <= 0.01:
			continue
		var offset: Vector3 = at - source.position
		if absf(offset.y) > 6.0:
			continue
		var radius := float(source.get("hazard_radius", CORIUM_HAZARD_RADIUS_M))
		exposure = maxf(exposure, 1.0 - smoothstep(radius * 0.25, radius, Vector2(offset.x, offset.z).length()))
	return exposure

func _apply_corium_hazards(delta: float) -> void:
	var seen: Dictionary = {}
	for group in ["ground_vehicles", "friendlies", "enemies", "aircraft"]:
		for unit in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(unit) or not unit is Node3D or unit.is_queued_for_deletion() or seen.has(unit.get_instance_id()) or not unit.has_method("take_damage"):
				continue
			seen[unit.get_instance_id()] = true
			var protection := 0.0
			if unit.has_method("corium_exposure_resistance"):
				protection = clampf(float(unit.corium_exposure_resistance()), 0.0, 1.0)
			var damage := CORIUM_DAMAGE_PER_S * delta * corium_exposure_at(unit.global_position) * (1.0 - protection)
			if damage > 0.0:
				unit.take_damage(damage)

func extract(id: int, budget: float, collector: Node3D) -> Dictionary:
	var result := {"corium": 0.0, "plasteel": 0.0}
	var source := get_source(id)
	if source.is_empty() or not bool(source.discovered) or available(source) <= 0.01 or not is_instance_valid(collector) or collector.global_position.distance_to(source.position) > 10.0 or not collector.has_method("can_extract") or not collector.can_extract():
		return result
	budget = minf(maxf(budget, 0), maxf(0, collector.CAPACITY - collector.cargo_total()))
	for material in ["corium", "plasteel"]:
		var taken := minf(budget, float(source.materials[material]))
		var accepted: float = collector.load_cargo(material, taken)
		source.materials[material] -= accepted
		result[material] = accepted
		budget -= accepted
	if str(source.kind) == "corium" and remaining(source) <= 0.01:
		source.seep_phase = "exhausted"
		source.phase_left = 0.0
	_update_visual(source)
	return result

func _spawn_visual(source: Dictionary) -> void:
	if get_tree().current_scene == null:
		return
	var root: Node3D = CORIUM_VISUAL.new() if str(source.kind) == "corium" else Node3D.new()
	root.name = "ResourceSource_%d" % int(source.id)
	get_tree().current_scene.add_child(root)
	root.global_position = source.position
	root.add_to_group("resource_sources")
	_visuals[int(source.id)] = root
	if str(source.kind) == "corium":
		root.setup(int(source.id))
		_update_visual(source)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(source.id) * 1739
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("667a7b")
	mat.roughness = 0.88
	for i in range(11):
		var part := MeshInstance3D.new()
		var scrap := BoxMesh.new()
		scrap.size = Vector3(rng.randf_range(0.4, 1.4), rng.randf_range(0.2, 0.8), rng.randf_range(0.6, 1.7))
		part.mesh = scrap
		part.material_override = mat
		part.position = Vector3(rng.randf_range(-2, 2), 0.35, rng.randf_range(-2, 2))
		part.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
		root.add_child(part)
	if str(source.kind) == "ruin":
		var variant := clampi(int(source.get("ruin_variant", 0)), 0, SALVAGE_VARIANTS.size() - 1)
		var ruin := (load(str(SALVAGE_VARIANTS[variant].scene)) as PackedScene).instantiate() as Node3D
		var wreck_at: Vector3 = source.get("wreck_position", source.position + Vector3(12, 0, -12))
		if not source.has("wreck_position") and TerrainNavGrid.has_query_grid():
			var height := TerrainNavGrid.sample_query_height(wreck_at.x, wreck_at.z)
			if height > TerrainNavGrid.IMPASSABLE * 0.5:
				wreck_at.y = height
		ruin.position = wreck_at - source.position
		ruin.rotation.y = float(source.get("wreck_yaw", 0.0))
		root.add_child(ruin)
		source["wreck_position"] = ruin.global_position
	_update_visual(source)

func _update_visual(source: Dictionary) -> void:
	var root := _visuals.get(int(source.id)) as Node3D
	if not is_instance_valid(root):
		return
	if root.has_method("update_source"):
		root.update_source(source)
		return
	var fraction := remaining(source) / maxf(1.0, float(source.initial))
	for child in root.get_children():
		if child is MeshInstance3D:
			child.visible = fraction > 0.001
			child.scale = Vector3.ONE * maxf(0.1, pow(fraction, 0.3333))

func capture_save_state() -> Dictionary:
	return {"sources": sources.duplicate(true), "next_id": _next_id, "seeded": seeded,
		"seed_origin": _seed_origin, "seed_origin_set": _seed_origin_set,
		"seed_cursor": _seed_cursor, "seed_attempts": _seed_attempts.duplicate(),
		"seed_turn": _seed_turn,
		"salvage_seeded": _salvage_seeded, "salvage_cursor": _salvage_cursor,
		"salvage_attempts": _salvage_attempts.duplicate()}

func restore_save_state(state: Dictionary) -> void:
	reset()
	seeded = bool(state.get("seeded", false))
	_seed_origin = state.get("seed_origin", Vector3.ZERO)
	_seed_origin_set = bool(state.get("seed_origin_set", false))
	_seed_cursor = posmod(int(state.get("seed_cursor", 0)), SEED_SITE_COUNT)
	_seed_turn = bool(state.get("seed_turn", false))
	_seed_attempts.resize(SEED_SITE_COUNT)
	_seed_attempts.fill(0)
	var attempts: Array = state.get("seed_attempts", [])
	for index in range(mini(SEED_SITE_COUNT, attempts.size())):
		_seed_attempts[index] = maxi(0, int(attempts[index]))
	_salvage_seeded = bool(state.get("salvage_seeded", false))
	_salvage_cursor = posmod(int(state.get("salvage_cursor", 0)), SALVAGE_SITE_COUNT)
	_salvage_attempts.resize(SALVAGE_SITE_COUNT)
	_salvage_attempts.fill(0)
	var salvage_attempts: Array = state.get("salvage_attempts", [])
	for index in range(mini(SALVAGE_SITE_COUNT, salvage_attempts.size())):
		_salvage_attempts[index] = maxi(0, int(salvage_attempts[index]))
	_next_id = int(state.get("next_id", 1))
	for entry in state.get("sources", []):
		if not entry is Dictionary or not entry.get("position") is Vector3 or not entry.get("materials") is Dictionary:
			continue
		var source: Dictionary = entry.duplicate(true)
		for material in ["corium", "plasteel"]:
			source.materials[material] = maxf(0.0, float(source.materials.get(material, 0.0)))
		source["initial"] = float(source.get("initial", float(source.materials.corium) + float(source.materials.plasteel)))
		if str(source.get("kind", "")) == "corium":
			# Legacy deposits gain a cycle, without gaining any resource.
			source["reserve_corium"] = maxf(0.0, float(source.get("reserve_corium", 0.0)))
			source["surface_capacity"] = maxf(160.0, float(source.get("surface_capacity", source.materials.corium)))
			source["seep_phase"] = str(source.get("seep_phase", "seeping"))
			if not str(source.seep_phase) in ["seeping", "dormant", "exhausted"] or (str(source.seep_phase) == "exhausted" and remaining(source) > 0.01):
				source.seep_phase = "seeping"
			source["phase_left"] = maxf(0.0, float(source.get("phase_left", SEEP_ACTIVE_S)))
			source["hazard_radius"] = CORIUM_HAZARD_RADIUS_M
			if remaining(source) <= 0.01:
				source.seep_phase = "exhausted"
				source.phase_left = 0.0
		sources.append(source)
		_next_id = maxi(_next_id, int(source.id) + 1)
		_spawn_visual(source)

func reset() -> void:
	for node in _visuals.values():
		if is_instance_valid(node):
			node.queue_free()
	_visuals.clear()
	sources.clear()
	_next_id = 1
	seeded = false
	_seed_origin = Vector3.ZERO
	_seed_origin_set = false
	_seed_cursor = 0
	_seed_attempts.clear()
	_salvage_seeded = false
	_salvage_cursor = 0
	_salvage_attempts.clear()
	_seed_turn = false
	_poll = 0.0
	_hazard_poll = 0.0
	_visual_poll = 0.0

func apply_origin_shift(offset: Vector3) -> void:
	if _seed_origin_set:
		_seed_origin -= offset
	for source in sources:
		source.position -= offset
		if source.get("wreck_position") is Vector3:
			source.wreck_position -= offset
