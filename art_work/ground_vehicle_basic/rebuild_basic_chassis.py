"""Run in the inspected live Blender scene, retaining the original tracked running gear.

Creates a separate art study, not a replacement for any Godot runtime asset.
Original body/door meshes remain as datablocks and in the before-edit blend.
"""
import bpy
import bmesh
from mathutils import Matrix, Vector

OUT = 'C:/Godot projects/Project-Flight/art_work/ground_vehicle_basic/'
scene = bpy.context.scene
body = bpy.data.objects['body']
assert body.type == 'MESH' and len(body.data.vertices) == 327, 'Expected untouched ground vehicle 2 source'
bpy.ops.wm.save_as_mainfile(filepath=OUT + 'ground_vehicle_2_before.blend', copy=True)
source = body.data
source.use_fake_user = True
source.name = 'Original ground vehicle 2 body (preserved)'
materials = list(source.materials)
track_material = bpy.data.materials.new('Basic transport matte running gear')
track_material.use_nodes = True
track_material.diffuse_color = (.018,.020,.022,1)
track_shader = next(n for n in track_material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
track_shader.inputs['Base Color'].default_value = track_material.diffuse_color
track_shader.inputs['Roughness'].default_value = .95
materials.append(track_material)

verts, faces, slots = [], [], []
def face(points, material=0):
    start = len(verts)
    verts.extend(points)
    faces.append(tuple(range(start, len(verts))))
    slots.append(material)

# Retain the authored track/bogie/belly geometry, scaled with the smaller chassis.
track_map = {}
for p in source.polygons:
    if p.material_index != 1 or max(source.vertices[i].co.z for i in p.vertices) > 0.05:
        continue
    indices = []
    for i in p.vertices:
        if i not in track_map:
            co = source.vertices[i].co
            track_map[i] = len(verts)
            verts.append((co.x * .88, co.y * .82, co.z * .90))
        indices.append(track_map[i])
    faces.append(tuple(indices)); slots.append(1)

# Close the running-gear opening formerly hidden by the larger original shell.
track_mesh=bpy.data.meshes.new('Track closure temporary')
track_mesh.from_pydata(verts,[],faces)
track_bm=bmesh.new();track_bm.from_mesh(track_mesh)
bmesh.ops.remove_doubles(track_bm,verts=list(track_bm.verts),dist=.00001)
bmesh.ops.holes_fill(track_bm,edges=[e for e in track_bm.edges if e.is_boundary],sides=0)
bmesh.ops.recalc_face_normals(track_bm,faces=list(track_bm.faces))
track_bm.to_mesh(track_mesh);track_bm.free()
verts=[tuple(v.co) for v in track_mesh.vertices]
faces=[tuple(p.vertices) for p in track_mesh.polygons]
slots=[len(materials)-1]*len(faces)
bpy.data.meshes.remove(track_mesh)

# A modest chamfered van-like hull. Narrower shoulders and a straight sill replace
# the original long, pointed, deeply scalloped armored shell.
# y, width, top_width, roof_z, bottom_z
sections = [(-4.02,1.28,1.18,.32,-.40), (-3.66,1.56,1.40,.56,-.30),
            (-2.65,1.60,1.43,1.35,-.30), (-1.25,1.60,1.43,1.35,-.30),
            (-.22,1.60,1.43,1.35,-.30), (3.25,1.60,1.43,1.35,-.30),
            (3.82,1.45,1.32,1.25,-.34)]
def ring(section):
    y,w,t,h,b = section
    shoulder = min(.36, h-.18)
    return [(-w+.12,y,b),(w-.12,y,b),(w,y,b+.13),(w,y,shoulder),
            (t,y,h-.10),(t-.10,y,h),(-t+.10,y,h),(-t,y,h-.10),
            (-w,y,shoulder),(-w,y,b+.13)]
rings = [ring(s) for s in sections]
face(list(reversed(rings[0])))
face(rings[-1])
for n in range(len(rings)-1):
    for j in range(10):
        # Leave functional door openings, with separate door objects retained.
        if n == 3 and j in (2,3,7,8):
            continue
        k=(j+1)%10
        face([rings[n][j],rings[n][k],rings[n+1][k],rings[n+1][j]])

def section_at(y):
    for a,b in zip(sections, sections[1:]):
        if a[0] <= y <= b[0]:
            f=(y-a[0])/(b[0]-a[0])
            return [a[i]+(b[i]-a[i])*f for i in range(5)]
    return sections[0] if y < sections[0][0] else sections[-1]

def roof_point(x,y,offset=.012):
    return (x,y,section_at(y)[3]+offset)

# Broad cab glazing: visibility rather than slit-like armored viewports.
face([roof_point(-1.16,-3.48),roof_point(1.16,-3.48),
      roof_point(1.21,-2.78),roof_point(-1.21,-2.78)],1)
def side_point(sign,y,z,offset=.012):
    _,w,t,h,_=section_at(y)
    shoulder=min(.36,h-.18)
    f=max(0,min(1,(z-shoulder)/(h-.10-shoulder)))
    return (sign*(w+(t-w)*f+offset), y,z)
for sign in [-1,1]:
    face([side_point(sign,-2.60,.53),side_point(sign,-2.40,1.15),
          side_point(sign,-1.44,1.15),side_point(sign,-1.44,.53)],1)

# Plain front lamps and a narrow, non-armored bumper. No weapon ports.
for x in [-.91,.91]:
    face([(x-.16,-4.025,-.04),(x+.16,-4.025,-.04),
          (x+.16,-4.025,.16),(x-.16,-4.025,.16)],2)
face([(-.64,-4.028,-.20),(.64,-4.028,-.20),(.64,-4.028,-.09),(-.64,-4.028,-.09)],1)

# One low service hatch instead of the original three raised roof stations.
lower=[(-.56,.60,1.356),(.56,.60,1.356),(.56,1.64,1.356),(-.56,1.64,1.356)]
upper=[(-.48,.68,1.40),(.48,.68,1.40),(.48,1.56,1.40),(-.48,1.56,1.40)]
face(upper,2)
for i in range(4): face([lower[i],lower[(i+1)%4],upper[(i+1)%4],upper[i]],2)

def mesh_data(name, vs, fs, ms):
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(vs,[],fs)
    for mat in materials: mesh.materials.append(mat)
    for p,mi in zip(mesh.polygons,ms): p.material_index=mi
    bm=bmesh.new();bm.from_mesh(mesh)
    # Weld only coincident construction vertices, leaving deliberate panel gaps.
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.00001)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh);bm.free();mesh.update()
    return mesh

