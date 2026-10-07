"""Build a disposable double-sided menu variant from the exported logo."""
import bpy
from pathlib import Path
from mathutils import Matrix, Vector
from math import pi

root = Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(root / 'Models/Branding/land_carrier_logo.glb'))
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
plate = next(o for o in meshes if o.name.replace('_', ' ') == 'Dark Backing Plate')
# Bake world coordinates before joining the two backing solids.
for obj in meshes:
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
rear_y = max(v.co.y for v in plate.data.vertices) - 0.01
turn = Matrix.Translation(Vector((0, rear_y, 0))) @ Matrix.Rotation(pi, 4, 'Z') @ Matrix.Translation(Vector((0, -rear_y, 0)))
rear_plate = None
for original in meshes:
    rear = original.copy()
    rear.data = original.data.copy()
    rear.name = original.name + '_Rear'
    bpy.context.collection.objects.link(rear)
    rear.data.transform(turn)
    if original == plate:
        rear_plate = rear
bpy.context.view_layer.objects.active = plate
union = plate.modifiers.new('Symmetric shared backing', 'BOOLEAN')
union.operation = 'UNION'
union.solver = 'EXACT'
union.object = rear_plate
bpy.ops.object.modifier_apply(modifier=union.name)
bpy.data.objects.remove(rear_plate, do_unlink=True)
for obj in bpy.context.scene.objects:
    obj.select_set(obj.type == 'MESH')
bpy.ops.export_scene.gltf(filepath=str(root / 'Models/Branding/land_carrier_logo_spin.glb'), export_format='GLB', use_selection=True, export_animations=False, export_cameras=False, export_lights=False)
print('DOUBLE_SIDED_LOGO_EXPORT_PASS')
