extends Node

## Small global reserve for expensive cockpit pilot rigs. Routine aircraft keep
## only a lightweight mount; viewed aircraft and active ejections check out one
## real rig. Overflow is allowed so gameplay never steals an ejecting pilot.

const PILOT_VISUAL_SCENE: PackedScene = preload(
	"res://Models/Characters/pilot/CockpitPilotCharacter.tscn"
)
const PILOTING_ANIMATION: StringName = &"piloting"
const SLOW_ACQUIRE_LOG_THRESHOLD_USEC := 8000

@export_range(1, 4, 1) var reserve_size: int = 2

var _available: Array[Node3D] = []
var _created_count: int = 0
var _acquire_count_total: int = 0
var _release_count_total: int = 0
var _overflow_created_total: int = 0
var _failed_acquire_total: int = 0
var _peak_checked_out: int = 0
var _acquire_total_usec: int = 0
var _acquire_max_usec: int = 0
var _animation_prepare_count_total: int = 0
var _animation_prepare_total_usec: int = 0
var _animation_prepare_max_usec: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for _index in range(maxi(reserve_size, 1)):
		var pilot := _create_prepared_pilot(true)
		if pilot != null:
			_park_pilot(pilot)
	print("[CockpitPilotPool] reserve_ready size=%d created=%d animation_prepare_ms=%.3f animation_prepare_max_ms=%.3f" % [
		reserve_size,
		_created_count,
		float(_animation_prepare_total_usec) * 0.001,
		float(_animation_prepare_max_usec) * 0.001,
	])


func acquire_pilot(require_animation: bool = true) -> Node3D:
	var acquire_start_usec: int = Time.get_ticks_usec()
	var pilot: Node3D = null
	var created_for_acquire: bool = false
	while not _available.is_empty() and pilot == null:
		var candidate_index := _find_available_candidate(require_animation)
		var candidate: Node3D = _available.pop_at(candidate_index)
		if candidate != null and is_instance_valid(candidate):
			pilot = candidate
	if pilot == null:
		pilot = _create_prepared_pilot(require_animation)
		created_for_acquire = pilot != null
	if pilot == null:
		_failed_acquire_total += 1
		return null
	if require_animation:
		_prepare_animation_if_needed(pilot)
	if pilot.get_parent() != null:
		pilot.get_parent().remove_child(pilot)
	pilot.visible = true
	pilot.process_mode = Node.PROCESS_MODE_INHERIT
	pilot.set_meta("cockpit_pilot_pool_owned", true)
	_acquire_count_total += 1
	if created_for_acquire and _created_count > maxi(reserve_size, 1):
		_overflow_created_total += 1
	var checked_out: int = maxi(_created_count - _available.size(), 0)
	_peak_checked_out = maxi(_peak_checked_out, checked_out)
	var elapsed_usec: int = maxi(Time.get_ticks_usec() - acquire_start_usec, 0)
	_acquire_total_usec += elapsed_usec
	_acquire_max_usec = maxi(_acquire_max_usec, elapsed_usec)
	if created_for_acquire or elapsed_usec >= SLOW_ACQUIRE_LOG_THRESHOLD_USEC:
		print("[CockpitPilotPool] acquire elapsed_ms=%.3f created_new=%s require_animation=%s created=%d available=%d checked_out=%d overflow_total=%d" % [
			float(elapsed_usec) * 0.001,
			str(created_for_acquire),
			str(require_animation),
			_created_count,
			_available.size(),
			checked_out,
			_overflow_created_total,
		])
	return pilot


func release_pilot(pilot: Node3D) -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	if pilot.has_method("set_presentation_active"):
		pilot.call("set_presentation_active", false)
	if pilot.get_parent() != null:
		pilot.get_parent().remove_child(pilot)
	_park_pilot(pilot)
	_release_count_total += 1


func get_pool_stats() -> Dictionary:
	var checked_out: int = maxi(_created_count - _available.size(), 0)
	return {
		"reserve_size": reserve_size,
		"created": _created_count,
		"available": _available.size(),
		"checked_out": checked_out,
		"peak_checked_out": _peak_checked_out,
		"acquire_count": _acquire_count_total,
		"release_count": _release_count_total,
		"overflow_created_total": _overflow_created_total,
		"failed_acquire_total": _failed_acquire_total,
		"acquire_total_ms": float(_acquire_total_usec) * 0.001,
		"acquire_max_ms": float(_acquire_max_usec) * 0.001,
		"animation_prepare_count": _animation_prepare_count_total,
		"animation_prepare_total_ms": float(_animation_prepare_total_usec) * 0.001,
		"animation_prepare_max_ms": float(_animation_prepare_max_usec) * 0.001,
	}


func _create_prepared_pilot(prewarm_animation: bool) -> Node3D:
	var pilot := PILOT_VISUAL_SCENE.instantiate() as Node3D
	if pilot == null:
		return null
	_created_count += 1
	pilot.name = "ReservedCockpitPilot%d" % _created_count
	pilot.set("initial_baked_animation", PILOTING_ANIMATION)
	pilot.set("defer_initial_baked_animation_until_presented", true)
	add_child(pilot)
	pilot.set_meta("cockpit_pilot_animation_prepared", false)
	if prewarm_animation:
		_prepare_animation_if_needed(pilot)
	return pilot


func _prepare_animation_if_needed(pilot: Node3D) -> void:
	if bool(pilot.get_meta("cockpit_pilot_animation_prepared", false)):
		return
	var prepare_start_usec: int = Time.get_ticks_usec()
	# Pay dense cockpit-animation registration for the two normal reserve bodies
	# during loading. Static passenger overflow deliberately skips this path.
	pilot.set("initial_baked_animation", PILOTING_ANIMATION)
	pilot.set("defer_initial_baked_animation_until_presented", true)
	pilot.set("hide_head_in_cockpit", true)
	if pilot.has_method("set_presentation_active"):
		pilot.call("set_presentation_active", true)
		pilot.call("set_presentation_active", false)
		pilot.set_meta("cockpit_pilot_animation_prepared", true)
	var elapsed_usec: int = maxi(Time.get_ticks_usec() - prepare_start_usec, 0)
	_animation_prepare_count_total += 1
	_animation_prepare_total_usec += elapsed_usec
	_animation_prepare_max_usec = maxi(_animation_prepare_max_usec, elapsed_usec)


func _find_available_candidate(require_animation: bool) -> int:
	if not require_animation:
		return _available.size() - 1
	for index in range(_available.size() - 1, -1, -1):
		var candidate := _available[index]
		if candidate != null and is_instance_valid(candidate) \
				and bool(candidate.get_meta("cockpit_pilot_animation_prepared", false)):
			return index
	return _available.size() - 1


func _park_pilot(pilot: Node3D) -> void:
	# Overflow protects exceptional simultaneous states (for example, an ejection
	# while two aircraft presentations overlap), but the idle reserve stays capped.
	if _available.size() >= maxi(reserve_size, 1):
		_created_count = maxi(_created_count - 1, 0)
		_clear_surface_overrides(pilot)
		pilot.queue_free()
		return
	if pilot.get_parent() != self:
		add_child(pilot)
	pilot.transform = Transform3D.IDENTITY
	pilot.visible = false
	pilot.process_mode = Node.PROCESS_MODE_DISABLED
	if not _available.has(pilot):
		_available.append(pilot)


func _clear_surface_overrides(node: Node) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			mesh_instance.set_surface_override_material(surface_index, null)
	for child_variant in node.get_children():
		var child := child_variant as Node
		if child != null:
			_clear_surface_overrides(child)
