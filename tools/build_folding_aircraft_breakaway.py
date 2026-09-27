"""Bake matching jagged wing/tail fractures for aircraft 1, 2 and 5.

Blender 4.5, --background --factory-startup --python-exit-code 1 --python this.py
Pass -- --build to export derivatives; originals remain untouched.
"""
import sys
import argparse
import json
from pathlib import Path
import bpy
import bmesh
from mathutils import Matrix
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_aircraft6_breakaway import godot_position, make_cutter, boolean, surface_geometry, validate, restore_skin_normals

SOURCES = {
    1: 'Models/Aircraft_1/aircraft 1.glb',
    2: 'Models/Aircraft_2/aircraft 2 body.glb',
    5: 'Models/Aircraft_5/aircraft_5.glb',
}


def profile(base, start, end, amplitude=0.09):
    # Uneven teeth, expressed in Godot coordinates, in metres.
    teeth = [(0, 0), (0.17, 0.25), (0.30, -0.9), (0.39, 0.7),
             (0.53, -0.55), (0.66, 1.0), (0.76, -0.8), (0.89, 0.45), (1, 0)]
    return [(start + (end - start) * t, base + amplitude * offset) for t, offset in teeth]


def fracture_material():
    mat = bpy.data.materials.get('FractureInterior') or bpy.data.materials.new('FractureInterior')
    mat.diffuse_color = (0.19, 0.21, 0.23, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = mat.diffuse_color
    bsdf.inputs['Metallic'].default_value = 0.55
    bsdf.inputs['Roughness'].default_value = 0.8
    return mat


def thicken_edge_sliver(obj, points, normal, material_index):
    """Preserve an authored zero-thickness tip sliver as a closed 0.4-mm wedge."""
    n = len(points)
    center = sum(points, Vector()) / n
    points = [center + (p - center) * 1.003 for p in points]
    verts = [p + normal * side * 0.0002 for side in (-1, 1) for p in points]
    faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    mesh = bpy.data.meshes.new('TipSliver')
    mesh.from_pydata(verts, [], faces)
    for mat in obj.data.materials:
        mesh.materials.append(mat)
    for face in mesh.polygons:
        face.material_index = material_index
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    wedge = bpy.data.objects.new('TipSliver', mesh)
    bpy.context.collection.objects.link(wedge)
    boolean(obj, wedge, 'UNION')
    bpy.data.objects.remove(wedge, do_unlink=True)


def cut_object(obj, specs, number):
    original_world = obj.matrix_world.copy()
    original = surface_geometry([obj])
    normal_matrix = original_world.to_3x3().inverted().transposed()
    normals = [tuple((normal_matrix @ obj.data.corner_normals[i].vector).normalized() for i in tri.loops)
               for tri in obj.data.loop_triangles]
    if (number == 1 and obj.name == 'fuselage') or (number == 5 and obj.name == 'body'):
        # Exclude the known interior fin/crossbar center sheet from the EXTERIOR
        # audit. It is not an outside skin surface.
        vertices, triangles = original
        keep = [i for i, tri in enumerate(triangles) if not all(
            abs(vertices[j].x) < 0.000001 and godot_position(vertices[j])[2] < (-2.7 if number == 1 else -3.8)
            and (number == 1 or godot_position(vertices[j])[1] > 1.2) for j in tri)]
        original = (vertices, [triangles[i] for i in keep])
        normals = [normals[i] for i in keep]
    obj.data.transform(original_world)
    obj.matrix_world = Matrix.Identity(4)
    preserved_hinge = None
    if number in (2, 5) and 'wing' in obj.name:
        # The unpainted hinge mechanism is separate overlapping geometry inside
        # this mesh. Preserve it verbatim rather than Boolean-unioning it away.
        preserved_hinge = obj.data.copy()
        bm = bmesh.new()
        bm.from_mesh(preserved_hinge)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if obj.data.materials[f.material_index] is not None], context='FACES')
        assert all(abs(v.co.x) < (4.35 if number == 2 else 3.6) for v in bm.verts), 'hinge intrudes into fracture'
        bm.to_mesh(preserved_hinge)
        bm.free()
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if obj.data.materials[f.material_index] is None], context='FACES')
        bm.to_mesh(obj.data)
        bm.free()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
    bm.to_mesh(obj.data)
    bm.free()
    mat = fracture_material()
    obj.data.materials.append(mat)
    pieces = [obj]
    for name, cutter in specs:
        for material in obj.data.materials:
            cutter.data.materials.append(material)
        for face in cutter.data.polygons:
            face.material_index = len(obj.data.materials) - 1
        piece = obj.copy()
        piece.data = obj.data.copy()
        piece.parent = None
        piece.matrix_world = Matrix.Identity(4)
        piece.name = name
        bpy.context.collection.objects.link(piece)
        boolean(piece, cutter, 'INTERSECT')
        boolean(obj, cutter, 'DIFFERENCE')
        bpy.data.objects.remove(cutter, do_unlink=True)
        assert len(piece.data.polygons) > 0, name + ' is empty'
        bm = bmesh.new()
        bm.from_mesh(piece.data)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
        bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=0.000001)
        # The Aircraft 1 source contains redundant flaps attached along a
        # three-face edge, including interior faces on the fin's center plane.
        # Surface validation below prevents this cleanup deleting real skin.
        slivers = []
        for _ in range(3):
            redundant = [f for f in bm.faces if
                         (sum(e.is_boundary for e in f.edges) >= 2 and any(len(e.link_faces) > 2 for e in f.edges))
                         or (name in ('VerticalTip', 'HorizontalBridge') and number in (1, 5)
                             and all(abs(v.co.x) < 0.000001 for v in f.verts))]
            if not redundant:
                break
            if number == 1 and name.startswith('HorizontalTip'):
                slivers.extend(([v.co.copy() for v in f.verts], f.normal.copy(), f.material_index) for f in redundant)
            bmesh.ops.delete(bm, geom=redundant, context='FACES')
        print('PIECE_TOPOLOGY', name, 'boundary', sum(e.is_boundary for e in bm.edges),
              'nonmanifold', sum(not e.is_manifold for e in bm.edges),
              'bad_edges', [(tuple(round(x, 4) for x in godot_position(e.verts[0].co)), len(e.link_faces))
                            for e in bm.edges if not e.is_manifold][:12])
        bm.to_mesh(piece.data)
        bm.free()
        for points, normal, material_index in slivers:
            thicken_edge_sliver(piece, points, normal, material_index)
        pieces.append(piece)
    if number == 5 and obj.name == 'body':
        # The bridge meets the newly open elevator hinge. Blender's exact
        # Boolean keeps the correct matching side polygons there but can retain
        # the cutter's former Glass slot instead of the fracture slot.
        for candidate in pieces:
            fracture_index = candidate.data.materials.find(mat.name)
            for face in candidate.data.polygons:
                source_material = candidate.data.materials[face.material_index]
                if (source_material is not None and source_material.name.startswith('Glass')
                        and abs(face.center.x) > 1.5 and face.center.y > 3.8
                        and face.center.z > 1.2):
                    face.material_index = fracture_index
    if number == 1 and obj.name == 'fuselage':
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        interior = [f for f in bm.faces if all(abs(v.co.x) < 0.000001 and godot_position(v.co)[2] < -2.7 for v in f.verts)]
        bmesh.ops.delete(bm, geom=interior, context='FACES')
        bm.to_mesh(obj.data)
        bm.free()
    if preserved_hinge is not None:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.from_mesh(preserved_hinge)
        bm.to_mesh(obj.data)
        bm.free()
        bpy.data.meshes.remove(preserved_hinge)
    validate(original, pieces, 'AIRCRAFT%d_%s' % (number, obj.name), allow_overlap_cleanup=True,
             allow_closed_shell_junctions=(number == 2 and obj.name in ('main fuselage', 'main fuselage.001')) or (number == 5 and obj.name == 'body') or (number == 3 and obj.name == 'tail.002'),
             allow_authored_control_openings=(number == 5 and obj.name == 'body'))
    restore_skin_normals(pieces, (*original, normals))
    # Restore original origins and hierarchy. The new wing tips are children of
    # the existing moving panel, so fold pivots/controllers need no replacement.
    for piece in pieces:
        piece.data.transform(original_world.inverted())
    obj.matrix_world = original_world
    for piece in pieces[1:]:
        piece.parent = obj
        piece.matrix_parent_inverse = Matrix.Identity(4)
        piece.matrix_basis = Matrix.Identity(4)


