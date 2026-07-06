extends Node
## Livery — Autoload singleton that stores the player's chosen colors
## and applies them to aircraft and the carrier.
##
## Aircraft materials "upper fuselage" / "lower fuselage" use the chosen colors.
## Carrier materials "main color 1/2/3", "base color 1/2/3", and legacy "blue plasteel" derive
## from upper_color so the whole fleet matches.
##
## Insignia decals use markers in aircraft scenes:
## - "InsigniaWing" (mirrored to left/right wings)
## - "InsigniaTail" (mirrored to left/right tail sides)
## - "InsigniaNose" (projected down and back from the nose)
## Adjust marker position in the editor per aircraft.

@export var upper_color := Color(0.28, 0.33, 0.38)   # Dark blue-grey
@export var lower_color := Color(0.72, 0.73, 0.74)   # Light grey
## How much darker "dark blue plasteel" is relative to the base carrier color.
@export var carrier_dark_factor := 0.6
## Hue offset for carrier base color variants 2 and 3.
@export var carrier_base_color_hue_offset := 0.01
## Target width of the insignia on the wing (height adjusts to match aspect ratio).
@export var insignia_width := 1.0
## Decal projection depth — how far into the wing the decal reaches.
@export var insignia_depth := 0.6
## Tail insignia size (smaller than wing insignia).
@export var tail_insignia_width := 0.65
@export var tail_insignia_depth := 0.35
## Nose insignia size (front fuselage decal).
@export var nose_insignia_width := 0.55
@export var nose_insignia_depth := 0.55
## Carrier hull insignia scale (much larger than wing insignia).
@export var carrier_insignia_width := 6.0
@export var carrier_insignia_depth := 4.0
@export_group("Test Markings")
@export var helicopter_upper_pattern_index := 0
## Legacy export names are kept so saved editor values continue to load.
@export var helicopter_upper_pattern_frequency_per_meter := 1.1
@export_range(0.01, 0.95, 0.01) var helicopter_upper_pattern_width_fraction := 0.18
@export var carrier_pattern_frequency_per_meter := 0.055
@export_range(0.01, 0.95, 0.01) var carrier_pattern_width_fraction := 0.22

## Insignia textures — loaded at startup.
var insignia_textures: Array[Texture2D] = []
var insignia_index: int = 0   # Which insignia is active
var _upper_color_preset_index: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _team_upper_preset_indices: Dictionary = {}
var _team_secondary_preset_indices: Dictionary = {}
var _team_insignia_indices: Dictionary = {}
var _player_custom_livery_enabled := false
var _player_custom_primary_color := Color(0.28, 0.33, 0.38)
var _player_custom_secondary_color := Color(0.90, 0.75, 0.20)
var _player_custom_pattern_index := 0
var _active_apply_upper_color: Color = Color(0.28, 0.33, 0.38)
var _active_apply_secondary_color: Color = Color(0.02, 0.02, 0.02)
var _active_apply_tertiary_color: Color = Color(0.35, 0.42, 0.22)
var _active_apply_insignia_index: int = 0
var _active_apply_has_pilot_colors: bool = false
var _active_apply_pilot_main_color: Color = Color(0.36, 0.40, 0.44)
var _active_apply_pilot_main_dark_color: Color = Color(0.17, 0.18, 0.20)
var _active_apply_pilot_helmet_color_1: Color = Color(0.36, 0.40, 0.44)
var _active_apply_pilot_helmet_color_2: Color = Color(0.36, 0.40, 0.44)
var _active_apply_is_carrier: bool = false
var _carrier_pattern_shader: Shader = null
const PLAYER_TEAM_ID: int = 1
const PILOT_LIVERY_META_KEY: StringName = &"pilot_livery_colors"
const UPPER_FUSELAGE_TEST_STRIPE_SHADER: Shader = preload("res://Shaders/upper_fuselage_test_stripes.gdshader")
const AIRCRAFT_UPPER_PATTERN_NAMES: Array[String] = [
	"off",
	"vertical stripes",
	"zebra stripes",
	"tiger stripes",
	"camo pattern",
	"horizontal lines",
	"polka dots",
	"horizontal lightning",
	"plaid",
	"squares",
	"stars",
	"digital camo",
	"chevrons",
	"wavy vertical",
	"wavy diagonal",
	"diamonds",
	"triangles",
	"angular shard camo",
	"angular splinter camo",
	"faceted camo",
	"front quarter color 2",
	"center half color 1",
	"tail quarter color 2",
	"quarter thirds",
	"offset block bands",
]

const PRESET_UPPER_COLOR_NAMES: Array[String] = [
	"BLACK",
	"CREAM",
	"ROSE PINK",
	"HOT PINK",
	"RED",
	"CRIMSON",
	"RUST",
	"ORANGE",
	"AMBER",
	"MUSTARD",
	"OLIVE",
	"GREEN",
	"FOREST",
	"SAGE MINT",
	"TEAL",
	"CYAN",
	"SKY BLUE",
	"COBALT",
	"NAVY",
	"VIOLET",
	"PLUM",
	"TAN",
	"BROWN",
	"STEEL GREY",
]

