class_name EnemyBase
extends Node3D
## A stationary enemy installation: runway, buildings, and a unit inventory.
## EnemyOpsManager deploys flights and platoons from this base's reserves.

# ── Faction identity ──────────────────────────────────────────────────────────

const FACTION_NAMES: Array[String] = [
	"Crimson Pact",
	"Iron Veil",
]

## Enemy team ID used in the Livery system (all enemy factions share team 2).
const ENEMY_LIVERY_TEAM_ID: int = 2

const PAD_COLOR    := Color(0.16, 0.11, 0.09, 1.0)
const PAD_RADIUS_M := 420.0
const PATROL_RADIUS_M := 9000.0

# ── Config ────────────────────────────────────────────────────────────────────

@export var faction_id:    int  = 0
@export var debug_enabled: bool = false

# ── Inventory ─────────────────────────────────────────────────────────────────

## Total aircraft the base can ever field (permanent losses reduce this).
@export var aircraft_max: int = 24
## Aircraft currently at base, available for deployment.
var aircraft_reserve: int = 0

## Total vehicles the base can ever field.
@export var vehicle_max: int = 56
## Vehicles currently at base, available for deployment.
var vehicle_reserve: int = 0

## Seconds between each replacement aircraft being produced (while reserve < max).
@export var aircraft_replenish_interval_s: float = 90.0
## Seconds between each replacement vehicle being produced.
@export var vehicle_replenish_interval_s: float = 45.0

var _aircraft_replenish_timer: float = 0.0
var _vehicle_replenish_timer:  float = 0.0
var _flight_counter:   int = 0
var _platoon_counter:  int = 0

# ── State ─────────────────────────────────────────────────────────────────────

var faction_color: Color  = Color.WHITE
var faction_name:  String = ""

var _rng := RandomNumberGenerator.new()
var _fighter_scene:        PackedScene = null   # Aircraft_3 — nimble fighter
var _bomber_scene:         PackedScene = null   # Aircraft_4 — heavy strike bomber
var _attack_scene:         PackedScene = null   # Aircraft_6 — multirole attacker
var _enemy_vehicle_scenes: Array[PackedScene] = []

## Patrol compositions: each entry is [group_a_slots, group_b_slots].
## Each slot is [aircraft_key, loadout]. Total aircraft per patrol: 4–6.
## aircraft_key: "fighter"=AC3, "bomber"=AC4, "attack"=AC6
const PATROL_COMPOSITIONS: Array = [
	# Pure fighter sweep — 4 total
	[[["fighter","guns"],["fighter","guns"]], [["fighter","guns"],["fighter","guns"]]],
	# Escort + strike bombers — 4 total
	[[["fighter","guns"],["fighter","guns"]], [["bomber","bombs"],["bomber","bombs"]]],
	# Attacker rockets + strike bombers — 4 total
	[[["attack","rockets"],["attack","rockets"]], [["bomber","bombs"],["bomber","bombs"]]],
	# Fighter cover + rocket attackers — 5 total
	[[["fighter","guns"],["fighter","guns"],["fighter","guns"]], [["attack","rockets"],["attack","rockets"]]],
	# Heavy bombing raid with gun escort — 5 total
	[[["bomber","bombs"],["bomber","bombs"],["bomber","bombs"]], [["fighter","guns"],["fighter","guns"]]],
	# Full strike package — 6 total
	[[["attack","rockets"],["attack","rockets"],["attack","rockets"]], [["bomber","bombs"],["bomber","bombs"],["bomber","bombs"]]],
	# Mixed attacker pair — 4 total
	[[["attack","guns"],["attack","guns"]], [["attack","rockets"],["attack","rockets"]]],
]


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("enemy_bases")
	add_to_group("origin_shifter")

	faction_color = Livery.get_team_upper_color(ENEMY_LIVERY_TEAM_ID)
	faction_name  = FACTION_NAMES[faction_id % FACTION_NAMES.size()]
	_rng.seed = hash(global_position) ^ (faction_id * 99991 + 12345)

	aircraft_reserve = aircraft_max
	vehicle_reserve  = vehicle_max

	_fighter_scene = load("res://Aircraft/Aircraft_3.tscn") as PackedScene
	_bomber_scene  = load("res://Aircraft/Aircraft_4.tscn") as PackedScene
	_attack_scene  = load("res://Aircraft/Aircraft_6.tscn") as PackedScene

	# Vehicle scenes — load all available enemy vehicle types
	for path in [
		"res://GroundVehicle/vehicle_enemy_buggy.tscn",
		"res://GroundVehicle/vehicle_enemy_pickup.tscn",
		"res://GroundVehicle/vehicle_enemy_battle_bus.tscn",
	]:
		var scene := load(path) as PackedScene
		if scene != null:
			_enemy_vehicle_scenes.append(scene)

	EnemyOpsManager.register_base(self)

	# Defer so global_position is fully set by EnemyBaseManager before we build
	call_deferred("_build_base")


