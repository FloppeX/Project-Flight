extends Node3D

const PANEL_SCENE: PackedScene = preload("res://HUD/InstrumentPanel.tscn")
const POOL_CAPACITY: int = 2

var _available: Array[Node3D] = []
var _mount_to_panel: Dictionary = {}
var _next_panel_number: int = 1
var _render_warming: Dictionary = {}
var _render_warm_count: int = 0
var _render_warm_total_ms: float = 0.0
var _render_warm_max_ms: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_prewarm_remaining")


func _prewarm_remaining() -> void:
	while _available.size() + _mount_to_panel.size() < POOL_CAPACITY:
		_available.append(_create_warm_panel())
	# Instantiation alone does not initialize SubViewport render targets. Exercise
	# each reserve member for two real frames, one at a time, while the loading/menu
	# flow can absorb the native render-target and pipeline setup cost.
	for panel_variant in _available.duplicate():
		var panel := panel_variant as Node3D
		if panel == null or not is_instance_valid(panel) or not _available.has(panel):
			continue
		await _render_warm_panel(panel)


func _render_warm_panel(panel: Node3D) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var panel_id := panel.get_instance_id()
	_render_warming[panel_id] = true
	var started_us := Time.get_ticks_usec()
	panel.call("set_view_updates_active", true)
	await get_tree().process_frame
	await get_tree().process_frame
	# Checkout may legitimately take ownership while startup is still running.
	# In that case leave the live panel active and let normal release own cleanup.
	if not _render_warming.has(panel_id):
		return
	_render_warming.erase(panel_id)
	if not _available.has(panel):
		return
	panel.call("set_view_updates_active", false)
	panel.set_meta("pool_render_warmed", true)
	var elapsed_ms := float(Time.get_ticks_usec() - started_us) / 1000.0
	_render_warm_count += 1
	_render_warm_total_ms += elapsed_ms
	_render_warm_max_ms = maxf(_render_warm_max_ms, elapsed_ms)
	print("[InstrumentPanelPool] render_warm panel=%s elapsed_ms=%.3f" % [panel.name, elapsed_ms])


func acquire(mount: Node3D) -> Node3D:
	if mount == null or not is_instance_valid(mount):
		return null
	var mount_id := mount.get_instance_id()
	var existing_variant: Variant = _mount_to_panel.get(mount_id)
	var existing := existing_variant as Node3D
	if existing != null and is_instance_valid(existing):
		return existing

	var profiler_start := FrameProfiler.begin("InstrumentPanelPool.checkout")
	var panel: Node3D = null
	if not _available.is_empty():
		panel = _available.pop_back() as Node3D
	elif _mount_to_panel.size() < POOL_CAPACITY:
		# This path is expected only during initial startup before deferred prewarm
		# has completed. Never grow beyond the fixed reserve during play.
		panel = _create_warm_panel()
	else:
		push_warning("[InstrumentPanelPool] reserve exhausted; refusing runtime panel allocation")
		FrameProfiler.end("InstrumentPanelPool.checkout", profiler_start)
		return null
	_render_warming.erase(panel.get_instance_id())
	_mount_to_panel[mount_id] = panel
	panel.call("configure_for_pooled_mount", mount)
	panel.visible = true
	panel.set_process(true)
	panel.set_physics_process(true)
	panel.set_process_input(true)
	panel.call("set_view_updates_active", true)
	FrameProfiler.end("InstrumentPanelPool.checkout", profiler_start)
	return panel


func release(mount: Node3D) -> void:
	if mount == null:
		return
	var mount_id := mount.get_instance_id()
	if not _mount_to_panel.has(mount_id):
		return
	var profiler_start := FrameProfiler.begin("InstrumentPanelPool.release")
	var panel := _mount_to_panel[mount_id] as Node3D
	_mount_to_panel.erase(mount_id)
	if panel == null or not is_instance_valid(panel):
		FrameProfiler.end("InstrumentPanelPool.release", profiler_start)
		return
	panel.call("release_pooled_mount")
	panel.visible = false
	panel.set_process(false)
	panel.set_physics_process(false)
	panel.set_process_input(false)
	if not _available.has(panel):
		_available.append(panel)
	FrameProfiler.end("InstrumentPanelPool.release", profiler_start)


