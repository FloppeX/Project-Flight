"""Rig the authored control-surface model and retain Aircraft 5's damage pieces.

Run in Blender with --background --python-exit-code 1 --python this.py.
The source GLB and previous breakaway GLB remain untouched.
"""
import sys
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_folding_aircraft_breakaway import build

# Reuse the established hinge transforms, not the previous model's geometry.
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'Models/Aircraft_5/aircraft_5_breakaway.glb'))
names = ['world.001', 'body', 'canopy', 'instrument panel', 'outer wing left',
         'outer wing right', 'aileron left', 'aileron right', 'elevator',
         'rudder left', 'rudder right']
rest = {name: bpy.data.objects[name].matrix_world.copy() for name in names}
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.outliner.orphans_purge(do_recursive=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'Models/Aircraft_5/aircraft 5 with control surfaces.glb'))
bpy.context.view_layer.update()
mapping = {'fuselage': 'body', 'left aileron': 'aileron left', 'right aileron': 'aileron right'}
objects = list(bpy.context.scene.objects)
world = {obj: obj.matrix_world.copy() for obj in objects}
# These surfaces have new outlines (and the rudder names changed sides).
# Place hinges on their own leading edges rather than the old mesh origins.
for obj in objects:
    name = mapping.get(obj.name, obj.name)
    if name in ('aileron left', 'aileron right', 'elevator', 'rudder left', 'rudder right'):
        points = [world[obj] @ vertex.co for vertex in obj.data.vertices]
        pivot = rest[name].translation.copy()
        pivot.y = min(point.y for point in points)  # Blender -Y = Godot +Z, forward.
        if name.startswith('rudder'):
            # The forward edge is swept aft toward the top. Its hinge runs
            # through the thickness centre at BOTH ends, not vertically
            # through the foremost point of the bounding box.
            edge_ends = []
            for height in (min(p.z for p in points), max(p.z for p in points)):
                row = [p for p in points if abs(p.z - height) < 0.0001]
                forward = min(p.y for p in row)
                edge = [p for p in row if abs(p.y - forward) < 0.0001]
                edge_ends.append(sum(edge, Vector()) / len(edge))
            pivot = (edge_ends[0] + edge_ends[1]) * 0.5
            axis = (edge_ends[1] - edge_ends[0]).normalized()
            rest[name] = Vector((0, 0, 1)).rotation_difference(axis).to_matrix().to_4x4()
        else:
            pivot.z = (min(p.z for p in points) + max(p.z for p in points)) * 0.5
        rest[name].translation = pivot
for obj in objects:
    obj.parent = None
    obj.name = mapping.get(obj.name, obj.name)
    # Move each origin to its hinge without moving any authored vertex.
    obj.data.transform(rest[obj.name].inverted() @ world[obj])
    obj.matrix_world = rest[obj.name]
container = bpy.data.objects.new('world.001', None)
bpy.context.collection.objects.link(container)
container.matrix_world = rest['world.001']
parents = {'body': 'world.001', 'canopy': 'world.001', 'instrument panel': 'world.001',
           'aileron left': 'outer wing left', 'aileron right': 'outer wing right',
           'elevator': 'body', 'rudder left': 'body', 'rudder right': 'body'}
for name, parent in parents.items():
    obj = bpy.data.objects[name]
    obj.parent = bpy.data.objects[parent]
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_basis = rest[parent].inverted() @ rest[name]
bpy.context.view_layer.update()
build(5, ROOT / 'Models/Aircraft_5/aircraft_5_control_surfaces_rigged.glb')
