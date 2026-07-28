class_name EnemyVirtualFlight
extends Node

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")
## Abstract representation of an enemy flight on the tactical map.
## Moves as data until a friendly asset comes within ACTIVATE_RANGE_M,
## then spawns real aircraft. When they retreat beyond DEACTIVATE_RANGE_M
## from all friendly assets, aircraft are removed and the flight resumes
## as a map marker.
##
## Detection: scans for friendly assets every DETECTION_SCAN_INTERVAL_S.
## Spotted contacts are queued as delayed reports (25–75 s radio delay)
## sent to EnemyOpsManager.receive_intel() when the timer fires.

enum Mission      { PATROL, RTB, LANDED, INTERCEPT }
enum VState       { VIRTUAL, MATERIALIZING, ACTIVE }
enum AircraftRole { FIGHTER, BOMBER }

const ACTIVATE_RANGE_M        := 5500.0
const DEACTIVATE_RANGE_M      := 8000.0
const PATROL_SPEED_MPS        := 82.0
const RTB_SPEED_MPS           := 95.0
const PATROL_ALTITUDE_M       := 680.0
const PATROL_WP_REACH_M       := 350.0   # distance to advance to next waypoint
const PATROL_WP_COUNT         := 6       # waypoints generated per patrol route
const DETECTION_RANGE_M       := 8000.0  # how far the flight can see
const DETECTION_SCAN_INTERVAL_S := 5.0
const REPORT_DELAY_MIN_S      := 25.0    # radio delay range
const REPORT_DELAY_MAX_S      := 75.0
const ACTIVE_CONTACT_SCAN_INTERVAL_S := 2.0
const MAX_MATERIALIZE_SPAWNS_PER_TICK := 1

# Configuration (set before adding to tree)
@export var flight_name:    String       = "XX-01"
@export var aircraft_count: int          = 2
@export var patrol_radius:  float        = 4000.0
@export var faction_color:  Color        = Color.WHITE
@export var role:           AircraftRole = AircraftRole.FIGHTER

# Runtime state
var position:        Vector3 = Vector3.ZERO
var heading:         Vector3 = Vector3(1, 0, 0)
var home_position:   Vector3 = Vector3.ZERO
var mission:         Mission = Mission.PATROL
var vstate:          VState  = VState.VIRTUAL
var active_aircraft: Array[Node3D] = []

var _aircraft_slots:  Array[PackedScene] = []
var _loadout_slots:   Array[String] = []     # "guns", "bombs", or "rockets" per slot
var _active_slot_indices: Array[int] = []
var _patrol_waypoints:  Array[Vector3] = []
var _patrol_wp_idx:     int = 0
var _detection_timer:   float = 0.0
var _active_scan_timer: float = 0.0
var _materialize_next_slot_idx: int = 0
var _materialize_spawned_count: int = 0
# Each report: { "type": String, "position": Vector3, "strength": int, "countdown": float }
var _pending_reports:   Array[Dictionary] = []
var _rng:               RandomNumberGenerator = RandomNumberGenerator.new()


func setup(home_pos: Vector3, aircraft_scenes: Array[PackedScene], loadouts: Array[String], start_angle: float = 0.0) -> void:
	home_position   = home_pos
	_aircraft_slots = aircraft_scenes.duplicate()
	_loadout_slots  = loadouts.duplicate()
	aircraft_count  = _aircraft_slots.size()
	_rng.randomize()
	_generate_patrol_waypoints(start_angle)
	_randomize_initial_patrol_waypoint()
	position = _patrol_waypoints[_patrol_wp_idx] if not _patrol_waypoints.is_empty() else \
		Vector3(home_pos.x + cos(start_angle) * patrol_radius, home_pos.y + PATROL_ALTITUDE_M, home_pos.z + sin(start_angle) * patrol_radius)
	_update_heading_toward_next_patrol_waypoint(start_angle)
	_detection_timer = _rng.randf_range(0.0, DETECTION_SCAN_INTERVAL_S)
	_active_scan_timer = _rng.randf_range(0.0, ACTIVE_CONTACT_SCAN_INTERVAL_S)


