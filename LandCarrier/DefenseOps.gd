extends Node

## One coordinator per carrier. Turrets retain their own aiming, LOS and fire
## safety checks; this node owns target allocation and the monitor contact list.
@export var update_interval_s: float = 0.25
var _turrets: Array[Node] = []
var _contacts: Array[WeakRef] = []
var _timer: float = 0.0

func _ready() -> void:
	add_to_group("defense_ops")
	call_deferred("coordinate_defense")

func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = maxf(update_interval_s, 0.1)
		coordinate_defense()

func _exit_tree() -> void:
	for turret in _turrets:
		if is_instance_valid(turret) and turret.get("defense_coordinator") == self:
			turret.set("defense_coordinator", null)

func get_available_targets() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for contact in _contacts:
		var target: Variant = contact.get_ref()
		if is_live_target(target):
			result.append(target as Node3D)
	return result

static func is_live_target(target: Variant) -> bool:
	if not is_instance_valid(target) or not target is Node3D:
		return false
	return target.is_inside_tree() and not target.is_queued_for_deletion() \
		and not ("is_destroyed" in target and bool(target.get("is_destroyed"))) \
		and not ("is_dying" in target and bool(target.get("is_dying")))

func coordinate_defense() -> void:
	_refresh_sensor_contacts()
	_turrets.clear()
	var choices: Array[Dictionary] = []
	for node in get_parent().find_children("*", "Node", true, false):
		if not node.has_method("get_defense_candidates") or node.is_queued_for_deletion():
			continue
		_turrets.append(node)
		node.set("defense_coordinator", self)
		var candidates: Array = node.call("get_defense_candidates")
		choices.append({"turret": node, "targets": candidates})
	# Allocate constrained turrets first so a gun with only one reachable target
	# gets that job before flexible guns. Stable IDs break ties deterministically.
	choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.targets.size() != b.targets.size():
			return a.targets.size() < b.targets.size()
		return a.turret.get_instance_id() < b.turret.get_instance_id())
	var assigned_counts: Dictionary = {}
	for choice in choices:
		var turret: Node3D = choice.turret as Node3D
		var best: Node3D = null
		var best_score := INF
		for raw_target in choice.targets:
			if not is_live_target(raw_target):
				continue
			var target := raw_target as Node3D
			var load_count := int(assigned_counts.get(target.get_instance_id(), 0))
			var distance := turret.global_position.distance_to(target.global_position)
			# Coverage dominates distance. Nearby threats and aircraft win ties;
			# retain a sound assignment unless coverage or threat changes warrant it.
			var score := float(load_count) * 100000.0 + distance
			if target.is_in_group("aircraft") or target.is_in_group("ai_aircraft"):
				score -= 200.0
			if turret.get("current_target") == target:
				score -= 250.0
			if score < best_score:
				best_score = score
				best = target
		turret.call("set_defense_assignment", self, best)
		if best != null:
			var id := best.get_instance_id()
			assigned_counts[id] = int(assigned_counts.get(id, 0)) + 1

func _refresh_sensor_contacts() -> void:
	# The monitor gets the whole live radar picture, not just targets reachable
	# by a gun. In particular this still works on a carrier with no turrets.
	_contacts.clear()
	var sensors := get_node_or_null("/root/AirOpsManager")
	var carrier := get_parent() as Node3D
	if sensors == null or carrier == null:
		return
	var targets: Array = sensors.call("get_carrier_monitor_contacts", carrier)
	targets.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.get_instance_id() < b.get_instance_id())
	for target in targets:
		if is_live_target(target):
			_contacts.append(weakref(target))
