extends Node

## Authoritative carrier damage/repair state. UI and previews never own it.
signal changed
signal carrier_lost

const LABELS := {"flight": "Flight deck", "catapults": "Catapults", "hangar": "Hangar", "elevators": "Elevators", "island": "Island / sensors", "vehicle_bay": "Vehicle bay", "reactor": "Reactor / power", "replicator": "Replicator", "habitation": "Habitation", "defenses": "Defenses", "drive": "Drive / treads", "stores": "Stores"}
const MESH_REGIONS := {"flight deck": "flight", "catapult 1": "catapults", "catapult 2": "catapults", "hangar": "hangar", "elevators": "elevators", "superstructure main island": "island", "superstructure floor lower": "island", "superstructure floor upper": "island", "vehicle bay": "vehicle_bay", "reactor": "reactor", "power banks": "reactor", "replicator": "replicator", "habitation": "habitation", "storage": "stores"}
const DOCTRINES := ["SURVIVAL", "FLIGHT OPS", "MOBILITY", "DEFENSES"]
const HIT_VOLUME_LAYER := 1 << 19
@export var max_structure: float = 2000.0
@export var armor: float = 20.0
@export var subsystem_damage_scale: float = 0.3
@export var incident_threshold: float = 40.0
var structure: float = 2000.0
var lost: bool = false
var systems: Dictionary = {}
var doctrine: String = "SURVIVAL"
var urgent: String = ""
var repair_reserve: float = 100.0
var repairs_enabled: bool = true
var teams: Array[Dictionary] = [{"name": "ALPHA", "job": "", "task": "Standing by"}, {"name": "BRAVO", "job": "", "task": "Standing by"}]
var last_event: String = "Damage-control teams standing by."
var _regions: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _tick: float = 0.0
var _geometry_timer: float = 0.0
var _quiet_time: float = 60.0
var _pending_hits: Dictionary = {}
var _processed_hits: Dictionary = {}

func _ready() -> void:
	structure = max_structure
	_rng.randomize()
	for id in LABELS:
		systems[id] = _new_system(LABELS[id], id)
	add_to_group("carrier_damage_control")
	call_deferred("refresh_regions")
	call_deferred("_restore_pending_state")

func _restore_pending_state() -> void:
	if get_parent().has_method("_get_pending_carrier_save_state"):
		var saved: Dictionary = get_parent().call("_get_pending_carrier_save_state")
		if saved.get("damage_control") is Dictionary:
			restore_save_state(saved.damage_control)

func _new_system(label: String, region: String) -> Dictionary:
	return {"label": label, "region": region, "condition": 100.0, "fire": 0.0, "isolated": false, "patch": 0.0}

func _physics_process(delta: float) -> void:
	_tick += delta
	if _tick < 0.25:
		return
	flush_hits()
	advance(_tick)
	_tick = 0.0

func queue_hit(amount: float, position: Vector3, event_id: String) -> void:
	if lost or not is_finite(amount) or amount <= armor:
		return
	if _processed_hits.has(event_id):
		return
	# Impact and blast from the same round count as the strongest component,
	# not two armor deductions and two incident rolls.
	var previous: Dictionary = _pending_hits.get(event_id, {})
	if amount > float(previous.get("amount", 0.0)):
		_pending_hits[event_id] = {"amount": amount, "position": position, "at": Time.get_ticks_msec()}

func flush_hits(force: bool = false) -> void:
	var now := Time.get_ticks_msec()
	for id in _pending_hits.keys():
		var hit: Dictionary = _pending_hits[id]
		if not force and now - int(hit.at) < 100:
			continue
		_pending_hits.erase(id)
		_processed_hits[id] = now
		apply_hit(hit.amount, hit.position)
	for id in _processed_hits.keys():
		if now - int(_processed_hits[id]) > 5000:
			_processed_hits.erase(id)

func apply_hit(amount: float, world_position: Vector3) -> float:
	if lost or not is_finite(amount):
		return 0.0
	var damage := maxf(amount - armor, 0.0)
	if damage <= 0.0:
		return 0.0
	structure = maxf(structure - damage, 0.0)
	_quiet_time = 0.0
	var id := region_at(world_position)
	if not id.is_empty():
		damage_system(id, damage * subsystem_damage_scale)
		if damage >= incident_threshold and _rng.randf() < clampf((damage - incident_threshold + 20.0) / 300.0, 0.0, 0.65):
			systems[id].fire = maxf(float(systems[id].fire), 35.0)
			last_event = "%s: fire reported. Response teams dispatching." % systems[id].label
	else:
		last_event = "Hull hit: %.0f structure lost after armor." % damage
	_check_loss()
	changed.emit()
	return damage

