"""Build jagged one-third blade stubs and loose fragments, preserving the source propeller.
Run with Blender --background --factory-startup --python-exit-code 1 --python this_file.
"""
import math
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Models/Aircraft_1'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(OUT / 'aircraft 2 propeller.glb'))
source = bpy.data.objects['Propeller blades']
mesh = source.data.copy()
mesh.transform(source.matrix_world)
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
remaining = set(bm.verts)
islands = []
while remaining:
    stack = [remaining.pop()]
    island = set(stack)
    while stack:
        for edge in stack.pop().link_edges:
            for vertex in edge.verts:
                if vertex in remaining:
                    remaining.remove(vertex)
                    island.add(vertex)
                    stack.append(vertex)
    islands.append(island)
islands.sort(key=lambda vs: math.atan2(sum(v.co.z for v in vs), sum(v.co.x for v in vs)))
print('PROPELLER_COMPONENTS', [len(vs) for vs in islands], flush=True)
for vs in islands:
    print('BLADE_ISLAND', tuple(sum((v.co for v in vs), Vector()) / len(vs)),
          'radius', max(math.hypot(v.co.x,v.co.z) for v in vs), flush=True)
root_islands = [vs for vs in islands if max(math.hypot(v.co.x,v.co.z) for v in vs) < 0.2]
islands = [vs for vs in islands if vs not in root_islands]
assert len(islands) == 5, 'Expected the five authored radial blades'
fracture = bpy.data.materials.new('PropellerFractureInterior')
fracture.diffuse_color = (0.38, 0.32, 0.24, 1)
fracture.use_nodes = True
bsdf = fracture.node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Base Color'].default_value = fracture.diffuse_color
bsdf.inputs['Metallic'].default_value = 0.4
bsdf.inputs['Roughness'].default_value = 0.85

def cut(original, direction, distance, keep_root, seed):
    part = original.copy()
    plane = direction * distance
    bmesh.ops.bisect_plane(part, geom=list(part.verts) + list(part.edges) + list(part.faces),
        dist=0.000001, plane_co=plane, plane_no=direction,
        clear_outer=keep_root, clear_inner=not keep_root)
    boundary = [e for e in part.edges if e.is_boundary and
                all(abs((v.co-plane).dot(direction)) < 0.0001 for v in e.verts)]
    assert boundary
    bmesh.ops.subdivide_edges(part, edges=boundary, cuts=3, use_grid_fill=False)
    cut_vertices = [v for v in part.verts if abs((v.co-plane).dot(direction)) < 0.0001]
    tangent = Vector((-direction.z, 0, direction.x))
    for vertex in cut_vertices:
        # Same profile on both halves, with different tears on each blade and
        # across its width/depth. No smooth, straight guillotine edge.
        t = vertex.co.dot(tangent)
        vertex.co += direction * (0.045 * math.sin(t*57 + seed*1.7) +
                                  0.024 * math.sin(vertex.co.y*103 + t*31 + seed))
    boundary = [e for e in part.edges if e.is_boundary]
    caps = bmesh.ops.holes_fill(part, edges=boundary, sides=0)['faces']
    assert caps, 'Missing fracture interior'
    for face in caps:
        face.material_index = len(mesh.materials)
        face.smooth = False
    # A fan gives the non-planar torn cross-section a distinct central vertex;
    # ngon ear clipping can overlap the subdivided skin along a jagged edge.
    bmesh.ops.poke(part, faces=caps, center_mode='MEAN_WEIGHTED')
    bmesh.ops.triangulate(part, faces=list(part.faces))
    part.normal_update()
    assert not any(e.is_boundary for e in part.edges), 'Open damaged blade mesh'
    return part

outputs = []
disc_radius = 0.0
disc_half_depth = 0.0
for index, island in enumerate(root_islands):
    root_part = bm.copy()
    positions = {tuple(round(c, 6) for c in v.co) for v in island}
    bmesh.ops.delete(root_part, geom=[v for v in root_part.verts if
        tuple(round(c, 6) for c in v.co) not in positions], context='VERTS')
    root_mesh = bpy.data.meshes.new('BrokenBladeRoot')
    for material in mesh.materials: root_mesh.materials.append(material)
    root_part.to_mesh(root_mesh)
    root_part.free()
    obj = bpy.data.objects.new('BrokenBladeRoot', root_mesh)
    bpy.context.collection.objects.link(obj)
    outputs.append(obj)
for index, island in enumerate(islands):
    # Extract this component while retaining UVs and material indices.
    blade = bm.copy()
    positions = {tuple(round(c, 6) for c in v.co) for v in island}
    bmesh.ops.delete(blade, geom=[v for v in blade.verts if
        tuple(round(c, 6) for c in v.co) not in positions], context='VERTS')
    centre = sum((v.co for v in blade.verts), Vector()) / len(blade.verts)
    direction = Vector((centre.x, 0, centre.z)).normalized()
    distances = [v.co.dot(direction) for v in blade.verts]
    root, tip = min(distances), max(distances)
    split = root + (tip-root) * (0.32 + index * 0.008)
    disc_radius = max(disc_radius, max(math.hypot(v.co.x, v.co.z) for v in blade.verts))
    disc_half_depth = max(disc_half_depth, max(abs(v.co.y) for v in blade.verts))
    stub = cut(blade, direction, split, True, index)
    outer = cut(blade, direction, split, False, index)
    # Two loose chunks per blade make the strike read as shattering.
    split_outer = root + (tip-root)*0.73
    middle = cut(outer, direction, split_outer, True, index+4)
    end = cut(outer, direction, split_outer, False, index+4)
    for name, part in [(f'BrokenBladeStub{index}', stub),
                       (f'BladeFragment{index}A', middle), (f'BladeFragment{index}B', end)]:
        out_mesh = bpy.data.meshes.new(name)
        for material in mesh.materials: out_mesh.materials.append(material)
        out_mesh.materials.append(fracture)
        part.to_mesh(out_mesh)
        assert not out_mesh.validate(verbose=True), name
        out_mesh.update()
        obj = bpy.data.objects.new(name, out_mesh)
        bpy.context.collection.objects.link(obj)
        outputs.append(obj)
        part.free()
    print('PROPELLER_BLADE_CUT', index, 'root',root,'tip',tip,'cut',split, flush=True)
    outer.free()
    blade.free()
bm.free()
bpy.ops.object.select_all(action='DESELECT')
for obj in outputs: obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'propeller_shattered.glb'), export_format='GLB',
                         use_selection=True, export_cameras=False, export_lights=False)
script = '# Generated by tools/build_propeller_damage.py; thin disc in the authored propeller frame.\n'
script += 'extends RefCounted\n'
script += f'const RADIUS = {disc_radius:.6f}\nconst HEIGHT = {max(disc_half_depth * 2, 0.08):.6f}\n'
(OUT/'propeller_strike_geometry.gd').write_text(script, encoding='utf-8')
print('PROPELLER_DAMAGE_BUILD_PASS stubs=5 fragments=10 closed_caps=true', flush=True)