func get_panel_for_mount(mount: Node3D) -> Node3D:
	if mount == null or not is_instance_valid(mount):
		return null
	var panel_variant: Variant = _mount_to_panel.get(mount.get_instance_id())
	var panel := panel_variant as Node3D
	return panel if panel != null and is_instance_valid(panel) else null


func get_pool_stats() -> Dictionary:
	return {
		"capacity": POOL_CAPACITY,
		"available": _available.size(),
		"checked_out": _mount_to_panel.size(),
		"render_warm_count": _render_warm_count,
		"render_warm_complete": _render_warm_count >= POOL_CAPACITY,
		"render_warm_total_ms": _render_warm_total_ms,
		"render_warm_max_ms": _render_warm_max_ms,
	}


func standard_module_layout() -> Array[Dictionary]:
	return [
		{"id": "warning_strip", "lights": ["ENGINE", "WEAPONS", "CONTROLS", "GEAR", "STALL"], "rect": Rect2(125, 75, 750, 40), "title": "WARNINGS", "type": "warning_lights"},
		{"id": "mfd_left", "modes": ["MAP", "WEAPONS", "DAMAGE", "SYSTEMS"], "rect": Rect2(125, 125, 300, 235), "title": "MFD L", "type": "mfd"},
		{"id": "mfd_right", "modes": ["TARGET", "MAP", "WEAPONS", "DAMAGE", "SYSTEMS"], "rect": Rect2(575, 125, 300, 235), "title": "MFD R", "type": "mfd"},
		{"id": "speed", "instrument": "speed", "rect": Rect2(590, 25, 120, 45), "title": "SPEED", "type": "readout"},
		{"id": "altitude", "instrument": "altitude", "rect": Rect2(290, 25, 120, 45), "title": "ALT", "type": "readout"},
		{"id": "vertical_speed", "instrument": "vertical_speed", "rect": Rect2(795, 25, 75, 45), "title": "V/S", "type": "readout"},
		{"id": "fuel", "instrument": "fuel", "rect": Rect2(440, 185, 125, 54), "title": "FUEL", "type": "readout"},
		{"id": "gear", "instrument": "gear", "rect": Rect2(440, 245, 125, 54), "title": "GEAR", "type": "readout"},
		{"id": "flaps", "instrument": "flaps", "rect": Rect2(440, 305, 125, 54), "title": "FLAPS", "type": "readout"},
		{"id": "aoa", "rect": Rect2(165, 25, 120, 45), "title": "AOA", "type": "aoa"},
		{"id": "slip_ball", "rect": Rect2(415, 25, 170, 45), "title": "BALL", "type": "slip_ball"},
		{"id": "engine", "instrument": "engine", "rect": Rect2(440, 125, 125, 55), "title": "ENGINE", "type": "readout"},
		{"id": "damage", "instrument": "damage", "rect": Rect2(575, 370, 125, 50), "title": "STRUCT", "type": "readout"},
		{"id": "g_force", "instrument": "g_force", "rect": Rect2(715, 25, 75, 45), "title": "G", "type": "readout"},
		{"id": "weapons", "instrument": "weapons", "rect": Rect2(300, 370, 125, 50), "title": "WEAPONS", "type": "readout"},
	]


func _create_warm_panel() -> Node3D:
	var profiler_start := FrameProfiler.begin("InstrumentPanelPool.prewarm")
	var panel := PANEL_SCENE.instantiate() as Node3D
	panel.name = "PooledInstrumentPanel%d" % _next_panel_number
	_next_panel_number += 1
	panel.set_meta("pooled_instrument_panel", true)
	panel.set("aircraft_path", NodePath(".."))
	panel.set("panel_size", Vector2(1.0, 0.8))
	panel.set("viewport_resolution", Vector2i(1000, 480))
	panel.set("module_layout", standard_module_layout())
	# This globally-owned visual copies the already-interpolated cockpit mount in
	# _process(), so it must not receive a second interpolation pass of its own.
	panel.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(panel)
	panel.call("set_view_updates_active", false)
	panel.visible = false
	panel.set_process(false)
	panel.set_physics_process(false)
	panel.set_process_input(false)
	FrameProfiler.end("InstrumentPanelPool.prewarm", profiler_start)
	return panel