func damage_system(id: String, amount: float) -> void:
	if not systems.has(id) or lost or not is_finite(amount) or amount <= 0.0:
		return
	var s: Dictionary = systems[id]
	var actual := minf(float(s.condition), amount)
	s.condition = maxf(float(s.condition) - actual, 0.0)
	s.patch = minf(float(s.patch) + actual * 0.3, 25.0)
	last_event = "%s damaged: %s." % [s.label, status(id)]
	changed.emit()

func refresh_regions() -> void:
	_regions.clear()
	var carrier := get_parent() as Node3D
	if carrier == null or not carrier.is_inside_tree():
		return
	var inverse := carrier.global_transform.affine_inverse()
	for node in carrier.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var name_key := str(mesh.name).to_lower().replace("_", " ")
		var id := str(MESH_REGIONS.get(name_key, ""))
		var path := str(carrier.get_path_to(mesh)).to_lower()
		if "tread" in path or "track" in path:
			id = "drive"
		var ancestor: Node = mesh
		while ancestor != carrier and ancestor != null:
			if ancestor.has_method("build_turret"):
				if bool(ancestor.call("is_built")) and ancestor.get("built_turret").is_ancestor_of(mesh):
					id = "mount:" + str(carrier.get_path_to(ancestor))
					if not systems.has(id):
						systems[id] = _new_system(str(ancestor.name), "defenses")
				break
			ancestor = ancestor.get_parent()
		if id.is_empty():
			continue
		_regions.append({"id": id, "bounds": (inverse * mesh.global_transform) * mesh.mesh.get_aabb()})
		if id == "island" or id.begins_with("mount:"):
			_add_hit_volume(mesh)
	# Removed/dismantled mounts must not leave phantom fires or repair jobs.
	for id in systems.keys():
		if not str(id).begins_with("mount:"):
			continue
		var site := carrier.get_node_or_null(str(id).trim_prefix("mount:"))
		if site == null or not site.has_method("is_built") or not site.call("is_built"):
			systems.erase(id)

func _add_hit_volume(mesh: MeshInstance3D) -> void:
	if mesh.get_node_or_null("CarrierProjectileHitVolume") != null:
		return
	var bounds := mesh.mesh.get_aabb()
	if bounds.size.length_squared() < 0.0001:
		return
	# Projectile rays already query all layers. Physical aircraft/crew masks do
	# not include this layer, so this must not change deck/walk collision behavior.
	var body := StaticBody3D.new()
	body.name = "CarrierProjectileHitVolume"
	body.collision_layer = HIT_VOLUME_LAYER
	body.collision_mask = 0
	body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size.max(Vector3.ONE * 0.01)
	collision.shape = box
	collision.position = bounds.get_center()
	body.add_child(collision)
	mesh.add_child(body)

func region_at(world_position: Vector3) -> String:
	var point := (get_parent() as Node3D).to_local(world_position)
	var best := 6.0
	var result := ""
	for region in _regions:
		var bounds: AABB = region.bounds
		var nearest := point.clamp(bounds.position, bounds.end)
		var distance := point.distance_to(nearest)
		# Prefer a small local part over a large overlapping compartment.
		var score := distance + minf(bounds.size.length() * 0.002, 0.5)
		if score < best:
			best = score
			result = region.id
	return result

func explosion_sample(point: Vector3) -> Vector3:
	# Damage falloff must use the nearest hull surface, not the carrier's origin.
	var carrier := get_parent() as Node3D
	var local := carrier.to_local(point)
	var best := point
	var distance := INF
	for child in carrier.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D and not child.disabled:
			var relative: Vector3 = child.to_local(point)
			var extent: Vector3 = child.shape.size * 0.5
			var candidate: Vector3 = child.to_global(relative.clamp(-extent, extent))
			if candidate.distance_squared_to(point) < distance:
				distance = candidate.distance_squared_to(point)
				best = candidate
	for region in _regions:
		var bounds: AABB = region.bounds
		var candidate := carrier.to_global(local.clamp(bounds.position, bounds.end))
		if candidate.distance_squared_to(point) < distance:
			distance = candidate.distance_squared_to(point)
			best = candidate
	return best

func status(id: String) -> String:
	if lost:
		return "LOST"
	var s := system_snapshot(id)
	if s.is_empty():
		return "UNAVAILABLE"
	if s.isolated:
		return "ISOLATED"
	if float(s.fire) > 0.0:
		return "FIRE"
	if float(s.condition) <= 30.0:
		return "OFFLINE"
	return "DEGRADED" if float(s.condition) < 75.0 else "OPERATIONAL"

