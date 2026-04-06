class_name EnemyBase
extends Node3D
## A stationary enemy installation: runway, buildings, and virtual flights.
## Built procedurally at runtime. Each base has a unique faction color.

# ── Faction palette ──────────────────────────────────────────────────────────

const FACTION_COLORS: Array[Color] = [
	Color(0.82, 0.26, 0.12, 1.0),   # Rust red   (faction 0 / upper-left)
	Color(0.22, 0.44, 0.76, 1.0),   # Steel blue (faction 1 / upper-right)
]
const FACTION_NAMES: Array[String] = [
	"Crimson Pact",
	"Iron Veil",
]

const PAD_COLOR     := Color(0.16, 0.11, 0.09, 1.0)
const PAD_RADIUS_M  := 420.0
const PATROL_RADIUS := 4500.0
const FLIGHTS_PER_BASE := 2

# ── Config ────────────────────────────────────────────────────────────────────

@export var faction_id:    int  = 0
@export var debug_enabled: bool = false

# ── State ─────────────────────────────────────────────────────────────────────

var faction_color: Color  = Color.WHITE
var faction_name:  String = ""
var flights: Array[EnemyVirtualFlight] = []

var _rng := RandomNumberGenerator.new()
var _enemy_aircraft_scene: PackedScene = null
var _tick_acc: float = 0.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("enemy_bases")
	add_to_group("origin_shifter")

	faction_color = FACTION_COLORS[faction_id % FACTION_COLORS.size()]
	faction_name  = FACTION_NAMES[faction_id % FACTION_NAMES.size()]
	_rng.seed = hash(global_position) ^ (faction_id * 99991 + 12345)

	# Try the dedicated enemy aircraft scene; fall back to Aircraft_3
	_enemy_aircraft_scene = load("res://Enemies/EnemyAircraft.tscn") as PackedScene
	if _enemy_aircraft_scene == null:
		_enemy_aircraft_scene = load("res://Aircraft/Aircraft_3.tscn") as PackedScene

	# Defer so global_position is fully set by EnemyBaseManager before we build
	call_deferred("_build_base")


func _physics_process(delta: float) -> void:
	_tick_acc += delta
	if _tick_acc >= 1.0:
		var dt := _tick_acc
		_tick_acc = 0.0
		for f in flights:
			if is_instance_valid(f):
				f.tick(dt)


# ── Construction ──────────────────────────────────────────────────────────────

func _build_base() -> void:
	_build_pad()
	_place_buildings()
	_create_flights()
	if debug_enabled:
		print("[EnemyBase] %s built at %v" % [faction_name, global_position])


func _build_pad() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _generate_pad_mesh()
	mi.position = Vector3(0.0, 0.2, 0.0)   # slight lift to prevent z-fight with terrain

	var mat := StandardMaterial3D.new()
	mat.albedo_color = PAD_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)


func _generate_pad_mesh() -> ArrayMesh:
	var num_pts := _rng.randi_range(7, 11)
	var pts: Array[Vector2] = []
	for i in range(num_pts):
		var base_angle := TAU * float(i) / float(num_pts)
		var jitter     := _rng.randf_range(-0.28, 0.28)
		var r          := PAD_RADIUS_M * _rng.randf_range(0.68, 1.32)
		pts.append(Vector2(cos(base_angle + jitter) * r, sin(base_angle + jitter) * r))

	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in range(pts.size()):
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		verts.append(Vector3.ZERO)
		verts.append(Vector3(a.x, 0.0, a.y))
		verts.append(Vector3(b.x, 0.0, b.y))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _place_buildings() -> void:
	var runway_scene   := load("res://Buildings/building_enemy_runway.tscn") as PackedScene
	var barracks_scene := load("res://Buildings/building_barracks.tscn") as PackedScene

	var runway_yaw := _rng.randf_range(0.0, TAU)
	var fwd  := Vector2(cos(runway_yaw), sin(runway_yaw))
	var perp := Vector2(-fwd.y, fwd.x)

	# Runway at center
	if runway_scene:
		var rw := runway_scene.instantiate() as Node3D
		add_child(rw)
		rw.position   = Vector3(0.0, _terrain_offset(0.0, 0.0), 0.0)
		rw.rotation.y = runway_yaw

	# Barracks at fixed offsets relative to runway axis
	if barracks_scene:
		var offsets: Array[Vector2] = [
			perp *  130.0,
			perp * -130.0,
			fwd  *  220.0,
			fwd  * -190.0,
			perp *  190.0 + fwd * 110.0,
		]
		var count := _rng.randi_range(3, offsets.size())
		for i in range(count):
			var off := offsets[i]
			var bx := off.x
			var bz := off.y
			var b := barracks_scene.instantiate() as Node3D
			add_child(b)
			b.position   = Vector3(bx, _terrain_offset(bx, bz), bz)
			b.rotation.y = _rng.randf_range(-PI * 0.15, PI * 0.15)


func _terrain_offset(local_x: float, local_z: float) -> float:
	## Returns the Y offset (relative to base origin) for a point in local XZ space.
	var wx := global_position.x + local_x
	var wz := global_position.z + local_z
	var h  := TerrainNavGrid.sample_height(wx, wz)
	if h <= TerrainNavGrid.IMPASSABLE * 0.5:
		return 0.0
	return h - global_position.y


func _create_flights() -> void:
	for i in range(FLIGHTS_PER_BASE):
		var f := EnemyVirtualFlight.new()
		f.flight_name    = "%s-%02d" % [faction_name.left(3).to_upper(), i + 1]
		f.aircraft_count = 2
		f.patrol_radius  = PATROL_RADIUS
		f.faction_color  = faction_color
		f.setup(global_position, _enemy_aircraft_scene,
				float(i) * TAU / float(FLIGHTS_PER_BASE))
		add_child(f)
		flights.append(f)


# ── Origin shift ──────────────────────────────────────────────────────────────

func _is_shifted_by_scene_root_node3d_chain() -> bool:
	var root := get_tree().current_scene
	if root == null:
		return false

	var node: Node = self
	while node != null and node != root:
		var parent := node.get_parent()
		if parent == null:
			return false
		if parent == root:
			# FloatingOrigin shifts only direct Node3D children of current_scene.
			# If our topmost node under current_scene is Node3D, we were shifted via parent chain.
			return node is Node3D
		node = parent

	return false


func apply_origin_shift(offset: Vector3) -> void:
	# Fallback: if this base is not under a shifted Node3D chain, shift it manually.
	if not _is_shifted_by_scene_root_node3d_chain():
		global_position -= offset

	# Flights keep raw world-space vectors; always forward the shift.
	for f in flights:
		if is_instance_valid(f):
			f.apply_origin_shift(offset)


# ── Public API ────────────────────────────────────────────────────────────────

func get_faction_color() -> Color:
	return faction_color

func get_flights() -> Array[EnemyVirtualFlight]:
	return flights
