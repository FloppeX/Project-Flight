extends AircraftModule
class_name AircraftModule_ControlTargeting

@export var fov_cone_deg: float = 60.0
@export var max_range_m: float = 3000.0
@export var targeting_update_rate_hz: float = 5.0
@export var auto_target_when_none: bool = false
@export var auto_replace_target: bool = false
@export var relaxed_lock_when_none: bool = false
@export var manual_cycle_range_m: float = 3500.0
@export var enable_legacy_keyboard_shortcuts: bool = false
@export var external_target_authority: bool = false

signal target_changed(previous_target: Node3D, current_target: Node3D)

var _time_accum: float = 0.0
var current_target: Node3D
var _destroyed_connection: Callable = Callable()
@export var debug_enabled: bool = false

func _ready():
	ReceiveInput = true
	ProcessPhysics = true
	ModuleType = "targeting"

func receive_input(event):
	if event != null and event.is_action_pressed("target_closest_ahead", false, true):
		target_closest_ahead()
		return
	if event != null and event.is_action_pressed("target_next", false, true):
		target_next()
		return
	if event != null and event.is_action_pressed("target_prev", false, true):
		target_prev()
		return

	if event is InputEventJoypadButton and event.pressed:
		var button_event: InputEventJoypadButton = event as InputEventJoypadButton
		if button_event.button_index == JOY_BUTTON_DPAD_RIGHT:
			target_next()
			return
		if button_event.button_index == JOY_BUTTON_DPAD_LEFT:
			target_prev()
			return
		if button_event.button_index == JOY_BUTTON_DPAD_DOWN:
			target_closest_ahead()
			return

	if not enable_legacy_keyboard_shortcuts:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			Key.KEY_E:
				target_next()
				return
			Key.KEY_Q:
				target_prev()
				return
			Key.KEY_X:
				clear_target()
				return

func process_physic_frame(delta):
	if current_target != null and not _is_live_target(current_target):
		set_target(null)
	if external_target_authority:
		return
	# Manual selection is the player-facing default. Avoid both the global target
	# scan and any unrequested selection while no auto mode is enabled.
	if not auto_target_when_none and not auto_replace_target:
		return
	_time_accum += delta
	var interval = 1.0 / max(targeting_update_rate_hz, 0.1)
	if _time_accum >= interval:
		_time_accum = 0.0
		_update_best_target_if_needed()

func _update_best_target_if_needed():
	if not is_instance_valid(aircraft):
		return
	if _is_live_target(current_target) and not auto_replace_target:
		return
	if not auto_target_when_none and not auto_replace_target:
		return
	var enemies: Array[Node3D] = _get_hostile_targets()
	# Filter by cone and range
	var forward: Vector3 = aircraft.global_transform.basis.z
	var origin: Vector3 = aircraft.global_position
	var cos_half := cos(deg_to_rad(fov_cone_deg * 0.5))
	var candidates := []
	for e in enemies:
		if not (e and is_instance_valid(e)):
			continue
		var to_vec: Vector3 = (e.global_position - origin)
		var dist := to_vec.length()
		if dist <= max_range_m and dist > 0.1:
			var dir: Vector3 = to_vec.normalized()
			var dotv: float = forward.dot(dir)
			if debug_enabled:
				print("[Targeting] cand ", e.name, " dist=", int(dist), " dot=", "%.2f" % dotv)
			if dotv >= cos_half:
				candidates.append({"node": e, "dist": dist})
	if candidates.size() == 0:
		if not auto_target_when_none or not relaxed_lock_when_none:
			return
		# Fall back to nearest enemy in range (ignore cone) so we always get a target
		var nearest: Node3D = null
		var best_dist: float = max_range_m
		for e2 in enemies:
			if e2 and is_instance_valid(e2):
				var d2 = (e2.global_position - origin).length()
				if d2 < best_dist:
					best_dist = d2
					nearest = e2
		if nearest:
			set_target(nearest)
			if debug_enabled:
				print("[Targeting] relaxed selected ", current_target.name, " dist=", int(best_dist))
		return
	# Select nearest in-cone
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"]) 
	if auto_target_when_none or auto_replace_target:
		var new_target = candidates[0]["node"]
		set_target(new_target)
		if debug_enabled:
			print("[Targeting] selected ", current_target.name)

