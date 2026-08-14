extends CanvasLayer
## Reusable scenario-loading overlay. Scenario launchers explicitly activate it
## before changing scenes so the animated main-menu terrain cannot consume it.

const GAME_SCENE_PATH := "res://Main_Scene.tscn"
const SPLASH_TEXTURE: Texture2D = preload("res://Images/Splash/splash screen 8.png")

const FADE_DURATION_S := 0.65
const MIN_DISPLAY_S := 1.0
const NAVGRID_WEIGHT := 0.75
const TERRAIN_WEIGHT := 0.25
const NONSENSE_MESSAGE_INTERVAL_S := 1.65
const NONSENSE_LOADING_MESSAGES := [
	"RETICULATING CONTRAILS",
	"CALIBRATING THE RELATIVE WIND",
	"SYNCHRONIZING PORT AND STARBOARD GRAVITY",
	"DECONFLICTING THE SKYBOX",
	"PRESSURIZING THE FLIGHT ENVELOPE",
	"TRIMMING THE HORIZON",
	"POLISHING THE RADAR SHADOWS",
	"WARMING THE COLD AIR INTAKES",
	"TORQUING THE SKYHOOKS",
	"INDEXING ALL AVAILABLE CLOUDS",
	"HARMONIZING THE ANGLES OF ATTACK",
	"SPINNING UP THE EMERGENCY HEADWIND",
	"GREASING THE WAKE TURBULENCE",
	"ALIGNING THE RUNWAY WITH TRUE NORTH",
	"DEFROSTING THE AFTERBURNERS",
	"COUNTING THE REMAINING KNOTS",
	"TUNING THE SUPERSONIC CARBURETORS",
	"TEACHING THE AUTOPILOT HAND SIGNALS",
	"VERIFYING THAT LIFT REMAINS UPWARD",
	"FOLDING THE UNFOLDABLE WINGS",
]
const NONSENSE_DETAIL_TEXT := "GROUND CREW REPORTS EVERYTHING IS WITHIN IMAGINARY TOLERANCES"

var _root: Control
var _bar: ProgressBar
var _label: Label
var _detail_label: Label

var _active: bool = false
var _disabled_for_test_mode: bool = false
var _fading: bool = false
var _fade_t: float = 0.0
var _elapsed: float = 0.0
var _navgrid_done: bool = false
var _terrain_done: bool = false
var _nonsense_message_index: int = -1
var _nonsense_message_elapsed_s: float = 0.0

var _source_scene_id: int = 0
var _bound_scene_id: int = 0
var _terrain_node: Node = null
var _nav_grid: Node = null


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_hide_immediately()
	_nav_grid = get_node_or_null("/root/TerrainNavGrid")
	_connect_navgrid_signal()
	call_deferred("_activate_for_direct_game_launch")


## Called before changing from a menu or reloading a running scenario.
func begin_scenario_load() -> void:
	var current_scene: Node = get_tree().current_scene
	var source_id: int = current_scene.get_instance_id() if current_scene != null else 0
	_start_loading(source_id)


func disable_for_test_mode() -> void:
	_disabled_for_test_mode = true
	_hide_immediately()


func _activate_for_direct_game_launch() -> void:
	if _active:
		return
	var current_scene: Node = get_tree().current_scene
	if current_scene != null and current_scene.scene_file_path == GAME_SCENE_PATH:
		_start_loading(0)


func _start_loading(source_scene_id: int) -> void:
	_disabled_for_test_mode = false
	_active = true
	_fading = false
	_fade_t = 0.0
	_elapsed = 0.0
	_navgrid_done = false
	_terrain_done = false
	_source_scene_id = source_scene_id
	_bound_scene_id = 0
	_terrain_node = null
	_nav_grid = get_node_or_null("/root/TerrainNavGrid")
	_connect_navgrid_signal()
	_advance_nonsense_message()
	_nonsense_message_elapsed_s = 0.0
	visible = true
	_root.visible = true
	_root.modulate = Color.WHITE
	_bar.value = 0.0
	_label.text = "%s  0%%" % _current_nonsense_message()
	_detail_label.text = NONSENSE_DETAIL_TEXT
	set_process(true)


func _connect_navgrid_signal() -> void:
	if _nav_grid == null or not _nav_grid.has_signal("bake_complete"):
		return
	var callback := Callable(self, "_on_navgrid_bake_complete")
	if not _nav_grid.is_connected("bake_complete", callback):
		_nav_grid.connect("bake_complete", callback)


func _process(delta: float) -> void:
	if not _active or _disabled_for_test_mode:
		return
	_elapsed += delta

	if _fading:
		_fade_t += delta / FADE_DURATION_S
		_root.modulate.a = 1.0 - clampf(_fade_t, 0.0, 1.0)
		if _fade_t >= 1.0:
			_hide_immediately()
		return

	_try_bind_scenario_nodes()
	_update_completion_state()
	_update_nonsense_message(delta)
	_update_progress_display()

	if _navgrid_done and _terrain_done and _elapsed >= MIN_DISPLAY_S:
		_fading = true
		_fade_t = 0.0


