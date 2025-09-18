extends AircraftModule
class_name AircraftModule_ControlTargeting

@export var fov_cone_deg: float = 60.0
@export var max_range_m: float = 3000.0
@export var targeting_update_rate_hz: float = 5.0
@export var auto_target_when_none: bool = true
@export var auto_replace_target: bool = false
@export var relaxed_lock_when_none: bool = true  # If true, pick nearest in range even if out of cone

var _time_accum: float = 0.0
var current_target: Node3D
@export var debug_enabled: bool = true

func _ready():
	ReceiveInput = true
	ProcessPhysics = true
	ModuleType = "targeting"

func receive_input(event):
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
	_time_accum += delta
	var interval = 1.0 / max(targeting_update_rate_hz, 0.1)
	if _time_accum >= interval:
		_time_accum = 0.0
		_update_best_target_if_needed()

func _update_best_target_if_needed():
	if not is_instance_valid(aircraft):
		return
	var team_id: int = 1
	if aircraft and aircraft.has_method("get_team"):
		team_id = int(aircraft.get_team())
	var enemies: Array = []
	var registry: Node = get_node_or_null("/root/EnemyRegistry")
	if registry and registry.has_method("get_enemies_for_team"):
		enemies = registry.get_enemies_for_team(1 if team_id != 1 else 2)
	if enemies.size() == 0:
		# Fallback: find by group
		var group_nodes: Array = get_tree().get_nodes_in_group("enemies")
		for e in group_nodes:
			if e and is_instance_valid(e) and e != aircraft:
				if e.has_method("get_team"):
					if int(e.get_team()) != team_id:
						enemies.append(e)
				else:
					enemies.append(e)
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
			current_target = nearest
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
	# Add a guard clause to ensure we never assign a freed instance.
	if new_target != null and not is_instance_valid(new_target):
		# If the new target is invalid, treat it as if we're clearing the target.
		new_target = null

	if new_target == current_target:
		return

	# Disconnect from the old target's destroyed signal if it was valid
	if is_instance_valid(current_target) and current_target.has_signal("destroyed"):
		current_target.destroyed.disconnect(on_target_destroyed)

	current_target = new_target

	# Connect to the new target's destroyed signal if it is valid
	if is_instance_valid(current_target) and current_target.has_signal("destroyed"):
		current_target.destroyed.connect(on_target_destroyed)

func on_target_destroyed(enemy_node):
	"""Callback function for when a target is destroyed."""
	if debug_enabled:
		print("[Targeting] Target destroyed signal received from: ", enemy_node)
	# If the destroyed enemy is our current target, clear it.
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
	var team_id: int = 1
	if aircraft and aircraft.has_method("get_team"):
		team_id = int(aircraft.get_team())
	var enemies: Array = []
	var registry: Node = get_node_or_null("/root/EnemyRegistry")
	if registry and registry.has_method("get_enemies_for_team"):
		enemies = registry.get_enemies_for_team(1 if team_id != 1 else 2)
	if enemies.size() == 0:
		var group_nodes2: Array = get_tree().get_nodes_in_group("enemies")
		for e2 in group_nodes2:
			if e2 and is_instance_valid(e2) and e2 != aircraft:
				if e2.has_method("get_team"):
					if int(e2.get_team()) != team_id:
						enemies.append(e2)
				else:
					enemies.append(e2)
	if enemies.size() == 0:
		clear_target()
		return
	# Build list in-cone for cycling
	var forward: Vector3 = aircraft.global_transform.basis.z
	var origin: Vector3 = aircraft.global_position
	var cos_half := cos(deg_to_rad(fov_cone_deg * 0.5))
	var in_cone := []
	for e in enemies:
		if e and is_instance_valid(e):
			var to_vec: Vector3 = e.global_position - origin
			if to_vec.length() <= max_range_m and to_vec.length() > 0.1:
				var dir: Vector3 = to_vec.normalized()
				if forward.dot(dir) >= cos_half:
					in_cone.append(e)
	if in_cone.size() == 0:
		clear_target()
		return
	if not current_target or not is_instance_valid(current_target):
		set_target(in_cone[0])
		return
	var idx := in_cone.find(current_target)
	if idx == -1:
		set_target(in_cone[0])
		return
	idx = (idx + direction) % in_cone.size()
	if idx < 0:
		idx += in_cone.size()
	set_target(in_cone[idx])