func set_target(new_target: Node3D):
	"""Sets the current target and handles signal connections."""
	if new_target != null and not _is_live_target(new_target):
		new_target = null

	if new_target == current_target:
		return

	var previous_target: Node3D = current_target if is_instance_valid(current_target) else null
	_disconnect_destroyed_signal()
	current_target = new_target
	if is_instance_valid(current_target) and current_target.has_signal("destroyed"):
		# Some targets emit destroyed(target), while older test/aircraft targets emit
		# destroyed() with no arguments. Binding the selected target supports both.
		_destroyed_connection = Callable(self, "on_target_destroyed").bind(current_target)
		if not current_target.is_connected("destroyed", _destroyed_connection):
			current_target.connect("destroyed", _destroyed_connection)
	target_changed.emit(previous_target, current_target)

func on_target_destroyed(emitted_target: Variant = null, bound_target: Node3D = null):
	"""Callback function for when a target is destroyed."""
	var destroyed_target := bound_target
	if destroyed_target == null and emitted_target is Node3D:
		destroyed_target = emitted_target as Node3D
	if debug_enabled:
		print("[Targeting] Target destroyed signal received from: ", destroyed_target)
	if destroyed_target == current_target:
		clear_target()
		if debug_enabled:
			print("[Targeting] Current target was destroyed. Target cleared.")


func _disconnect_destroyed_signal() -> void:
	if is_instance_valid(current_target) and current_target.has_signal("destroyed") \
			and _destroyed_connection.is_valid() \
			and current_target.is_connected("destroyed", _destroyed_connection):
		current_target.disconnect("destroyed", _destroyed_connection)
	_destroyed_connection = Callable()

func target_next():
	if external_target_authority:
		return
	_cycle_target(1)

func target_prev():
	if external_target_authority:
		return
	_cycle_target(-1)

func target_closest_ahead() -> bool:
	if external_target_authority or not is_instance_valid(aircraft):
		return false
	var aircraft_node := aircraft as Node3D
	if aircraft_node == null:
		return false
	var forward: Vector3 = aircraft_node.global_transform.basis.z.normalized()
	var cos_half_cone: float = cos(deg_to_rad(maxf(fov_cone_deg, 0.0) * 0.5))
	var best_target: Node3D = null
	var best_distance := INF
	for candidate in _get_radar_visible_hostile_candidates():
		var target := candidate.get("node") as Node3D
		if not _is_live_target(target):
			continue
		var to_target: Vector3 = target.global_position - aircraft_node.global_position
		var distance: float = to_target.length()
		if distance <= 0.1 or forward.dot(to_target / distance) < cos_half_cone:
			continue
		if distance < best_distance:
			best_distance = distance
			best_target = target
	if not is_instance_valid(best_target):
		return false
	set_target(best_target)
	return true

func clear_target():
	set_target(null)

func _cycle_target(direction: int):
	if not is_instance_valid(aircraft):
		return
	var candidates := _get_radar_visible_hostile_candidates()
	if candidates.is_empty():
		return
	candidates.sort_custom(_cycle_candidate_less)
	if not _is_live_target(current_target):
		set_target(_closest_to_nose(candidates))
		return

	var current_index := -1
	for i in range(candidates.size()):
		if candidates[i].get("node") == current_target:
			current_index = i
			break
	if current_index >= 0:
		var next_index := posmod(current_index + (1 if direction >= 0 else -1), candidates.size())
		set_target(candidates[next_index].get("node") as Node3D)
		return

	# The retained target may be beyond the current cycle range. Use its bearing
	# as the anchor instead of unexpectedly jumping to the nearest contact.
	var anchor_bearing := _signed_bearing_to(current_target)
	if direction >= 0:
		for candidate in candidates:
			if float(candidate.get("bearing", 0.0)) > anchor_bearing + 0.0001:
				set_target(candidate.get("node") as Node3D)
				return
		set_target(candidates[0].get("node") as Node3D)
		return
	for i in range(candidates.size() - 1, -1, -1):
		if float(candidates[i].get("bearing", 0.0)) < anchor_bearing - 0.0001:
			set_target(candidates[i].get("node") as Node3D)
			return
	set_target(candidates[-1].get("node") as Node3D)


