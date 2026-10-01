"""Generate Aircraft 3 damage pieces and control hinges; preserve source GLB."""
import sys
import argparse
from pathlib import Path
import bpy
import bmesh
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_folding_aircraft_breakaway import cut_object, profile, rig_aircraft_controls
from build_aircraft6_breakaway import make_cutter

parser = argparse.ArgumentParser()
parser.add_argument('--source-blend')
parser.add_argument('--output-blend')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
if args.source_blend:
    bpy.ops.wm.open_mainfile(filepath=args.source_blend)
    # Bake the authored mirrors once, then retain the established separate wheel
    # node names used by LandingGear and ground-contact presentation.
    for obj in list(bpy.context.scene.objects):
        bpy.context.view_layer.objects.active = obj
        for modifier in list(obj.modifiers):
            if modifier.type == 'MIRROR':
                bpy.ops.object.modifier_apply(modifier=modifier.name)
    for name, mirror_name in [('Object.003', 'MainWheelLeft'), ('Cylinder', 'MainGearSupportLeft')]:
        original = bpy.data.objects[name]
        for negative in [True, False]:
            mesh = original.data.copy()
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bmesh.ops.delete(bm, geom=[v for v in bm.verts
                if ((original.matrix_world @ v.co).x >= 0 if negative else (original.matrix_world @ v.co).x < 0)], context='VERTS')
            bm.to_mesh(mesh)
            bm.free()
            if negative:
                mirror = original.copy()
                mirror.data = mesh
                mirror.name = mirror_name
                bpy.context.collection.objects.link(mirror)
            else:
                original.data = mesh
    # Match the triangulated input used by the existing GLB fracture builder.
    # Planar-looking authored n-gons can otherwise tessellate differently after
    # a Boolean, shifting the tail skin and failing the surface audit.
    for name in ['wing left', 'wing right', 'tail.002']:
        mesh = bpy.data.objects[name].data
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()
else:
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / 'Models/Aircraft_3/Aircraft_3.glb'))
# The authored landing-gear struts span both sides, but its main wheel and
# matching support exist only on positive X. Complete that pair in the
# generated game model; never change the supplied export.
reflect_x = Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))
for name, mirror_name in [('Object.003', 'MainWheelLeft'), ('Cylinder', 'MainGearSupportLeft')]:
    if args.source_blend:
        continue
    original_gear = bpy.data.objects[name]
    mirror = original_gear.copy()
    mirror.data = original_gear.data.copy()
    bpy.context.collection.objects.link(mirror)
    mirror.name = mirror_name
    mirror.matrix_world = reflect_x @ original_gear.matrix_world
# The current export contains the left elevator only. Complete its symmetric
# partner in the derivative and retain one shared horizontal hinge controller.
elevator = bpy.data.objects['elevator']
if max((elevator.matrix_world @ v.co).x for v in elevator.data.vertices) < 0.0:
    mirrored = elevator.copy()
    mirrored.data = elevator.data.copy()
    bpy.context.collection.objects.link(mirrored)
    mirrored.scale.x *= -1.0
    bpy.ops.object.select_all(action='DESELECT')
    elevator.select_set(True)
    mirrored.select_set(True)
    bpy.context.view_layer.objects.active = elevator
    bpy.ops.object.join()
# Cap the newly separated control openings in this generated copy. Fracture
# validation below still requires closed pieces and matching cut surfaces.
for name in ['wing left', 'wing right', 'tail.002']:
    obj = bpy.data.objects[name]
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
    filled = bmesh.ops.edgeloop_fill(bm, edges=[e for e in bm.edges if e.is_boundary])['faces']
    bmesh.ops.triangulate(bm, faces=filled)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    print('CLOSED_SOURCE', name, 'filled', len(filled), 'boundary', sum(e.is_boundary for e in bm.edges),
          'nonmanifold', sum(not e.is_manifold for e in bm.edges))
    bm.to_mesh(obj.data)
    bm.free()
for sign, name, piece in [(1, 'wing left', 'OuterWingLeft'), (-1, 'wing right', 'OuterWingRight')]:
    cutter = make_cutter('FractureTool', 'X', sign, profile(2.7, -0.3, 1.9, 0.09), 5)
    cut_object(bpy.data.objects[name], [(piece, cutter)], 3)
tail = bpy.data.objects['tail.002']
specs = [(name, make_cutter('FractureTool', 'X', sign, profile(0.95, -4.6, -3.3, 0.06), 5))
         for sign, name in [(1, 'HorizontalTipLeft'), (-1, 'HorizontalTipRight')]]
specs.append(('VerticalTip', make_cutter('FractureTool', 'Y', 1, profile(0.35, -4.7, -3.0, 0.07), 5)))
cut_object(tail, specs, 3)
rig_aircraft_controls(3)
bpy.ops.object.select_all(action='SELECT')
if args.output_blend:
    bpy.ops.wm.save_as_mainfile(filepath=args.output_blend)
else:
    bpy.ops.export_scene.gltf(filepath=str(ROOT / 'Models/Aircraft_3/aircraft_3_breakaway.glb'),
                              export_format='GLB', use_selection=True, export_cameras=False, export_lights=False)
print('AIRCRAFT3_BREAKAWAY_BUILT')