def rig_aircraft_controls(number):
    """Keep authored vertices, but give separate controls leading-edge hinges."""
    parents = {'left aileron': 'left outer wing', 'right aileron': 'right outer wing',
               'elevator': 'main fuselage', 'rudder': 'main fuselage'}
    if number == 1:
        parents = {'aileron left': 'wing outer left', 'aileron right': 'wing outer right',
                   'elevator': 'fuselage', 'rudder': 'fuselage'}
    elif number == 3:
        parents = {'aileron left': 'wing left', 'aileron right': 'wing right',
                   'elevator': 'tail.002', 'rudder': 'tail.002'}
    bpy.context.view_layer.update()
    for name, parent_name in parents.items():
        obj = bpy.data.objects.get(name)
        if obj is None:
            continue  # Older source exports do not have separate controls.
        world = obj.matrix_world.copy()
        points = [world @ v.co for v in obj.data.vertices]
        span = 2 if name == 'rudder' else 0
        ends = []
        for limit in (min(p[span] for p in points), max(p[span] for p in points)):
            row = [p for p in points if abs(p[span] - limit) < 0.0001]
            forward = min(p.y for p in row)  # Blender -Y is aircraft forward.
            edge = [p for p in row if abs(p.y - forward) < 0.0001]
            ends.append(sum(edge, Vector()) / len(edge))
        axis = (ends[1] - ends[0]).normalized()
        reference = Vector((0, 0, 1)) if name == 'rudder' else Vector((1, 0, 0))
        hinge = reference.rotation_difference(axis).to_matrix().to_4x4()
        hinge.translation = (ends[0] + ends[1]) * 0.5
        obj.data.transform(hinge.inverted() @ world)
        obj.parent = bpy.data.objects[parent_name]
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_basis = obj.parent.matrix_world.inverted() @ hinge
    bpy.context.view_layer.update()


