"""Preserve authored helicopter hierarchies; add capped detachable tail sections."""
import sys
import argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_aircraft_damage_meshes import split_mesh
import bpy

ROOT = Path(__file__).resolve().parents[1]
CONFIG = {9:('Fuselage',-2.4),10:('Fuselage',-1.0),11:('Fuselage',-1.8),
          12:('fuselage',-2.3),13:('tail boom',-1.2),15:('fuselage',-2.0)}
parser = argparse.ArgumentParser()
parser.add_argument('--aircraft', type=int, choices=CONFIG)
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
for number,(name,cut) in CONFIG.items():
    if args.aircraft is not None and number != args.aircraft:
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if number == 15:
        bpy.ops.wm.open_mainfile(filepath=str(ROOT/'Models/Aircraft_15/aircraft 15.blend'))
    else:
        bpy.ops.import_scene.gltf(filepath=str(ROOT/f'Models/Aircraft_{number}/aircraft_{number}.glb'))
    if bpy.context.object and bpy.context.object.mode != 'OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
    # Native Blender sources can use Solidify; split the evaluated game surface.
    for obj in list(bpy.data.objects):
        if obj.type == 'MESH' and obj.modifiers:
            print('HELI_EVALUATE',number,obj.name,[m.type for m in obj.modifiers],flush=True)
            obj.data = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
            obj.modifiers.clear()
    split_mesh(bpy.data.objects[name], 'z', cut, True, 'TailBreakaway', cap_open_cross_section=number == 15)
    if number == 11:
        # The authored skid tubes are separate geometry inside the fuselage
        # object. Separate their material faces without changing their surface.
        obj = bpy.data.objects[name]
        count = len(obj.data.polygons)
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        for vertex in obj.data.vertices: vertex.select = False
        for edge in obj.data.edges: edge.select = False
        for face in obj.data.polygons:
            face.select = obj.data.materials[face.material_index].name == 'Grey'
            if face.select:
                assert all((obj.matrix_world @ obj.data.vertices[i].co).z < -0.75 for i in face.vertices), 'Unexpected skid material geometry'
        bpy.context.tool_settings.mesh_select_mode = (False, False, True)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.separate(type='SELECTED')
        bpy.ops.object.mode_set(mode='OBJECT')
        skids, = [other for other in bpy.context.selected_objects if other != obj]
        skids.name = 'Skids'
        assert len(skids.data.polygons) > 0
        assert len(obj.data.polygons) + len(skids.data.polygons) == count
        print('HELICOPTER_SKID_MESH_PASS faces=', len(skids.data.polygons), flush=True)
    if number == 13:
        for name in ['struts 1']:
            split_mesh(bpy.data.objects[name], 'z', cut, True, 'TailSupportBreakaway'+name[-1])
    bpy.ops.object.select_all(action='SELECT')
    target=ROOT/f'Models/Aircraft_{number}/aircraft_{number}_damage.glb'
    bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB', use_selection=True, export_cameras=False, export_lights=False)
    print('HELICOPTER_DAMAGE_MESH_PASS',number,flush=True)
