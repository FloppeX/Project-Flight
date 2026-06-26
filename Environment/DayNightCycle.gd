extends Node

## Dust-first day/night cycle using volumetric fog.

@export var phase_duration_s: float = 300.0   ## 5 min per phase
@export var start_phase: int = 0              ## 0=Dawn 1=Day 2=Dusk 3=Twilight
@export var freeze_daytime: bool = true       ## Hold the cycle at noon/day for visual testing
@export_range(0.0, 1.0, 0.001) var frozen_daytime_t: float = 0.25
@export_range(1.0, 89.9, 0.1) var sun_max_elevation_deg: float = 89.0

@export var vol_length_m: float = 5000.0      ## How far volumetric fog extends
@export var sky_ground_darkening: float = 0.0
@export var update_interval_s: float = 0.25  ## How often to recalculate sky/fog (cycle is 1200s total)

@export_group("Dust Layer")
@export var altitude_clears_dust: bool = true
@export var dust_layer_top_m: float = 4000.0
@export var dust_layer_fade_m: float = 900.0
@export_range(0.0, 1.0) var clear_air_density_multiplier: float = 0.08
@export var clear_air_vol_length_multiplier: float = 1.8
@export var dust_layer_top_variation_m: float = 450.0
@export var dust_layer_top_variation_frequency: float = 0.00016
@export var dust_layer_noise_seed: int = 24681
@export var dust_layer_bottom_m: float = -500.0
@export var dust_layer_horizontal_size_m: float = 80000.0
@export var dust_layer_volume_density: float = 0.002
@export var dust_layer_red_color: Color = Color(0.70, 0.22, 0.10)
@export_range(0.0, 1.0) var dust_layer_red_blend: float = 0.55
@export var dust_deck_enabled: bool = true
@export_range(0.0, 1.0) var dust_deck_alpha_above: float = 0.88
@export_range(0.0, 1.0) var dust_deck_alpha_below: float = 0.0
@export var dust_deck_vertical_offset_m: float = -80.0
@export var clear_air_sky_top_color: Color = Color(0.24, 0.46, 0.78)
@export var clear_air_sky_horizon_color: Color = Color(0.55, 0.72, 0.92)
@export var clear_air_ground_horizon_dust_blend: float = 0.65

@export_group("Sun Breaks")
@export var sun_breaks_enabled: bool = true
@export_range(0, 24) var sun_break_count: int = 8
@export var sun_break_seed: int = 9031
@export var sun_break_spawn_radius_m: float = 10000.0
@export var sun_break_min_radius_m: float = 280.0
@export var sun_break_max_radius_m: float = 850.0
@export var sun_break_max_length_m: float = 6500.0
@export var sun_break_drift_speed_mps: float = 22.0
@export_range(3, 12) var sun_break_polygon_sides: int = 7
@export_range(0.0, 1.0) var sun_break_shaft_alpha: float = 0.42
@export_range(0.0, 1.0) var sun_break_highlight_alpha: float = 0.24
@export var sun_break_color: Color = Color(1.0, 0.82, 0.55)
@export_range(0.0, 1.0) var sun_break_above_layer_bias: float = 0.7

@onready var _sun: DirectionalLight3D = get_parent().get_node_or_null("DirectionalLight3D")
@onready var _we: WorldEnvironment = get_parent().get_node_or_null("WorldEnvironment")

var _env: Environment
var _sky: ProceduralSkyMaterial
var _t: float = 0.0  # normalized 0..1 over full cycle
var _update_acc: float = 0.0
var _night_mode: bool = false
var _ai_darkness_factor: float = 0.0
var _dust_top_noise: FastNoiseLite
var _dust_volume: FogVolume
var _dust_volume_material: FogMaterial
var _dust_deck: MeshInstance3D
var _dust_deck_material: StandardMaterial3D
var _sun_break_root: Node3D
var _sun_breaks: Array[Dictionary] = []
var _sun_break_material: StandardMaterial3D
var _sun_break_highlight_material: StandardMaterial3D
var _sun_break_time: float = 0.0
var _last_sun_break_color: Color = Color(1.0, 0.82, 0.55)
var _last_clear_air_factor: float = 0.0

