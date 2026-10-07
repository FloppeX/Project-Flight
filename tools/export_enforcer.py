"""Export the Enforcer hull while preserving authored meshes and materials.
Run with Blender --background --factory-startup "D:/3D printing files/vehicle 3.blend"
--python-exit-code 1 --python tools/export_enforcer.py. The source is read only.
"""
import bpy, json, hashlib
from pathlib import Path
from mathutils import Vector
project=Path(__file__).resolve().parents[1]
source=Path(bpy.data.filepath)
out=project/'Models/Vehicles/Enforcer'
out.mkdir(parents=True, exist_ok=True)
# Export every authored mesh with modifiers, materials and object hierarchy intact.
bpy.ops.export_scene.gltf(filepath=str(out/'enforcer_hull.glb'),export_format='GLB',export_yup=True,export_apply=True,export_animations=False,export_cameras=False,export_lights=False,export_extras=True)
records=[]
for obj in bpy.context.scene.objects:
    if obj.type != 'MESH': continue
    evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    pts=[evaluated.matrix_world @ Vector(c) for c in evaluated.bound_box]
    records.append({'name':obj.name,'parent':obj.parent.name if obj.parent else None,'bounds_blender':[[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]],'materials':[slot.material.name if slot.material else None for slot in obj.material_slots]})
(out/'source.json').write_text(json.dumps({'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'export':'enforcer_hull.glb','blender_version':bpy.app.version_string,'objects':records},indent=2)+'\n',encoding='utf-8')
print('ENFORCER_EXPORT_PASS meshes='+str(len(records)))
