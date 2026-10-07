"""Read-only topology audit of Aircraft 16's saved Blender source."""
import bpy
import bmesh
import sys

arguments = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
bpy.ops.wm.open_mainfile(filepath=arguments[0] if arguments else r'D:/3D printing files/aircraft 16.blend')
if bpy.context.object is not None and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
for obj in bpy.context.scene.objects:
    if obj.type != 'MESH' or not obj.data.polygons:
        continue
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    before = [face.normal.copy() for face in bm.faces]
    inconsistent = sum(edge.is_manifold and not edge.is_contiguous for edge in bm.edges)
    boundary = sum(edge.is_boundary for edge in bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.normal_update()
    flipped = [face.index for face in bm.faces if face.normal.dot(before[face.index]) < -0.5]
    print('NORMAL_AUDIT', obj.name, 'faces', len(bm.faces), 'inconsistent_edges', inconsistent,
          'boundary_edges', boundary, 'reversed_faces', flipped,
          'transform_determinant', round(obj.matrix_world.determinant(), 5),
          'custom_normals', obj.data.has_custom_normals)

    if obj.name == 'fuselage':
        print('FUSELAGE_ATTRIBUTES', [(a.name, a.domain, a.data_type) for a in obj.data.attributes])
        print('FUSELAGE_SMOOTH_FACES', sum(p.use_smooth for p in obj.data.polygons))
    bm.free()
