"""Cut movable control surfaces out of Aircraft 5's untouched original GLB.

Produces ailerons, an elevator and twin boom rudders as separate objects, each
with its origin on its own hinge axis and its local X axis pointing along that
axis, so the game can deflect a surface with a single rotation about local X.

Run with Blender 4.5 in background mode, or with the `bpy` module directly.
Coordinates in this file use Godot's Y-up, +Z-forward frame, not Blender's
Z-up frame; `to_blender()` converts at the boundary. +X is the aircraft's left.

    blender --background --factory-startup --python-exit-code 1 \
        --python tools/build_aircraft5_control_surfaces.py -- --build
"""
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Models/Aircraft_5/aircraft_5.glb"
OUTPUT = ROOT / "Models/Aircraft_5/aircraft_5_control_surfaces.glb"

# Hinge gap in metres. The parent loses a slightly larger volume than the
# surface gains, so the two never share a face and the hinge line stays visible.
GAP = 0.015

# --- Aileron -----------------------------------------------------------------
# The wing trailing edge sweeps forward going outboard; the hinge line is that
# edge offset forward by a constant chord, so aileron chord stays uniform.
TE_ROOT = (3.0, -0.830)          # (X, Z) of the trailing edge at the wing root
TE_SLOPE = 0.0711                # dZ/dX of the trailing edge, measured off the mesh
AILERON_CHORD = 0.36
AILERON_X_INBOARD = 4.70
AILERON_X_OUTBOARD = 6.45
WING_HALF_THICKNESS = 1.0        # generous; the cutter only needs to exceed the aerofoil

# --- Elevator ----------------------------------------------------------------
# The stabiliser spans the booms at Y 1.75..1.85, chord Z -5.18 (TE) .. -4.36 (LE).
ELEVATOR_HINGE_Z = -4.934        # aft 30 per cent of the 0.82 m chord
ELEVATOR_X_HALF_SPAN = 2.15      # stays inboard of the booms at |X| 2.25..2.62
ELEVATOR_Y_LOW = 1.30
ELEVATOR_Y_HIGH = 2.30

# --- Rudder ------------------------------------------------------------------
# Each boom is a swept plate; its aft edge rakes back as it rises. The hinge is
# that edge offset forward by a constant chord, so both rudders stay uniform.
BOOM_AFT_REF = (-0.20, -4.685)   # (Y, Z) on the boom aft edge
BOOM_AFT_SLOPE = -0.2005         # dZ/dY of the boom aft edge
RUDDER_CHORD = 0.30
RUDDER_Y_LOW = 0.50
# The stabiliser spans X +/-2.48 at Y 1.75..1.85, which reaches through the
# boom's own X band. Stopping below its underside keeps the rudder from taking
# a bite out of the stabiliser tip.
RUDDER_Y_HIGH = 1.68
BOOM_X_INNER = 2.00              # brackets the boom's 2.25..2.62 thickness
BOOM_X_OUTER = 2.90


