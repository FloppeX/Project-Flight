"""Author Aircraft 6 breakaway geometry from its untouched original GLB.

Run with Blender 4.5 in background mode. Coordinates printed below use Godot's
Y-up frame, not Blender's Z-up frame.
"""
import json
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Models/Aircraft_6/aircraft_6.glb"
OUTPUT = ROOT / "Models/Aircraft_6/aircraft_6_breakaway.glb"


def blender_position(point):
    return Vector((point[0], -point[2], point[1]))


def make_cutter(name, axis, sign, profile, cross_extent):
    """Closed prism: a serrated boundary in Godot X/Z (or Y/Z) space."""
    polygon = [(sign * distance, z) for z, distance in profile]
    polygon += [(sign * 20, profile[-1][0]), (sign * 20, profile[0][0])]
    vertices = []
    for cross in (-cross_extent, cross_extent):
        for distance, z in polygon:
            vertices.append(blender_position((distance, cross, z) if axis == 'X' else (cross, distance, z)))
    n = len(polygon)
    faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def boolean(obj, cutter, operation):
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new('Author fracture', 'BOOLEAN')
    modifier.operation = operation
    modifier.solver = 'EXACT'
    modifier.use_self = True
    modifier.use_hole_tolerant = True
    modifier.object = cutter
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def surface_geometry(objects, exterior_only=False):
    vertices, triangles = [], []
    for obj in objects:
        offset = len(vertices)
        vertices.extend(obj.matrix_world @ v.co for v in obj.data.vertices)
        obj.data.calc_loop_triangles()
        for tri in obj.data.loop_triangles:
            mat = obj.data.materials[tri.material_index]
            if exterior_only and mat is not None and mat.name == 'FractureInterior':
                continue
            triangles.append(tuple(offset + i for i in tri.vertices))
    return vertices, triangles


def validate(original, pieces, label='AIRCRAFT6', allow_overlap_cleanup=False,
             allow_closed_shell_junctions=False, allow_authored_control_openings=False):
    vertices, triangles = surface_geometry(pieces, exterior_only=True)
    old_vertices, old_triangles = original
    def area(vs, ts):
        return sum((vs[b] - vs[a]).cross(vs[c] - vs[a]).length * 0.5 for a, b, c in ts)
    area_error = abs(area(vertices, triangles) - area(old_vertices, old_triangles))
    max_error = 0.0
    worst_sample = None
    # Bidirectional surface coverage: cuts must not delete skin or add protrusions.
    for source_v, source_t, dest_v, dest_t in [(old_vertices, old_triangles, vertices, triangles),
                                              (vertices, triangles, old_vertices, old_triangles)]:
        tree = BVHTree.FromPolygons(dest_v, dest_t, all_triangles=True)
        for tri in source_t:
            samples = [source_v[i] for i in tri]
            samples.append(sum(samples, Vector()) / 3.0)
            for sample in samples:
                result = tree.find_nearest(sample)
                if result[3] > max_error:
                    max_error = result[3]
                    worst_sample = (godot_position(sample), godot_position(result[0]), source_v is old_vertices)
    print(label + '_SURFACE_CHECK', 'area_error', area_error, 'max_error', max_error)
    if max_error > 0.005:
        print(label + '_WORST_SAMPLE', worst_sample)
    # Exact booleans retriangulate near-coplanar low-poly faces. Bound that
    # numerical change to 5 mm and 0.1% area on this 12-metre-span asset.
    area_matches = area_error / area(old_vertices, old_triangles) < 0.001
    # Some source airframes contain overlapping duplicate skin faces. Booleans
    # can remove that redundant area without removing surface coverage. Permit
    # only area REDUCTION, and demand a tighter 0.5-mm bidirectional check there.
    overlap_cleanup = (allow_overlap_cleanup and max_error < 0.0005
                       and area(vertices, triangles) <= area(old_vertices, old_triangles))
    # A model with separately authored control surfaces has deliberate open
    # hinge boundaries. Exact booleans can retriangulate a narrow strip beside
    # those openings, so retain a bounded Aircraft-5-specific escape hatch
    # instead of weakening the default validation used by every other model.
    control_openings_match = (allow_authored_control_openings
                              and area_error < 0.40 and max_error < 0.08)
    assert area_matches or overlap_cleanup or control_openings_match, ('exterior area changed', area_error)
    assert max_error < (0.08 if allow_authored_control_openings else 0.005), ('exterior surface changed', max_error)
    cap_areas = []
    for obj in pieces:
        obj.data.calc_loop_triangles()
        cap_area = sum(t.area for t in obj.data.loop_triangles
                       if obj.data.materials[t.material_index] is not None and obj.data.materials[t.material_index].name == 'FractureInterior')
        cap_areas.append(cap_area)
        assert cap_area > 0.001, obj.name + ' lacks fracture cap'
        if obj != pieces[0]:
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            assert all(e.is_manifold or allow_authored_control_openings
                       or (allow_closed_shell_junctions and len(e.link_faces) >= 2
                           and len(e.link_faces) % 2 == 0) for e in bm.edges), obj.name + ' is not closed'
            bm.free()
    # On a T-tail, a horizontal root cap can itself belong to the detachable
    # upper fin. Pair cap surfaces across ALL pieces, not just against the body.
    cap_geometry = []
    for obj in pieces:
        vs = [obj.matrix_world @ v.co for v in obj.data.vertices]
        ts = [tuple(t.vertices) for t in obj.data.loop_triangles
              if obj.data.materials[t.material_index] is not None and obj.data.materials[t.material_index].name == 'FractureInterior']
        cap_geometry.append((vs, ts, BVHTree.FromPolygons(vs, ts, all_triangles=True)))
    for index, (vs, ts, _) in enumerate(cap_geometry):
        for a, b, c in ts:
            center = (vs[a] + vs[b] + vs[c]) / 3
            nearest = min(other[2].find_nearest(center)[3] for j, other in enumerate(cap_geometry) if j != index)
            assert nearest < 0.001, ('fracture cap lacks matching surface', pieces[index].name, nearest)
    print(label + '_GEOMETRY_OK max_surface_error_m=%.9f exterior_area_error_m2=%.9f cap_area_m2=%.4f' %
          (max_error, area_error, sum(cap_areas) * 0.5))


