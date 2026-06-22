@tool
extends Node3D
class_name InsigniaMarker

## Editor gizmo that marks where an insignia decal goes on an aircraft / vehicle.
##
## Place one of these for each insignia. The semi-transparent cylinder shows the
## projection volume:
##   - DIAMETER (radius * 2)  -> the size of the insignia on the surface
##   - HEIGHT (length)        -> how deep the decal projects into the body
##   - The cylinder's -Y axis -> the projection direction (point the flat top at
##                               the surface the insignia should appear on)
##
## At runtime Livery.gd reads every InsigniaMarker, spawns a Decal matching its
## transform / size, and the marker mesh itself is hidden. So this is purely an
## authoring aid — what you see in the editor is what gets stamped.
##
## ORIENTATION SYMBOL: an arrow on the OUTER (+Y) face shows how the decal image is
## rotated. It points toward the insignia's UP and a side tick marks its RIGHT, so
## you can see exactly how the emblem reads in game, not just the cylinder axis.

## Diameter of the insignia footprint on the surface (metres). The texture aspect
## ratio adjusts the cross-axis automatically, this is the nominal size.
@export var diameter: float = 1.0:
	set(value):
		diameter = maxf(value, 0.01)
		_rebuild()

## How deep the decal projects through the body (metres) = the cylinder length.
@export var depth: float = 0.6:
	set(value):
		depth = maxf(value, 0.01)
		_rebuild()

## Optional explicit insignia size on the cross axis. 0 = use diameter (square),
## the texture aspect ratio is then applied by Livery.
@export var cross_diameter: float = 0.0:
	set(value):
		cross_diameter = maxf(value, 0.0)
		_rebuild()

var _mesh: MeshInstance3D
var _symbol: MeshInstance3D


func _ready() -> void:
	add_to_group("insignia_marker")
	_rebuild()
	# In game (not the editor), the gizmo must never be visible — Livery hides it,
	# but hide here too so it's invisible even before livery runs.
	if not Engine.is_editor_hint():
		visible = false


## The decal footprint size (X, Z) and projection depth (Y), in this node's space.
func get_decal_size(texture_aspect: float) -> Vector3:
	var w := maxf(diameter, 0.01)
	var cross := cross_diameter if cross_diameter > 0.0 else w * texture_aspect
	# Decal.size = (width_X, depth_Y, height_Z); projection is along local -Y.
	return Vector3(w, maxf(depth, 0.01), cross)


func _rebuild() -> void:
	if not Engine.is_editor_hint():
		return
	# Setters can fire during scene load before the node is in the tree; defer.
	if not is_inside_tree():
		return
	if _mesh == null:
		_mesh = get_node_or_null("_GizmoMesh") as MeshInstance3D
		if _mesh == null:
			_mesh = MeshInstance3D.new()
			_mesh.name = "_GizmoMesh"
			# Editor-only helper: never picked up as a real mesh and not saved as a
			# child of the marker in the host scene.
			_mesh.set_meta("_edit_lock_", true)
			add_child(_mesh)
	var cyl := CylinderMesh.new()
	cyl.top_radius = maxf(diameter, 0.01) * 0.5
	cyl.bottom_radius = cyl.top_radius
	cyl.height = maxf(depth, 0.01)
	_mesh.mesh = cyl
	# Cylinder is centred on its origin along Y; the decal projects from the origin
	# along -Y, so leave it centred (the gizmo straddles the surface).
	_mesh.position = Vector3.ZERO
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	_mesh.material_override = mat

	_rebuild_symbol()


## Draw the orientation symbol showing how the decal IMAGE is oriented in game.
## The decal projects along -Y onto the surface near the marker origin; in Godot the
## insignia's TOP ends up toward the decal's -Z and its RIGHT toward +X. So the arrow
## points -Z ("up" of the emblem) with a right tick along +X. The symbol sits on the
## +Y (outer) side — the surface the insignia actually shows on — so it's visible
## outside the body rather than buried at the deep projecting end.
func _rebuild_symbol() -> void:
	if _symbol == null:
		_symbol = get_node_or_null("_GizmoSymbol") as MeshInstance3D
		if _symbol == null:
			_symbol = MeshInstance3D.new()
			_symbol.name = "_GizmoSymbol"
			_symbol.set_meta("_edit_lock_", true)
			add_child(_symbol)

	var r := maxf(diameter, 0.01) * 0.5
	var cross_r := (cross_diameter * 0.5) if cross_diameter > 0.0 else r
	var half_depth := maxf(depth, 0.01) * 0.5

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	# Symbol on BOTH ends, IDENTICAL (both arrows -Z, both ticks +X). Because the two
	# ends share the same world-space directions, sighting straight through the
	# cylinder from either end shows both ticks on the same physical side — so "right"
	# is unambiguous no matter which end you look from.
	_draw_orientation_symbol(im, half_depth + 0.01, r, cross_r, 1.0)
	_draw_orientation_symbol(im, -half_depth - 0.01, r, cross_r, 1.0)
	im.surface_end()
	_symbol.mesh = im

	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(1.0, 0.85, 0.1, 1.0)  # bright yellow, reads on any surface
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smat.no_depth_test = true  # always visible even when inside the body
	_symbol.material_override = smat


## Draw the up-arrow (-Z) and right-tick (+X) at face height `y`. `mirror` (+/-1)
## can flip the tick across the projection axis if ever needed; both ends use +1 so
## the symbol points the same world direction on each face.
func _draw_orientation_symbol(im: ImmediateMesh, y: float, r: float, cross_r: float, mirror: float) -> void:
	var up := minf(cross_r, r) * 0.8     # arrow length toward insignia-up (-Z)
	var half_w := up * 0.35              # arrow head half-width
	var head := up * 0.45                # arrow head length
	var tick := minf(r, cross_r) * 0.5 * mirror  # right-tick along +X (mirrored on deep face)
	# Arrow shaft: origin -> -Z (insignia up)
	_line(im, Vector3(0, y, 0), Vector3(0, y, -up))
	# Arrow head (two barbs)
	_line(im, Vector3(0, y, -up), Vector3(half_w, y, -up + head))
	_line(im, Vector3(0, y, -up), Vector3(-half_w, y, -up + head))
	# Right tick: origin -> +X (insignia right)
	_line(im, Vector3(0, y, 0), Vector3(tick, y, 0))


func _line(im: ImmediateMesh, a: Vector3, b: Vector3) -> void:
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