func _generate_patrol_waypoints(start_angle: float) -> void:
	_patrol_waypoints.clear()
	for i in range(PATROL_WP_COUNT):
		var angle := start_angle + float(i) * TAU / float(PATROL_WP_COUNT) + _rng.randf_range(-0.38, 0.38)
		var r     := patrol_radius * _rng.randf_range(0.65, 1.15)
		_patrol_waypoints.append(Vector3(
			home_position.x + cos(angle) * r,
			home_position.y + PATROL_ALTITUDE_M,
			home_position.z + sin(angle) * r
		))
	_patrol_wp_idx = 0


func _randomize_initial_patrol_waypoint() -> void:
	if _patrol_waypoints.is_empty():
		_patrol_wp_idx = 0
		return
	_patrol_wp_idx = _rng.randi() % _patrol_waypoints.size()


func _update_heading_toward_next_patrol_waypoint(fallback_angle: float) -> void:
	if _patrol_waypoints.size() <= 1:
		heading = Vector3(-sin(fallback_angle), 0.0, cos(fallback_angle)).normalized()
		return
	var next_idx: int = (_patrol_wp_idx + 1) % _patrol_waypoints.size()
	var to_next: Vector3 = _patrol_waypoints[next_idx] - position
	to_next.y = 0.0
	if to_next.length_squared() <= 1.0:
		heading = Vector3(-sin(fallback_angle), 0.0, cos(fallback_angle)).normalized()
		return
	heading = to_next.normalized()


func tick(delta: float) -> void:
	var _profiler_start: int = FrameProfiler.begin("EnemyVirtualFlight.tick")
	_prune_active_aircraft()

	if vstate == VState.ACTIVE:
		if active_aircraft.is_empty():
			vstate = VState.VIRTUAL
			aircraft_count = 0
			FrameProfiler.end("EnemyVirtualFlight.tick", _profiler_start)
			return
		position = _active_aircraft_centroid()
		_check_dematerialize()
		if vstate != VState.ACTIVE:
			FrameProfiler.end("EnemyVirtualFlight.tick", _profiler_start)
			return
		# Materialized units report immediately — pilots can see and talk
		_tick_active_contact_scan(delta)
		FrameProfiler.end("EnemyVirtualFlight.tick", _profiler_start)
		return

	if vstate == VState.MATERIALIZING:
		if _nearest_player_relevance_distance() > DEACTIVATE_RANGE_M:
			dematerialize()
			FrameProfiler.end("EnemyVirtualFlight.tick", _profiler_start)
			return
		_tick_materialize_step()
		_process_pending_reports(delta)
		FrameProfiler.end("EnemyVirtualFlight.tick", _profiler_start)
		return

	if aircraft_count <= 0:
		FrameProfiler.end("EnemyVirtualFlight.tick", _profiler_start)
		return

	match mission:
		Mission.PATROL:    _tick_patrol(delta)
		Mission.RTB:       _tick_rtb(delta)
		Mission.LANDED:    pass
		Mission.INTERCEPT: _tick_intercept(delta)

	_check_materialize()
	_tick_detection(delta)
	FrameProfiler.end("EnemyVirtualFlight.tick", _profiler_start)


# ── Movement ──────────────────────────────────────────────────────────────────

func _tick_patrol(delta: float) -> void:
	if _patrol_waypoints.is_empty():
		_generate_patrol_waypoints(0.0)
		return
	var target   := _patrol_waypoints[_patrol_wp_idx]
	var to_target := target - position
	if to_target.length() < PATROL_WP_REACH_M:
		_patrol_wp_idx = (_patrol_wp_idx + 1) % _patrol_waypoints.size()
		return
	var dir  := to_target.normalized()
	position += dir * PATROL_SPEED_MPS * delta
	heading   = Vector3(dir.x, 0.0, dir.z)


func _tick_rtb(delta: float) -> void:
	var target   := home_position + Vector3(0.0, PATROL_ALTITUDE_M, 0.0)
	var to_base  := target - position
	if to_base.length() < 250.0:
		mission  = Mission.LANDED
		position = home_position
		return
	var dir  := to_base.normalized()
	position += dir * RTB_SPEED_MPS * delta
	heading   = Vector3(dir.x, 0.0, dir.z).normalized()