const PRESET_UPPER_COLORS: Array[Color] = [
	Color(0.03, 0.03, 0.03),  # Black
	Color(0.96, 0.93, 0.82),  # Cream
	Color(0.93, 0.62, 0.74),  # Rose Pink
	Color(0.86, 0.28, 0.55),  # Hot Pink
	Color(0.78, 0.16, 0.16),  # Red
	Color(0.53, 0.09, 0.18),  # Crimson
	Color(0.55, 0.24, 0.12),  # Rust
	Color(0.86, 0.42, 0.14),  # Orange
	Color(0.90, 0.66, 0.18),  # Amber
	Color(0.62, 0.52, 0.14),  # Mustard
	Color(0.36, 0.38, 0.17),  # Olive
	Color(0.16, 0.47, 0.20),  # Green
	Color(0.10, 0.28, 0.14),  # Forest
	Color(0.47, 0.68, 0.56),  # Sage Mint
	Color(0.12, 0.46, 0.45),  # Teal
	Color(0.17, 0.62, 0.67),  # Cyan
	Color(0.46, 0.68, 0.86),  # Sky Blue
	Color(0.20, 0.33, 0.73),  # Cobalt
	Color(0.09, 0.13, 0.30),  # Navy
	Color(0.48, 0.32, 0.64),  # Violet
	Color(0.31, 0.17, 0.40),  # Plum
	Color(0.73, 0.60, 0.44),  # Tan
	Color(0.37, 0.24, 0.15),  # Brown
	Color(0.36, 0.40, 0.44),  # Steel Grey
]

const PILOT_MAIN_COLOR_POOL: Array[Color] = [
	Color(0.36, 0.40, 0.44),  # Grey
	Color(0.73, 0.60, 0.44),  # Tan
	Color(0.16, 0.47, 0.20),  # Green
	Color(0.09, 0.13, 0.30),  # Dark Blue
]

const PILOT_MAIN_DARK_COLOR_POOL: Array[Color] = [
	Color(0.17, 0.18, 0.20),  # Dark Grey
	Color(0.37, 0.24, 0.15),  # Brown
	Color(0.09, 0.13, 0.30),  # Dark Blue
]

func _ready() -> void:
	_rng.randomize()
	for path in _find_insignia_paths():
		var tex := load(path) as Texture2D
		if tex:
			insignia_textures.append(tex)
	_reset_team_livery_assignments()
	call_deferred("_reapply_all")

func set_player_livery(primary_color: Color, secondary_color: Color, pattern_index: int) -> void:
	_player_custom_livery_enabled = true
	_player_custom_primary_color = primary_color
	_player_custom_secondary_color = secondary_color
	_player_custom_pattern_index = clampi(pattern_index, 0, max(AIRCRAFT_UPPER_PATTERN_NAMES.size() - 1, 0))
	upper_color = primary_color
	lower_color = secondary_color
	helicopter_upper_pattern_index = _player_custom_pattern_index
	_reapply_all()


func set_player_insignia(index: int) -> void:
	if insignia_textures.is_empty():
		return
	_ensure_team_livery(PLAYER_TEAM_ID)
	var safe_index := clampi(index, 0, insignia_textures.size() - 1)
	_team_insignia_indices[PLAYER_TEAM_ID] = safe_index
	insignia_index = safe_index
	_reapply_all()


func get_preset_upper_color_count() -> int:
	return PRESET_UPPER_COLORS.size()

func get_preset_upper_color(index: int) -> Color:
	if PRESET_UPPER_COLORS.is_empty():
		return Color.WHITE
	return PRESET_UPPER_COLORS[clampi(index, 0, PRESET_UPPER_COLORS.size() - 1)]

func get_preset_upper_color_name(index: int) -> String:
	if PRESET_UPPER_COLOR_NAMES.is_empty():
		return "COLOR"
	return PRESET_UPPER_COLOR_NAMES[clampi(index, 0, PRESET_UPPER_COLOR_NAMES.size() - 1)]


func get_insignia_count() -> int:
	return insignia_textures.size()


func get_insignia_name(index: int) -> String:
	if insignia_textures.is_empty():
		return "NONE"
	var tex := insignia_textures[clampi(index, 0, insignia_textures.size() - 1)]
	var label := tex.resource_path.get_file().get_basename()
	if label.to_lower().begins_with("insignia "):
		label = label.substr("insignia ".length())
	return label.replace("_", " ").replace("-", " ").to_upper()


func get_livery_pattern_count() -> int:
	return AIRCRAFT_UPPER_PATTERN_NAMES.size()


func get_livery_pattern_name(index: int) -> String:
	if AIRCRAFT_UPPER_PATTERN_NAMES.is_empty():
		return "SOLID"
	var label := AIRCRAFT_UPPER_PATTERN_NAMES[clampi(index, 0, AIRCRAFT_UPPER_PATTERN_NAMES.size() - 1)]
	return "SOLID" if label == "off" else label.to_upper()


func get_livery_pattern_index(index: int) -> int:
	return clampi(index, 0, max(AIRCRAFT_UPPER_PATTERN_NAMES.size() - 1, 0))

var _c_was_pressed := false
var _v_was_pressed := false
var _k_was_pressed := false
var _j_was_pressed := false

func _process(_delta: float) -> void:
	var c_now := Input.is_key_pressed(KEY_C)
	var v_now := Input.is_key_pressed(KEY_V)
	var k_now := Input.is_key_pressed(KEY_K)
	var j_now := Input.is_key_pressed(KEY_J)
	if c_now and not _c_was_pressed:
		cycle_upper_color()
	if v_now and not _v_was_pressed:
		cycle_insignia()
	if k_now and not _k_was_pressed:
		cycle_aircraft_upper_pattern()
	if j_now and not _j_was_pressed:
		cycle_secondary_color()
	_c_was_pressed = c_now
	_v_was_pressed = v_now
	_k_was_pressed = k_now
	_j_was_pressed = j_now

