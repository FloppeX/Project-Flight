extends AircraftModule
class_name AircraftModule_ControlTargeting_AAM

@export var fov_cone_deg: float = 60.0
@export var max_range_m: float = 3000.0
@export var targeting_update_rate_hz: float = 5.0
@export var auto_target_when_none: bool = true
@export var auto_replace_target: bool = false
@export var relaxed_lock_when_none: bool = true  # If true, pick nearest in range even if out of cone
@export var enable_legacy_keyboard_shortcuts: bool = false

var _time_accum: float = 0.0
var current_target: Node3D
@export var debug_enabled: bool = false

# AA Missile Lock-on variables
var target_lock_time: float = 0.0
@export var required_lock_time: float = 3.0
@export var lock_loss_rate: float = 1.0  # Lose 1s of lock per second if target slips out of cone

func _ready():
	ReceiveInput = true
	ProcessPhysics = true
	ModuleType = "targeting"

func receive_input(event):
	if event != null and event.is_action_pressed("target_lock_center", false, true):
		lock_target_to_hud_center()
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
	if current_target != null and not is_instance_valid(current_target):
		current_target = null
		target_lock_time = 0.0

	_time_accum += delta
	var interval = 1.0 / max(targeting_update_rate_hz, 0.1)
	if _time_accum >= interval:
		_time_accum = 0.0
		_update_best_target_if_needed()
		
	# Track continuous lock time over the 30-degree (total) cone
	if current_target and is_instance_valid(current_target) and aircraft and is_instance_valid(aircraft):
		var forward: Vector3 = aircraft.global_transform.basis.z
		var to_tgt: Vector3 = (current_target.global_position - aircraft.global_position).normalized()
		var dist_to_tgt = current_target.global_position.distance_to(aircraft.global_position)
		
		# 30 degree cone = 15 degrees each side. cos(15) = 0.9659
		var cos_half = cos(deg_to_rad(30.0 * 0.5))
		
		if forward.dot(to_tgt) >= cos_half and dist_to_tgt <= max_range_m:
			target_lock_time += delta
			if target_lock_time > required_lock_time:
				target_lock_time = required_lock_time
		else:
			target_lock_time -= delta * lock_loss_rate
			if target_lock_time < 0.0:
				target_lock_time = 0.0
	else:
		target_lock_time = 0.0

func get_target_lock_time() -> float:
	return target_lock_time

func _update_best_target_if_needed():
	if not is_instance_valid(aircraft):
		return
	if current_target != null and not is_instance_valid(current_target):
		current_target = null
		target_lock_time = 0.0
	var enemies: Array = _get_hostile_enemies()
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
	# Keep target if valid and allowed
	var keep_current: bool = false
	if current_target and is_instance_valid(current_target) and not auto_replace_target:
		# Verify current is still in cone/range
		var cur_to: Vector3 = current_target.global_position - origin
		var cur_dist: float = cur_to.length()
		if cur_dist <= max_range_m and cur_dist > 0.1:
			var cur_dir: Vector3 = cur_to.normalized()
			keep_current = forward.dot(cur_dir) >= cos_half
	if keep_current and not auto_replace_target:
		return
	# Select nearest in-cone
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"]) 
	if auto_target_when_none or auto_replace_target or (current_target == null or not is_instance_valid(current_target)):
		var new_target = candidates[0]["node"]
		set_target(new_target)
		if debug_enabled:
			print("[Targeting] selected ", current_target.name)

func set_target(new_target: Node3D):
	"""Sets the current target and handles signal connections."""
	if new_target != null and not is_instance_valid(new_target):
		new_target = null

	if current_target != null and not is_instance_valid(current_target):
		current_target = null

	if new_target == current_target:
		return

	if is_instance_valid(current_target) and current_target.has_signal("destroyed"):
		current_target.destroyed.disconnect(on_target_destroyed)

	current_target = new_target
	target_lock_time = 0.0  # Reset lock when swapping targets!

	if is_instance_valid(current_target) and current_target.has_signal("destroyed"):
		current_target.destroyed.connect(on_target_destroyed)

