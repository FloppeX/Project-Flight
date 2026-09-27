import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r'C:\Godot projects\Project-Flight\Models\Aircraft_5\aircraft_5_with_control_surfaces.glb')
for obj in bpy.context.scene.objects:
 if 'rudder' in obj.name:
  pts=sorted(set(tuple(round(v,5) for v in obj.matrix_world @ vert.co) for vert in obj.data.vertices),key=lambda p:(p[2],p[1],p[0]))
  print(obj.name,pts)