def build(number, output=None):
    if number == 1:
        # The authored elevator was separated without closing its fixed-tail
        # hinge opening. Close only that rim in the generated derivative so
        # the tail fractures remain solid; leave the source GLB untouched.
        body = bpy.data.objects['fuselage']
        bm = bmesh.new()
        bm.from_mesh(body.data)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
        rim = [e for e in bm.edges if e.is_boundary and all(
            (body.matrix_world @ v.co).y > 4.96 and
            (body.matrix_world @ v.co).z > 0.77 for v in e.verts)]
        filled = bmesh.ops.holes_fill(bm, edges=rim, sides=0)['faces']
        bmesh.ops.triangulate(bm, faces=filled)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(body.data)
        bm.free()
    wing_names = {1: ('wing outer left', 'wing outer right'),
                  2: ('left outer wing', 'right outer wing'),
                  5: ('outer wing left', 'outer wing right')}[number]
    # Keep the insignias entirely outboard and the new fractures clear of hinges.
    wing_cut = {1: 4.22, 2: 4.45, 5: 3.8}[number]
    z_bounds = (-2.1, 0.6) if number == 2 else (-1.3, 0.9)
    for sign, name in zip((1, -1), wing_names):
        cutter = make_cutter('FractureTool', 'X', sign, profile(wing_cut, *z_bounds, 0.07 if number == 2 else 0.11), 5)
        cut_object(bpy.data.objects[name], [('OuterWingLeft' if sign == 1 else 'OuterWingRight', cutter)], number)
    body_name = {1: 'fuselage', 2: 'main fuselage.001', 5: 'body'}[number]
    if number == 2 and 'main fuselage' in bpy.data.objects:
        body_name = 'main fuselage'
    body = bpy.data.objects[body_name]
    if number in (1, 2):
        distance = 0.73 if number == 1 else 1.1
        z_bounds = (-5.8, -3.9) if number == 1 else (-6.0, -3.8)
        specs = [(name, make_cutter('FractureTool', 'X', sign, profile(distance, *z_bounds, 0.08), 5))
                 for sign, name in [(1, 'HorizontalTipLeft'), (-1, 'HorizontalTipRight')]]
        height = 0.12 if number == 1 else 1.65
        specs.append(('VerticalTip', make_cutter('FractureTool', 'Y', 1, profile(height, -6, -2.8, 0.10), 5)))
    else:
        # H-tail: the horizontal surface is a bridge between the two fins.
        # Keep the junctions on the fins, detach the central bridge as one piece.
        bridge = make_cutter('FractureTool', 'X', 1, profile(-1.75, -5.6, -3.8, 0.08), 0.65)
        bridge.location.z = 1.85  # Blender Z = Godot Y; exclude the lower booms.
        bound = make_cutter('FractureBound', 'X', -1, profile(-1.75, -5.6, -3.8, 0.08), 5)
        boolean(bridge, bound, 'INTERSECT')
        bpy.data.objects.remove(bound, do_unlink=True)
        specs = [('HorizontalBridge', bridge)]
        for sign, name in [(1, 'VerticalTipLeft'), (-1, 'VerticalTipRight')]:
            cutter = make_cutter('FractureTool', 'Y', 1, profile(0.65, -5.8, -2.9, 0.12), 5)
            bound = make_cutter('FractureBound', 'X', sign, [(-6, 0), (-2.8, 0)], 5)
            boolean(cutter, bound, 'INTERSECT')
            bpy.data.objects.remove(bound, do_unlink=True)
            specs.append((name, cutter))
    cut_object(body, specs, number)
    if number == 2:
        body.name = 'main fuselage'  # Match the existing canopy/shadow scene path.
    if number in (1, 2):
        rig_aircraft_controls(number)
    if number == 1:
        # Aircraft 1's source carries blended corner normals on the fuselage.
        # Shade every exported mesh face flat, including the newly cut pieces,
        # without changing the authored source or the breakaway hierarchy.
        for mesh_obj in bpy.data.objects:
            if mesh_obj.type == 'MESH':
                custom_normals = mesh_obj.data.attributes.get('custom_normal')
                if custom_normals is not None:
                    mesh_obj.data.attributes.remove(custom_normals)
                for face in mesh_obj.data.polygons:
                    face.use_smooth = False
                mesh_obj.data.update()
    output = output or ROOT / ('Models/Aircraft_%d/aircraft_%d_breakaway.glb' % (number, number))
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(output), export_format='GLB', use_selection=True,
                             export_cameras=False, export_lights=False)
    print('FOLDING_AIRCRAFT_BUILT', number, output)


