extends Node3D
class_name RockFeature

## Procedural low-poly stone feature — pillar, cluster, or arch.
## Uses the same height-based coloring and flat-shaded material as LowPolyTerrain.
## Arches use ConcavePolygonShape3D so aircraft can fly through the opening.

enum FeatureType { PILLAR, CLUSTER, ARCH }

@export var feature_type: FeatureType = FeatureType.PILLAR
@export var rng_seed: int = 0

# ── Color palette — match LowPolyTerrain exports ────────────────────────────
@export_group("Colors")
@export var canyon_floor_color:   Color = Color(0.30, 0.17, 0.09)
@export var canyon_wall_color:    Color = Color(0.72, 0.34, 0.17)
@export var canyon_upper_color:   Color = Color(0.86, 0.57, 0.34)
@export var plateau_color:        Color = Color(0.88, 0.80, 0.42)
@export var steep_slope_color:    Color = Color(0.28, 0.27, 0.25)
@export var color_noise_strength: float = 0.05
@export var color_floor_y:        float = 0.0    # world Y of canyon floor
@export var color_top_y:          float = 370.0  # world Y of plateau top
@export var steep_slope_min_ny:   float = 0.88
@export var steep_slope_band:     float = 0.08
@export var steep_slope_strength: float = 1.0

# ── Pillar / cluster params ──────────────────────────────────────────────────
@export_group("Pillar")
@export var pillar_height: float = 80.0
@export var pillar_radius: float = 18.0
@export var pillar_sides:  int   = 6
## How much narrower the top is than the base (0 = straight column, 0.5 = half-width top)
@export var pillar_taper:  float = 0.20

# ── Arch params ──────────────────────────────────────────────────────────────
@export_group("Arch")
## Horizontal distance between the two leg bases
@export var arch_span:      float = 120.0
## Height of the arch crown above the base
@export var arch_height:    float = 70.0
## Cross-section tube radius — controls how thick the stone is
@export var arch_thickness: float = 14.0
## Number of polygon sides on the tube cross-section (5-8 looks good)
@export var arch_sides:     int   = 6
## Horizontal offset of the meeting point from centre (0 = symmetric lean)
@export var arch_lean_bias: float = 0.0

# ── Build API ────────────────────────────────────────────────────────────────

## Called by spawner after positioning the node.  Also called on _ready for
## editor-placed instances.
func build() -> void:
	for c in get_children():
		c.queue_free()

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors  := PackedColorArray()

	match feature_type:
		FeatureType.PILLAR:
			_gen_pillar(verts, normals, colors, rng,
				Vector3.ZERO, pillar_height, pillar_radius, pillar_sides)
		FeatureType.CLUSTER:
			_gen_cluster(verts, normals, colors, rng)
		FeatureType.ARCH:
			_gen_arch(verts, normals, colors, rng)

	if verts.is_empty():
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR]  = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _make_material()
	add_child(mi)

	var body := StaticBody3D.new()
	add_child(body)
	body.add_to_group("terrain")
	var cnode := CollisionShape3D.new()
	# ConcavePolygonShape3D preserves the arch opening so aircraft can fly through.
	var cshape := ConcavePolygonShape3D.new()
	cshape.set_faces(mesh.get_faces())
	cnode.shape = cshape
	body.add_child(cnode)

func _ready() -> void:
	build()

# ── Material (identical to LowPolyTerrain) ───────────────────────────────────

func _make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness  = 1.0
	mat.specular   = 0.05
	mat.cull_mode  = BaseMaterial3D.CULL_DISABLED  # double-sided like terrain
	return mat

# ── Generators ───────────────────────────────────────────────────────────────

func _gen_pillar(
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		rng: RandomNumberGenerator,
		origin: Vector3, height: float, radius: float, sides: int) -> void:

	var top_r := radius * (1.0 - pillar_taper)

	# Top ring with slight organic vertex variation
	var top_ring: Array[Vector3] = []
	for i in sides:
		var a := TAU * float(i) / float(sides)
		var r := top_r  * rng.randf_range(0.86, 1.14)
		var y := height * rng.randf_range(0.93, 1.07)
		top_ring.append(origin + Vector3(cos(a) * r, y, sin(a) * r))

	# Side quads (base ring is at Y=0, perfectly regular)
	for i in sides:
		var ni := (i + 1) % sides
		var ai := TAU * float(i)  / float(sides)
		var an := TAU * float(ni) / float(sides)
		var b0 := origin + Vector3(cos(ai) * radius, 0.0, sin(ai) * radius)
		var b1 := origin + Vector3(cos(an) * radius, 0.0, sin(an) * radius)
		var t0 := top_ring[i]
		var t1 := top_ring[ni]
		_tri(verts, normals, colors, b0, t0, t1, rng)
		_tri(verts, normals, colors, b0, t1, b1, rng)

	# Top cap (fan from centroid of top ring)
	var top_sum := Vector3.ZERO
	for v in top_ring:
		top_sum += v
	var top_cen := top_sum / float(sides)
	for i in sides:
		_tri(verts, normals, colors, top_cen, top_ring[i], top_ring[(i + 1) % sides], rng)