func _physics_process(delta: float) -> void:
	_replenish(delta)


func _replenish(delta: float) -> void:
	# Aircraft — slow trickle up to aircraft_max
	if aircraft_reserve < aircraft_max:
		_aircraft_replenish_timer += delta
		if _aircraft_replenish_timer >= aircraft_replenish_interval_s:
			_aircraft_replenish_timer = 0.0
			aircraft_reserve = mini(aircraft_reserve + 1, aircraft_max)
			if debug_enabled:
				print("[EnemyBase] %s +1 aircraft reserve → %d" % [faction_name, aircraft_reserve])

	# Vehicles — faster trickle
	if vehicle_reserve < vehicle_max:
		_vehicle_replenish_timer += delta
		if _vehicle_replenish_timer >= vehicle_replenish_interval_s:
			_vehicle_replenish_timer = 0.0
			vehicle_reserve = mini(vehicle_reserve + 1, vehicle_max)
			if debug_enabled:
				print("[EnemyBase] %s +1 vehicle reserve → %d" % [faction_name, vehicle_reserve])


# ── Construction ──────────────────────────────────────────────────────────────

func _build_base() -> void:
	_build_pad()
	_place_buildings()
	if debug_enabled:
		print("[EnemyBase] %s built at %v (aircraft=%d, vehicles=%d)" % [
			faction_name, global_position, aircraft_max, vehicle_max])


func _build_pad() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _generate_pad_mesh()
	mi.position = Vector3(0.0, 0.2, 0.0)

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

	if runway_scene:
		var rw := runway_scene.instantiate() as Node3D
		add_child(rw)
		rw.position   = Vector3(0.0, _terrain_offset(0.0, 0.0), 0.0)
		rw.rotation.y = runway_yaw

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
	var wx := global_position.x + local_x
	var wz := global_position.z + local_z
	var h  := TerrainNavGrid.sample_height(wx, wz)
	if h <= TerrainNavGrid.IMPASSABLE * 0.5:
		return 0.0
	return h - global_position.y


# ── Deployment API ────────────────────────────────────────────────────────────

