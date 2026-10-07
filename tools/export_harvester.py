"""Export the authored hull/head without changing the live Blender scene.

Run in Blender's Python context after opening harvester.blend. Unsaved edits
are included; a source snapshot is kept under the ignored captures directory.
"""
from pathlib import Path
from datetime import datetime
import json
import bpy
from mathutils import Matrix, Vector


def export_live():
    project = Path(__file__).resolve().parents[1]
    destination = project / "Models" / "Vehicles" / "Harvester"
    destination.mkdir(parents=True, exist_ok=True)
    snapshot = project / "captures" / "harvester_source"
    snapshot.mkdir(parents=True, exist_ok=True)
    source_path = bpy.data.filepath
    backup = snapshot / ("harvester-live-" + datetime.now().strftime("%Y%m%d-%H%M%S") + ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=str(backup), copy=True, check_existing=False)
    selected = list(bpy.context.selected_objects)
    active = bpy.context.view_layer.objects.active
    records = []
    for name, filename in [("Vehicle body", "harvester_hull.glb"), ("Extractor head", "extractor_head.glb")]:
        source = bpy.data.objects[name]
        mesh = source.data.copy()
        mesh.transform(source.matrix_world)
        # Hull keeps its authored world coordinates and metre scale. The head
        # has its mounting end at the origin and points forward (+Z in Godot).
        if name == "Extractor head":
            coords = [v.co for v in mesh.vertices]
            attachment = Vector((0, max(v.y for v in coords), 0))
            mesh.transform(Matrix.Translation(-attachment))
        duplicate = bpy.data.objects.new(name.replace(" ", ""), mesh)
        bpy.context.collection.objects.link(duplicate)
        try:
            for ob in bpy.context.selected_objects:
                ob.select_set(False)
            duplicate.select_set(True)
            bpy.context.view_layer.objects.active = duplicate
            # GLB is Blender's default export format; no version-specific enum.
            bpy.ops.export_scene.gltf(filepath=str(destination / filename), use_selection=True,
                export_yup=True, export_normals=True, export_animations=False,
                export_materials='EXPORT')
            records.append({"object":name,"file":filename,"vertices":len(mesh.vertices),
                "polygons":len(mesh.polygons),"dimensions":list(source.dimensions)})
        finally:
            bpy.data.objects.remove(duplicate, do_unlink=True)
            bpy.data.meshes.remove(mesh)
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    for ob in selected:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = active
    (destination / "source.json").write_text(json.dumps({"source":source_path,
        "snapshot":str(backup),"objects":records}, indent=2) + "\n", encoding="utf-8")
    print("HARVESTER_EXPORTED", records)


if __name__ == "__main__":
    export_live()
