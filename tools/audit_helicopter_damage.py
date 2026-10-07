import bpy, json
from pathlib import Path
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[1]
out = {}
for n in [9,10,11,12,13,15]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if n == 15:
        bpy.ops.wm.open_mainfile(filepath=str(ROOT/'Models/Aircraft_15/aircraft 15.blend'))
    else:
        bpy.ops.import_scene.gltf(filepath=str(ROOT/f'Models/Aircraft_{n}/aircraft_{n}.glb'))
    out[n] = {}
    for obj in bpy.data.objects:
        if obj.type != 'MESH': continue
        pts = [obj.matrix_world @ Vector(p) for p in obj.bound_box]
        pts = [(p.x,p.z,-p.y) for p in pts]
        out[n][obj.name] = [[round(min(p[i] for p in pts),3) for i in range(3)], [round(max(p[i] for p in pts),3) for i in range(3)]]
    print('HELI_GEOMETRY',n,out[n],flush=True)
(ROOT/'logs/helicopter_damage_geometry.json').write_text(json.dumps(out,indent=2))
