extends CanvasLayer
## Autoload: shows splash image 5 + progress bar while TerrainNavGrid bakes.
## Fades out and removes itself once bake_complete fires.

const FADE_DURATION   := 1.0   # seconds to fade out after bake complete
const MIN_DISPLAY_S   := 2.0   # minimum time to show the splash
const BAR_HEIGHT      := 18    # pixels
const BAR_MARGIN      := 60    # pixels from screen bottom
const BAR_WIDTH_PCT   := 0.70  # fraction of screen width

var _root: Control   # single child Control; modulate this for fade
var _bar: ProgressBar
var _label: Label

var _fading      := false
var _fade_t      := 0.0
var _elapsed     := 0.0
var _bake_done   := false


func _ready() -> void:
	layer = 100

	# Root control fills the viewport — all children go inside so modulate works
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# --- Background splash ---
	var bg := TextureRect.new()
	bg.texture = load("res://splash image 5.png")
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	# --- Progress bar area (centered at bottom) ---
	var screen := DisplayServer.screen_get_size()
	var bar_w := int(screen.x * BAR_WIDTH_PCT)
	var bar_x := int((screen.x - bar_w) / 2)
	var bar_y := screen.y - BAR_MARGIN - BAR_HEIGHT

	# dark strip for contrast
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
	_label.text                  = "LOADING..."
	_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_label.position              = Vector2(0, bar_y - 22)
	_label.size                  = Vector2(screen.x, 20)
	_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_root.add_child(_label)

	TerrainNavGrid.bake_complete.connect(_on_bake_complete)


func _process(delta: float) -> void:
	_elapsed += delta

	if _fading:
		_fade_t += delta / FADE_DURATION
		_root.modulate = Color(1, 1, 1, 1.0 - clampf(_fade_t, 0.0, 1.0))
		if _fade_t >= 1.0:
			queue_free()
		return

	# Start fade once bake is done AND minimum display time has elapsed
	if _bake_done and _elapsed >= MIN_DISPLAY_S:
		_fading = true
		_fade_t = 0.0
		return

	var p := TerrainNavGrid.get_bake_progress()
	_bar.value = p
	_label.text = "LOADING..." if p < 0.01 else "LOADING  %d%%" % int(p * 100)


func _on_bake_complete() -> void:
	_bar.value   = 1.0
	_label.text  = "READY"
	_bake_done   = true