const _KF := [
	{ # DAWN — apricot/dusty salmon sky, smoky mauve ambient
	  # Twilight->Dawn blend gives pre-dawn: plum fading to dusty rose
		"sun_energy": 0.75,
		"sun_color": Color(1.00, 0.60, 0.34),   # peach-amber disc, soft not white
		"ambient_color": Color(0.48, 0.32, 0.26),
		"ambient_energy": 0.26,
		"dust_color": Color(0.68, 0.42, 0.28),   # apricot/muted salmon
		"vol_density": 0.0012,
		"vol_anisotropy": 0.4,
		"sky_energy": 0.48,
		"zenith_darkness": 0.0,
	},
	{ # DAY — bleached ochre, oppressive yellow-gray glare
		"sun_energy": 2.20,
		"sun_color": Color(1.00, 0.98, 0.88),   # bleached cream
		"ambient_color": Color(0.80, 0.76, 0.64),
		"ambient_energy": 0.58,
		"dust_color": Color(0.84, 0.76, 0.60),   # pale ochre / yellow-gray haze
		"vol_density": 0.0007,
		"vol_anisotropy": 0.15,
		"sky_energy": 1.0,
		"zenith_darkness": 0.0,
	},
	{ # DUSK — copper/rust/burnt orange near sun, mauve-gray away
	  # Day->Dusk blend gives pre-sunset: warm ochre shifting into amber
		"sun_energy": 0.80,
		"sun_color": Color(1.00, 0.38, 0.12),   # deep burnt orange disc
		"ambient_color": Color(0.42, 0.22, 0.18),
		"ambient_energy": 0.26,
		"dust_color": Color(0.70, 0.30, 0.14),   # copper/cinnabar
		"vol_density": 0.0014,
		"vol_anisotropy": 0.5,
		"sky_energy": 0.48,
		"zenith_darkness": 0.0,
	},
	{ # TWILIGHT — plum, wine-red residue, brown-violet murk
	  # Dusk->Twilight blend gives post-sunset: rust cooling into bruised purple
		"sun_energy": 0.07,
		"sun_color": Color(0.68, 0.36, 0.30),   # wine-red residue on horizon
		"ambient_color": Color(0.13, 0.09, 0.12),
		"ambient_energy": 0.10,
		"dust_color": Color(0.24, 0.14, 0.19),   # plum/brown-violet
		"vol_density": 0.0008,
		"vol_anisotropy": 0.0,
		"sky_energy": 0.13,
		"zenith_darkness": 0.0,
	},
]

func _ready() -> void:
	add_to_group("day_night_cycle")
	if _we == null or _we.environment == null:
		push_warning("[DayNightCycle] WorldEnvironment/environment not found.")
		set_process(false)
		return
	if _sun == null:
		push_warning("[DayNightCycle] DirectionalLight3D not found.")

	_env = _we.environment
	if _env.sky and _env.sky.sky_material is ProceduralSkyMaterial:
		_sky = _env.sky.sky_material as ProceduralSkyMaterial

	_env.background_mode = Environment.BG_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.fog_enabled = false
	_build_dust_top_noise()
	_ensure_dust_volume()
	_ensure_dust_deck()
	_ensure_sun_breaks()

	_t = frozen_daytime_t if freeze_daytime else float(start_phase) / float(_KF.size())
	_update(_t)

