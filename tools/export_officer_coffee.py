"""Blender --background <coffee mug blend> --python tools/export_officer_coffee.py.

Exports the selected character, original rig, Coffee_Hold and Coffee_Sip actions.
Does not save or modify the Blender source on disk.
"""
from pathlib import Path
import bpy
import numpy as np
import math
import hashlib

root = Path(__file__).resolve().parents[1]
names = ['rig', 'Officer female.001', 'sunglasses', 'CoffeeMug',
         'CoffeeMug_Coffee', 'CoffeeMug_Insignia']
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
for name in names:
    obj = bpy.data.objects[name]
    obj.hide_set(False)
    obj.select_set(True)
bpy.context.view_layer.objects.active = bpy.data.objects['rig']

# Flatten the Blender-only alpha-over-white shader to a standard glTF texture.
material = bpy.data.objects['CoffeeMug_Insignia'].data.materials[0]
nodes = material.node_tree.nodes
source = next(n.image for n in nodes if n.type == 'TEX_IMAGE')
pixels = np.empty(len(source.pixels), dtype=np.float32)
source.pixels.foreach_get(pixels)
pixels = pixels.reshape((-1, 4))
pixels[:, :3] = pixels[:, :3] * pixels[:, 3:4] + np.array([.92, .92, .9]) * (1 - pixels[:, 3:4])
pixels[:, 3] = 1
texture = bpy.data.images.new('CoffeeMug_DefaultInsignia', width=source.size[0], height=source.size[1], alpha=True)
texture.pixels.foreach_set(pixels.ravel())
texture.pack()
node = nodes.new('ShaderNodeTexImage')
node.image = texture
material.node_tree.links.new(node.outputs['Color'], nodes.get('Principled BSDF').inputs['Base Color'])

scene = bpy.context.scene
scene.name = 'Coffee_Hold'
scene.frame_start = 1
scene.frame_end = 121
scene.frame_set(1)
bpy.context.view_layer.update()
rig = bpy.data.objects['rig']
direction = rig.pose.bones['hand.r'].tail - rig.pose.bones['hand.r'].head
rig['coffee_hold_hand_azimuth_degrees'] = math.degrees(math.atan2(direction.y, direction.x))
rig['coffee_mug_mesh_sha256'] = hashlib.sha256(repr([
    tuple(v.co) for v in bpy.data.objects['CoffeeMug'].data.vertices
]).encode()).hexdigest()
bpy.ops.export_scene.gltf(
    filepath=str(root / 'Models/Characters/OfficerFemaleCoffee.glb'),
    export_format='GLB', use_selection=True, export_extras=True,
    export_cameras=False, export_lights=False, export_animations=True,
    export_animation_mode='ACTIONS', export_frame_range=False,
    export_force_sampling=True, export_def_bones=False,
    export_skins=True, export_all_influences=True,
    export_anim_scene_split_object=False,
)
print('OFFICER_COFFEE_EXPORT_OK')
print('Reimport in Godot, then run tools/BuildOfficerCoffeeWalk.gd to refresh the runtime animation library.')