func _tick_intercept(delta: float) -> void:
	# Move toward the best known friendly aircraft position from intel,
	# falling back to real-time scan. Once materialized the AI handles it.
	var target := _nearest_friendly_aircraft_position()
	if target == Vector3.INF:
		mission = Mission.PATROL
		return
	var flat_target := Vector3(target.x, position.y, target.z)
	var to_target   := flat_target - position
	if to_target.length() < 600.0:
		return
	var dir  := to_target.normalized()
	position += dir * RTB_SPEED_MPS * delta
	heading   = Vector3(dir.x, 0.0, dir.z)


# ── Detection & reporting ─────────────────────────────────────────────────────

func _tick_detection(delta: float) -> void:
	_detection_timer -= delta
	if _detection_timer <= 0.0:
		_detection_timer = DETECTION_SCAN_INTERVAL_S
		_scan_for_contacts(false)
	_process_pending_reports(delta)


func _scan_for_contacts(immediate: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var delay_s := 0.0 if immediate else _rng.randf_range(REPORT_DELAY_MIN_S, REPORT_DELAY_MAX_S)

	# Carrier
	var carrier := tree.get_first_node_in_group("carrier") as Node3D
	if carrier and is_instance_valid(carrier):
		if position.distance_to(carrier.global_position) <= DETECTION_RANGE_M:
			_queue_report("carrier", carrier.global_position, 1, delay_s)

	# Friendly aircraft
	var friendly_air_pos := Vector3.ZERO
	var friendly_air_count := 0
	for aircraft in _get_friendly_air_nodes():
		if position.distance_to(aircraft.global_position) <= DETECTION_RANGE_M:
			friendly_air_pos += aircraft.global_position
			friendly_air_count += 1
	if friendly_air_count > 0:
		_queue_report("air", friendly_air_pos / float(friendly_air_count), friendly_air_count, delay_s)

	# Friendly ground vehicles
	var friendly_gnd_pos := Vector3.ZERO
	var friendly_gnd_count := 0
	for node in tree.get_nodes_in_group("ground_vehicles"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		if (node as Node3D).is_in_group("enemies"):
			continue
		if position.distance_to((node as Node3D).global_position) <= DETECTION_RANGE_M:
			friendly_gnd_pos += (node as Node3D).global_position
			friendly_gnd_count += 1
	if friendly_gnd_count > 0:
		_queue_report("ground", friendly_gnd_pos / float(friendly_gnd_count), friendly_gnd_count, delay_s)


func _queue_report(contact_type: String, contact_pos: Vector3, strength: int, delay_s: float) -> void:
	# Only one pending report per contact type at a time
	for r in _pending_reports:
		if r["type"] == contact_type:
			# Update position to latest spotted location
			r["position"] = contact_pos
			r["strength"] = strength
			return
	_pending_reports.append({
		"type":      contact_type,
		"position":  contact_pos,
		"strength":  strength,
		"countdown": delay_s,
	})


func _process_pending_reports(delta: float) -> void:
	var sent: Array[int] = []
	for i in range(_pending_reports.size()):
		_pending_reports[i]["countdown"] -= delta
		if _pending_reports[i]["countdown"] <= 0.0:
			var r: Dictionary = _pending_reports[i]
			EnemyOpsManager.receive_intel(flight_name, r["type"], r["position"], r["strength"])
			sent.append(i)
	# Remove in reverse order to preserve indices
	for i in range(sent.size() - 1, -1, -1):
		_pending_reports.remove_at(sent[i])


# ── Materialize / dematerialize ───────────────────────────────────────────────

func _check_materialize() -> void:
	if _aircraft_slots.is_empty() or vstate != VState.VIRTUAL:
		return
	if _should_materialize():
		_begin_materialize()


func _check_dematerialize() -> void:
	if _nearest_player_relevance_distance() > DEACTIVATE_RANGE_M:
		dematerialize()


func _should_materialize() -> bool:
	var player_dist: float = _nearest_player_relevance_distance()
	if player_dist <= ACTIVATE_RANGE_M:
		return true
	if player_dist <= DEACTIVATE_RANGE_M and _nearest_friendly_distance() <= ACTIVATE_RANGE_M:
		return true
	return false


func _begin_materialize() -> void:
	if _aircraft_slots.is_empty() or vstate != VState.VIRTUAL:
		return
	vstate = VState.MATERIALIZING
	_materialize_next_slot_idx = 0
	_materialize_spawned_count = 0
	active_aircraft.clear()
	_active_slot_indices.clear()


func _tick_materialize_step() -> void:
	if vstate != VState.MATERIALIZING:
		return
	var _materialize_profiler_start: int = FrameProfiler.begin("EnemyVirtualFlight.materialize_step")
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		FrameProfiler.end("EnemyVirtualFlight.materialize_step", _materialize_profiler_start)
		return
	var spawned_this_tick: int = 0
	var slot_count: int = _aircraft_slots.size()
	while _materialize_next_slot_idx < slot_count and spawned_this_tick < MAX_MATERIALIZE_SPAWNS_PER_TICK:
		var slot_idx: int = _materialize_next_slot_idx
		_materialize_next_slot_idx += 1
		var scene: PackedScene = _aircraft_slots[slot_idx]
		if scene == null:
			continue
		var ac: Node3D = scene.instantiate() as Node3D
		if ac == null:
			continue
		scene_root.add_child(ac)
		ac.set_meta("faction_color", faction_color)
		var spread := Vector3(
			cos(float(slot_idx) * TAU / float(maxi(slot_count, 1))) * 110.0,
			float(slot_idx) * 30.0,
			sin(float(slot_idx) * TAU / float(maxi(slot_count, 1))) * 110.0
		)
		ac.global_position = position + spread
		if "linear_velocity" in ac:
			ac.set("linear_velocity", heading * 75.0)
		var loadout: String = _loadout_slots[slot_idx] if slot_idx < _loadout_slots.size() else "guns"
		_configure_materialized_enemy_aircraft(ac, loadout)
		active_aircraft.append(ac)
		_active_slot_indices.append(slot_idx)
		_materialize_spawned_count += 1
		spawned_this_tick += 1
	if _materialize_next_slot_idx >= slot_count:
		_finish_materialize()
	FrameProfiler.end("EnemyVirtualFlight.materialize_step", _materialize_profiler_start)


func _finish_materialize() -> void:
	_prune_active_aircraft()
	if active_aircraft.is_empty():
		aircraft_count = 0
		vstate = VState.VIRTUAL
		return
	position = _active_aircraft_centroid()
	vstate = VState.ACTIVE
	_active_scan_timer = 0.0
	_tick_active_contact_scan(ACTIVE_CONTACT_SCAN_INTERVAL_S)
	print("[EnemyVirtualFlight] %s materialized (%d/%d ac) at %.0f,%.0f" % [
		flight_name, active_aircraft.size(), _aircraft_slots.size(), position.x, position.z])


func _strip_enemy_external_stores(ac: Node3D, loadout: String = "guns") -> void:
	for hp in ac.find_children("*", "Hardpoint", true, false):
		var hardpoint := hp as Hardpoint
		if hardpoint == null or hardpoint.weapon_instance == null:
			continue
		var wname := String(hardpoint.weapon_instance.weapon_name)
		var is_bomb   := wname == "Bomb"
		var is_rocket := wname == "Rocket Pod"
		var is_missile := "Missile" in wname
		var should_strip := false
		match loadout:
			"guns":    should_strip = is_bomb or is_rocket or is_missile
			"bombs":   should_strip = is_rocket or is_missile
			"rockets": should_strip = is_bomb or is_missile
		if should_strip:
			hardpoint.weapon_instance.queue_free()
			hardpoint.weapon_instance = null
			hardpoint.mounted_weapon = null
	var cw := ac.find_child("ControlWeapons", true, false) as ControlWeapons
	if cw:
		cw.find_hardpoints()
		cw.categorize_weapons()
		if cw.weapon_types.size() > 0:
			var preferred: String
			match loadout:
				"bombs":   preferred = "Bomb"
				"rockets": preferred = "Rocket Pod"
				_:         preferred = "Guns"
			var idx := cw.weapon_types.find(preferred)
			if idx == -1:
				idx = cw.weapon_types.find("Guns")
			if idx == -1:
				idx = cw.weapon_types.find("Autocannon")
			if idx == -1:
				idx = 0
			cw.selected_weapon_type_index = idx
			cw.selected_weapon_type = cw.weapon_types[idx]


func _configure_materialized_enemy_aircraft(ac: Node3D, loadout: String = "guns") -> void:
	if ac == null or not is_instance_valid(ac):
		return
	if ac.is_in_group("aircraft"):
		ac.remove_from_group("aircraft")
	ac.add_to_group("ai_aircraft")
	ac.add_to_group("enemies")
	if "team" in ac:
		ac.set("team", 2)

	for node_name in ["CameraController", "HeadsUpDisplay", "InstrumentPanel", "ControlTargeting"]:
		var node: Node = ac.find_child(node_name, true, false)
		if node == null:
			continue
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_input(false)
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		elif node is Node3D:
			(node as Node3D).visible = false

	_strip_enemy_external_stores(ac, loadout)

	var ai_toggle: Node = ac.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("enable_ai"):
		ai_toggle.call("enable_ai")

	var ai_pilot := ac.find_child("AIPilot", true, false) as AIPilot
	if ai_pilot:
		ai_pilot.carrier_position = home_position
		ai_pilot.waypoints.clear()
		ai_pilot.engagement_radius_from_carrier_m = 0.0
		ai_pilot.skill = AIPilot.AIPilotSkill.ROOKIE
		var is_strike := loadout in ["bombs", "rockets"]
		if is_strike:
			ai_pilot.dogfight_enabled = false
			ai_pilot.dogfight_proximity_override_m = 0.0
			ai_pilot.ground_attack_enabled = true
		else:
			ai_pilot.dogfight_enabled = true
			ai_pilot.ground_attack_enabled = false
		ai_pilot.apply_skill_preset()
		var initial_state := AIPilot.State.DOGFIGHT \
			if (not is_strike and mission == Mission.INTERCEPT) \
			else AIPilot.State.SEARCH
		ai_pilot.change_state(initial_state)


func dematerialize() -> void:
	var was_materializing: bool = vstate == VState.MATERIALIZING
	_prune_active_aircraft()
	var remaining_scenes: Array[PackedScene] = []
	var remaining_loadouts: Array[String] = []
	for slot_idx: int in _active_slot_indices:
		if slot_idx >= 0 and slot_idx < _aircraft_slots.size():
			remaining_scenes.append(_aircraft_slots[slot_idx])
			remaining_loadouts.append(_loadout_slots[slot_idx] if slot_idx < _loadout_slots.size() else "guns")
	if not active_aircraft.is_empty():
		position = _active_aircraft_centroid()
	for ac in active_aircraft:
		if is_instance_valid(ac):
			ac.queue_free()
	active_aircraft.clear()
	_active_slot_indices.clear()
	if vstate != VState.VIRTUAL:
		if not was_materializing:
			_aircraft_slots = remaining_scenes
			_loadout_slots = remaining_loadouts
		aircraft_count = _aircraft_slots.size()
	_materialize_next_slot_idx = 0
	_materialize_spawned_count = 0
	vstate = VState.VIRTUAL
	mission = Mission.RTB
	print("[EnemyVirtualFlight] %s dematerialized → RTB" % flight_name)


# ── Loadout helpers ───────────────────────────────────────────────────────────

func _has_strike_weapons(ac: Node3D) -> bool:
	var cw: Node = ac.find_child("ControlWeapons", true, false)
	if cw == null or not ("weapon_types" in cw):
		return false
	for wt in cw.weapon_types:
		if wt in ["Bomb", "Rocket Pod"]:
			return true
	return false


# ── Proximity helpers ─────────────────────────────────────────────────────────

func _nearest_friendly_distance() -> float:
	var tree := get_tree()
	if tree == null:
		return INF
	var best_sq := INF
	var carrier := tree.get_first_node_in_group("carrier") as Node3D
	if carrier and is_instance_valid(carrier):
		best_sq = minf(best_sq, position.distance_squared_to(carrier.global_position))
	for aircraft in _get_friendly_air_nodes():
		best_sq = minf(best_sq, position.distance_squared_to(aircraft.global_position))
	for node in tree.get_nodes_in_group("ground_vehicles"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		if (node as Node3D).is_in_group("enemies"):
			continue
		best_sq = minf(best_sq, position.distance_squared_to((node as Node3D).global_position))
	return sqrt(best_sq)


func _nearest_player_relevance_distance() -> float:
	var player_node: Node3D = _get_player_relevance_node()
	if player_node != null and is_instance_valid(player_node):
		return position.distance_to(player_node.global_position)
	return _nearest_friendly_distance()


func _get_player_relevance_node() -> Node3D:
	var camera_node: Node3D = _get_active_camera_relevance_node()
	if camera_node != null and is_instance_valid(camera_node):
		return camera_node
	var flight_director: Node = get_node_or_null("/root/FlightDirector")
	if flight_director != null:
		var controlled_value: Variant = flight_director.get("player_controlled_plane")
		if controlled_value is Node3D and is_instance_valid(controlled_value):
			return controlled_value as Node3D
		var viewed_value: Variant = flight_director.get("current_viewed_aircraft")
		if viewed_value is Node3D and is_instance_valid(viewed_value):
			return viewed_value as Node3D
	return null


func _get_active_camera_relevance_node() -> Node3D:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		var camera: Camera3D = viewport.get_camera_3d()
		if camera != null and is_instance_valid(camera):
			var node: Node = camera
			while node != null:
				if node is Node3D and _is_player_relevance_root(node):
					return node as Node3D
				node = node.get_parent()
			return camera
	return null


func _is_player_relevance_root(node: Node) -> bool:
	return node.is_in_group("aircraft") \
		or node.is_in_group("ai_aircraft") \
		or node.is_in_group("ground_vehicles") \
		or node.is_in_group("carrier") \
		or node.is_in_group("friendlies")


func _tick_active_contact_scan(delta: float) -> void:
	_active_scan_timer -= delta
	if _active_scan_timer > 0.0:
		return
	_active_scan_timer = ACTIVE_CONTACT_SCAN_INTERVAL_S
	_scan_for_contacts(true)


func _prune_active_aircraft() -> void:
	if active_aircraft.is_empty():
		_active_slot_indices.clear()
		return
	var kept_aircraft: Array[Node3D] = []
	var kept_slots: Array[int] = []
	for i in range(active_aircraft.size()):
		var aircraft: Node3D = active_aircraft[i]
		if not is_instance_valid(aircraft):
			continue
		kept_aircraft.append(aircraft)
		if i < _active_slot_indices.size():
			kept_slots.append(_active_slot_indices[i])
	active_aircraft = kept_aircraft
	_active_slot_indices = kept_slots


func _active_aircraft_centroid() -> Vector3:
	var count: int = 0
	var sum: Vector3 = Vector3.ZERO
	for aircraft: Node3D in active_aircraft:
		if not is_instance_valid(aircraft):
			continue
		sum += aircraft.global_position
		count += 1
	if count <= 0:
		return position
	return sum / float(count)


func _nearest_friendly_aircraft_position() -> Vector3:
	var best_sq  := INF
	var best_pos := Vector3.INF
	for aircraft in _get_friendly_air_nodes():
		var sq := position.distance_squared_to(aircraft.global_position)
		if sq < best_sq:
			best_sq  = sq
			best_pos = aircraft.global_position
	return best_pos


func _get_friendly_air_nodes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var tree := get_tree()
	if tree == null:
		return result
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft", "friendlies"]:
		for node in tree.get_nodes_in_group(group_name):
			if not is_instance_valid(node) or not (node is Node3D):
				continue
			var aircraft := node as Node3D
			if aircraft.is_in_group("enemies"):
				continue
			var id := aircraft.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			result.append(aircraft)
	return result


# ── Origin shift ──────────────────────────────────────────────────────────────

func apply_origin_shift(offset: Vector3) -> void:
	position      -= offset
	home_position -= offset
	for i in range(_patrol_waypoints.size()):
		_patrol_waypoints[i] -= offset
	for r in _pending_reports:
		r["position"] = (r["position"] as Vector3) - offset