func on_target_destroyed(enemy_node):
	if debug_enabled:
		print("[Targeting] Target destroyed signal received from: ", enemy_node)
	if enemy_node == current_target:
		clear_target()
		if debug_enabled:
			print("[Targeting] Current target was destroyed. Target cleared.")

func target_next():
	_cycle_target(1)

func target_prev():
	_cycle_target(-1)

func clear_target():
	set_target(null)

func _cycle_target(direction: int):
	if not is_instance_valid(aircraft):
		return
	var enemies: Array = _get_hostile_enemies()
	if enemies.size() == 0:
		clear_target()
		return
	# Cycle through all enemies in range — no aspect restriction
	var origin: Vector3 = aircraft.global_position
	var candidates := []
	for e in enemies:
		if e and is_instance_valid(e):
			var dist: float = (e.global_position - origin).length()
			if dist <= max_range_m and dist > 0.1:
				candidates.append({"node": e, "dist": dist})
	if candidates.size() == 0:
		clear_target()
		return
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])
	var sorted: Array = candidates.map(func(c): return c["node"])
	if not current_target or not is_instance_valid(current_target):
		set_target(sorted[0])
		return
	var idx := sorted.find(current_target)
	if idx == -1:
		set_target(sorted[0])
		return
	idx = (idx + direction) % sorted.size()
	if idx < 0:
		idx += sorted.size()
	set_target(sorted[idx])

func lock_target_to_hud_center() -> bool:
	if not is_instance_valid(aircraft):
		return false

	var enemies: Array = _get_hostile_enemies()
	if enemies.is_empty():
		return false

	var origin: Vector3 = aircraft.global_position
	var forward: Vector3 = aircraft.global_transform.basis.z.normalized()
	var best_target: Node3D = null
	var best_alignment: float = -INF
	var best_dist_m: float = INF

	for enemy_variant in enemies:
		if not is_instance_valid(enemy_variant):
			continue
		var enemy: Node3D = enemy_variant as Node3D
		if enemy == null or enemy == aircraft:
			continue

		var to_vec: Vector3 = enemy.global_position - origin
		var dist_m: float = to_vec.length()
		if dist_m <= 0.1 or dist_m > max_range_m:
			continue

		var alignment: float = forward.dot(to_vec / dist_m)
		if alignment <= 0.0:
			continue

		if alignment > best_alignment + 0.0001:
			best_alignment = alignment
			best_dist_m = dist_m
			best_target = enemy
			continue
		if absf(alignment - best_alignment) <= 0.0001 and dist_m < best_dist_m:
			best_dist_m = dist_m
			best_target = enemy

	if not is_instance_valid(best_target):
		return false

	set_target(best_target)
	if debug_enabled:
		print("[Targeting] center lock -> ", best_target.name, " alignment=", "%.3f" % best_alignment)
	return true

func _get_hostile_enemies() -> Array:
	var enemies: Array = []
	if not is_instance_valid(aircraft):
		return enemies

	var team_id: int = 1
	if aircraft.has_method("get_team"):
		team_id = int(aircraft.get_team())

	var registry: Node = get_node_or_null("/root/EnemyRegistry")
	if registry and registry.has_method("get_enemies_for_team"):
		enemies = registry.get_enemies_for_team(1 if team_id != 1 else 2)
	if enemies.size() > 0:
		return enemies

	var group_nodes: Array = get_tree().get_nodes_in_group("enemies")
	for enemy_variant in group_nodes:
		if not is_instance_valid(enemy_variant):
			continue
		var enemy: Node3D = enemy_variant as Node3D
		if enemy == null or enemy == aircraft:
			continue
		if enemy.has_method("get_team"):
			if int(enemy.get_team()) != team_id:
				enemies.append(enemy)
		else:
			enemies.append(enemy)

	return enemies
