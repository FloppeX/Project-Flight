extends CanvasLayer
## Autoload: splash + progress bar that keeps the player waiting until the game
## is genuinely ready to play.
##
## Three phases (weights sum to 1.0):
##   1. NavGrid bake        — terrain A* grid computed row by row
##   2. Terrain chunks      — initial visible ring streamed in via WorkerThreadPool
##   3. FPS stabilisation   — frame rate holds above FPS_TARGET for FPS_STABLE_S seconds

const FADE_DURATION  := 1.5
const MIN_DISPLAY_S  := 2.0
const BAR_HEIGHT     := 18
const BAR_MARGIN     := 60
const BAR_WIDTH_PCT  := 0.70

const NAVGRID_WEIGHT := 0.50   # fraction of bar devoted to phase 1
const TERRAIN_WEIGHT := 0.35   # fraction of bar devoted to phase 2
const FPS_WEIGHT     := 0.15   # fraction of bar devoted to phase 3

const FPS_TARGET     := 25.0   # minimum FPS considered "stable"
const FPS_STABLE_S   := 2.0    # seconds FPS must hold above target to pass phase 3

var _root: Control
var _bar: ProgressBar
var _label: Label

var _fading          := false
var _fade_t          := 0.0
var _elapsed         := 0.0

var _navgrid_done    := false
var _terrain_done    := false
var _fps_stable_acc  := 0.0    # cumulative seconds above FPS_TARGET

var _terrain_node: Node = null


func _ready() -> void:
	layer = 100

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# --- Background splash ---
	var bg := TextureRect.new()
	bg.texture = load("res://Images/Splash/Splash screen 6.png")
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	# --- Progress bar area (centered at bottom) ---
	var screen := DisplayServer.screen_get_size()
	var bar_w  := int(screen.x * BAR_WIDTH_PCT)
	var bar_x  := int((screen.x - bar_w) / 2)
	var bar_y  := screen.y - BAR_MARGIN - BAR_HEIGHT

	var strip := ColorRect.new()
	strip.color    = Color(0, 0, 0, 0.55)
	strip.position = Vector2(0, bar_y - 14)
	strip.size     = Vector2(screen.x, BAR_HEIGHT + 28)
	_root.add_child(strip)

	_bar = ProgressBar.new()
	_bar.position        = Vector2(bar_x, bar_y)
	_bar.size            = Vector2(bar_w, BAR_HEIGHT)
	_bar.min_value       = 0.0
	_bar.max_value       = 1.0
	_bar.value           = 0.0
	_bar.show_percentage = false

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.08, 0.85)
	bg_style.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", bg_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.90, 0.75, 0.20, 1.0)
	fill_style.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill_style)
	_root.add_child(_bar)

	_label = Label.new()
	_label.text                 = "LOADING..."
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position             = Vector2(0, bar_y - 22)
	_label.size                 = Vector2(screen.x, 20)
	_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_root.add_child(_label)

	TerrainNavGrid.bake_complete.connect(_on_navgrid_bake_complete)


func _process(delta: float) -> void:
	_elapsed += delta

	if _fading:
		_fade_t += delta / FADE_DURATION
		_root.modulate = Color(1, 1, 1, 1.0 - clampf(_fade_t, 0.0, 1.0))
		if _fade_t >= 1.0:
			queue_free()
		return

	# --- Phase 2: terrain chunk streaming ---
	if _navgrid_done and not _terrain_done:
		if _terrain_node == null:
			_terrain_node = get_tree().get_first_node_in_group("terrain_provider")
		if is_instance_valid(_terrain_node) and _terrain_node.has_method("is_initial_load_complete"):
			if _terrain_node.is_initial_load_complete():
				_terrain_done = true

	# --- Phase 3: FPS stabilisation ---
	var fps_fraction := 0.0
	if _terrain_done:
		if Engine.get_frames_per_second() >= FPS_TARGET:
			_fps_stable_acc += delta
		else:
			# Decay faster than accumulate so a single bad frame resets noticeably
			_fps_stable_acc = maxf(0.0, _fps_stable_acc - delta * 3.0)
		fps_fraction = clampf(_fps_stable_acc / FPS_STABLE_S, 0.0, 1.0)

	# --- Compute overall bar value ---
	var navgrid_p  := TerrainNavGrid.get_bake_progress()
	var terrain_p  := 0.0
	if _terrain_done:
		terrain_p = 1.0
	elif _navgrid_done and is_instance_valid(_terrain_node) and _terrain_node.has_method("get_chunk_load_fraction"):
		terrain_p = _terrain_node.get_chunk_load_fraction()

	var overall := navgrid_p * NAVGRID_WEIGHT + terrain_p * TERRAIN_WEIGHT + fps_fraction * FPS_WEIGHT
	_bar.value = clampf(overall, _bar.value, 1.0)  # bar never goes backward

	# --- Label ---
	if not _navgrid_done:
		_label.text = "MAPPING TERRAIN  %d%%" % int(navgrid_p * 100)
	elif not _terrain_done:
		_label.text = "LOADING TERRAIN  %d%%" % int((NAVGRID_WEIGHT + terrain_p * TERRAIN_WEIGHT) * 100)
	elif fps_fraction < 1.0:
		_label.text = "PREPARING..."
	else:
		_label.text = "READY"

	# --- Dismiss when all phases complete and minimum time has elapsed ---
	if _navgrid_done and _terrain_done and fps_fraction >= 1.0 and _elapsed >= MIN_DISPLAY_S:
		_fading = true
		_fade_t = 0.0


func _on_navgrid_bake_complete() -> void:
	_navgrid_done = true