func get_ai_darkness_factor() -> float:
	"""0.0 in good daylight, 1.0 in the darkest twilight/night phase."""
	return _ai_darkness_factor

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == KEY_N:
		_night_mode = not _night_mode
		_t = 0.875 if _night_mode else frozen_daytime_t  # TWILIGHT mid vs frozen day test time
		_update(_t)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_sun_break_time += delta
	_update_sun_breaks(_last_sun_break_color, _last_clear_air_factor)

	if freeze_daytime:
		_t = frozen_daytime_t
	elif not _night_mode:
		_t = fmod(_t + delta / (phase_duration_s * float(_KF.size())), 1.0)
	_update_acc += delta
	if _update_acc < update_interval_s:
		return
	_update_acc = 0.0
	_update(_t)

func _update(t: float) -> void:
	var n := _KF.size()
	var pos := t * float(n)
	var idx_a := int(pos) % n
	var idx_b := (idx_a + 1) % n
	var f := smoothstep(0.0, 1.0, pos - float(int(pos)))

	var a: Dictionary = _KF[idx_a]
	var b: Dictionary = _KF[idx_b]

	_apply_sun_direction(t)

	if is_instance_valid(_sun):
		var current_sun_energy := lerpf(float(a.sun_energy), float(b.sun_energy), f)
		_sun.light_energy = current_sun_energy
		_sun.light_color = (a.sun_color as Color).lerp(b.sun_color as Color, f)

	_env.ambient_light_color = (a.ambient_color as Color).lerp(b.ambient_color as Color, f)
	var current_ambient_energy := lerpf(float(a.ambient_energy), float(b.ambient_energy), f)
	_env.ambient_light_energy = current_ambient_energy

	var dust_col: Color = (a.dust_color as Color).lerp(b.dust_color as Color, f)
	var zenith_darkness := lerpf(float(a.zenith_darkness), float(b.zenith_darkness), f)
	var clear_t: float = _get_clear_air_factor()
	var sky_top := dust_col.darkened(zenith_darkness).lerp(clear_air_sky_top_color, clear_t)
	var sky_horizon := dust_col.lerp(clear_air_sky_horizon_color, clear_t)
	var ground_horizon := dust_col.lerp(dust_col.lerp(clear_air_sky_horizon_color, 0.35), clear_t * clampf(1.0 - clear_air_ground_horizon_dust_blend, 0.0, 1.0))
	var sky_ground := dust_col.darkened(sky_ground_darkening)
	var dust_ocean_col := dust_col.lerp(dust_layer_red_color, clampf(dust_layer_red_blend, 0.0, 1.0))

	_env.volumetric_fog_enabled = true
	var base_vol_density: float = lerpf(float(a.vol_density), float(b.vol_density), f)
	_env.volumetric_fog_density = base_vol_density * lerpf(1.0, clear_air_density_multiplier, clear_t)
	_env.volumetric_fog_albedo = dust_col
	_env.volumetric_fog_emission = Color(0, 0, 0)
	_env.volumetric_fog_emission_energy = 0.0
	_env.volumetric_fog_anisotropy = lerpf(float(a.vol_anisotropy), float(b.vol_anisotropy), f)
	_env.volumetric_fog_length = vol_length_m * lerpf(1.0, maxf(clear_air_vol_length_multiplier, 0.01), clear_t)
	_env.volumetric_fog_detail_spread = 1.0
	_update_dust_volume(dust_ocean_col, clear_t)
	_update_dust_deck(dust_ocean_col, clear_t)
	_last_sun_break_color = sun_break_color.lerp(dust_col, 0.22)
	_last_clear_air_factor = clear_t
	_update_sun_breaks(_last_sun_break_color, clear_t)

	if _sky:
		_sky.sky_top_color = sky_top
		_sky.sky_horizon_color = sky_horizon
		_sky.ground_horizon_color = ground_horizon
		_sky.ground_bottom_color = sky_ground
		_sky.sky_curve = 0.45
		_sky.ground_curve = 0.45
		var current_sky_energy := lerpf(float(a.sky_energy), float(b.sky_energy), f)
		_sky.sky_energy_multiplier = current_sky_energy

	var sun_energy_for_ai := lerpf(float(a.sun_energy), float(b.sun_energy), f)
	var sky_energy_for_ai := lerpf(float(a.sky_energy), float(b.sky_energy), f)
	var light_score := sun_energy_for_ai * 0.35 + current_ambient_energy * 0.55 + sky_energy_for_ai * 0.10
	_ai_darkness_factor = clampf(1.0 - smoothstep(0.16, 0.75, light_score), 0.0, 1.0)

