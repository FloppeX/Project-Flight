extends Node3D
## Presentation only: ResourceField owns the finite surface and underground stock.
## Process-driven shader time keeps pulses and vapour paused with the world.

const LIQUID_SHADER: Shader = preload("res://POI/World/CoriumLiquid.gdshader")
const VAPOUR_SHADER: Shader = preload("res://POI/World/CoriumVapour.gdshader")
const SCAR_RADIUS := 4.8
const SEGMENTS := 48

var _built := false
var _elapsed := 0.0
var _activity := 1.0
var _surface_fraction := 1.0
var _liquid: ShaderMaterial
var _vapour: ShaderMaterial
var _pool: MeshInstance3D
var _fissures: Array[MeshInstance3D] = []
var _wisps: Array[MeshInstance3D] = []
var _wisp_offsets: Array[Vector3] = []
var _light: OmniLight3D


func setup(source_id: int) -> void:
	if _built:
		return
	_built = true
	name = "CoriumSeep_%d" % source_id
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_align_with_surface()
	var rng := RandomNumberGenerator.new()
	rng.seed = source_id * 1739 + 54719
	_elapsed = rng.randf_range(0.0, 40.0)
	_liquid = ShaderMaterial.new()
	_liquid.shader = LIQUID_SHADER
	_vapour = ShaderMaterial.new()
	_vapour.shader = VAPOUR_SHADER
	var basalt := StandardMaterial3D.new()
	basalt.albedo_color = Color("2e292f")
	basalt.roughness = 0.97
	var crust := StandardMaterial3D.new()
	crust.albedo_color = Color("464049")
	crust.roughness = 0.94
	var ash := StandardMaterial3D.new()
	ash.albedo_color = Color("625856")
	ash.roughness = 1.0

	var edge: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for i in range(SEGMENTS):
		var angle := TAU * i / SEGMENTS
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var variation := 1.0 + 0.09 * sin(angle * 5.0 + 0.7) + 0.06 * sin(angle * 9.0)
		edge.append(direction * SCAR_RADIUS * variation)
		inner.append(direction * (2.6 + 0.18 * sin(angle * 3.0) + 0.18 * sin(angle * 7.0 + 0.2)) + Vector3.UP * rng.randf_range(0.21, 0.30))
	var scar := SurfaceTool.new()
	scar.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(SEGMENTS):
		var next := (i + 1) % SEGMENTS
		var rim := inner[i]
		var next_rim := inner[next]
		_triangle(scar, edge[i] + Vector3.UP * 0.025, rim, edge[next] + Vector3.UP * 0.025)
		_triangle(scar, edge[next] + Vector3.UP * 0.025, rim, next_rim)
		var bed_edge := Vector3(rim.x, 0.105, rim.z)
		var next_bed_edge := Vector3(next_rim.x, 0.105, next_rim.z)
		_triangle(scar, rim, bed_edge, next_bed_edge)
		_triangle(scar, rim, next_bed_edge, next_rim)
	scar.generate_normals()
	_mesh("MineralScar", scar.commit(), Vector3.ZERO, crust)

	var bed := _disc(inner, 0.105)
	_mesh("DryMineralBed", bed, Vector3.ZERO, basalt)
	_pool = _mesh("SurfaceCorium", _disc(inner, 0.132), Vector3.ZERO, _liquid)
	for i in range(15):
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(2.6, 4.3)
		var shard := CylinderMesh.new()
		shard.radial_segments = rng.randi_range(4, 6)
		shard.top_radius = rng.randf_range(0.11, 0.26)
		shard.bottom_radius = rng.randf_range(0.27, 0.54)
		shard.height = rng.randf_range(0.24, 0.55)
		var rock := _mesh("CrustFragment_%02d" % i, shard, Vector3(cos(angle) * radius, shard.height * 0.32 + 0.08, sin(angle) * radius), basalt if i % 3 else ash)
		rock.rotation = Vector3(rng.randf_range(-0.18, 0.18), rng.randf() * TAU, rng.randf_range(-0.16, 0.16))
		rock.scale = Vector3(rng.randf_range(0.9, 1.7), 1.0, rng.randf_range(0.7, 1.2))
	for i in range(7):
		var angle := TAU * i / 7.0 + rng.randf_range(-0.24, 0.24)
		var fissure := SurfaceTool.new()
		fissure.begin(Mesh.PRIMITIVE_TRIANGLES)
		var previous := Vector3(cos(angle), 0.0, sin(angle)) * 2.2 + Vector3.UP * 0.15
		for step in range(4):
			var radius := 2.7 + step * 0.44
			var direction := Vector3(cos(angle + rng.randf_range(-0.09, 0.09)), 0.0, sin(angle + rng.randf_range(-0.09, 0.09)))
			var next := direction * radius + Vector3.UP * lerpf(0.325, 0.155, step / 3.0)
			var tangent := Vector3(-(next - previous).z, 0.0, (next - previous).x).normalized() * rng.randf_range(0.025, 0.06)
			_triangle(fissure, previous - tangent, previous + tangent, next - tangent)
			_triangle(fissure, next - tangent, previous + tangent, next + tangent)
			previous = next
		fissure.generate_normals()
		_fissures.append(_mesh("LiquidFissure_%02d" % i, fissure.commit(), Vector3.ZERO, _liquid))
	for i in range(7):
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(0.2, 2.1)
		var quad := QuadMesh.new()
		quad.size = Vector2(rng.randf_range(0.5, 0.85), rng.randf_range(0.9, 1.45))
		var at := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_wisp_offsets.append(at)
		_wisps.append(_mesh("CoriumVapour_%02d" % i, quad, at, _vapour))
	_light = OmniLight3D.new()
	_light.name = "SeepGlow"
	_light.light_color = Color("efb35b")
	_light.light_energy = 0.9
	_light.omni_range = 8.0
	_light.omni_attenuation = 1.8
	_light.position.y = 0.85
	_light.shadow_enabled = false
	add_child(_light)
	_apply_state()


