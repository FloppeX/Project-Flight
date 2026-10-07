"""Generate capped tail/wing derivatives from the currently referenced game assets.

Run with Blender --background --factory-startup --python-exit-code 1 --python
tools/build_aircraft_damage_meshes.py. Source assets and their hierarchies survive.
The split is performed in world Godot coordinates; transforms and child names
are retained so existing folding and control-surface bindings remain valid.
"""
import argparse
import sys
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

ROOT = Path(__file__).resolve().parents[1]
CONFIG = {
    1: ('Models/Aircraft_1/aircraft_1_breakaway.glb', 'fuselage', -2.55),
    2: ('Models/Aircraft_2/aircraft_2_breakaway.glb', 'main fuselage', -3.05),
    3: ('Models/Aircraft_3/aircraft_3_breakaway.glb', 'tail.002', -2.15),
    4: ('Models/Aircraft_4/aircraft_4.glb', 'fuselage', -2.55),
    5: ('Models/Aircraft_5/aircraft_5_control_surfaces_rigged.glb', 'body', -2.55),
    6: ('Models/Aircraft_6/aircraft_6_breakaway.glb', 'Airframe', -3.45),
    7: ('Models/Aircraft_7/aircraft_7.glb', 'fuselage', -3.15),
    8: ('Models/Aircraft_8/aircraft_8.glb', 'fuselage.001', -3.25),
    14: ('Models/Aircraft_14/aircraft_14-2.glb', 'fuselage', -0.8),
    16: ('Models/Aircraft_16/aircraft_16.blend', 'fuselage', -3.25),
}