func _apply_sun_direction(t: float) -> void:
	if not is_instance_valid(_sun):
		return

	var elev := deg_to_rad(sin(t * TAU) * sun_max_elevation_deg)
	var azim := deg_to_rad(t * 360.0 + 80.0)

	var to_sun := Vector3(
		cos(elev) * sin(azim),
		sin(elev),
		cos(elev) * cos(azim)
	)
	var light_fwd := -to_sun

	var up := Vector3.RIGHT if abs(light_fwd.y) > 0.99 else Vector3.UP
	_sun.global_transform.basis = Basis.looking_at(light_fwd, up)

func _build_dust_top_noise() -> void:
	_dust_top_noise = FastNoiseLite.new()
	_dust_top_noise.seed = dust_layer_noise_seed
	_dust_top_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dust_top_noise.frequency = maxf(dust_layer_top_variation_frequency, 0.000001)
	_dust_top_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_dust_top_noise.fractal_octaves = 2
	_dust_top_noise.fractal_lacunarity = 2.0
	_dust_top_noise.fractal_gain = 0.5

func _ensure_dust_volume() -> void:
	if _dust_volume != null and is_instance_valid(_dust_volume):
		return
	_dust_volume = FogVolume.new()
	_dust_volume.name = "DustLayerVolume"
	_dust_volume_material = FogMaterial.new()
	_dust_volume.material = _dust_volume_material
	var scene_root := get_tree().current_scene
	if scene_root != null:
		scene_root.add_child.call_deferred(_dust_volume)
	else:
		add_child.call_deferred(_dust_volume)

func _ensure_dust_deck() -> void:
	if _dust_deck != null and is_instance_valid(_dust_deck):
		return
	_dust_deck = MeshInstance3D.new()
	_dust_deck.name = "DustLayerDeck"
	var plane := PlaneMesh.new()
	plane.size = Vector2(maxf(dust_layer_horizontal_size_m, 1.0), maxf(dust_layer_horizontal_size_m, 1.0))
	plane.subdivide_width = 24
	plane.subdivide_depth = 24
	_dust_deck.mesh = plane
	_dust_deck_material = StandardMaterial3D.new()
	_dust_deck_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_deck_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_deck_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_dust_deck_material.no_depth_test = false
	_dust_deck_material.albedo_color = Color(0.7, 0.22, 0.1, 0.6)
	_dust_deck.material_override = _dust_deck_material
	var scene_root := get_tree().current_scene
	if scene_root != null:
		scene_root.add_child.call_deferred(_dust_deck)
	else:
		add_child.call_deferred(_dust_deck)

func _update_dust_volume(dust_color: Color, clear_t: float) -> void:
	_ensure_dust_volume()
	if _dust_volume == null or not is_instance_valid(_dust_volume):
		return
	if not _dust_volume.is_inside_tree():
		return
	if _dust_volume_material == null:
		_dust_volume_material = FogMaterial.new()
		_dust_volume.material = _dust_volume_material
	var sample_pos := _get_weather_sample_position()
	var layer_top := _get_dust_layer_top_for_position(sample_pos)
	var bottom := minf(dust_layer_bottom_m, layer_top - 1.0)
	var height := maxf(layer_top - bottom, 1.0)
	_dust_volume.size = Vector3(
		maxf(dust_layer_horizontal_size_m, 1.0),
		height,
		maxf(dust_layer_horizontal_size_m, 1.0)
	)
	_dust_volume.global_position = Vector3(sample_pos.x, bottom + height * 0.5, sample_pos.z)
	var inside_layer_density_scale := lerpf(0.12, 1.0, clear_t)
	_dust_volume_material.density = maxf(dust_layer_volume_density, 0.0) * inside_layer_density_scale
	_dust_volume_material.albedo = dust_color