def restore_skin_normals(pieces, reference):
    """Retain the authored faceted shading instead of smoothing welded seams."""
    vertices, triangles, normals = reference
    tree = BVHTree.FromPolygons(vertices, triangles, all_triangles=True)
    for obj in pieces:
        loop_normals = [Vector()] * len(obj.data.loops)
        for face in obj.data.polygons:
            face.use_smooth = True
            if obj.data.materials[face.material_index] is not None and obj.data.materials[face.material_index].name == 'FractureInterior':
                for loop_index in face.loop_indices:
                    loop_normals[loop_index] = face.normal.copy()
                continue
            _, _, source_index, _ = tree.find_nearest(face.center)
            a, b, c = [vertices[i] for i in triangles[source_index]]
            na, nb, nc = normals[source_index]
            for loop_index in face.loop_indices:
                point = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
                loop_normals[loop_index] = barycentric_transform(point, a, b, c, na, nb, nc).normalized()
        obj.data.normals_split_custom_set(loop_normals)


def build():
    main = max((obj for obj in bpy.context.scene.objects if obj.type == 'MESH'), key=lambda obj: len(obj.data.vertices))
    main.name = 'Airframe'
    original = surface_geometry([main])
    normal_matrix = main.matrix_world.to_3x3().inverted().transposed()
    original_normals = [tuple((normal_matrix @ main.data.corner_normals[i].vector).normalized() for i in tri.loops)
                        for tri in main.data.loop_triangles]
    pieces = [main]
    bpy.ops.object.select_all(action='DESELECT')
    main.select_set(True)
    bpy.context.view_layer.objects.active = main
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # glTF stores material/normal seams as duplicate vertices. Weld only coincident
    # vertices; UVs remain per-loop and the original source file is never rewritten.
    bm = bmesh.new()
    bm.from_mesh(main.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method='FIXED', ngon_method='EAR_CLIP')
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
    bm.to_mesh(main.data)
    bm.free()
    fracture = bpy.data.materials.new('FractureInterior')
    fracture.diffuse_color = (0.19, 0.21, 0.23, 1.0)
    fracture.use_nodes = True
    bsdf = fracture.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = fracture.diffuse_color
    bsdf.inputs['Metallic'].default_value = 0.55
    bsdf.inputs['Roughness'].default_value = 0.8
    main.data.materials.append(fracture)
    # Cuts stay outboard of the pylons; matching serrations and closed end caps
    # are baked into both halves, with no runtime slicing or intact-state gap.
    wing = [(-3, 3.7), (-0.9, 3.7), (-0.65, 3.84), (-0.43, 3.61),
            (-0.19, 3.83), (0.02, 3.62), (0.23, 3.79), (0.46, 3.65), (1, 3.72), (3, 3.72)]
    tail = [(-8, 0.95), (-6.6, 0.95), (-6.25, 1.08), (-5.95, 0.87),
            (-5.65, 1.06), (-5.38, 0.88), (-5.1, 1.05), (-4.8, 0.93), (-4.2, 0.98)]
    fin = [(-8, 0.48), (-6.55, 0.48), (-6.32, 0.59), (-6.08, 0.41),
           (-5.84, 0.58), (-5.6, 0.43), (-5.35, 0.56), (-5.05, 0.48), (-4.2, 0.48)]
    for name, axis, sign, profile, cross in [
        ('OuterWingLeft', 'X', 1, wing, 5),
        ('OuterWingRight', 'X', -1, wing, 5),
        ('HorizontalTipLeft', 'X', 1, tail, 5),
        ('HorizontalTipRight', 'X', -1, tail, 5),
        ('VerticalTip', 'Y', 1, fin, 4),
    ]:
        cutter = make_cutter('FractureTool', axis, sign, profile, cross)
        # Boolean-generated polygons inherit this final material slot.
        for material in main.data.materials:
            cutter.data.materials.append(material)
        for face in cutter.data.polygons:
            face.material_index = len(main.data.materials) - 1
        piece = main.copy()
        piece.data = main.data.copy()
        piece.name = name
        bpy.context.collection.objects.link(piece)
        boolean(piece, cutter, 'INTERSECT')
        boolean(main, cutter, 'DIFFERENCE')
        bpy.data.objects.remove(cutter, do_unlink=True)
        assert len(piece.data.polygons) > 0, name + ' is empty'
        print('AIRCRAFT6_CUT', name, 'faces', len(piece.data.polygons), 'cap_faces',
              sum(piece.data.materials[p.material_index] == fracture for p in piece.data.polygons))
        pieces.append(piece)
    validate(original, pieces)
    restore_skin_normals(pieces, (*original, original_normals))
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format='GLB', use_selection=True,
                             export_cameras=False, export_lights=False)
    print('AIRCRAFT6_BUILT', OUTPUT)


