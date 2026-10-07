extends SceneTree

var failures: Array[String] = []
var graph: Node
var grid: Node
var scheduler: Node
var callback_results: Array = []
var lock_shift_ms := 0.0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	graph = root.get_node("NavGraph")
	grid = root.get_node("TerrainNavGrid")
	scheduler = root.get_node("NavPathScheduler")
	var heights := PackedFloat32Array()
	for z in 41:
		for x in 45: heights.append(120.0 + x * 0.5 + z * 0.25)
	grid.set("_cols", 45)
	grid.set("_rows", 41)
	grid.set("cell_size_m", 40.0)
	grid.set("_origin_x", -901.25)
	grid.set("_origin_z", -801.25)
	grid.set("_heights", heights)
	grid.set("_h_min_passable", 120.0)
	grid.set("_is_baked", true)
	graph.call("_reset_graph")
	graph.call("_build")
	graph.call("_build_spatial_index")
	graph.set("_is_ready", true)
	var nodes: PackedVector3Array = graph.get("_nodes")
	var index: Dictionary = graph.get("_sp_grid").duplicate(true)
	var a := nodes[nodes.size() / 4]
	var b := nodes[nodes.size() * 3 / 4]
	var baseline: Array[Vector3] = graph.call("find_path", a, b, 0.0)
	_expect(baseline.size() > 2, "fixture did not exercise path simplification")
	_expect(bool(graph.call("can_traverse_segment", a + Vector3.UP * 2.0, a + Vector3.RIGHT, 0.0)), "short ground traversal treated chassis height as terrain grade")
	var total := Vector3.ZERO
	for offset in [Vector3(8123.5, 0, -5400.25), Vector3(-24567, 0, 10023), Vector3(45678.25, 0, -7890.5)]:
		total += offset
		_shift(offset)
		_expect(graph.get("_nodes") == nodes, "origin shift rewrote graph nodes")
		_expect(graph.get("_sp_grid") == index, "origin shift rebuilt spatial index")
		_expect(bool(graph.call("has_nearby_node", a - total, 0.0)), "nearest-node lookup broke")
		_expect(bool(graph.call("can_anchor", a - total, 0.0)), "anchor lookup broke")
		_expect(bool(graph.call("can_traverse_segment", a - total + Vector3.UP * 2.0, a - total + Vector3.RIGHT, 0.0)), "short final approach broke after origin shift")
		_expect_path(graph.call("find_path", a - total, b - total, 0.0), baseline, total)
	# A worker owns the expensive solver lock. Origin shifting must not wait for it.
	var lock: Mutex = graph.get("_lock")
	var acquired := Semaphore.new()
	var worker := Thread.new()
	worker.start(func():
		lock.lock()
		acquired.post()
		OS.delay_msec(250)
		lock.unlock())
	acquired.wait()
	var started := Time.get_ticks_usec()
	var last_shift := Vector3(5000, 0, -7000)
	_shift(last_shift)
	lock_shift_ms = (Time.get_ticks_usec() - started) / 1000.0
	total += last_shift
	worker.wait_to_finish()
	_expect(lock_shift_ms < 30.0, "origin shift waited on solver mutex")
	_expect_path(graph.call("find_path", a - total, b - total, 0.0), baseline, total)
	# Explicit cache round-trip after rebasing preserves the build frame.
	var cache_path := "res://logs/navgraph_origin_frame_smoketest.bin" if "--workspace-cache" in OS.get_cmdline_user_args() else "user://navgraph_origin_frame_smoketest.bin"
	graph.call("_save", cache_path)
	graph.call("_reset_graph")
	_expect(bool(graph.call("_load", cache_path)), "rebase cache load failed")
	graph.call("_build_spatial_index")
	graph.set("_is_ready", true)
	_expect_path(graph.call("find_path", a - total, b - total, 0.0), baseline, total)
	# Same dimensions/seed can hide changed terrain: reject stale graph geometry.
	var original_heights: PackedFloat32Array = grid.get("_heights").duplicate()
	var changed_heights := original_heights.duplicate()
	changed_heights[changed_heights.size() / 2] += 100.0
	grid.set("_heights", changed_heights)
	_expect(not bool(graph.call("_load", cache_path)), "cache accepted changed terrain heights")
	grid.set("_heights", original_heights)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))
	# Drop stale queued work before executing it, releasing the caller latch.
	scheduler.set("min_job_start_interval_s", 0.0)
	scheduler.set("start_jitter_s", 0.0)
	scheduler.call("request_work", func(): failures.append("stale queued work executed"), _callback)
	scheduler.call("apply_origin_shift", Vector3.ONE)
	scheduler.call("_start_ready_jobs")
	await process_frame
	_expect(callback_results.size() == 1 and callback_results[0] == null, "stale queued job was delivered")
	callback_results.clear()
	# In-flight job completion after a shift also returns a retry result.
	scheduler.call("request_work", func():
		OS.delay_msec(80)
		return {"path": [a, b]}, _callback)
	scheduler.call("_start_ready_jobs")
	var reap_started := Time.get_ticks_usec()
	scheduler.call("_reap_completed_tasks")
	_expect(Time.get_ticks_usec() - reap_started < 30000, "task cleanup blocked on unfinished work")
	scheduler.call("apply_origin_shift", Vector3.ONE)
	await _wait_callback()
	_expect(callback_results.size() == 1 and callback_results[0] == null, "stale running job was delivered")
	callback_results.clear()
	# Check again at deferred delivery, not only at worker completion.
	var job := {"coordinate_epoch": scheduler.get("_coordinate_epoch"), "callback": _callback,
		"guard_coordinates": true, "stale_result": null}
	scheduler.call_deferred("_deliver_job", job, {"path": [a, b]})
	scheduler.call("apply_origin_shift", Vector3.ONE)
	await process_frame
	_expect(callback_results.size() == 1 and callback_results[0] == null, "deferred delivery missed shift")
	callback_results.clear()
	# Provenance-aware aircraft jobs retain their serial-bearing result.
	scheduler.call("request_work", func(): return {"serial": 17}, _callback, 0, "provenance_test", false)
	scheduler.call("apply_origin_shift", Vector3.ONE)
	scheduler.call("_start_ready_jobs")
	await _wait_callback()
	_expect(callback_results.size() == 1 and callback_results[0] is Dictionary and callback_results[0].serial == 17, "provenance result was erased")
	var reap_deadline := Time.get_ticks_msec() + 3000
	while not scheduler.get("_worker_tasks").is_empty() and Time.get_ticks_msec() < reap_deadline:
		scheduler.call("_reap_completed_tasks")
		await process_frame
	_expect(scheduler.get("_worker_tasks").is_empty(), "completed pool tasks were not reclaimed")
	print("NAVGRAPH_ORIGIN_FRAME_SMOKETEST ", JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "failures": failures, "locked_solver_shift_ms": lock_shift_ms}))
	quit(0 if failures.is_empty() else 1)

func _shift(offset: Vector3) -> void:
	grid.call("apply_origin_shift", offset)
	graph.call("apply_origin_shift", offset)
	scheduler.call("apply_origin_shift", offset)

func _callback(value: Variant) -> void: callback_results.append(value)

func _wait_callback() -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while callback_results.is_empty() and Time.get_ticks_msec() < deadline: await process_frame

func _expect_path(actual: Array[Vector3], expected: Array[Vector3], offset: Vector3) -> void:
	_expect(actual.size() == expected.size(), "path point count changed after rebase")
	for i in mini(actual.size(), expected.size()):
		_expect(actual[i].distance_to(expected[i] - offset) < 0.03, "path point changed after rebase")

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