func _update_dust_deck(dust_color: Color, clear_t: float) -> void:
	_ensure_dust_deck()
	if _dust_deck == null or not is_instance_valid(_dust_deck):
		return
	if not _dust_deck.is_inside_tree():
		return
	_dust_deck.visible = dust_deck_enabled
	if not dust_deck_enabled:
		return
	if _dust_deck_material == null:
		_dust_deck_material = StandardMaterial3D.new()
		_dust_deck.material_override = _dust_deck_material
	var sample_pos := _get_weather_sample_position()
	var layer_top := _get_dust_layer_top_for_position(sample_pos)
	_dust_deck.global_position = Vector3(sample_pos.x, layer_top + dust_deck_vertical_offset_m, sample_pos.z)
	var alpha := lerpf(dust_deck_alpha_below, dust_deck_alpha_above, clear_t)
	_dust_deck_material.albedo_color = Color(dust_color.r, dust_color.g, dust_color.b, alpha)

func _ensure_sun_breaks() -> void:
	if _sun_break_root == null or not is_instance_valid(_sun_break_root):
		_sun_break_root = Node3D.new()
		_sun_break_root.name = "SunBreaks"
		var scene_root := get_tree().current_scene
		if scene_root != null:
			scene_root.add_child.call_deferred(_sun_break_root)
		else:
			add_child.call_deferred(_sun_break_root)
	if _sun_break_material == null:
		_sun_break_material = _make_sun_break_material(true)
	if _sun_break_highlight_material == null:
		_sun_break_highlight_material = _make_sun_break_material(false)
	if _sun_breaks.size() == sun_break_count:
		return
	for entry in _sun_breaks:
		var shaft := entry.get("shaft") as MeshInstance3D
		var highlight := entry.get("highlight") as MeshInstance3D
		if shaft != null and is_instance_valid(shaft):
			shaft.queue_free()
		if highlight != null and is_instance_valid(highlight):
			highlight.queue_free()
	_sun_breaks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = sun_break_seed
	var count: int = maxi(sun_break_count, 0)
	var sides: int = clampi(sun_break_polygon_sides, 3, 12)
	for i in count:
		var radius := rng.randf_range(
			minf(sun_break_min_radius_m, sun_break_max_radius_m),
			maxf(sun_break_min_radius_m, sun_break_max_radius_m)
		)
		var angle := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * maxf(sun_break_spawn_radius_m, 1.0)
		var shaft := MeshInstance3D.new()
		shaft.name = "SunShaft%02d" % i
		shaft.mesh = _build_sun_shaft_mesh(radius, maxf(sun_break_max_length_m, 1.0), sides)
		var shaft_material := _sun_break_material.duplicate() as StandardMaterial3D
		shaft.material_override = shaft_material
		_sun_break_root.add_child(shaft)
		var highlight := MeshInstance3D.new()
		highlight.name = "SunBreakHighlight%02d" % i
		highlight.mesh = _build_sun_highlight_mesh(radius, sides)
		var highlight_material := _sun_break_highlight_material.duplicate() as StandardMaterial3D
		highlight.material_override = highlight_material
		_sun_break_root.add_child(highlight)
		_sun_breaks.append({
			"offset": Vector2(cos(angle), sin(angle)) * dist,
			"radius": radius,
			"phase": rng.randf() * TAU,
			"strength": rng.randf_range(0.55, 1.0),
			"shaft": shaft,
			"shaft_material": shaft_material,
			"highlight": highlight,
			"highlight_material": highlight_material,
		})