def godot_position(point):
    return (point.x, point.z, -point.y)


def inspect():
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH':
            continue
        points = [godot_position(obj.matrix_world @ v.co) for v in obj.data.vertices]
        print("AIRCRAFT6_SOURCE " + json.dumps({
            "name": obj.name, "vertices": len(points), "faces": len(obj.data.polygons),
            "min": [min(p[i] for p in points) for i in range(3)],
            "max": [max(p[i] for p in points) for i in range(3)],
            "materials": [m.name if m else None for m in obj.data.materials],
        }))
        if len(points) > 1000:
            for label, selected in [
                ("tail", [p for p in points if p[2] < -4.3]),
                ("wing", [p for p in points if abs(p[0]) > 3.0]),
                ("fin", [p for p in points if p[2] < -4.3 and p[1] > 0.7]),
            ]:
                print("AIRCRAFT6_REGION", label, "min", [min(p[i] for p in selected) for i in range(3)],
                      "max", [max(p[i] for p in selected) for i in range(3)])
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
            print("AIRCRAFT6_TOPOLOGY", "vertices", len(bm.verts), "boundary_edges",
                  sum(e.is_boundary for e in bm.edges), "nonmanifold", sum(not e.is_manifold for e in bm.edges))
            bm.free()


if __name__ == '__main__':
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    if '--build' in sys.argv:
        build()
    inspect()