func _get_radar_visible_hostile_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if not is_instance_valid(aircraft):
		return candidates
	var aircraft_node := aircraft as Node3D
	if aircraft_node == null:
		return candidates
	var origin: Vector3 = aircraft_node.global_position
	var radar_range_m: float = _get_radar_display_range_m()
	var radar_range_sq: float = radar_range_m * radar_range_m
	for target in _get_hostile_targets():
		if not _is_live_target(target):
			continue
		var to_target: Vector3 = target.global_position - origin
		var flat_distance_sq: float = Vector2(to_target.x, to_target.z).length_squared()
		# RadarCanvas is a heading-up, top-down display and applies this same flat
		# range gate before drawing a contact. Manual selection must never reveal a
		# target that is outside that display.
		if flat_distance_sq > radar_range_sq or to_target.length_squared() <= 0.01:
			continue
		candidates.append({
			"node": target,
			"dist": to_target.length(),
			"bearing": _signed_bearing_to(target),
			"id": target.get_instance_id(),
		})
	return candidates


func _get_radar_display_range_m() -> float:
	var radar: Node = (aircraft as Node).find_child("RadarCanvas", true, false) \
			if is_instance_valid(aircraft) else null
	if radar != null and is_instance_valid(radar) and "terrain_map_range_m" in radar:
		return maxf(float(radar.get("terrain_map_range_m")), 0.0)
	return maxf(manual_cycle_range_m, 0.0)


func _get_hostile_targets() -> Array[Node3D]:
	var targets: Array[Node3D] = []
	if not is_instance_valid(aircraft):
		return targets
	var sources: Array = []
	var team_id: int = int(aircraft.call("get_team")) if aircraft.has_method("get_team") else 1
	var registry: Node = get_node_or_null("/root/EnemyRegistry")
	if registry != null and registry.has_method("get_enemies_for_team"):
		sources.append_array(registry.call("get_enemies_for_team", 1 if team_id != 1 else 2) as Array)
	var tree := get_tree()
	if tree != null:
		sources.append_array(tree.get_nodes_in_group("enemies"))
	var seen: Dictionary = {}
	for source in sources:
		var candidate := source as Node3D
		if not _is_hostile_candidate(candidate, team_id):
			continue
		var id := candidate.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		targets.append(candidate)
	return targets


func _is_hostile_candidate(candidate: Node3D, own_team_id: int) -> bool:
	if not _is_live_target(candidate) or candidate == aircraft:
		return false
	if candidate.has_method("get_team") and int(candidate.call("get_team")) == own_team_id:
		return false
	return candidate.is_in_group("enemies") or candidate.has_method("get_team")


func _is_live_target(target: Variant) -> bool:
	if target == null or not is_instance_valid(target) or not (target is Node3D):
		return false
	var target_node := target as Node3D
	if target_node.is_queued_for_deletion():
		return false
	if "is_destroyed" in target_node and bool(target_node.get("is_destroyed")):
		return false
	if "is_dying" in target_node and bool(target_node.get("is_dying")):
		return false
	return true


func _signed_bearing_to(target: Node3D) -> float:
	if not is_instance_valid(aircraft) or not _is_live_target(target):
		return 0.0
	var to_target: Vector3 = target.global_position - aircraft.global_position
	var right: Vector3 = aircraft.global_transform.basis.x.normalized()
	var forward: Vector3 = aircraft.global_transform.basis.z.normalized()
	return atan2(to_target.dot(right), to_target.dot(forward))


func _cycle_candidate_less(a: Dictionary, b: Dictionary) -> bool:
	var bearing_a := float(a.get("bearing", 0.0))
	var bearing_b := float(b.get("bearing", 0.0))
	if not is_equal_approx(bearing_a, bearing_b):
		return bearing_a < bearing_b
	var dist_a := float(a.get("dist", INF))
	var dist_b := float(b.get("dist", INF))
	if not is_equal_approx(dist_a, dist_b):
		return dist_a < dist_b
	return int(a.get("id", 0)) < int(b.get("id", 0))


func _closest_to_nose(candidates: Array[Dictionary]) -> Node3D:
	var best: Node3D = null
	var best_abs_bearing := INF
	var best_distance := INF
	for candidate in candidates:
		var abs_bearing := absf(float(candidate.get("bearing", 0.0)))
		var distance := float(candidate.get("dist", INF))
		if abs_bearing < best_abs_bearing - 0.0001 \
				or (is_equal_approx(abs_bearing, best_abs_bearing) and distance < best_distance):
			best = candidate.get("node") as Node3D
			best_abs_bearing = abs_bearing
			best_distance = distance
	return best
