"""One-time migration from Aircraft 16's saved source to a direct Blender asset.

Back up and correct the original's fuselage normals, then save a project .blend
with the existing suspension groups and folding/damage wing sections. Subsequent
model edits should be made in Models/Aircraft_16/aircraft_16.blend: Godot imports
that file directly. Refuse to overwrite an existing project copy.
"""
from pathlib import Path
from datetime import datetime
import hashlib
import shutil
import bpy
import bmesh
from mathutils import Vector

SOURCE = Path(r'D:/3D printing files/aircraft 16.blend')
DEST = Path(__file__).resolve().parents[1] / 'Models/Aircraft_16/aircraft_16.blend'
if DEST.exists():
    raise RuntimeError(f'Project source already exists; edit it directly: {DEST}')
source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
BACKUP = SOURCE.with_name('aircraft 16 - before normals fix ' + datetime.now().strftime('%Y%m%d-%H%M%S') + '.blend')
if BACKUP.exists():
    raise RuntimeError(f'Backup already exists: {BACKUP}')
shutil.copy2(SOURCE, BACKUP)
print('AIRCRAFT16_SOURCE_BACKUP', BACKUP)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
if bpy.context.object is not None and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')

# Several source fuselage polygons wind inward. Godot backface-culls those
# polygons, producing holes even though Blender's double-sided viewport looks
# intact. Correct topology rather than hiding the fault with two-sided materials.
# Do not globally recalculate the intentionally open seat/interior panels.
fuselage_mesh = bpy.data.objects['fuselage'].data
original_counts = (len(fuselage_mesh.vertices), len(fuselage_mesh.polygons))
custom_normals = fuselage_mesh.attributes.get('custom_normal')
if custom_normals:
    fuselage_mesh.attributes.remove(custom_normals)
bm = bmesh.new()
bm.from_mesh(fuselage_mesh)
bm.faces.ensure_lookup_table()
old_normals = [face.normal.copy() for face in bm.faces]
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.normal_update()
reversed_count = sum(face.normal.dot(old_normals[face.index]) < -0.5 for face in bm.faces)
assert not any(edge.is_manifold and not edge.is_contiguous for edge in bm.edges), 'Inconsistent fuselage winding'
bm.to_mesh(fuselage_mesh)
bm.free()
fuselage_mesh.update()
assert original_counts == (len(fuselage_mesh.vertices), len(fuselage_mesh.polygons)), 'Fuselage geometry changed'
print('AIRCRAFT16_FUSELAGE_NORMALS repaired_faces=', reversed_count)

if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != source_hash:
    raise RuntimeError('Source changed during preparation; refusing to overwrite it')
# Keep Blender from replacing any existing user .blend1 backup.
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), check_existing=False)
print('AIRCRAFT16_ORIGINAL_REPAIRED', SOURCE)

for obj in list(bpy.context.scene.objects):
    if obj.type == 'MESH' and not obj.data.vertices:
        bpy.data.objects.remove(obj, do_unlink=True)

for name, members in {
    'MainGearLeft': ['Main tire 1', 'Wheel hub 1', 'Main gear leg 1', 'Main axle 1'],
    'MainGearRight': ['Main tire -1', 'Wheel hub -1', 'Main gear leg -1', 'Main axle -1'],
    'TailGear': ['Tailwheel tire', 'Tailwheel hub', 'Tailwheel spring'],
}.items():
    group = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(group)
    for member in members:
        obj = bpy.data.objects[member]
        world = obj.matrix_world.copy()
        obj.parent = group
        obj.matrix_world = world

wing = bpy.data.objects['wing']
for name, low, high in [
    ('WingLeftRoot', 0.0, 4.0), ('WingLeft', 4.0, 7.0),
    ('WingRightRoot', -4.0, 0.0), ('WingRight', -7.0, -4.0),
]:
    mesh = wing.data.copy()
    mesh.transform(wing.matrix_world)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    for seam, keep_positive in [(low, True), (high, False)]:
        bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
            dist=0.00001, plane_co=Vector((seam, 0, 0)), plane_no=Vector((1, 0, 0)),
            clear_inner=keep_positive, clear_outer=not keep_positive)
        boundary = [e for e in bm.edges if e.is_boundary and all(abs(v.co.x-seam) < 0.0001 for v in e.verts)]
        if boundary:
            bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    part = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(part)
bpy.data.objects.remove(wing, do_unlink=True)

# Print material bounds as a useful cockpit/airframe integration reference.
fuselage = bpy.data.objects['fuselage']
for index, material in enumerate(fuselage.data.materials):
    vertices = {v for p in fuselage.data.polygons if p.material_index == index for v in p.vertices}
    coords = [fuselage.matrix_world @ fuselage.data.vertices[v].co for v in vertices]
    if coords:
        print('MATERIAL_BOUNDS', material.name if material else '',
              [round(min(p[i] for p in coords), 3) for i in range(3)],
              [round(max(p[i] for p in coords), 3) for i in range(3)])

DEST.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(DEST), check_existing=False)
print('AIRCRAFT16_PROJECT_BLEND', DEST)