func system_snapshot(id: String) -> Dictionary:
	if id == "hull":
		return {"label": "Structural integrity", "region": "hull", "condition": structure / max_structure * 100.0, "fire": 0.0, "isolated": false, "patch": 0.0}
	if not systems.has(id):
		return {}
	var s: Dictionary = systems[id].duplicate(true)
	if id == "defenses":
		for key in systems:
			if str(key).begins_with("mount:"):
				s.condition = minf(s.condition, systems[key].condition)
				s.fire = maxf(s.fire, systems[key].fire)
	return s

func capability(id: String, component: Node = null) -> float:
	if lost:
		return 0.0
	var value := _local_capability(id)
	if id == "defenses" and is_instance_valid(component):
		var ancestor := component.get_parent()
		while ancestor != null and ancestor != get_parent():
			if ancestor.has_method("build_turret"):
				value = minf(value, _local_capability("mount:" + str(get_parent().get_path_to(ancestor))))
				break
			ancestor = ancestor.get_parent()
	return value

func _local_capability(id: String) -> float:
	if not systems.has(id):
		return 1.0
	var s: Dictionary = systems[id]
	if s.isolated or float(s.fire) > 0.0 or float(s.condition) <= 30.0:
		return 0.0
	return 0.5 if float(s.condition) < 75.0 else 1.0

func set_urgent(id: String) -> void:
	if id == "hull" or systems.has(id):
		urgent = "" if urgent == id else id
		changed.emit()

func set_isolated(id: String, value: bool) -> bool:
	if not systems.has(id) or lost:
		return false
	if not value and float(systems[id].fire) > 0.0:
		return false
	systems[id].isolated = value
	last_event = "%s %s." % [systems[id].label, "isolated; new operations held" if value else "returned to service"]
	changed.emit()
	return true

func advance(delta: float) -> void:
	if lost:
		return
	_quiet_time += delta
	_geometry_timer += delta
	if _geometry_timer >= 2.0:
		_geometry_timer = 0.0
		refresh_regions()
	for id in systems:
		var s: Dictionary = systems[id]
		if float(s.fire) > 0.0:
			if not s.isolated:
				s.fire = minf(float(s.fire) + delta * 0.3, 100.0)
				s.condition = maxf(float(s.condition) - delta * 0.15, 0.0)
				structure = maxf(structure - delta * float(s.fire) / 100.0, 0.0)
	_check_loss()
	if lost:
		return
	var jobs: Array[String] = []
	for id in systems:
		if float(systems[id].fire) > 0.0 or (repairs_enabled and float(systems[id].condition) < 100.0 and _can_repair(id)):
			jobs.append(id)
	if repairs_enabled and structure < max_structure and _can_repair("hull"):
		jobs.append("hull")
	jobs.sort_custom(func(a: String, b: String): return _priority(a) > _priority(b))
	for i in range(teams.size()):
		teams[i].job = ""
		teams[i].task = "Standing by"
		if i >= jobs.size():
			continue
		var id := jobs[i]
		teams[i].job = id
		if id != "hull" and float(systems[id].fire) > 0.0:
			teams[i].task = "Fire suppression"
			systems[id].fire = maxf(float(systems[id].fire) - delta * 2.0, 0.0)
		else:
			_repair(id, delta, teams[i])
	changed.emit()

func _priority(id: String) -> float:
	var s := system_snapshot(id)
	var score := 100.0 - float(s.condition)
	if float(s.fire) > 0.0:
		return 10000.0 + float(s.fire) + (100.0 if not s.isolated else 0.0)
	if id == urgent or (urgent == "defenses" and id.begins_with("mount:")):
		score += 1000.0
	var favored := {"SURVIVAL": ["hull", "reactor", "habitation"], "FLIGHT OPS": ["flight", "catapults", "elevators", "hangar"], "MOBILITY": ["drive"], "DEFENSES": ["defenses"]}
	if favored.get(doctrine, []).has(str(s.region)):
		score += 200.0
	return score

func _manager() -> Node:
	return get_parent().get_node_or_null("CarrierManager")

func _available_material() -> float:
	var manager := _manager()
	return maxf(float(manager.get("plasteel_units")) - repair_reserve, 0.0) if manager != null else 0.0

func _can_repair(id: String) -> bool:
	if id == "hull":
		var carrier := get_parent()
		var speed := absf(float(carrier.call("get_speed"))) if carrier.has_method("get_speed") else 0.0
		return _quiet_time >= 15.0 and speed < 0.5 and _available_material() > 0.0
	return (float(systems[id].condition) < 65.0 and float(systems[id].patch) > 0.0) or _available_material() > 0.0