func _find_insignia_paths() -> Array[String]:
	var paths: Array[String] = []
	_collect_insignia_paths_recursive("res://Images/Insignia", paths)
	paths.sort()
	return paths

func _collect_insignia_paths_recursive(dir_path: String, paths: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if file_name.begins_with("."):
			continue
		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			_collect_insignia_paths_recursive(full_path, paths)
			continue
		var lower_name := file_name.to_lower()
		if not (lower_name.ends_with(".png") or lower_name.ends_with(".jpg") or lower_name.ends_with(".jpeg") or lower_name.ends_with(".webp")):
			continue
		paths.append(full_path)
	dir.list_dir_end()

func randomize_upper_color() -> void:
	# Backward-compatible alias: C now cycles fixed presets instead of random.
	cycle_upper_color()

func cycle_upper_color() -> void:
	if PRESET_UPPER_COLORS.is_empty():
		return
	_ensure_team_livery(PLAYER_TEAM_ID)
	_upper_color_preset_index = (int(_team_upper_preset_indices.get(PLAYER_TEAM_ID, 0)) + 1) % PRESET_UPPER_COLORS.size()
	_team_upper_preset_indices[PLAYER_TEAM_ID] = _upper_color_preset_index
	upper_color = PRESET_UPPER_COLORS[_upper_color_preset_index]
	_reapply_all()

func _nearest_upper_color_preset_index(col: Color) -> int:
	if PRESET_UPPER_COLORS.is_empty():
		return 0
	var best_idx: int = 0
	var best_dist_sq: float = INF
	for i in range(PRESET_UPPER_COLORS.size()):
		var p: Color = PRESET_UPPER_COLORS[i]
		var dr: float = col.r - p.r
		var dg: float = col.g - p.g
		var db: float = col.b - p.b
		var d_sq: float = dr * dr + dg * dg + db * db
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_idx = i
	return best_idx

func cycle_insignia() -> void:
	if insignia_textures.is_empty():
		return
	_ensure_team_livery(PLAYER_TEAM_ID)
	insignia_index = (int(_team_insignia_indices.get(PLAYER_TEAM_ID, 0)) + 1) % insignia_textures.size()
	_team_insignia_indices[PLAYER_TEAM_ID] = insignia_index
	_reapply_all()

func cycle_aircraft_upper_pattern() -> void:
	if AIRCRAFT_UPPER_PATTERN_NAMES.is_empty():
		return
	helicopter_upper_pattern_index = (helicopter_upper_pattern_index + 1) % AIRCRAFT_UPPER_PATTERN_NAMES.size()
	_reapply_all()
	print("[Livery] Aircraft/carrier test pattern: ", AIRCRAFT_UPPER_PATTERN_NAMES[helicopter_upper_pattern_index])

func cycle_helicopter_upper_pattern() -> void:
	cycle_aircraft_upper_pattern()

func _reapply_all() -> void:
	var seen_ids: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft", "friendlies", "ground_vehicles", "enemies", "buildings", "carrier"]:
		var nodes: Array = get_tree().get_nodes_in_group(group_name)
		for node_variant in nodes:
			if not (node_variant is Node):
				continue
			var node: Node = node_variant as Node
			var instance_id: int = node.get_instance_id()
			if seen_ids.has(instance_id):
				continue
			seen_ids[instance_id] = true
			if _can_apply_to_node(node):
				apply(node)

func _can_apply_to_node(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.is_in_group("carrier"):
		return true
	if node.has_method("get_team"):
		return true
	var team_variant: Variant = node.get("team")
	return typeof(team_variant) in [TYPE_INT, TYPE_FLOAT]

## Apply livery colors and insignia to all matching surfaces under `root`.
func apply(root: Node) -> void:
	var team_id: int = _resolve_team_id(root)
	_ensure_team_livery(team_id)
	_active_apply_upper_color = _get_team_upper_color(team_id)
	_active_apply_secondary_color = _get_team_secondary_color(team_id)
	_active_apply_tertiary_color = _get_team_tertiary_color(team_id)
	_active_apply_insignia_index = _get_team_insignia_index(team_id)
	_activate_pilot_colors_for_root(root)
	if team_id == PLAYER_TEAM_ID:
		upper_color = _active_apply_upper_color
		_upper_color_preset_index = int(_team_upper_preset_indices.get(PLAYER_TEAM_ID, _upper_color_preset_index))
		insignia_index = _active_apply_insignia_index
	_active_apply_is_carrier = root.is_in_group("carrier")
	_apply_recursive(root)
	if root is RigidBody3D and root.get("team") != null:
		_apply_insignia(root)
	if root.is_in_group("carrier"):
		_apply_carrier_insignia(root)

func _reset_team_livery_assignments() -> void:
	_team_upper_preset_indices.clear()
	_team_secondary_preset_indices.clear()
	_team_insignia_indices.clear()
	_ensure_team_livery(PLAYER_TEAM_ID)
	upper_color = _get_team_upper_color(PLAYER_TEAM_ID)
	_upper_color_preset_index = int(_team_upper_preset_indices.get(PLAYER_TEAM_ID, 0))
	insignia_index = _get_team_insignia_index(PLAYER_TEAM_ID)

func _resolve_team_id(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return PLAYER_TEAM_ID
	if node.has_method("get_team"):
		return int(node.call("get_team"))
	var team_variant: Variant = node.get("team")
	if typeof(team_variant) in [TYPE_INT, TYPE_FLOAT]:
		return int(team_variant)
	if node.is_in_group("carrier"):
		return PLAYER_TEAM_ID
	var groups: Array[StringName] = node.get_groups()
	for group_name_variant in groups:
		var group_name: String = String(group_name_variant)
		if not group_name.begins_with("team_"):
			continue
		var suffix: String = group_name.substr(5)
		if suffix.is_valid_int():
			return int(suffix)
	return PLAYER_TEAM_ID

func _ensure_team_livery(team_id: int) -> void:
	if not _team_upper_preset_indices.has(team_id):
		if team_id != PLAYER_TEAM_ID:
			_team_upper_preset_indices[team_id] = _pick_distant_index_from_player()
		else:
			_team_upper_preset_indices[team_id] = _pick_random_unassigned_index(PRESET_UPPER_COLORS.size(), _team_upper_preset_indices)
	if not _team_secondary_preset_indices.has(team_id):
		_team_secondary_preset_indices[team_id] = _rng.randi_range(0, PRESET_UPPER_COLORS.size() - 1)
	if not _team_insignia_indices.has(team_id):
		if insignia_textures.is_empty():
			_team_insignia_indices[team_id] = 0
		else:
			_team_insignia_indices[team_id] = _pick_random_unassigned_index(insignia_textures.size(), _team_insignia_indices)

func _pick_random_unassigned_index(pool_size: int, assignments: Dictionary) -> int:
	if pool_size <= 1:
		return 0
	var used_indices: Dictionary = {}
	for assigned_variant in assignments.values():
		var assigned_index: int = int(assigned_variant)
		if assigned_index >= 0 and assigned_index < pool_size:
			used_indices[assigned_index] = true
	var available_indices: Array[int] = []
	for i in range(pool_size):
		if not used_indices.has(i):
			available_indices.append(i)
	if available_indices.is_empty():
		return _rng.randi_range(0, pool_size - 1)
	return available_indices[_rng.randi_range(0, available_indices.size() - 1)]

func _get_team_upper_color(team_id: int) -> Color:
	_ensure_team_livery(team_id)
	if team_id == PLAYER_TEAM_ID and _player_custom_livery_enabled:
		return _player_custom_primary_color
	var idx: int = int(_team_upper_preset_indices.get(team_id, 0))
	idx = clampi(idx, 0, PRESET_UPPER_COLORS.size() - 1)
	return PRESET_UPPER_COLORS[idx]

func _get_team_insignia_index(team_id: int) -> int:
	_ensure_team_livery(team_id)
	if insignia_textures.is_empty():
		return 0
	return clampi(int(_team_insignia_indices.get(team_id, 0)), 0, insignia_textures.size() - 1)

func _activate_pilot_colors_for_root(root: Node) -> void:
	_active_apply_has_pilot_colors = false
	if root == null or not is_instance_valid(root):
		return
	if root.get_node_or_null("CockpitPilot") == null:
		return
	var palette: Dictionary = _get_or_assign_pilot_palette(root)
	if palette.is_empty():
		return

	var main_variant: Variant = palette.get("main_color", null)
	var main_dark_variant: Variant = palette.get("main_color_dark", null)
	var helmet_1_variant: Variant = palette.get("helmet_color_1", null)
	var helmet_2_variant: Variant = palette.get("helmet_color_2", null)
	if not (main_variant is Color and main_dark_variant is Color and helmet_1_variant is Color and helmet_2_variant is Color):
		return

	_active_apply_pilot_main_color = main_variant as Color
	_active_apply_pilot_main_dark_color = main_dark_variant as Color
	_active_apply_pilot_helmet_color_1 = helmet_1_variant as Color
	_active_apply_pilot_helmet_color_2 = helmet_2_variant as Color
	_active_apply_has_pilot_colors = true

func _get_or_assign_pilot_palette(root: Node) -> Dictionary:
	if root.has_meta(PILOT_LIVERY_META_KEY):
		var existing_variant: Variant = root.get_meta(PILOT_LIVERY_META_KEY)
		if existing_variant is Dictionary:
			var existing: Dictionary = existing_variant
			if _is_valid_pilot_palette(existing):
				return existing

	var created: Dictionary = _make_random_pilot_palette()
	root.set_meta(PILOT_LIVERY_META_KEY, created)
	return created

func _is_valid_pilot_palette(palette: Dictionary) -> bool:
	var main_variant: Variant = palette.get("main_color", null)
	var main_dark_variant: Variant = palette.get("main_color_dark", null)
	var helmet_1_variant: Variant = palette.get("helmet_color_1", null)
	var helmet_2_variant: Variant = palette.get("helmet_color_2", null)
	return main_variant is Color and main_dark_variant is Color and helmet_1_variant is Color and helmet_2_variant is Color

func _make_random_pilot_palette() -> Dictionary:
	var helmet_1: Color = _pick_random_color(PRESET_UPPER_COLORS)
	var helmet_2: Color = _pick_random_color(PRESET_UPPER_COLORS)
	if PRESET_UPPER_COLORS.size() > 1:
		var safety: int = 4
		while helmet_2 == helmet_1 and safety > 0:
			helmet_2 = _pick_random_color(PRESET_UPPER_COLORS)
			safety -= 1
	return {
		"main_color": _pick_random_color(PILOT_MAIN_COLOR_POOL),
		"main_color_dark": _pick_random_color(PILOT_MAIN_DARK_COLOR_POOL),
		"helmet_color_1": helmet_1,
		"helmet_color_2": helmet_2,
	}

func _pick_random_color(pool: Array[Color]) -> Color:
	if pool.is_empty():
		return Color.WHITE
	return pool[_rng.randi_range(0, pool.size() - 1)]

## Public: returns the raw upper fuselage color for a team.
func get_team_upper_color(team_id: int) -> Color:
	return _get_team_upper_color(team_id)

func _get_team_secondary_color(team_id: int) -> Color:
	_ensure_team_livery(team_id)
	if team_id == PLAYER_TEAM_ID and _player_custom_livery_enabled:
		return _player_custom_secondary_color
	var idx := int(_team_secondary_preset_indices.get(team_id, 0))
	return PRESET_UPPER_COLORS[clampi(idx, 0, PRESET_UPPER_COLORS.size() - 1)]

func _get_team_tertiary_color(team_id: int) -> Color:
	if team_id == PLAYER_TEAM_ID and _player_custom_livery_enabled:
		return _color_between_hues(_player_custom_primary_color, _player_custom_secondary_color)
	return _color_between_hues(_get_team_upper_color(team_id), _get_team_secondary_color(team_id))

func _color_between_hues(primary: Color, secondary: Color) -> Color:
	var hue_delta := fposmod(secondary.h - primary.h + 0.5, 1.0) - 0.5
	var midpoint_hue := fposmod(primary.h + hue_delta * 0.5, 1.0)
	var midpoint_saturation := (primary.s + secondary.s) * 0.5
	var midpoint_value := (primary.v + secondary.v) * 0.5
	var midpoint_alpha := (primary.a + secondary.a) * 0.5
	return Color.from_hsv(midpoint_hue, midpoint_saturation, midpoint_value, midpoint_alpha)

func cycle_secondary_color() -> void:
	if PRESET_UPPER_COLORS.is_empty():
		return
	_ensure_team_livery(PLAYER_TEAM_ID)
	var index := (int(_team_secondary_preset_indices.get(PLAYER_TEAM_ID, 0)) + 1) % PRESET_UPPER_COLORS.size()
	_team_secondary_preset_indices[PLAYER_TEAM_ID] = index
	_reapply_all()
	print("[Livery] Aircraft pattern secondary color changed to preset index: ", index, " (", PRESET_UPPER_COLORS[index], ")")

## Public: returns a bright, HUD-readable color for a team (same hue, boosted S/V).
## Useful for map and hologram markers so muted fuselage colors remain legible.
func get_team_hud_color(team_id: int) -> Color:
	var col := _get_team_upper_color(team_id)
	var h := col.h
	var s := col.s
	var v := col.v
	v = maxf(v, 0.75)
	if s > 0.05:
		s = maxf(s, 0.45)
	return Color.from_hsv(h, s, v, 1.0)

func _shift_hue(color: Color, hue_offset: float) -> Color:
	return Color.from_hsv(fposmod(color.h + hue_offset, 1.0), color.s, color.v, color.a)

func _normalized_material_name(material: Material) -> String:
	return String(material.resource_name).to_lower().replace("_", " ").replace("-", " ").strip_edges()

func _hue_distance(a: float, b: float) -> float:
	var d := absf(a - b)
	if d > 0.5:
		d = 1.0 - d
	return d

## Picks the preset index most hue-distant from the player's current color,
## preferring saturated colors so the enemy has a readable distinct map tint.
func _pick_distant_index_from_player() -> int:
	var player_idx: int = int(_team_upper_preset_indices.get(PLAYER_TEAM_ID, 0))
	var player_col: Color = PRESET_UPPER_COLORS[clampi(player_idx, 0, PRESET_UPPER_COLORS.size() - 1)]
	var used: Dictionary = {}
	for tid in _team_upper_preset_indices.keys():
		used[int(_team_upper_preset_indices[tid])] = true

	var best_idx: int = -1
	var best_dist: float = -1.0
	for i in range(PRESET_UPPER_COLORS.size()):
		if used.has(i):
			continue
		var col: Color = PRESET_UPPER_COLORS[i]
		if col.s < 0.2:   # skip near-greyscale presets for enemy tint
			continue
		var dist: float
		if player_col.s < 0.1:
			# Player is achromatic — prefer more saturated enemy colors
			dist = col.s + col.v * 0.2
		else:
			dist = _hue_distance(player_col.h, col.h)
		if dist > best_dist:
			best_dist = dist
			best_idx = i

	if best_idx == -1:
		# Fallback: any unassigned index
		return _pick_random_unassigned_index(PRESET_UPPER_COLORS.size(), _team_upper_preset_indices)
	return best_idx

func _apply_insignia(aircraft: Node) -> void:
	# Remove old decals from the full aircraft subtree.
	for decal in get_tree().get_nodes_in_group("livery_insignia"):
		if decal is Node and _is_descendant_of(decal as Node, aircraft):
			(decal as Node).queue_free()

	if insignia_textures.is_empty() or _active_apply_insignia_index < 0:
		return
	var tex: Texture2D = insignia_textures[_active_apply_insignia_index]
	var aspect := float(tex.get_height()) / maxf(float(tex.get_width()), 1.0)

	var aircraft_3d: Node3D = aircraft as Node3D
	if aircraft_3d == null:
		return

	# Insignia placement is driven entirely by InsigniaMarker cylinder gizmos placed
	# in the aircraft scene. Each marker = one decal: the cylinder's transform is the
	# decal's transform (Decal projects along local -Y, same as the cylinder's axis),
	# its diameter is the insignia size, its length is the projection depth. The
	# marker mesh is hidden at runtime. One cylinder per insignia, no mirroring.
	var markers: Array[Node] = []
	_collect_insignia_markers(aircraft_3d, markers)
	for marker_node in markers:
		var marker := marker_node as Node3D
		if marker == null:
			continue
		# Hide the editor gizmo in-game.
		marker.visible = false

		var decal := Decal.new()
		decal.name = "InsigniaDecal_%s" % marker.name
		decal.add_to_group("livery_insignia")
		decal.texture_albedo = tex
		decal.sorting_offset = 10.0
		decal.upper_fade = 0.0
		decal.lower_fade = 0.0

		# Size from the marker (diameter / depth), with texture aspect applied.
		if marker.has_method("get_decal_size"):
			decal.size = marker.call("get_decal_size", aspect)
		else:
			decal.size = Vector3(1.0, 0.6, aspect)

		# Parent the decal to the marker's own parent so it inherits the exact same
		# transform context (and follows folding wing parts, tail sections, etc.).
		var host: Node = marker.get_parent()
		if not (host is Node3D):
			host = aircraft_3d
		(host as Node3D).add_child(decal)
		# The decal sits exactly where the cylinder is, projecting along the same -Y.
		decal.transform = (marker as Node3D).transform

## Recursively collect every InsigniaMarker under `node`. Detected by duck-typing
## (the get_decal_size method) so this doesn't depend on the global class_name being
## registered at parse time.
func _collect_insignia_markers(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child is Node3D and child.has_method("get_decal_size"):
			out.append(child)
		_collect_insignia_markers(child, out)


func _make_decal_basis_from_projection(projection_dir: Vector3, up_hint: Vector3) -> Basis:
	var y_axis := (-projection_dir).normalized()
	var z_axis := up_hint - y_axis * up_hint.dot(y_axis)
	if z_axis.length_squared() < 0.0001:
		z_axis = Vector3.FORWARD - y_axis * Vector3.FORWARD.dot(y_axis)
	z_axis = z_axis.normalized()
	var x_axis := y_axis.cross(z_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()

func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var cur: Node = node
	while cur != null:
		if cur == ancestor:
			return true
		cur = cur.get_parent()
	return false

func _find_node3d_by_names(root: Node, names: Array[String]) -> Node3D:
	var desired: Array[String] = []
	for n in names:
		desired.append(n.to_lower())
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Node3D:
			var cur_name: String = cur.name.to_lower()
			if desired.has(cur_name):
				return cur as Node3D
		for child in cur.get_children():
			if child is Node:
				stack.append(child as Node)
	return null

func _resolve_wing_hosts(aircraft: Node) -> Dictionary:
	var left_host: Node3D = null
	var right_host: Node3D = null

	# Prefer explicit wing references captured by wing-fold scripts.
	var wing_fold5: Node = aircraft.get_node_or_null("WingFold5")
	if wing_fold5 != null:
		var left_variant: Variant = wing_fold5.get("_left_wing")
		var right_variant: Variant = wing_fold5.get("_right_wing")
		if left_variant is Node3D:
			left_host = left_variant as Node3D
		if right_variant is Node3D:
			right_host = right_variant as Node3D

	var wing_fold: Node = aircraft.get_node_or_null("WingFold")
	if wing_fold != null:
		if left_host == null:
			var left_variant: Variant = wing_fold.get("_left_wing")
			if left_variant is Node3D:
				left_host = left_variant as Node3D
		if right_host == null:
			var right_variant: Variant = wing_fold.get("_right_wing")
			if right_variant is Node3D:
				right_host = right_variant as Node3D

	# Fallback to name search for aircraft without wing-fold scripts.
	if right_host == null:
		right_host = _find_node3d_by_names(aircraft, ["outer wing right", "right outer wing"])
	if left_host == null:
		left_host = _find_node3d_by_names(aircraft, ["outer wing left", "left outer wing"])

	return {
		"left": left_host,
		"right": right_host,
	}

func _resolve_wing_hosts_by_aircraft_x(aircraft_root: Node3D, left_host: Node3D, right_host: Node3D) -> Dictionary:
	var hosts: Array[Node3D] = []
	if left_host != null:
		hosts.append(left_host)
	if right_host != null and right_host != left_host:
		hosts.append(right_host)
	if hosts.is_empty():
		return {"positive": null, "negative": null}

	var positive_host: Node3D = hosts[0]
	var negative_host: Node3D = hosts[0]
	var positive_x: float = _host_origin_x_in_aircraft_space(aircraft_root, hosts[0])
	var negative_x: float = positive_x
	for i in range(1, hosts.size()):
		var h: Node3D = hosts[i]
		var x: float = _host_origin_x_in_aircraft_space(aircraft_root, h)
		if x > positive_x:
			positive_x = x
			positive_host = h
		if x < negative_x:
			negative_x = x
			negative_host = h
	return {"positive": positive_host, "negative": negative_host}

func _host_origin_x_in_aircraft_space(aircraft_root: Node3D, host: Node3D) -> float:
	var rest_local_variant: Variant = _resolve_host_rest_local_transform(aircraft_root, host)
	var host_global: Transform3D
	if rest_local_variant is Transform3D:
		var host_parent: Node3D = host.get_parent() as Node3D
		if host_parent != null:
			host_global = host_parent.global_transform * (rest_local_variant as Transform3D)
		else:
			host_global = host.global_transform
	else:
		host_global = host.global_transform
	var host_in_aircraft: Transform3D = aircraft_root.global_transform.affine_inverse() * host_global
	return host_in_aircraft.origin.x

func _marker_transform_to_host_local(aircraft_root: Node3D, host: Node3D, marker_local_to_aircraft: Transform3D) -> Transform3D:
	var target_global: Transform3D = aircraft_root.global_transform * marker_local_to_aircraft
	var rest_local_variant: Variant = _resolve_host_rest_local_transform(aircraft_root, host)
	if rest_local_variant is Transform3D:
		var host_parent: Node3D = host.get_parent() as Node3D
		if host_parent != null:
			var host_rest_global: Transform3D = host_parent.global_transform * (rest_local_variant as Transform3D)
			return host_rest_global.affine_inverse() * target_global
	return host.global_transform.affine_inverse() * target_global

func _resolve_host_rest_local_transform(aircraft_root: Node3D, host: Node3D) -> Variant:
	var meta_rest: Variant = host.get_meta("livery_rest_transform_local", null)
	if meta_rest is Transform3D:
		return meta_rest

	# Fallback: ask wing-fold scripts for authored rest values if metadata
	# was not populated yet when livery was first applied.
	var wing_fold5: Node = aircraft_root.get_node_or_null("WingFold5")
	var rest_from_wf5: Variant = _resolve_rest_from_wing_fold5(wing_fold5, host)
	if rest_from_wf5 is Transform3D:
		return rest_from_wf5

	var wing_fold: Node = aircraft_root.get_node_or_null("WingFold")
	var rest_from_wf: Variant = _resolve_rest_from_wing_fold(wing_fold, host)
	if rest_from_wf is Transform3D:
		return rest_from_wf

	return null

func _resolve_rest_from_wing_fold5(wing_fold5: Node, host: Node3D) -> Variant:
	if wing_fold5 == null:
		return null
	var left_wing: Variant = wing_fold5.get("_left_wing")
	if left_wing == host:
		var left_quat: Variant = wing_fold5.get("_left_rest_quat")
		var left_pos: Variant = wing_fold5.get("_left_rest_pos")
		if left_quat is Quaternion and left_pos is Vector3:
			return Transform3D(Basis(left_quat as Quaternion), left_pos as Vector3)
	var right_wing: Variant = wing_fold5.get("_right_wing")
	if right_wing == host:
		var right_quat: Variant = wing_fold5.get("_right_rest_quat")
		var right_pos: Variant = wing_fold5.get("_right_rest_pos")
		if right_quat is Quaternion and right_pos is Vector3:
			return Transform3D(Basis(right_quat as Quaternion), right_pos as Vector3)
	return null

func _resolve_rest_from_wing_fold(wing_fold: Node, host: Node3D) -> Variant:
	if wing_fold == null:
		return null
	var left_wing: Variant = wing_fold.get("_left_wing")
	if left_wing == host:
		var left_quat: Variant = wing_fold.get("_left_rest_quat")
		var left_pos: Variant = wing_fold.get("_left_rest_pos")
		if left_quat is Quaternion and left_pos is Vector3:
			return Transform3D(Basis(left_quat as Quaternion), left_pos as Vector3)
	var right_wing: Variant = wing_fold.get("_right_wing")
	if right_wing == host:
		var right_quat: Variant = wing_fold.get("_right_rest_quat")
		var right_pos: Variant = wing_fold.get("_right_rest_pos")
		if right_quat is Quaternion and right_pos is Vector3:
			return Transform3D(Basis(right_quat as Quaternion), right_pos as Vector3)
	return null

func _apply_carrier_insignia(carrier: Node) -> void:
	# Remove old carrier decals
	for child in carrier.get_children():
		if child.is_in_group("livery_carrier_insignia"):
			child.queue_free()

	if insignia_textures.is_empty() or _active_apply_insignia_index < 0:
		return
	var tex: Texture2D = insignia_textures[_active_apply_insignia_index]

	var tex_w := float(tex.get_width())
	var tex_h := float(tex.get_height())
	var aspect := tex_h / maxf(tex_w, 1.0)
	var decal_size := Vector3(carrier_insignia_width, carrier_insignia_depth, carrier_insignia_width * aspect)

	# Place a decal at each InsigniaHull marker. Only position matters — rotation is ignored.
	# Name ending with "R" projects toward +X (starboard), otherwise toward -X (port).
	for child in carrier.get_children():
		if child is Marker3D and child.name.begins_with("InsigniaHull"):
			var inward := -1.0 if child.name.ends_with("R") else 1.0
			var decal := Decal.new()
			decal.name = child.name + "Decal"
			decal.add_to_group("livery_carrier_insignia")
			decal.texture_albedo = tex
			decal.size = decal_size
			decal.sorting_offset = 10.0
			decal.upper_fade = 0.0
			decal.lower_fade = 0.0
			decal.transform.origin = child.transform.origin
			decal.transform.basis = Basis(
				Vector3(0, 0, -1),         # decal X → carrier aft
				Vector3(inward, 0, 0),     # decal -Y → projects into wall
				Vector3(0, -1, 0)          # decal Z → down
			)
			carrier.add_child(decal)

func _apply_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for i in range(mesh.get_surface_count()):
				var mat = mesh.surface_get_material(i)
				if mat == null:
					continue
				var mat_name: String = _normalized_material_name(mat)
				var target_color := Color(-1, 0, 0)  # sentinel
				var is_upper_fuselage_surface := false
				var is_lower_fuselage_surface := false
				var is_carrier_pattern_surface := false
				if "upper fuselage" in mat_name:
					target_color = _active_apply_upper_color
					is_upper_fuselage_surface = true
				elif "lower fuselage" in mat_name:
					target_color = lower_color
					is_lower_fuselage_surface = true
				elif _active_apply_is_carrier and _is_carrier_color_2_material_name(mat_name):
					target_color = _active_apply_secondary_color
				elif _active_apply_is_carrier and _is_carrier_color_3_material_name(mat_name):
					target_color = _active_apply_tertiary_color
				elif _active_apply_is_carrier and _is_carrier_color_1_material_name(mat_name):
					target_color = _active_apply_upper_color
					is_carrier_pattern_surface = true
				elif "dark blue plasteel" in mat_name:
					target_color = Color(
						_active_apply_upper_color.r * carrier_dark_factor,
						_active_apply_upper_color.g * carrier_dark_factor,
						_active_apply_upper_color.b * carrier_dark_factor,
						_active_apply_upper_color.a
					)
				elif "blue plasteel" in mat_name:
					target_color = _active_apply_upper_color
				elif _active_apply_has_pilot_colors and mat_name == "main color":
					target_color = _active_apply_pilot_main_color
				elif _active_apply_has_pilot_colors and mat_name == "main color dark":
					target_color = _active_apply_pilot_main_dark_color
				elif _active_apply_has_pilot_colors and (mat_name == "helmet color" or mat_name == "helmet color 1"):
					target_color = _active_apply_pilot_helmet_color_1
				elif _active_apply_has_pilot_colors and mat_name == "helmet color 2":
					target_color = _active_apply_pilot_helmet_color_2
				if target_color.r >= 0.0:
					var pattern_index := _normalized_aircraft_upper_pattern_index()
					if is_upper_fuselage_surface and pattern_index > 0:
						mi.set_surface_override_material(
							i,
							_make_test_pattern_material(
								target_color,
								mat,
								pattern_index,
								UPPER_FUSELAGE_TEST_STRIPE_SHADER,
								helicopter_upper_pattern_frequency_per_meter,
								helicopter_upper_pattern_width_fraction
							)
						)
						continue
					if is_carrier_pattern_surface and _active_apply_is_carrier and pattern_index > 0:
						mi.set_surface_override_material(
							i,
							_make_test_pattern_material(
								target_color,
								mat,
								pattern_index,
								_get_carrier_pattern_shader(),
								carrier_pattern_frequency_per_meter,
								carrier_pattern_width_fraction
							)
						)
						continue
					var override: StandardMaterial3D
					if mat is StandardMaterial3D:
						override = mat.duplicate() as StandardMaterial3D
					else:
						override = StandardMaterial3D.new()
					override.albedo_color = target_color
					if is_upper_fuselage_surface or is_lower_fuselage_surface:
						# Force backface culling on fuselage shells to reduce overlap artifacts.
						override.cull_mode = BaseMaterial3D.CULL_BACK
					mi.set_surface_override_material(i, override)
	for child in node.get_children():
		_apply_recursive(child)

func _normalized_aircraft_upper_pattern_index() -> int:
	if AIRCRAFT_UPPER_PATTERN_NAMES.is_empty():
		return 0
	var size := AIRCRAFT_UPPER_PATTERN_NAMES.size()
	if _player_custom_livery_enabled:
		return clampi(_player_custom_pattern_index, 0, size - 1)
	return ((helicopter_upper_pattern_index % size) + size) % size

func _is_carrier_color_1_material_name(mat_name: String) -> bool:
	return "main color 1" in mat_name or "maincolor1" in mat_name \
			or "base color 1" in mat_name or "basecolor1" in mat_name

func _is_carrier_color_2_material_name(mat_name: String) -> bool:
	return "main color 2" in mat_name or "maincolor2" in mat_name \
			or "base color 2" in mat_name or "basecolor2" in mat_name

func _is_carrier_color_3_material_name(mat_name: String) -> bool:
	return "main color 3" in mat_name or "maincolor3" in mat_name \
			or "base color 3" in mat_name or "basecolor3" in mat_name

func _get_carrier_pattern_shader() -> Shader:
	if _carrier_pattern_shader != null:
		return _carrier_pattern_shader
	var shader := Shader.new()
	shader.code = UPPER_FUSELAGE_TEST_STRIPE_SHADER.code.replace("render_mode cull_back", "render_mode cull_disabled")
	_carrier_pattern_shader = shader
	return _carrier_pattern_shader

func _make_test_pattern_material(
	base_color: Color,
	source_material: Material,
	pattern_index: int,
	shader: Shader,
	frequency_per_meter: float,
	width_fraction: float
) -> ShaderMaterial:
	var pattern_material := ShaderMaterial.new()
	pattern_material.resource_name = "Livery Test Pattern"
	pattern_material.shader = shader
	pattern_material.set_shader_parameter("base_color", base_color)
	pattern_material.set_shader_parameter("pattern_color", _active_apply_secondary_color)
	pattern_material.set_shader_parameter("tertiary_pattern_color", _active_apply_tertiary_color)
	pattern_material.set_shader_parameter("pattern_mode", pattern_index)
	pattern_material.set_shader_parameter("pattern_frequency_per_meter", frequency_per_meter)
	pattern_material.set_shader_parameter("pattern_width_fraction", width_fraction)
	pattern_material.set_shader_parameter("projection_mode", 1)
	pattern_material.set_shader_parameter("projection_blend_sharpness", 4.0)
	pattern_material.set_shader_parameter("box_top_normal_threshold", 0.55)
	pattern_material.set_shader_parameter("side_projection_enabled", _active_apply_is_carrier)

	if source_material is StandardMaterial3D:
		var standard := source_material as StandardMaterial3D
		pattern_material.set_shader_parameter("roughness", standard.roughness)
		pattern_material.set_shader_parameter("metallic", standard.metallic)

	return pattern_material