func update_source(source: Dictionary) -> void:
	if not _built:
		setup(int(source.get("id", 0)))
	var materials: Dictionary = source.get("materials", {})
	var surface := maxf(0.0, float(materials.get("corium", 0.0)))
	_surface_fraction = clampf(surface / maxf(1.0, float(source.get("surface_capacity", source.get("initial", 160.0)))), 0.0, 1.0)
	var phase := str(source.get("seep_phase", "seeping"))
	_activity = 1.0 if phase == "seeping" else 0.12
	if phase == "exhausted" or (surface <= 0.001 and float(source.get("reserve_corium", 0.0)) <= 0.001):
		_activity = 0.0
	_apply_state()


func _process(delta: float) -> void:
	if not _built:
		return
	_elapsed += delta
	_liquid.set_shader_parameter("elapsed", _elapsed)
	_vapour.set_shader_parameter("elapsed", _elapsed)
	for i in range(_wisps.size()):
		var rise := fposmod(_elapsed * 0.22 + float(i) / _wisps.size(), 1.0)
		var at := _wisp_offsets[i]
		_wisps[i].position = at + Vector3(sin(_elapsed * 0.5 + i) * rise * 0.3, 0.44 + rise * 1.5, cos(_elapsed * 0.35 + i) * rise * 0.2)
		_wisps[i].scale = Vector3.ONE * (0.65 + rise * 0.7)
	_light.light_energy = _activity * (0.7 + 0.15 * sin(_elapsed * 0.8))


func _align_with_surface() -> void:
	# The campaign chooses stable terrain, which can still have a gentle slope.
	# Match that slope so the shallow pool is not buried under the uphill edge.
	if not is_inside_tree():
		return
	var grid := get_tree().root.get_node_or_null("TerrainNavGrid")
	if grid == null or not grid.has_query_grid():
		return
	var at := global_position
	var left: float = grid.sample_query_height(at.x - 4.0, at.z)
	var right: float = grid.sample_query_height(at.x + 4.0, at.z)
	var back: float = grid.sample_query_height(at.x, at.z - 4.0)
	var front: float = grid.sample_query_height(at.x, at.z + 4.0)
	if minf(minf(left, right), minf(back, front)) <= -500000.0:
		return
	var normal := Vector3((left - right) / 8.0, 1.0, (back - front) / 8.0).normalized()
	basis = Basis(Quaternion(Vector3.UP, normal))


func _apply_state() -> void:
	_liquid.set_shader_parameter("activity", _activity)
	_liquid.set_shader_parameter("surface_fraction", _surface_fraction)
	_liquid.set_shader_parameter("elapsed", _elapsed)
	_vapour.set_shader_parameter("activity", _activity)
	_vapour.set_shader_parameter("elapsed", _elapsed)
	_pool.visible = _surface_fraction > 0.001 or _activity > 0.5
	_pool.scale = Vector3.ONE * lerpf(0.32, 1.0, sqrt(_surface_fraction))
	_pool.scale.y = 1.0
	for fissure in _fissures:
		fissure.visible = _activity > 0.0
	for wisp in _wisps:
		wisp.visible = _activity > 0.5
	_light.visible = _activity > 0.0
	_light.light_energy = _activity * 0.8


func _disc(ring: Array[Vector3], height: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(ring.size()):
		var next := (i + 1) % ring.size()
		_triangle(surface, Vector3(0.0, height, 0.0), Vector3(ring[next].x, height, ring[next].z), Vector3(ring[i].x, height, ring[i].z))
	surface.generate_normals()
	return surface.commit()


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot's front faces use clockwise winding when seen from above.
	for at in [a, c, b]:
		surface.set_uv(Vector2(at.x, at.z) / 5.0 + Vector2.ONE * 0.5)
		surface.add_vertex(at)


func _mesh(label: String, shape: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = shape
	result.position = at
	result.material_override = material
	add_child(result)
	return result