body.data = mesh_data('Basic transport chassis',verts,faces,slots)
body.matrix_world=Matrix.Identity(4)
body['design_note']='Basic utility variant: shorter hull, slimmer shoulders, broad glazing, one hatch; original running gear retained.'

for name,sign in [('door left',1),('door right',-1)]:
    door=bpy.data.objects[name]
    door.data.use_fake_user=True
    # Six-vertex perimeter follows the sill/shoulder/cab bevel precisely.
    profile=[(-1.24,-.17),(-.23,-.17),(-.23,.36),(-.23,1.25),(-1.24,1.25),(-1.24,.36)]
    outer=[side_point(sign,y,z,.007) for y,z in profile]
    inner=[(x-sign*.045,y,z) for x,y,z in outer]
    dv=outer+inner
    df=[(0,1,2,5),(5,2,3,4),(6,11,8,7),(11,10,9,8)]
    for i in range(6): df.append((i,(i+1)%6,(i+1)%6+6,i+6))
    dm=[0]*len(df)
    start=len(dv)
    dv.extend([side_point(sign,y,z,.024) for y,z in [(-.66,.59),(-.41,.59),(-.41,.64),(-.66,.64)]])
    df.append(tuple(range(start,start+4)));dm.append(1)
    door.data=mesh_data('Basic transport '+name,dv,df,dm)
    door.matrix_world=Matrix.Identity(4)

# Preserve original shader colors. Make solid viewport display agree with them.
for mat in materials:
    if mat and mat.use_nodes:
        node=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
        if node: mat.diffuse_color=node.inputs['Base Color'].default_value
for o in bpy.context.selected_objects:o.select_set(False)
body.select_set(True);bpy.context.view_layer.objects.active=body
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':
        space=area.spaces.active
        space.overlay.show_overlays=False
        space.region_3d.view_location=Vector((0,0,.10))
        space.region_3d.view_distance=12.0

scene['basic_vehicle_source']='D:/3D printing files/ground vehicle 2.blend'
scene['basic_vehicle_scope']='Visual design study only; not exported or wired into game scenes.'
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=OUT + 'ground_vehicle_basic.blend')
print('BASIC_CHASSIS_SAVED',bpy.data.filepath)
print('BODY_DIMENSIONS',tuple(round(v,3) for v in body.dimensions))
print('OBJECTS',[(o.name,len(o.data.vertices),len(o.data.polygons)) for o in scene.objects if o.type=='MESH'])