func _make_sun_break_material(additive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	return mat

func _update_sun_breaks(color: Color, clear_t: float) -> void:
	_ensure_sun_breaks()
	if _sun_break_root == null or not is_instance_valid(_sun_break_root):
		return
	if not _sun_break_root.is_inside_tree():
		return
	var ray_dir := _get_sun_ray_direction()
	var sun_power := clampf(-ray_dir.y, 0.0, 1.0)
	var layer_visibility := lerpf(1.0, smoothstep(0.12, 0.85, clear_t), clampf(sun_break_above_layer_bias, 0.0, 1.0))
	var visible := sun_breaks_enabled and sun_break_count > 0 and sun_power > 0.08 and layer_visibility > 0.02
	_sun_break_root.visible = visible
	if not visible:
		return
	var sample_pos := _get_weather_sample_position()
	var wind_dir := Vector2(0.82, -0.57).normalized()
	var drift := wind_dir * sun_break_drift_speed_mps * _sun_break_time
	var wrap_radius := maxf(sun_break_spawn_radius_m, 1.0)
	var max_length := maxf(sun_break_max_length_m, 10.0)
	var shaft_basis := _basis_from_y(-ray_dir)
	for i in _sun_breaks.size():
		var entry := _sun_breaks[i]
		var offset := entry.get("offset") as Vector2
		offset += drift
		offset = _wrap_sun_break_offset(offset, wrap_radius)
		var radius := float(entry.get("radius", 500.0))
		var strength := float(entry.get("strength", 1.0))
		var phase := float(entry.get("phase", 0.0))
		var shimmer := lerpf(0.72, 1.0, 0.5 + 0.5 * sin(_sun_break_time * 0.18 + phase))
		var top_center := Vector3(sample_pos.x + offset.x, 0.0, sample_pos.z + offset.y)
		top_center.y = _get_dust_layer_top_for_position(top_center) + 120.0
		var approx_length := minf(max_length, maxf((top_center.y - 0.0) / maxf(-ray_dir.y, 0.08), 200.0))
		var bottom_center := top_center + ray_dir * approx_length
		var ground_y := _sample_ground_height(bottom_center, 0.0)
		var shaft_length := minf(max_length, maxf((top_center.y - ground_y) / maxf(-ray_dir.y, 0.08), 200.0))
		bottom_center = top_center + ray_dir * shaft_length
		ground_y = _sample_ground_height(bottom_center, ground_y)
		bottom_center.y = ground_y + 6.0
		shaft_length = maxf(top_center.distance_to(bottom_center), 10.0)
		var shaft := entry.get("shaft") as MeshInstance3D
		var highlight := entry.get("highlight") as MeshInstance3D
		var alpha_scale := strength * shimmer * sun_power * layer_visibility
		if shaft != null and is_instance_valid(shaft):
			shaft.visible = true
			shaft.global_transform = Transform3D(shaft_basis.scaled(Vector3(1.0, shaft_length / max_length, 1.0)), (top_center + bottom_center) * 0.5)
			var shaft_material := entry.get("shaft_material") as StandardMaterial3D
			if shaft_material != null:
				shaft_material.albedo_color = Color(color.r, color.g, color.b, sun_break_shaft_alpha * alpha_scale)
		if highlight != null and is_instance_valid(highlight):
			highlight.visible = true
			var highlight_color := color.lerp(Color(1.0, 0.92, 0.70), 0.55)
			highlight.global_transform = Transform3D(Basis().scaled(Vector3(1.55, 1.0, 1.0)), bottom_center + Vector3.UP * 0.35)
			highlight.rotation.y = atan2(ray_dir.x, ray_dir.z)
			var highlight_material := entry.get("highlight_material") as StandardMaterial3D
			if highlight_material != null:
				highlight_material.albedo_color = Color(highlight_color.r, highlight_color.g, highlight_color.b, sun_break_highlight_alpha * alpha_scale)

func _build_sun_shaft_mesh(radius: float, height: float, sides: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var ring_count := 4
	for ring in ring_count:
		var t := float(ring) / float(ring_count - 1)
		var y := lerpf(-height * 0.5, height * 0.5, t)
		var r := lerpf(radius * 1.15, radius * 0.25, t)
		var alpha := 0.0
		if ring == 1:
			alpha = 0.65
		elif ring == 2:
			alpha = 1.0
		elif ring == 3:
			alpha = 0.12
		for side in sides:
			var a := float(side) / float(sides) * TAU
			vertices.append(Vector3(cos(a) * r, y, sin(a) * r))
			colors.append(Color(1.0, 1.0, 1.0, alpha))
	for ring in ring_count - 1:
		for side in sides:
			var next_side := (side + 1) % sides
			var a0 := ring * sides + side
			var a1 := ring * sides + next_side
			var b0 := (ring + 1) * sides + side
			var b1 := (ring + 1) * sides + next_side
			indices.append_array(PackedInt32Array([a0, b0, a1, a1, b0, b1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _build_sun_highlight_mesh(radius: float, sides: int) -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3.ZERO])
	var colors := PackedColorArray([Color(1.0, 1.0, 1.0, 1.0)])
	var indices := PackedInt32Array()
	for side in sides:
		var a := float(side) / float(sides) * TAU
		vertices.append(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
		colors.append(Color(1.0, 1.0, 1.0, 0.0))
	for side in sides:
		var next_side := 1 + (side + 1) % sides
		indices.append_array(PackedInt32Array([0, 1 + side, next_side]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _get_sun_ray_direction() -> Vector3:
	if is_instance_valid(_sun):
		return (-_sun.global_transform.basis.z).normalized()
	return Vector3.DOWN

func _basis_from_y(y_axis: Vector3) -> Basis:
	var y := y_axis.normalized()
	var helper := Vector3.FORWARD
	if absf(y.dot(helper)) > 0.94:
		helper = Vector3.RIGHT
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _wrap_sun_break_offset(offset: Vector2, radius: float) -> Vector2:
	var wrapped := offset
	var diameter := radius * 2.0
	wrapped.x = fposmod(wrapped.x + radius, diameter) - radius
	wrapped.y = fposmod(wrapped.y + radius, diameter) - radius
	return wrapped

func _sample_ground_height(world_pos: Vector3, fallback: float) -> float:
	var terrain := TerrainReference.get_terrain_node()
	if terrain != null and is_instance_valid(terrain) and terrain.has_method("get_height"):
		var sampled = terrain.call("get_height", world_pos)
		if sampled is float or sampled is int:
			return float(sampled)
	return fallback

func _get_clear_air_factor() -> float:
	if not altitude_clears_dust:
		return 0.0
	var camera := _get_active_camera()
	if camera == null:
		return 0.0
	var top_m := _get_dust_layer_top_for_position(camera.global_position)
	var fade_m: float = maxf(dust_layer_fade_m, 1.0)
	return smoothstep(top_m - fade_m * 0.5, top_m + fade_m * 0.5, camera.global_position.y)

func _get_dust_layer_top_for_position(pos: Vector3) -> float:
	var top_m := dust_layer_top_m
	if _dust_top_noise != null and dust_layer_top_variation_m > 0.0:
		var n := _dust_top_noise.get_noise_2d(pos.x, pos.z)
		top_m += n * dust_layer_top_variation_m
	return top_m

func _get_weather_sample_position() -> Vector3:
	var camera := _get_active_camera()
	if camera != null:
		return camera.global_position
	return Vector3.ZERO

func _get_active_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport != null:
		var viewport_camera := viewport.get_camera_3d()
		if viewport_camera != null and is_instance_valid(viewport_camera) and viewport_camera.is_inside_tree():
			return viewport_camera
	for camera_controller in get_tree().get_nodes_in_group("camera_controller"):
		if camera_controller != null and camera_controller.has_method("get_current_camera"):
			var current_camera = camera_controller.call("get_current_camera")
			if current_camera is Camera3D and is_instance_valid(current_camera) and (current_camera as Camera3D).is_inside_tree() and (current_camera as Camera3D).current:
				return current_camera as Camera3D
	return null
