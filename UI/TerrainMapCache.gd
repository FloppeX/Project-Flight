extends Node
## One bounded shared result per navigation generation. Images are built from
## copied plain arrays on a worker; all textures and signals stay on the main
## thread. Origin shifts only change consumers' live map bounds, not the pixels.

signal map_ready
signal map_invalidated

const Builder := preload("res://UI/WorldMapTextureBuilder.gd")
var _generation := 0
var _thread: Thread
var _job_generation := -1
var _want_build := false
var _textures: Dictionary = {}
var _build_count := 0
var _discarded_count := 0
var _worker_ms := 0.0
var _upload_ms := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	TerrainNavGrid.bake_invalidated.connect(invalidate)
	NavGraph.graph_invalidated.connect(invalidate)
	NavGraph.graph_ready.connect(_graph_ready)
	if NavGraph.is_ready(): _graph_ready()

func invalidate() -> void:
	_generation += 1
	_textures.clear()
	_want_build = false
	map_invalidated.emit()

func _graph_ready() -> void:
	invalidate()
	_want_build = true

func get_textures() -> Dictionary:
	# A getter must never start a synchronous raster build from a UI draw call.
	return _textures.duplicate()

func get_debug_snapshot() -> Dictionary:
	return {"generation": _generation, "ready": not _textures.is_empty(),
		"building": _thread != null, "build_count": _build_count,
		"discarded_count": _discarded_count, "worker_ms": _worker_ms, "upload_ms": _upload_ms}

func _process(_delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		var result: Dictionary = _thread.wait_to_finish()
		_thread = null
		_accept_result(_job_generation, result)
	if _thread == null and _want_build and TerrainNavGrid.is_ready() and NavGraph.is_ready():
		_start_build()

func _start_build() -> void:
	var started := FrameProfiler.begin("TerrainMapCache.snapshot")
	# Explicit copies avoid worker reads of arrays replaced/mutated by a rebake.
	var snapshot := {"heights": TerrainNavGrid._heights.duplicate(),
		"clearance": NavGraph._cl_map.duplicate(), "cols": TerrainNavGrid._cols,
		"rows": TerrainNavGrid._rows, "cell_size": TerrainNavGrid.cell_size_m}
	FrameProfiler.end("TerrainMapCache.snapshot", started)
	_want_build = false
	_job_generation = _generation
	_thread = Thread.new()
	var error := _thread.start(_build_snapshot.bind(snapshot))
	if error != OK:
		_thread = null
		push_warning("TerrainMapCache: could not start map worker (%d)" % error)
		return
	_build_count += 1

static func _build_snapshot(snapshot: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := Builder.build_images_from_snapshot(snapshot.heights, snapshot.clearance,
		snapshot.cols, snapshot.rows, snapshot.cell_size)
	result["worker_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	return result

func _accept_result(generation: int, result: Dictionary) -> void:
	if generation != _generation:
		_discarded_count += 1
		return
	var relief := result.get("relief") as Image
	var mobility := result.get("mobility") as Image
	if relief == null or mobility == null: return
	var started := FrameProfiler.begin("TerrainMapCache.upload")
	_textures = {"relief": ImageTexture.create_from_image(relief),
		"mobility": ImageTexture.create_from_image(mobility)}
	_worker_ms = float(result.get("worker_ms", 0.0))
	_upload_ms = (Time.get_ticks_usec() - started) / 1000.0 if started > 0 else 0.0
	FrameProfiler.end("TerrainMapCache.upload", started)
	map_ready.emit()

func _exit_tree() -> void:
	# The bounded worker must not outlive its script/resources during shutdown.
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
