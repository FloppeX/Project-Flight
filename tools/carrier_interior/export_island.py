"""Run with Blender --background <latest blend> --python this_file.
Exports only the island so existing game hull, aircraft lifts and materials survive.
"""
import bpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if bpy.context.scene.get('godot_clearance_revision', 0) < 1:
    raise RuntimeError('Use the synchronized island Blender source; clearance edits must be authored, not applied during export.')
originals = {'superstructure main island', 'superstructure floor lower',
             'superstructure floor upper', 'Superstructure elevator'}
bpy.ops.object.select_all(action='DESELECT')
selected = []
for obj in bpy.context.scene.objects:
    if obj.name in originals or any(c.name.startswith(('ISLAND',)) for c in obj.users_collection):
        obj.hide_set(False)
        obj['carrier_interior'] = True
        obj.select_set(True)
        selected.append(obj.name)
assert all(n in selected for n in originals)
doors = [bpy.data.objects[n] for n in selected if bpy.data.objects[n].get('door_type') == 'center_split_sliding']
assert doors, 'No authored sliding doors found'
for door in doors:
    leaves = [child for child in door.children if 'open_offset_x_m' in child]
    assert len(leaves) == 2, f'{door.name}: expected two leaves with signed open_offset_x_m'
    assert all(key in door for key in ('opening_width_m', 'opening_height_m')), f'{door.name}: missing aperture dimensions'
bpy.ops.export_scene.gltf(filepath=str(ROOT / 'Models/LandCarrier/CarrierIsland.glb'),
    export_format='GLB', use_selection=True, export_apply=True,
    export_extras=True, export_animations=False, export_cameras=False, export_lights=False)
print('ISLAND_EXPORT_OK', len(selected))