def to_blender(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((x, -z, y))


def trailing_edge_z(x):
    return TE_ROOT[1] + TE_SLOPE * (abs(x) - TE_ROOT[0])


def boom_aft_z(y):
    return BOOM_AFT_REF[1] + BOOM_AFT_SLOPE * (y - BOOM_AFT_REF[0])


def make_prism(name, corners):
    """Build a closed hexahedron from eight Godot-space corners.

    Corner order is front face (0-3) then back face (4-7), each wound the same
    way, so the side quads below connect matching pairs.
    """
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(
        [to_blender(*c) for c in corners],
        [],
        [
            (0, 1, 2, 3),          # front (the hinge plane)
            (7, 6, 5, 4),          # back
            (0, 4, 5, 1),
            (1, 5, 6, 2),
            (2, 6, 7, 3),
            (3, 7, 4, 0),
        ],
    )
    mesh.validate()

    # Mirroring a cutter to the other side reverses its winding, which the EXACT
    # solver reads as an inside-out volume and then carves almost nothing. Force
    # outward normals so both sides behave identically.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def aileron_cutter(name, side, margin):
    """Everything aft of the aileron hinge, between the span limits."""
    x_in = side * (AILERON_X_INBOARD - margin)
    x_out = side * (AILERON_X_OUTBOARD + margin)
    z_in = trailing_edge_z(AILERON_X_INBOARD) + AILERON_CHORD + margin
    z_out = trailing_edge_z(AILERON_X_OUTBOARD) + AILERON_CHORD + margin
    t = WING_HALF_THICKNESS
    deep = 3.0
    return make_prism(name, [
        (x_in, -t, z_in), (x_out, -t, z_out), (x_out, t, z_out), (x_in, t, z_in),
        (x_in, -t, z_in - deep), (x_out, -t, z_out - deep),
        (x_out, t, z_out - deep), (x_in, t, z_in - deep),
    ])


def elevator_cutter(name, margin):
    """Everything aft of the elevator hinge, between the booms."""
    x = ELEVATOR_X_HALF_SPAN + margin
    z = ELEVATOR_HINGE_Z + margin
    y0 = ELEVATOR_Y_LOW - margin
    y1 = ELEVATOR_Y_HIGH + margin
    deep = 2.0
    return make_prism(name, [
        (-x, y0, z), (x, y0, z), (x, y1, z), (-x, y1, z),
        (-x, y0, z - deep), (x, y0, z - deep),
        (x, y1, z - deep), (-x, y1, z - deep),
    ])


def rudder_cutter(name, side, margin):
    """Everything aft of the rudder hinge, up the boom's aft edge."""
    y0 = RUDDER_Y_LOW - margin
    y1 = RUDDER_Y_HIGH + margin
    z0 = boom_aft_z(y0) + RUDDER_CHORD + margin
    z1 = boom_aft_z(y1) + RUDDER_CHORD + margin
    xi = side * (BOOM_X_INNER - margin)
    xo = side * (BOOM_X_OUTER + margin)
    deep = 2.0
    return make_prism(name, [
        (xi, y0, z0), (xo, y0, z0), (xo, y1, z1), (xi, y1, z1),
        (xi, y0, z0 - deep), (xo, y0, z0 - deep),
        (xo, y1, z1 - deep), (xi, y1, z1 - deep),
    ])


def dominant_material_index(obj):
    counts = {}
    for poly in obj.data.polygons:
        counts[poly.material_index] = counts.get(poly.material_index, 0) + 1
    return max(counts, key=counts.get) if counts else 0


def match_materials(cutter, target):
    """Give the cutter the target's material list so cap faces inherit a real
    material instead of falling back to slot zero."""
    cutter.data.materials.clear()
    for slot in target.data.materials:
        cutter.data.materials.append(slot)
    index = dominant_material_index(target)
    for poly in cutter.data.polygons:
        poly.material_index = index


def apply_boolean(obj, cutter, operation):
    modifier = obj.modifiers.new(name="cut", type="BOOLEAN")
    modifier.object = cutter
    modifier.operation = operation
    modifier.solver = "EXACT"
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    obj.data = bpy.data.meshes.new_from_object(evaluated)
    obj.modifiers.clear()


def hinge_from_cut(obj, plane_point, plane_normal, tolerance=1e-4):
    """Derive the hinge straight from the face the cut actually produced.

    Every vertex the boolean placed on the cutting plane belongs to the new
    cut face, so its centroid is the middle of the hinge line and its longest
    in-plane direction is the hinge axis. Deriving both from the geometry keeps
    the hinge aligned with the slot the surface came out of; restating the axis
    by hand lets the two drift apart, which mirrored parts do silently.
    """
    matrix = obj.matrix_world
    on_plane = [
        matrix @ vertex.co for vertex in obj.data.vertices
        if abs(((matrix @ vertex.co) - plane_point).dot(plane_normal)) < tolerance
    ]
    if len(on_plane) < 3:
        raise RuntimeError(f"{obj.name}: found no cut face to hinge on")

    centroid = Vector((0.0, 0.0, 0.0))
    for point in on_plane:
        centroid += point
    centroid /= len(on_plane)

    # Build any orthonormal basis inside the plane, then rotate it onto the
    # principal axis of the cut face.
    seed = Vector((1.0, 0.0, 0.0))
    if abs(seed.dot(plane_normal)) > 0.9:
        seed = Vector((0.0, 0.0, 1.0))
    u = (seed - plane_normal * seed.dot(plane_normal)).normalized()
    v = plane_normal.cross(u).normalized()

    suu = svv = suv = 0.0
    for point in on_plane:
        offset = point - centroid
        a, b = offset.dot(u), offset.dot(v)
        suu += a * a
        svv += b * b
        suv += a * b
    from math import atan2, cos, sin
    angle = 0.5 * atan2(2.0 * suv, suu - svv)
    axis = (u * cos(angle) + v * sin(angle)).normalized()
    return centroid, axis


def place_on_hinge(obj, hinge_point, hinge_axis):
    """Move the object's origin onto its hinge and point local X along the axis,
    so deflection is a single rotation about local X. Both arguments are already
    in Blender space."""
    x_axis = hinge_axis.normalized()
    reference = Vector((0.0, 0.0, 1.0))
    if abs(x_axis.dot(reference)) > 0.9:
        reference = Vector((0.0, 1.0, 0.0))
    y_axis = reference.cross(x_axis).normalized()
    z_axis = x_axis.cross(y_axis).normalized()

    basis = Matrix((x_axis, y_axis, z_axis)).transposed().to_4x4()
    basis.translation = hinge_point.copy()

    bpy.context.view_layer.update()
    obj.data.transform(basis.inverted() @ obj.matrix_world)
    obj.matrix_world = basis
    bpy.context.view_layer.update()


def carve(parent, name, cutter_fn):
    """Split one surface out of `parent` and return it, hinged and parented."""
    surface = parent.copy()
    surface.data = parent.data.copy()
    surface.name = name
    surface.data.name = name
    bpy.context.scene.collection.objects.link(surface)

    # Object world matrices are evaluated lazily. Without this the copy still
    # reports the matrix it had before being linked, and place_on_hinge() then
    # bakes that stale transform into the mesh.
    bpy.context.view_layer.update()
    parent_world = parent.matrix_world.copy()

    # The copy inherits the parent's own parent, so assigning matrix_world below
    # would be resolved against that grandparent and leave the origin somewhere
    # else entirely. Detach first, keeping the world transform, and re-parent
    # once the hinge is placed.
    world_before = surface.matrix_world.copy()
    surface.parent = None
    surface.matrix_world = world_before
    bpy.context.view_layer.update()

    tight = cutter_fn(f"{name}_tight", 0.0)
    loose = cutter_fn(f"{name}_loose", GAP)
    match_materials(tight, parent)
    match_materials(loose, parent)

    # Face 0 of every cutter prism is its hinge plane, by construction.
    hinge_face = tight.data.polygons[0]
    plane_point = hinge_face.center.copy()
    plane_normal = hinge_face.normal.normalized()

    apply_boolean(surface, tight, "INTERSECT")
    apply_boolean(parent, loose, "DIFFERENCE")

    for cutter in (tight, loose):
        bpy.data.objects.remove(cutter, do_unlink=True)

    if not surface.data.polygons:
        raise RuntimeError(f"{name}: intersection produced no geometry")

    hinge_point, hinge_axis = hinge_from_cut(surface, plane_point, plane_normal)
    place_on_hinge(surface, hinge_point, hinge_axis)
    surface.parent = parent
    surface.matrix_parent_inverse = parent_world.inverted()
    bpy.context.view_layer.update()
    return surface


def godot_hinge(obj):
    """Return the object's hinge point and local X axis in Godot coordinates."""
    matrix = obj.matrix_world
    t = matrix.translation
    a = matrix.to_3x3() @ Vector((1.0, 0.0, 0.0))
    return Vector((t.x, t.z, -t.y)), Vector((a.x, a.z, -a.y))


def check_mirror(left, right, tolerance=1e-4):
    """A mirrored surface must get a mirrored hinge.

    The original hand-written axes passed this pair the same Z slope instead of
    opposite ones, so the right aileron and both rudders hinged out of their own
    slots. Deriving the hinge from the cut fixed that; this keeps it fixed.
    """
    left_point, left_axis = godot_hinge(left)
    right_point, right_axis = godot_hinge(right)

    expected_point = Vector((-left_point.x, left_point.y, left_point.z))
    if (right_point - expected_point).length > tolerance:
        raise RuntimeError(
            f"{right.name}: hinge point {tuple(round(v, 4) for v in right_point)} "
            f"is not the mirror of {left.name} {tuple(round(v, 4) for v in left_point)}"
        )

    expected_axis = Vector((-left_axis.x, left_axis.y, left_axis.z))
    # An axis and its negation describe the same hinge line.
    if min((right_axis - expected_axis).length,
           (right_axis + expected_axis).length) > tolerance:
        raise RuntimeError(
            f"{right.name}: hinge axis {tuple(round(v, 4) for v in right_axis)} "
            f"is not the mirror of {left.name} {tuple(round(v, 4) for v in left_axis)}"
        )


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))

    body = bpy.data.objects["body"]
    built = []

    for side, label in ((1, "left"), (-1, "right")):
        wing = bpy.data.objects[f"outer wing {label}"]
        built.append(carve(
            wing,
            f"aileron {label}",
            lambda name, margin, s=side: aileron_cutter(name, s, margin),
        ))

    built.append(carve(body, "elevator", elevator_cutter))

    for side, label in ((1, "left"), (-1, "right")):
        built.append(carve(
            body,
            f"rudder {label}",
            lambda name, margin, s=side: rudder_cutter(name, s, margin),
        ))

    by_name = {surface.name: surface for surface in built}
    check_mirror(by_name["aileron left"], by_name["aileron right"])
    check_mirror(by_name["rudder left"], by_name["rudder right"])

    for surface in built:
        point, axis = godot_hinge(surface)
        print(f"  {surface.name:<16} verts={len(surface.data.vertices):>4} "
              f"faces={len(surface.data.polygons):>4}\n"
              f"{'':<18} hinge(godot) point={tuple(round(v, 3) for v in point)} "
              f"axis={tuple(round(v, 4) for v in axis)}")
    print("  mirror symmetry: ok")

    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        export_apply=False,
        export_yup=True,
    )
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    if "--build" in sys.argv:
        build()
    else:
        print(__doc__)
