extends Node

## Dust-first day/night cycle using volumetric fog.

@export var phase_duration_s: float = 300.0   ## 5 min per phase
@export var start_phase: int = 0              ## 0=Dawn 1=Day 2=Dusk 3=Twilight

@export var vol_length_m: float = 5000.0      ## How far volumetric fog extends
@export var sky_ground_darkening: float = 0.0
@export var update_interval_s: float = 0.25  ## How often to recalculate sky/fog (cycle is 1200s total)

@onready var _sun: DirectionalLight3D = get_parent().get_node_or_null("DirectionalLight3D")
@onready var _we: WorldEnvironment = get_parent().get_node_or_null("WorldEnvironment")

var _env: Environment
var _sky: ProceduralSkyMaterial
var _t: float = 0.0  # normalized 0..1 over full cycle
var _update_acc: float = 0.0
var _night_mode: bool = false
var _ai_darkness_factor: float = 0.0

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

	_t = float(start_phase) / float(_KF.size())
	_update(_t)

func get_ai_darkness_factor() -> float:
	"""0.0 in good daylight, 1.0 in the darkest twilight/night phase."""
	return _ai_darkness_factor

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == KEY_N:
		_night_mode = not _night_mode
		_t = 0.875 if _night_mode else 0.375  # TWILIGHT mid vs DAY mid
		_update(_t)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _night_mode:
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
	var sky_top := dust_col.darkened(zenith_darkness)
	var sky_ground := dust_col.darkened(sky_ground_darkening)

	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = lerpf(float(a.vol_density), float(b.vol_density), f)
	_env.volumetric_fog_albedo = dust_col
	_env.volumetric_fog_emission = Color(0, 0, 0)
	_env.volumetric_fog_emission_energy = 0.0
	_env.volumetric_fog_anisotropy = lerpf(float(a.vol_anisotropy), float(b.vol_anisotropy), f)
	_env.volumetric_fog_length = vol_length_m
	_env.volumetric_fog_detail_spread = 1.0

	if _sky:
		_sky.sky_top_color = sky_top
		_sky.sky_horizon_color = dust_col
		_sky.ground_horizon_color = dust_col
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

	var elev := deg_to_rad(sin(t * TAU) * 68.0)
	var azim := deg_to_rad(t * 360.0 + 80.0)

	var to_sun := Vector3(
		cos(elev) * sin(azim),
		sin(elev),
		cos(elev) * cos(azim)
	)
	var light_fwd := -to_sun

	var up := Vector3.RIGHT if abs(light_fwd.y) > 0.99 else Vector3.UP
	_sun.global_transform.basis = Basis.looking_at(light_fwd, up)