func _gen_cluster(
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		rng: RandomNumberGenerator) -> void:

	var count := rng.randi_range(3, 6)
	for _i in count:
		var angle  := rng.randf() * TAU
		var dist   := rng.randf_range(0.0, pillar_radius * 2.2)
		var h      := pillar_height * rng.randf_range(0.30, 1.20)
		var r      := pillar_radius  * rng.randf_range(0.40, 1.0)
		var sides  := rng.randi_range(5, 7)
		var origin := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		_gen_pillar(verts, normals, colors, rng, origin, h, r, sides)


func _gen_arch(
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		rng: RandomNumberGenerator) -> void:

	# Two thick stone columns leaning inward, meeting near the top.
	# The gap between them at ground level is the flythrough opening.
	var half_span := arch_span * 0.5

	# Meeting point — slightly off-centre so one column looks like it fell onto the other.
	var bias := arch_lean_bias + rng.randf_range(-half_span * 0.15, half_span * 0.15)
	var meet  := Vector3(bias, arch_height, 0.0)

	# Left column
	var left_base  := Vector3(-half_span, 0.0, 0.0)
	var left_thick := arch_thickness * rng.randf_range(0.90, 1.10)
	_gen_stone_column(verts, normals, colors, rng,
		left_base, meet, left_thick, arch_sides,
		rng.randf() * TAU)  # random polygon twist

	# Right column — slightly different thickness for the "resting on" look
	var right_base  := Vector3(half_span, 0.0, 0.0)
	var right_thick := arch_thickness * rng.randf_range(0.90, 1.10)
	_gen_stone_column(verts, normals, colors, rng,
		right_base, meet, right_thick, arch_sides,
		rng.randf() * TAU)


## Extruded polygon prism from base_center to top_center.
## twist_angle rotates the polygon cross-section for visual variety.
func _gen_stone_column(
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		rng: RandomNumberGenerator,
		base_center: Vector3, top_center: Vector3,
		radius: float, sides: int, twist_angle: float) -> void:

	var axis := (top_center - base_center).normalized()

	# Two vectors perpendicular to the axis (column cross-section plane)
	var b1: Vector3
	if absf(axis.dot(Vector3.UP)) > 0.98:
		b1 = axis.cross(Vector3.RIGHT).normalized()
	else:
		b1 = axis.cross(Vector3.UP).normalized()
	var b2 := axis.cross(b1).normalized()

	# Build base and top rings with slight organic vertex variation
	var base_ring: Array[Vector3] = []
	var top_ring:  Array[Vector3] = []
	for v in range(sides):
		var a  := TAU * float(v) / float(sides) + twist_angle
		var rb := radius * rng.randf_range(0.88, 1.12)
		var rt := radius * rng.randf_range(0.88, 1.12)
		var dir := b1 * cos(a) + b2 * sin(a)
		base_ring.append(base_center + dir * rb)
		top_ring.append(top_center  + dir * rt)

	# Side quads
	for v in range(sides):
		var nv := (v + 1) % sides
		_tri(verts, normals, colors, base_ring[v],  base_ring[nv], top_ring[nv],  rng)
		_tri(verts, normals, colors, base_ring[v],  top_ring[nv],  top_ring[v],   rng)

	# Bottom cap (faces down — buried in terrain, but caps the mesh cleanly)
	for v in range(sides):
		_tri(verts, normals, colors, base_center, base_ring[(v + 1) % sides], base_ring[v], rng)

	# Top cap
	for v in range(sides):
		_tri(verts, normals, colors, top_center, top_ring[v], top_ring[(v + 1) % sides], rng)

# ── Triangle emitter (same logic as LowPolyTerrain._append_face) ─────────────

func _tri(
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		v0: Vector3, v1: Vector3, v2: Vector3,
		rng: RandomNumberGenerator) -> void:

	var n := (v1 - v0).cross(v2 - v0).normalized()

	# Height-based colour — world Y of face centroid
	var wy    := global_position.y + (v0.y + v1.y + v2.y) / 3.0
	var ht    := clampf((wy - color_floor_y) / maxf(color_top_y - color_floor_y, 1.0), 0.0, 1.0)

	var base: Color
	if ht < 0.25:
		base = canyon_floor_color.lerp(canyon_wall_color,  ht / 0.25)
	elif ht < 0.72:
		base = canyon_wall_color.lerp(canyon_upper_color,  (ht - 0.25) / 0.47)
	else:
		base = canyon_upper_color.lerp(plateau_color,      (ht - 0.72) / 0.28)

	# Steep-face grey (same thresholds as terrain)
	var steep := clampf(
		(steep_slope_min_ny - absf(n.y)) / maxf(steep_slope_band, 0.001), 0.0, 1.0
	) * steep_slope_strength
	base = base.lerp(steep_slope_color, steep)

	# Per-face micro-tint
	var tint := 1.0 + (rng.randf() * 2.0 - 1.0) * color_noise_strength
	var c := Color(
		clampf(base.r * tint, 0.0, 1.0),
		clampf(base.g * tint, 0.0, 1.0),
		clampf(base.b * tint, 0.0, 1.0))

	verts.push_back(v0);  verts.push_back(v1);  verts.push_back(v2)
	normals.push_back(n); normals.push_back(n); normals.push_back(n)
	colors.push_back(c);  colors.push_back(c);  colors.push_back(c)