def inspect(number):
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH':
            continue
        points = [godot_position(obj.matrix_world @ v.co) for v in obj.data.vertices]
        print('BREAKAWAY_SOURCE ' + json.dumps({
            'aircraft': number, 'name': obj.name,
            'parent': obj.parent.name if obj.parent else None,
            'vertices': len(points), 'faces': len(obj.data.polygons),
            'min': [round(min(p[i] for p in points), 4) for i in range(3)],
            'max': [round(max(p[i] for p in points), 4) for i in range(3)],
            'origin': list(godot_position(obj.matrix_world.translation)),
        }))
        if obj.name in ('fuselage', 'main fuselage.001', 'body'):
            for label, selected in [
                ('tail', [p for p in points if p[2] < -2.7]),
                ('tail outer', [p for p in points if p[2] < -2.7 and abs(p[0]) > 0.9]),
                ('tail high', [p for p in points if p[2] < -2.7 and p[1] > 0.4]),
            ]:
                print('TAIL_REGION', number, label,
                      [round(min(p[i] for p in selected), 4) for i in range(3)],
                      [round(max(p[i] for p in selected), 4) for i in range(3)])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--aircraft', type=int, choices=list(SOURCES), help='Rebuild only this aircraft')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    for number, path in SOURCES.items():
        if args.aircraft is not None and number != args.aircraft:
            continue
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.object.delete(use_global=False)
        bpy.ops.outliner.orphans_purge(do_recursive=True)
        bpy.ops.import_scene.gltf(filepath=str(ROOT / path))
        inspect(number)
        if args.build:
            build(number)
