extends Node3D
## One reusable flash per weapon. Shared geometry/material; no lights, particles,
## timers or processing between shots. Gun/projectile forward is local +Z.
const DURATION_S := 0.055
static var _shared_mesh: ArrayMesh
static var _shared_material: ShaderMaterial
var _mesh: MeshInstance3D
var _anchor: WeakRef
var _anchor_offset := Transform3D.IDENTITY
var _remaining_s := 0.0
var _first_update := false
var _size := 1.0
var pulses := 0

static func emit_hardpoint(weapon: Node3D, muzzle: Transform3D, caliber_mm: int, recoil: Node) -> Node3D:
	# Some authored firing markers are offset from the visible barrel. Use the
	# already-resolved recoil mesh for presentation, keeping ballistics untouched.
	var anchor: Node3D = weapon
	if is_instance_valid(recoil) and not recoil.targets.is_empty():
		var barrel = recoil.targets[0].node
		if is_instance_valid(barrel) and barrel is MeshInstance3D and barrel.mesh != null:
			var bounds: AABB = (muzzle.affine_inverse() * barrel.global_transform) * barrel.get_aabb()
			muzzle.origin = muzzle * Vector3(bounds.get_center().x, bounds.get_center().y, bounds.end.z)
			anchor = barrel
	return emit(weapon, muzzle, caliber_mm, anchor)

static func emit(weapon: Node3D, muzzle: Transform3D, caliber_mm: int, anchor: Node3D = null) -> Node3D:
	var flash = weapon.get_node_or_null("MuzzleFlash")
	if flash == null:
		flash = load("res://Weapons/Guns/MuzzleFlash.gd").new()
		flash.name = "MuzzleFlash"
		weapon.add_child(flash)
	flash.pulse(muzzle, caliber_mm, anchor if is_instance_valid(anchor) else weapon)
	return flash

func _ready() -> void:
	_ensure_resources()
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _shared_mesh
	_mesh.material_override = _shared_material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mesh)
	hide()
	set_process(false)

func pulse(muzzle: Transform3D, caliber_mm: int, anchor: Node3D) -> void:
	_anchor = weakref(anchor)
	_anchor_offset = anchor.global_transform.affine_inverse() * muzzle
	_size = clampf(float(caliber_mm) / 20.0, 0.45, 2.0) * 1.2
	_remaining_s = DURATION_S
	_first_update = true
	pulses += 1
	# Deterministic variation must not consume the gameplay spread RNG.
	_mesh.rotation.z = float(pulses % 7) * 0.8976
	_mesh.scale = Vector3.ONE * (0.90 + float(pulses % 3) * 0.10)
	_mesh.set_instance_shader_parameter("flash_strength", 1.0)
	_follow_anchor()
	show()
	set_process(true)

func _follow_anchor() -> void:
	var anchor = _anchor.get_ref() if _anchor != null else null
	if not is_instance_valid(anchor) or not anchor.is_inside_tree():
		_finish()
		return
	var world: Transform3D = anchor.global_transform * _anchor_offset
	world.basis = world.basis.orthonormalized().scaled(Vector3.ONE * _size)
	global_transform = world

func _process(delta: float) -> void:
	_follow_anchor()
	if not visible: return
	# Keep at least one rendered frame even when the frame time exceeds 55 ms.
	if _first_update:
		_first_update = false
		return
	_remaining_s -= maxf(delta, 0.0)
	if _remaining_s <= 0.0:
		_finish()
		return
	_mesh.set_instance_shader_parameter("flash_strength", _remaining_s / DURATION_S)

func _finish() -> void:
	hide()
	set_process(false)

static func _ensure_resources() -> void:
	if _shared_mesh != null: return
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
instance uniform float flash_strength = 1.0;
void fragment() {
    ALBEDO = COLOR.rgb;
    EMISSION = COLOR.rgb * 0.65 * flash_strength;
}
"""
	_shared_material = ShaderMaterial.new()
	_shared_material.shader = shader
	# Opaque flat-color polygons match the faceted tracers. A cream core and
	# amber border give a crisp burst without transparent gradients or stacking.
	# Crossed sheets keep the shape readable from every viewing direction.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sheet in 3:
		var axis := Vector3(cos(sheet * PI / 3.0), sin(sheet * PI / 3.0), 0)
		var center := Vector3(0, 0, 0.20)
		var edge := [Vector3(0, 0, 0.01), axis * 0.07 + Vector3(0, 0, 0.08),
			axis * 0.25 + Vector3(0, 0, 0.28), axis * 0.08 + Vector3(0, 0, 0.43),
			Vector3(0, 0, 1.05), -axis * 0.08 + Vector3(0, 0, 0.43),
			-axis * 0.25 + Vector3(0, 0, 0.28), -axis * 0.07 + Vector3(0, 0, 0.08)]
		for i in edge.size():
			var next: int = (i + 1) % edge.size()
			var inner_a: Vector3 = center.lerp(edge[i], 0.64)
			var inner_b: Vector3 = center.lerp(edge[next], 0.64)
			var rim := Color(1.0, 0.51, 0.065) if sheet % 2 == 0 else Color(1.0, 0.66, 0.12)
			_triangle(surface, edge[i], edge[next], inner_a, rim)
			_triangle(surface, edge[next], inner_b, inner_a, rim)
			_triangle(surface, center, inner_a, inner_b, Color(1.0, 0.96, 0.73))
	for i in 12:
		var a := float(i) * TAU / 12.0
		var b := float(i + 1) * TAU / 12.0
		var ra := 0.23 if i % 2 == 0 else 0.08
		var rb := 0.08 if i % 2 == 0 else 0.23
		var center := Vector3(0, 0, 0.12)
		var outer_a := Vector3(cos(a) * ra, sin(a) * ra, 0.12)
		var outer_b := Vector3(cos(b) * rb, sin(b) * rb, 0.12)
		var inner_a := center.lerp(outer_a, 0.55)
		var inner_b := center.lerp(outer_b, 0.55)
		_triangle(surface, outer_a, outer_b, inner_a, Color(1.0, 0.61, 0.08))
		_triangle(surface, outer_b, inner_b, inner_a, Color(1.0, 0.61, 0.08))
		_triangle(surface, center, inner_a, inner_b, Color(1.0, 0.96, 0.73))
	_shared_mesh = surface.commit()

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_vertex(surface, a, color)
	_vertex(surface, b, color)
	_vertex(surface, c, color)

static func _vertex(surface: SurfaceTool, point: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(point)
