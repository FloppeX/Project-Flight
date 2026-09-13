extends SceneTree
## Launched by --write-movie, never simulates a second battle.
var take: RefCounted
var camera: Camera3D
var directory := ""
var shot := 0
var clock := 0.0
var ready_to_render := false
var rendered_frames := 0
var frame_count := 1

func _initialize() -> void:
	call_deferred("_load_take")

func _load_take() -> void:
	AudioServer.set_bus_mute(0, true)
	for node in root.get_children():
		node.process_mode = Node.PROCESS_MODE_DISABLED
		if node is CanvasLayer: node.hide()
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--take": directory = args[index + 1]
		if args[index] == "--shot": shot = clampi(int(args[index + 1]), 0, 1)
	take = load("res://Recording/SceneTake.gd").new()
	if directory.is_empty() or not take.load_from(directory) or take.shots[shot].is_empty():
		push_error("ExportTake: missing take or camera keys")
		quit(1)
		return
	root.add_child(take.world)
	current_scene = take.world
	take.world.show()
	camera = load("res://Recording/RecordingCamera.gd").new()
	root.add_child(camera)
	camera.far = 20000.0
	camera.near = 0.1
	camera.make_current()
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	take.seek(0.0)
	camera.apply_keys(take.shots[shot], 0.0, take.subjects)
	# MovieWriter already captures the composed time-zero startup frame before
	# our first frame_post_draw callback. Count the remaining frames here.
	frame_count = maxi(1, ceili(take.duration() * 30.0) - 1)
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	ready_to_render = true

func _process(_delta: float) -> bool:
	if not ready_to_render: return false
	clock = (rendered_frames + 1) / 30.0
	take.seek(clock)
	camera.apply_keys(take.shots[shot], clock, take.subjects)
	return false

func _on_frame_drawn() -> void:
	if not ready_to_render: return
	rendered_frames += 1
	if rendered_frames < frame_count: return
	ready_to_render = false
	var file := FileAccess.open(directory.path_join("export_result.txt"), FileAccess.WRITE)
	if file != null: file.store_string("OK\n")
	print("[ExportTake] PASS shot=%d frames=%d seconds=%.2f (silent)" % [shot, rendered_frames, take.duration()])
	quit(0)