## Deploy a patrol as two paired virtual flights. Returns [] if reserve is insufficient.
func deploy_patrol_pair() -> Array[EnemyVirtualFlight]:
	# Pick a composition, fall back to smallest if reserve is low
	var comp_idx := _rng.randi() % PATROL_COMPOSITIONS.size()
	var comp: Array = PATROL_COMPOSITIONS[comp_idx]
	var total: int = (comp[0] as Array).size() + (comp[1] as Array).size()

	if aircraft_reserve < total:
		# Find smallest composition that fits
		var best_idx := -1
		var best_size := 9999
		for ci in range(PATROL_COMPOSITIONS.size()):
			var c: Array = PATROL_COMPOSITIONS[ci]
			var n: int = (c[0] as Array).size() + (c[1] as Array).size()
			if n <= aircraft_reserve and n < best_size:
				best_size = n
				best_idx  = ci
		if best_idx == -1:
			return []
		comp_idx = best_idx
		comp     = PATROL_COMPOSITIONS[comp_idx]
		total    = best_size

	aircraft_reserve -= total
	_flight_counter  += 1
	var start_angle  := _rng.randf_range(0.0, TAU)
	var result: Array[EnemyVirtualFlight] = []

	# Weighted patrol radius: ~50% standard, ~30% extended, ~20% deep ranging
	var radius_roll := _rng.randf()
	var patrol_radius: float
	if radius_roll < 0.50:
		patrol_radius = _rng.randf_range(5000.0, 10000.0)   # standard CAP
	elif radius_roll < 0.80:
		patrol_radius = _rng.randf_range(10000.0, 18000.0)  # extended patrol
	else:
		patrol_radius = _rng.randf_range(18000.0, 30000.0)  # deep ranging

	for gi in range(2):
		var group_def: Array = comp[gi]
		var f := EnemyVirtualFlight.new()
		f.flight_name   = "%s-%02d%s" % [faction_name.left(3).to_upper(), _flight_counter, "A" if gi == 0 else "B"]
		f.patrol_radius = patrol_radius
		f.faction_color = faction_color

		var scenes:   Array[PackedScene] = []
		var loadouts: Array[String]      = []
		var has_strike := false
		for slot in group_def:
			scenes.append(_resolve_aircraft_scene(slot[0] as String))
			loadouts.append(slot[1] as String)
			if (slot[1] as String) in ["bombs", "rockets"]:
				has_strike = true
		f.role = EnemyVirtualFlight.AircraftRole.BOMBER if has_strike else EnemyVirtualFlight.AircraftRole.FIGHTER
		f.setup(global_position, scenes, loadouts, start_angle + float(gi) * PI * 0.5)
		result.append(f)

	return result


func _resolve_aircraft_scene(key: String) -> PackedScene:
	match key:
		"fighter": return _fighter_scene
		"bomber":  return _bomber_scene
		"attack":  return _attack_scene if _attack_scene != null else _fighter_scene
	return _fighter_scene


## Deploy a virtual platoon from reserve. Returns null if reserve is insufficient.
func deploy_platoon(count: int) -> EnemyVirtualPlatoon:
	count = mini(count, vehicle_reserve)
	if count <= 0 or _enemy_vehicle_scenes.is_empty():
		return null

	vehicle_reserve -= count
	_platoon_counter += 1

	var radius_roll := _rng.randf()
	var platoon_radius: float
	if radius_roll < 0.50:
		platoon_radius = _rng.randf_range(3000.0, 8000.0)    # close patrol
	elif radius_roll < 0.80:
		platoon_radius = _rng.randf_range(8000.0, 15000.0)   # extended patrol
	else:
		platoon_radius = _rng.randf_range(15000.0, 24000.0)  # deep ranging

	var p := EnemyVirtualPlatoon.new()
	p.platoon_name   = "%s-P%02d" % [faction_name.left(3).to_upper(), _platoon_counter]
	p.vehicle_count  = count
	p.patrol_radius  = platoon_radius
	p.faction_color  = faction_color
	var start_angle  := _rng.randf_range(0.0, TAU)
	p.setup(global_position, _enemy_vehicle_scenes, start_angle)
	return p


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
			return node is Node3D
		node = parent
	return false


func apply_origin_shift(offset: Vector3) -> void:
	if not _is_shifted_by_scene_root_node3d_chain():
		global_position -= offset
	# EnemyOpsManager ticks the virtual units and they apply_origin_shift themselves.
	# Virtual units in the scene root are shifted by FloatingOrigin directly if they
	# are Node3D, but EnemyVirtualFlight/Platoon are plain Nodes — forward the shift.
	for f: EnemyVirtualFlight in EnemyOpsManager._get_flights(self):
		f.apply_origin_shift(offset)
	for p: EnemyVirtualPlatoon in EnemyOpsManager._get_platoons(self):
		p.apply_origin_shift(offset)


# ── Public API ────────────────────────────────────────────────────────────────

func get_faction_color() -> Color:
	return faction_color


## Legacy accessor — EnemyOpsManager is now the authority on active flights.
func get_flights() -> Array[EnemyVirtualFlight]:
	return EnemyOpsManager._get_flights(self)
