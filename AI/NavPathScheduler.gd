extends Node
## Central gate for expensive NavGraph path jobs.
## 
## Callers can enqueue threaded work, but this node controls when jobs start so
## many units cannot all hit NavGraph.find_path() on the same frame.

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")

@export var max_concurrent_jobs: int = 1
@export var min_job_start_interval_s: float = 0.16
@export var start_jitter_s: float = 0.05
@export var max_queue_size: int = 96
@export var debug_print: bool = false

var _queue: Array[Dictionary] = []
var _running_jobs: Dictionary = {}
var _next_job_id: int = 1
var _next_start_msec: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_process(true)


func request_find_path(
		from_world: Vector3,
		to_world: Vector3,
		min_clearance_m: float,
		callback: Callable,
		priority: int = 0,
		tag: String = "") -> int:
	var start: Vector3 = from_world
	var goal: Vector3 = to_world
	var clearance: float = min_clearance_m
	var work: Callable = func() -> Array[Vector3]:
		return NavGraph.find_path(start, goal, clearance)
	return request_work(work, callback, priority, tag)


func request_work(work: Callable, callback: Callable, priority: int = 0, tag: String = "") -> int:
	if not work.is_valid() or not callback.is_valid():
		return -1
	if _queue.size() >= max_queue_size:
		if debug_print:
			print("[NavPathScheduler] queue full; dropping job tag=", tag)
		return -1

	var job_id: int = _next_job_id
	_next_job_id += 1
	_queue.append({
		"id": job_id,
		"work": work,
		"callback": callback,
		"priority": priority,
		"tag": tag,
	})
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 0)) > int(b.get("priority", 0))
	)
	return job_id


func _process(_delta: float) -> void:
	var _profiler_start: int = FrameProfiler.begin("NavPathScheduler.process")
	_start_ready_jobs()
	FrameProfiler.end("NavPathScheduler.process", _profiler_start)


func _start_ready_jobs() -> void:
	if _queue.is_empty():
		return
	if _running_jobs.size() >= maxi(max_concurrent_jobs, 1):
		return
	var now: int = Time.get_ticks_msec()
	if now < _next_start_msec:
		return

	var job: Dictionary = _queue.pop_front() as Dictionary
	var job_id: int = int(job.get("id", 0))
	if job_id <= 0:
		return
	job["started_msec"] = Time.get_ticks_msec()
	_running_jobs[job_id] = job
	if str(job.get("tag", "")) == "AIPilot.recovery_approach":
		print("[NavPathScheduler] starting recovery job id=%d queued=%d" % [job_id, _queue.size()])
	var interval_ms: int = int(maxf(min_job_start_interval_s + _rng.randf_range(0.0, start_jitter_s), 0.0) * 1000.0)
	_next_start_msec = now + interval_ms

	WorkerThreadPool.add_task(func() -> void:
		var result: Variant = null
		var work: Callable = job.get("work", Callable())
		if work.is_valid():
			result = work.call()
		_complete_job.call_deferred(job_id, result)
	)


func _complete_job(job_id: int, result: Variant) -> void:
	if not _running_jobs.has(job_id):
		return
	var job: Dictionary = _running_jobs[job_id] as Dictionary
	_running_jobs.erase(job_id)
	if str(job.get("tag", "")) == "AIPilot.recovery_approach":
		print("[NavPathScheduler] completed recovery job id=%d elapsed=%dms" % [
			job_id,
			Time.get_ticks_msec() - int(job.get("started_msec", Time.get_ticks_msec())),
		])
	var callback: Callable = job.get("callback", Callable())
	if callback.is_valid():
		callback.call_deferred(result)
	_start_ready_jobs()


func get_pending_count() -> int:
	return _queue.size()


func get_running_count() -> int:
	return _running_jobs.size()