func _try_bind_scenario_nodes() -> void:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return
	var current_id: int = current_scene.get_instance_id()
	if current_id == _source_scene_id:
		return
	if current_id != _bound_scene_id:
		_bound_scene_id = current_id
		_terrain_node = null
		_navgrid_done = false
		_terrain_done = false
	for candidate in get_tree().get_nodes_in_group("terrain_provider"):
		var candidate_node: Node = candidate as Node
		if candidate_node == current_scene or current_scene.is_ancestor_of(candidate_node):
			_terrain_node = candidate_node
			break
	if _nav_grid == null:
		_nav_grid = get_node_or_null("/root/TerrainNavGrid")
		_connect_navgrid_signal()
	if _nav_grid != null and _nav_grid.has_method("is_ready"):
		_navgrid_done = bool(_nav_grid.call("is_ready"))


func _update_completion_state() -> void:
	if _bound_scene_id == 0:
		return
	if not _navgrid_done and _nav_grid != null and _nav_grid.has_method("is_ready"):
		_navgrid_done = bool(_nav_grid.call("is_ready"))
	if _navgrid_done and not _terrain_done and is_instance_valid(_terrain_node):
		if _terrain_node.has_method("is_initial_load_complete"):
			_terrain_done = bool(_terrain_node.call("is_initial_load_complete"))
		else:
			_terrain_done = true


func _update_progress_display() -> void:
	var navgrid_fraction: float = 0.0
	if _nav_grid != null:
		if _nav_grid.has_method("get_bake_progress"):
			navgrid_fraction = float(_nav_grid.call("get_bake_progress"))
	if _navgrid_done:
		navgrid_fraction = 1.0

	var terrain_fraction: float = 0.0
	if _terrain_done:
		terrain_fraction = 1.0
	elif _navgrid_done and is_instance_valid(_terrain_node) and _terrain_node.has_method("get_chunk_load_fraction"):
		terrain_fraction = float(_terrain_node.call("get_chunk_load_fraction"))

	var overall: float = (
		navgrid_fraction * NAVGRID_WEIGHT
		+ terrain_fraction * TERRAIN_WEIGHT
	)
	_bar.value = maxf(_bar.value, clampf(overall, 0.0, 1.0))
	var percentage: int = int(floor(_bar.value * 100.0))

	if _navgrid_done and _terrain_done:
		_bar.value = 1.0
		_label.text = "DECLARING THE SKY AIRWORTHY  100%"
	else:
		_label.text = "%s  %d%%" % [_current_nonsense_message(), percentage]


func _update_nonsense_message(delta: float) -> void:
	_nonsense_message_elapsed_s += maxf(delta, 0.0)
	if _nonsense_message_elapsed_s < NONSENSE_MESSAGE_INTERVAL_S:
		return
	var advances: int = maxi(int(floor(_nonsense_message_elapsed_s / NONSENSE_MESSAGE_INTERVAL_S)), 1)
	_nonsense_message_elapsed_s = fmod(_nonsense_message_elapsed_s, NONSENSE_MESSAGE_INTERVAL_S)
	_nonsense_message_index = wrapi(
		_nonsense_message_index + advances,
		0,
		NONSENSE_LOADING_MESSAGES.size()
	)


func _advance_nonsense_message() -> void:
	_nonsense_message_index = wrapi(
		_nonsense_message_index + 1,
		0,
		NONSENSE_LOADING_MESSAGES.size()
	)


func _current_nonsense_message() -> String:
	if NONSENSE_LOADING_MESSAGES.is_empty():
		return "ADJUSTING THE AIR"
	var safe_index := clampi(_nonsense_message_index, 0, NONSENSE_LOADING_MESSAGES.size() - 1)
	return String(NONSENSE_LOADING_MESSAGES[safe_index])


func _on_navgrid_bake_complete() -> void:
	if _active and _bound_scene_id != 0:
		_navgrid_done = true


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "ScenarioLoadingRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var background := TextureRect.new()
	background.texture = SPLASH_TEXTURE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)

	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.02, 0.42)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	var strip := ColorRect.new()
	strip.color = Color(0.015, 0.02, 0.025, 0.90)
	strip.anchor_right = 1.0
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	strip.offset_top = -126.0
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(strip)

	_label = Label.new()
	_label.anchor_right = 1.0
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_top = -112.0
	_label.offset_bottom = -84.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.93, 0.82, 0.38))
	_root.add_child(_label)

	_bar = ProgressBar.new()
	_bar.anchor_left = 0.15
	_bar.anchor_right = 0.85
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_top = -78.0
	_bar.offset_bottom = -56.0
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	var bar_background := StyleBoxFlat.new()
	bar_background.bg_color = Color(0.04, 0.05, 0.055, 0.96)
	bar_background.border_color = Color(0.43, 0.45, 0.42, 0.9)
	bar_background.set_border_width_all(1)
	_bar.add_theme_stylebox_override("background", bar_background)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.91, 0.71, 0.18)
	_bar.add_theme_stylebox_override("fill", bar_fill)
	_root.add_child(_bar)

	_detail_label = Label.new()
	_detail_label.anchor_right = 1.0
	_detail_label.anchor_top = 1.0
	_detail_label.anchor_bottom = 1.0
	_detail_label.offset_top = -49.0
	_detail_label.offset_bottom = -25.0
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.add_theme_font_size_override("font_size", 12)
	_detail_label.add_theme_color_override("font_color", Color(0.68, 0.71, 0.70))
	_root.add_child(_detail_label)


func _hide_immediately() -> void:
	_active = false
	_fading = false
	visible = false
	set_process(false)
	if _root != null:
		_root.visible = false
		_root.modulate = Color.WHITE