def split_mesh(obj, godot_axis, coordinate, negative, piece_name, cap_open_cross_section=False):
    before = obj.data.copy()
    before.calc_loop_triangles()
    reference_vertices = [v.co.copy() for v in before.vertices]
    reference_triangles = [tuple(t.vertices) for t in before.loop_triangles]
    reference_normals = [tuple(before.corner_normals[i].vector.copy() for i in t.loops) for t in before.loop_triangles]
    reference_tree = BVHTree.FromPolygons(reference_vertices, reference_triangles, all_triangles=True)
    transform = obj.matrix_world.copy()
    # Godot (x,y,z) = Blender (x,z,-y).
    axis = Vector((1,0,0)) if godot_axis == 'x' else Vector((0,-1,0))
    plane_world = axis * coordinate
    plane = transform.inverted() @ plane_world
    normal = (transform.to_3x3().transposed() @ axis).normalized()
    material = bpy.data.materials.get('FractureInterior')
    if material is None:
        material = bpy.data.materials.new('FractureInterior')
        material.diffuse_color = (0.18,0.19,0.21,1)
        material.use_nodes = True
        bsdf = material.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Base Color'].default_value = material.diffuse_color
        bsdf.inputs['Metallic'].default_value = 0.45
        bsdf.inputs['Roughness'].default_value = 0.85
    pieces = []
    for keep_negative in [not negative, negative]:
        mesh = before.copy()
        mesh.materials.append(material)
        cap_index = len(mesh.materials)-1
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
            dist=0.00001, plane_co=plane, plane_no=normal,
            clear_outer=keep_negative, clear_inner=not keep_negative)
        # glTF duplicates vertices at UV/material/normal seams. Join only the
        # new cut boundary so it forms closed rings, retaining the authored
        # skin seams everywhere else. Skin corner normals are restored below.
        cut_vertices = [v for v in bm.verts if abs((v.co-plane).dot(normal)) < 0.0001]
        bmesh.ops.remove_doubles(bm, verts=cut_vertices, dist=0.0001)
        cut_edges = [e for e in bm.edges if e.is_boundary and
            all(abs((v.co-plane).dot(normal)) < 0.0001 for v in e.verts)]
        caps = bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)['faces'] if cut_edges else []
        if not caps and cap_open_cross_section:
            # Some authored open/mirrored shells have no closed cut-edge ring.
            # Add only a cross-section cap; preserve their existing skin/seams.
            from mathutils.geometry import convex_hull_2d
            cut_vertices = [v for v in bm.verts if abs((v.co-plane).dot(normal)) < 0.0001]
            u = normal.orthogonal().normalized()
            v_axis = normal.cross(u).normalized()
            hull = convex_hull_2d([Vector((v.co.dot(u),v.co.dot(v_axis))) for v in cut_vertices])
            cap = bm.faces.new([cut_vertices[i] for i in hull])
            cap.normal_update()
            if cap.normal.dot(normal) * (1 if keep_negative else -1) < 0: cap.normal_flip()
            caps = [cap]
        for face in caps:
            face.material_index = cap_index
            face.smooth = False
        assert caps and sum(face.calc_area() for face in caps) > 0.0001, (obj.name, piece_name, 'missing fracture cap')
        bmesh.ops.triangulate(bm, faces=caps)
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        # Restore the authored split normals on the retained skin. A new cap
        # uses its face normal; cutting must not smooth away existing facets.
        loop_normals = [Vector()] * len(mesh.loops)
        for face in mesh.polygons:
            face.use_smooth = True
            if face.material_index == cap_index:
                for index in face.loop_indices: loop_normals[index] = face.normal.copy()
                continue
            _, _, source_index, _ = reference_tree.find_nearest(face.center)
            a,b,c = [reference_vertices[i] for i in reference_triangles[source_index]]
            na,nb,nc = reference_normals[source_index]
            for index in face.loop_indices:
                point = mesh.vertices[mesh.loops[index].vertex_index].co
                loop_normals[index] = barycentric_transform(point,a,b,c,na,nb,nc).normalized()
        mesh.normals_split_custom_set(loop_normals)
        assert len(mesh.polygons), (obj.name, piece_name, 'empty piece')
        pieces.append(mesh)
    # External triangle area is conserved by a planar split. Ignore only the
    # new caps (existing authored fracture interiors still count as skin here).
    def area(mesh, exclude_last=False):
        mesh.calc_loop_triangles()
        return sum(((transform @ mesh.vertices[t.vertices[1]].co - transform @ mesh.vertices[t.vertices[0]].co).cross(
                    transform @ mesh.vertices[t.vertices[2]].co - transform @ mesh.vertices[t.vertices[0]].co)).length/2
                   for t in mesh.loop_triangles if not exclude_last or t.material_index != len(mesh.materials)-1)
    original_area = area(before)
    error = abs(sum(area(m, True) for m in pieces)-original_area)/max(original_area,1e-6)
    assert error < 0.001, (obj.name, 'surface area changed', error)
    obj.data = pieces[0]
    detached = bpy.data.objects.new(piece_name, pieces[1])
    bpy.context.collection.objects.link(detached)
    detached.parent = obj
    detached.matrix_world = transform
    print('DAMAGE_MESH_SPLIT', obj.name, piece_name, 'area_error', error, flush=True)
    return detached

def build(number):
    source, mesh_name, cut = CONFIG[number]
    if source.endswith('.blend'):
        bpy.ops.wm.open_mainfile(filepath=str(ROOT/source))
        if bpy.context.object is not None and bpy.context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(ROOT/source))
    obj = bpy.data.objects.get(mesh_name)
    if obj is None:
        obj = bpy.data.objects.get(mesh_name.replace('.', '_'))
    assert obj is not None, (number, mesh_name, [o.name for o in bpy.data.objects])
    # Models 4/7/8 have no separate wing mesh in their existing game asset.
    if number in [4,7,8]:
        split_mesh(obj, 'x', 3.0, False, 'WingBreakawayLeft')
        split_mesh(obj, 'x', -3.0, True, 'WingBreakawayRight')
    split_mesh(obj, 'z', cut, True, 'TailBreakaway')
    target = ROOT/f'Models/Aircraft_{number}/aircraft_{number}_damage.glb'
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB',
        use_selection=True, export_cameras=False, export_lights=False)
    print('AIRCRAFT_DAMAGE_MESH_BUILT', number, str(target), flush=True)

if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument('--aircraft', nargs='+', type=int, default=list(CONFIG))
    options = parser.parse_args(args)
    for number in options.aircraft:
        build(number)
