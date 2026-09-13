"""Export the complete carrier from its saved unified Blender source."""
import bpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
scene = bpy.context.scene
if scene.get('godot_clearance_revision', 0) < 1:
    raise RuntimeError('Use the synchronized carrier source with authored interior clearances.')
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
originals = {'superstructure main island', 'superstructure floor lower',
             'superstructure floor upper', 'Superstructure elevator'}
bpy.ops.object.select_all(action='DESELECT')
selected = []
for obj in scene.objects:
    if obj.type not in {'MESH', 'EMPTY', 'FONT', 'CURVE', 'SURFACE', 'META'}:
        continue
    obj.hide_set(False)
    obj.select_set(True)
    obj['carrier_interior'] = obj.name in originals or any(
        c.name.startswith('ISLAND') for c in obj.users_collection)
    selected.append(obj)
assert {'main hull', 'Flight deck', 'Elevators', *originals}.issubset({o.name for o in selected})
doors = [o for o in selected if o.get('door_type') == 'center_split_sliding']
assert doors, 'Missing sliding door assemblies'
for door in doors:
    assert len([c for c in door.children if 'open_offset_x_m' in c]) == 2, door.name
    assert all(k in door for k in ('opening_width_m', 'opening_height_m')), door.name
bpy.ops.export_scene.gltf(
    filepath=str(ROOT / 'Models/LandCarrier/CarrierUnified.glb'),
    export_format='GLB', use_selection=True, export_apply=True,
    export_extras=True, export_animations=False, export_cameras=False, export_lights=False)
print('CARRIER_UNIFIED_EXPORT_OK', len(selected), 'objects', len(doors), 'doors')
