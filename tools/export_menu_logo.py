"""Export the saved, user-edited logo without rebuilding or saving its Blender source.
Blender --background --factory-startup art_work/land_carrier_logo/Land_Carrier_Logo.blend
        --python-exit-code 1 --python tools/export_menu_logo.py
"""
import bpy
import hashlib
import json
from pathlib import Path
from mathutils import Vector

project = Path(__file__).resolve().parents[1]
source = Path(bpy.data.filepath)
destination = project / "Models" / "Branding"
destination.mkdir(parents=True, exist_ok=True)
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
collection = bpy.data.collections.get("LAND CARRIER | six editable meshes")
assert collection is not None, "Open the authored logo .blend before exporting."
originals = [ob for ob in collection.all_objects if ob.type == "MESH"]
assert len(originals) == 6
graph = bpy.context.evaluated_depsgraph_get()
for ob in bpy.context.selected_objects:
    ob.select_set(False)
records = []
for original in originals:
    name = original.name
    evaluated = original.evaluated_get(graph)
    mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=graph)
    mesh.calc_loop_triangles()
    original.name = "__source__" + name
    exported = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(exported)
    exported.matrix_world = original.matrix_world.copy()
    exported.select_set(True)
    source_material = original.data.materials[0]
    ramps = [node for node in source_material.node_tree.nodes if node.type == "VALTORGB"]
    assert len(ramps) == 1, "Logo palette changed; update the export material adapter."
    ramp = ramps[0]
    palette = [{"position": e.position, "color": list(e.color)} for e in ramp.color_ramp.elements]
    assert len(palette) == 4
    # Portable placeholder; MenuLogo3D recreates the authored four-tone shader.
    material = bpy.data.materials.new(name + " | export palette")
    material.use_nodes = True
    shader = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = source_material.diffuse_color
    shader.inputs["Roughness"].default_value = 1.0
    mesh.materials.clear()
    mesh.materials.append(material)
    points = [exported.matrix_world @ Vector(corner) for corner in exported.bound_box]
    records.append({
        "name": name,
        "source_vertices": len(original.data.vertices),
        "export_vertices": len(mesh.vertices),
        "triangles": len(mesh.loop_triangles),
        "palette": palette,
        "bounds_blender": [[min(p[i] for p in points) for i in range(3)],
                           [max(p[i] for p in points) for i in range(3)]],
    })
bpy.ops.export_scene.gltf(
    filepath=str(destination / "land_carrier_logo.glb"),
    export_format="GLB", use_selection=True, export_yup=True,
    export_apply=False, export_animations=False, export_cameras=False,
    export_lights=False, export_extras=False,
)
manifest = {
    "source": str(source.relative_to(project)).replace(chr(92), "/"),
    "source_sha256": source_hash,
    "blender_version": bpy.app.version_string,
    "normal_light_direction_godot": [-0.32, 0.70, 0.64],
    "objects": records,
}
(destination / "land_carrier_logo.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
assert hashlib.sha256(source.read_bytes()).hexdigest() == source_hash
print("MENU_LOGO_EXPORT_PASS", len(records), "authored meshes", sum(r["triangles"] for r in records), "triangles; source unchanged")