func _repair(id: String, delta: float, team: Dictionary) -> void:
	if id != "hull" and float(systems[id].condition) < 65.0 and float(systems[id].patch) > 0.0:
		var amount := minf(delta * 1.0, minf(65.0 - float(systems[id].condition), float(systems[id].patch)))
		systems[id].condition += amount
		systems[id].patch -= amount
		team.task = "Emergency patch"
		return
	var missing := max_structure - structure if id == "hull" else 100.0 - float(systems[id].condition)
	var cost := 2.0 if id == "hull" else 1.0
	var amount := minf(missing, minf(delta * (1.0 if id == "hull" else 0.5), _available_material() / cost))
	if amount <= 0.0:
		return
	var manager := _manager()
	manager.set("plasteel_units", float(manager.get("plasteel_units")) - amount * cost)
	if id == "hull":
		structure += amount
	else:
		systems[id].condition += amount
	team.task = "Structural repair" if id == "hull" else "Permanent repair"

func repair_note(id: String) -> String:
	var s := system_snapshot(id)
	if lost:
		return "Carrier lost. Repairs unavailable."
	for team in teams:
		if team.job == id or (id == "defenses" and str(team.job).begins_with("mount:")):
			var estimate := ""
			if team.task == "Fire suppression":
				var target := system_snapshot(str(team.job))
				estimate = " · containment ~%d s" % ceili(float(target.fire) / (2.0 if target.isolated else 1.7))
			elif team.task == "Permanent repair":
				estimate = " · full repair ~%d s if supplied" % ceili((100.0 - float(s.condition)) / 0.5)
			return "Team %s: %s%s" % [team.name, team.task, estimate]
	if float(s.fire) > 0.0:
		return "Fire contained by isolation; awaiting team." if s.isolated else "Fire active; awaiting response team."
	if float(s.condition) >= 100.0:
		return "Return to service when ready." if s.isolated else "No repairs required."
	if not repairs_enabled:
		return "Repairs paused. Fire response remains automatic."
	if id == "hull" and not _can_repair(id) and _available_material() > 0.0:
		return "Stop carrier; structural work starts 15 s after last hit."
	if id != "hull" and _can_repair(id):
		return "Queued for an available response team."
	return "Waiting for plasteel above the repair reserve."

func _check_loss() -> void:
	if structure <= 0.0 and not lost:
		lost = true
		last_event = "CARRIER LOST — structural integrity exhausted."
		for team in teams:
			team.job = ""
			team.task = "Carrier lost"
		carrier_lost.emit()

func capture_save_state() -> Dictionary:
	flush_hits(true)
	return {"version": 1, "structure": structure, "systems": systems.duplicate(true), "doctrine": doctrine, "urgent": urgent, "reserve": repair_reserve, "repairs_enabled": repairs_enabled, "quiet_time": _quiet_time, "rng_state": str(_rng.state)}

func restore_save_state(saved: Dictionary) -> bool:
	if not saved.get("systems") is Dictionary or not is_finite(float(saved.get("structure", NAN))):
		return false
	if not is_finite(float(saved.get("reserve", 100.0))) or not is_finite(float(saved.get("quiet_time", 0.0))):
		return false
	var restored: Dictionary = saved.systems.duplicate(true)
	for id in LABELS:
		if not restored.has(id):
			return false
	for id in restored:
		if not restored[id] is Dictionary:
			return false
		for key in ["condition", "fire", "patch"]:
			if not is_finite(float(restored[id].get(key, NAN))):
				return false
			restored[id][key] = clampf(float(restored[id][key]), 0.0, 100.0)
		if not restored[id].has("isolated") or not restored[id].has("label") or not restored[id].has("region"):
			return false
	systems = restored
	structure = clampf(float(saved.structure), 0.0, max_structure)
	lost = false
	doctrine = str(saved.get("doctrine", "SURVIVAL"))
	if not DOCTRINES.has(doctrine):
		doctrine = "SURVIVAL"
	urgent = str(saved.get("urgent", ""))
	repair_reserve = clampf(float(saved.get("reserve", 100.0)), 0.0, 10000.0)
	repairs_enabled = bool(saved.get("repairs_enabled", true))
	_quiet_time = clampf(float(saved.get("quiet_time", 0.0)), 0.0, 60.0)
	_rng.state = int(saved.get("rng_state", "0"))
	_pending_hits.clear()
	_processed_hits.clear()
	_check_loss()
	changed.emit()
	return true
