extends Node

## Dawn → Day → Dusk → Twilight cycle, 5 minutes per phase (20 min total).
## Place as a child of Main_Scene. Finds DirectionalLight3D and WorldEnvironment
## automatically as siblings.

@export var phase_duration_s: float = 300.0   ## 5 min per phase
@export var start_phase: int = 0              ## 0=Dawn 1=Day 2=Dusk 3=Twilight

@onready var _sun: DirectionalLight3D = get_parent().get_node("DirectionalLight3D")
@onready var _we: WorldEnvironment    = get_parent().get_node("WorldEnvironment")

var _env: Environment
var _sky: ProceduralSkyMaterial
var _t: float = 0.0  # normalised 0..1 over full cycle

# ── Keyframes ──────────────────────────────────────────────────────────────────
# Four entries at t = 0.0 (Dawn), 0.25 (Day), 0.5 (Dusk), 0.75 (Twilight).
# Values lerp smoothly between consecutive pairs, wrapping at end.

const _KF := [
	{ # DAWN — t = 0.00
		"sun_energy":      0.55,
		"sun_color":       Color(1.00, 0.45, 0.15),
		"sky_top":         Color(0.04, 0.06, 0.22),
		"sky_horizon":     Color(0.90, 0.40, 0.12),
		"ground_horizon":  Color(0.55, 0.20, 0.05),
		"ground_bottom":   Color(0.02, 0.01, 0.04),
		"sky_energy":      0.45,
		"ambient_color":   Color(0.65, 0.38, 0.22),
		"ambient_energy":  0.35,
		"fog_color":       Color(0.72, 0.38, 0.16),
		"fog_scatter":     0.40,
	},
	{ # DAY — t = 0.25
		"sun_energy":      2.0,
		"sun_color":       Color(1.00, 0.97, 0.88),
		"sky_top":         Color(0.06, 0.22, 0.72),
		"sky_horizon":     Color(0.38, 0.58, 0.88),
		"ground_horizon":  Color(0.22, 0.32, 0.38),
		"ground_bottom":   Color(0.04, 0.08, 0.10),
		"sky_energy":      1.0,
		"ambient_color":   Color(0.68, 0.78, 1.00),
		"ambient_energy":  0.60,
		"fog_color":       Color(0.62, 0.52, 0.38),
		"fog_scatter":     0.05,
	},
	{ # DUSK — t = 0.50
		"sun_energy":      0.80,
		"sun_color":       Color(1.00, 0.28, 0.05),
		"sky_top":         Color(0.04, 0.04, 0.18),
		"sky_horizon":     Color(0.95, 0.32, 0.05),
		"ground_horizon":  Color(0.48, 0.12, 0.02),
		"ground_bottom":   Color(0.02, 0.01, 0.02),
		"sky_energy":      0.45,
		"ambient_color":   Color(0.50, 0.22, 0.12),
		"ambient_energy":  0.30,
		"fog_color":       Color(0.78, 0.26, 0.07),
		"fog_scatter":     0.55,
	},
	{ # TWILIGHT — t = 0.75
		"sun_energy":      0.05,
		"sun_color":       Color(0.30, 0.35, 0.75),
		"sky_top":         Color(0.01, 0.01, 0.04),
		"sky_horizon":     Color(0.05, 0.05, 0.16),
		"ground_horizon":  Color(0.02, 0.02, 0.06),
		"ground_bottom":   Color(0.005, 0.005, 0.010),
		"sky_energy":      0.05,
		"ambient_color":   Color(0.10, 0.12, 0.32),
		"ambient_energy":  0.12,
		"fog_color":       Color(0.05, 0.06, 0.18),
		"fog_scatter":     0.02,
	},
]

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	_env = _we.environment
	if _env.sky:
		_sky = _env.sky.sky_material as ProceduralSkyMaterial
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR

	# Start at the chosen phase
	_t = float(start_phase) / float(_KF.size())
	_update(_t)

func _process(delta: float) -> void:
	_t = fmod(_t + delta / (phase_duration_s * float(_KF.size())), 1.0)
	_update(_t)

# ── Update ─────────────────────────────────────────────────────────────────────

func _update(t: float) -> void:
	var n   := _KF.size()
	var pos := t * float(n)
	var idx_a := int(pos) % n
	var idx_b := (idx_a + 1) % n
	var f := smoothstep(0.0, 1.0, pos - float(int(pos)))

	var a: Dictionary = _KF[idx_a]
	var b: Dictionary = _KF[idx_b]

	_apply_sun_direction(t)

	# Sun light
	_sun.light_energy = lerpf(a.sun_energy, b.sun_energy, f)
	_sun.light_color  = (a.sun_color as Color).lerp(b.sun_color, f)

	# Sky material
	if _sky:
		_sky.sky_top_color        = (a.sky_top       as Color).lerp(b.sky_top,       f)
		_sky.sky_horizon_color    = (a.sky_horizon    as Color).lerp(b.sky_horizon,   f)
		_sky.ground_horizon_color = (a.ground_horizon as Color).lerp(b.ground_horizon,f)
		_sky.ground_bottom_color  = (a.ground_bottom  as Color).lerp(b.ground_bottom, f)
		_sky.sky_energy_multiplier = lerpf(a.sky_energy, b.sky_energy, f)

	# Ambient light
	_env.ambient_light_color  = (a.ambient_color as Color).lerp(b.ambient_color, f)
	_env.ambient_light_energy = lerpf(a.ambient_energy, b.ambient_energy, f)

	# Fog colour and sun scatter animate through the day
	_env.fog_light_color = (a.fog_color as Color).lerp(b.fog_color, f)
	_env.fog_sun_scatter = lerpf(a.fog_scatter, b.fog_scatter, f)

# ── Sun direction ──────────────────────────────────────────────────────────────

func _apply_sun_direction(t: float) -> void:
	# Elevation: 0° at dawn/dusk, +68° at midday, -68° at midnight
	var elev := deg_to_rad(sin(t * TAU) * 68.0)
	# Azimuth: sweeps east → south → west → (under) → east
	var azim := deg_to_rad(t * 360.0 + 80.0)

	# Sun position vector (direction FROM sun toward origin)
	var to_sun := Vector3(
		cos(elev) * sin(azim),
		sin(elev),
		cos(elev) * cos(azim)
	)
	var light_fwd := -to_sun  # light travels away from sun

	# Build basis: -Z axis aligns with light_fwd
	var up := Vector3.RIGHT if abs(light_fwd.y) > 0.99 else Vector3.UP
	_sun.global_transform.basis = Basis.looking_at(light_fwd, up)
