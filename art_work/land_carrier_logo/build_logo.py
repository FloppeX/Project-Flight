import bpy
import bmesh
import math
import json
from mathutils import Vector, Quaternion
from mathutils.geometry import delaunay_2d_cdt

# Pixel-space outlines hand traced from the supplied LAND CARRIER reference.
# X = horizontal, Z = up; all visible surfaces face Blender Front (-Y).
SCALE = 0.01
CENTER = (950.0, 399.0)
scene = bpy.context.scene
old_model = bpy.data.collections.get("LAND CARRIER | six editable meshes")
if old_model:
    for old_ob in list(old_model.objects):
        bpy.data.objects.remove(old_ob, do_unlink=True)
    bpy.data.collections.remove(old_model)
model = bpy.data.collections.new("LAND CARRIER | six editable meshes")
scene.collection.children.link(model)

def material(name, color):
    # True face normals select solid tones: no gradients, metallic reflections or smooth normals.
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    geometry = nodes.new("ShaderNodeNewGeometry")
    geometry.location = (-600,0)
    dot = nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = (-0.32,-0.64,0.70)
    dot.location = (-390,0)
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.location = (-180,0)
    ramp.color_ramp.interpolation = "CONSTANT"
    levels = [(0.0,0.22),(0.30,0.48),(0.56,1.0),(0.81,1.32)]
    for i,(position,factor) in enumerate(levels):
        el = ramp.color_ramp.elements[i] if i < 2 else ramp.color_ramp.elements.new(position)
        el.position = position
        el.color = (*(min(c*factor,1.0) for c in color),1.0)
    emission = nodes.new("ShaderNodeEmission")
    emission.location = (80,0)
    output = nodes.new("ShaderNodeOutputMaterial")
    output.location = (310,0)
    links.new(geometry.outputs["True Normal"],dot.inputs[0])
    links.new(dot.outputs["Value"],ramp.inputs[0])
    links.new(ramp.outputs["Color"],emission.inputs["Color"])
    links.new(emission.outputs[0],output.inputs["Surface"])
    mat.diffuse_color = (*color,1.0)
    mat["style"] = "Four solid face tones from true geometric normals; no smooth shading."
    return mat

gold = material("LAND | warm signal gold", (1.0,0.48,0.004))
orange = material("Band and rings | safety orange", (1.0,0.28,0.002))
silver = material("CARRIER | warm brushed alloy", (0.60,0.60,0.56))
charcoal = material("Backing | charcoal bronze", (0.027,0.031,0.038))

def inside(p, loop):
    x, y = p
    odd = False
    for a, b in zip(loop, loop[1:] + loop[:1]):
        if (a[1] > y) != (b[1] > y):
            cross = (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]
            if x < cross:
                odd = not odd
    return odd

def planar(outer, holes=(), regions=()):
    coords, edges = [], []
    for loop in [outer] + list(holes) + list(regions):
        start = len(coords)
        coords.extend(Vector((float(x), float(y))) for x, y in loop)
        edges.extend((start + i, start + (i + 1) % len(loop)) for i in range(len(loop)))
    result = delaunay_2d_cdt(coords, edges, [], 0, 0.00001)
    points = [tuple(v) for v in result[0]]
    faces = []
    for f in result[2]:
        c = tuple(sum(points[i][axis] for i in f) / len(f) for axis in (0, 1))
        if inside(c, outer) and not any(inside(c, h) for h in holes):
            faces.append(f)
    return points, faces

def make_mesh(name, parts, mat, bevel):
    # Each part: outside, holes, front depth, rear depth, optional raised regions.
    verts, faces, lookup = [], [], {}
    def vid(p, depth):
        co = ((p[0] - CENTER[0]) * SCALE, depth, (CENTER[1] - p[1]) * SCALE)
        key = tuple(round(v, 7) for v in co)
        if key not in lookup:
            lookup[key] = len(verts)
            verts.append(co)
        return lookup[key]
    for part in parts:
        lookup = {}  # Keep separate glyph solids independent even when outlines meet.
        outer, holes, front, back = part[:4]
        terraces = part[4] if len(part) > 4 else []
        pts, triangles = planar(outer, holes, [t[0] for t in terraces])
        face_depths = []
        edge_users = {}
        for fi, tri in enumerate(triangles):
            c = tuple(sum(pts[i][axis] for i in tri) / len(tri) for axis in (0, 1))
            depth = front
            for boundary, region_depth in terraces:
                if inside(c, boundary):
                    depth = region_depth
            face_depths.append(depth)
            faces.append(tuple(vid(pts[i], depth) for i in tri))
            faces.append(tuple(vid(pts[i], back) for i in reversed(tri)))
            for a, b in zip(tri, tri[1:] + tri[:1]):
                edge_users.setdefault(tuple(sorted((a, b))), []).append(fi)
        for (a, b), users in edge_users.items():
            d0 = face_depths[users[0]]
            d1 = back if len(users) == 1 else face_depths[users[1]]
            if abs(d0 - d1) > 1e-7:
                levels = sorted(set([d0, d1] + [d for d in [front] + [t[1] for t in terraces] if min(d0,d1) < d < max(d0,d1)]))
                for lo, hi in zip(levels, levels[1:]):
                    faces.append((vid(pts[a], lo), vid(pts[b], lo), vid(pts[b], hi), vid(pts[a], hi)))
    mesh = bpy.data.meshes.new(name + " | planar solid")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    # Remove only interior coplanar cap diagonals; silhouette vertices stay intact.
    bmesh.ops.dissolve_limit(bm, angle_limit=0.001, verts=list(bm.verts), edges=list(bm.edges), use_dissolve_boundaries=False)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    weights = bm.edges.layers.float.get("bevel_weight_edge") or bm.edges.layers.float.new("bevel_weight_edge")
    for edge in bm.edges:
        # Only bevel the shallow front/back rims. Preserve all upright corner joins.
        edge[weights] = 1.0 if abs(edge.verts[0].co.y-edge.verts[1].co.y)<1e-6 and edge.calc_face_angle(0)>0.20 else 0.0
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    obj = bpy.data.objects.new(name, mesh)
    model.objects.link(obj)
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Flat rim bevel | sharp vertical corners", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "WEIGHT"
        mod.angle_limit = math.radians(15)
        mod.use_clamp_overlap = False
    obj["front_axis"] = "-Y (Blender Front)"
    obj["construction"] = "Closed shallow polygonal solid; flat face normals; rim-only planar chamfers."
    return obj

# Letter faces, retained as a single mesh object per word.
L = [(531,134),(600,134),(600,266),(674,266),(684,276),(684,311),(674,321),(521,321),(521,144)]
A_land = [(687,321),(777,134),(855,134),(928,321),(859,321),(846,282),(764,282),(746,321)]
A_land_hole = [(783,242),(833,242),(811,174)]
N = [(940,134),(1002,134),(1066,218),(1066,134),(1125,134),(1125,311),(1115,321),(1066,321),(989,216),(989,321),(930,321),(930,144)]
D = [(1141,134),(1287,134),(1349,196),(1349,259),(1287,321),(1141,321)]
D_hole = [(1204,182),(1256,182),(1278,204),(1278,248),(1256,270),(1204,270)]
land = make_mesh("LAND", [
    (L, [], -0.285, -0.132),
    (A_land, [A_land_hole], -0.285, -0.132),
    (N, [], -0.285, -0.132),
    (D, [D_hole], -0.285, -0.132)
], gold, 0.024)

C = [(294,372),(411,372),(457,418),(457,460),(387,460),(387,445),(365,423),(336,423),(314,445),(314,527),(336,549),(365,549),(387,527),(387,514),(454,514),(454,556),(409,601),(293,601),(248,556),(248,418)]
A = [(452,601),(533,372),(623,372),(693,601),(626,601),(613,553),(536,553),(522,601)]
Ah = [(548,513),(601,513),(576,419)]
R = [(705,372),(863,372),(908,417),(908,484),(866,526),(919,601),(842,601),(798,528),(772,528),(772,601),(705,601)]
Rh = [(772,423),(822,423),(842,443),(842,459),(822,479),(772,479)]
I = [(1166,372),(1221,372),(1221,591),(1211,601),(1156,601),(1156,382)]
E = [(1240,372),(1414,372),(1424,382),(1424,413),(1414,423),(1305,423),(1305,459),(1391,459),(1401,469),(1401,499),(1391,509),(1305,509),(1305,549),(1414,549),(1424,559),(1424,591),(1414,601),(1240,601)]
def shifted(loop, dx):
    return [(x + dx, y) for x, y in loop]
carrier = make_mesh("CARRIER", [
    (C, [], -0.211, -0.018),
    (A, [Ah], -0.211, -0.018),
    (R, [Rh], -0.211, -0.018),
    (shifted(R, 227), [shifted(Rh, 227)], -0.211, -0.018),
    (I, [], -0.211, -0.018),
    (E, [], -0.211, -0.018),
    (shifted(R, 737), [shifted(Rh, 737)], -0.211, -0.018)
], silver, 0.024)

# The backing is one manifold relief solid, including the raised dark LAND surround.
plate_outline = [
    (202,281),(499,281),(499,114),(621,114),(630,132),(630,246),
    (692,246),(766,114),(867,114),(907,214),(907,135),(916,114),
    (1009,114),(1040,156),(1040,134),(1056,114),(1308,114),
    (1370,176),(1370,281),(1704,281),(1866,443),(1866,590),
    (1768,688),(132,688),(34,590),(34,449)
]
land_surround = [
    (499,281),(499,114),(621,114),(630,132),(630,246),
    (692,246),(766,114),(867,114),(907,214),(907,135),(916,114),
    (1009,114),(1040,156),(1040,134),(1056,114),(1308,114),
    (1370,176),(1370,281),(1307,343),(511,343)
]
plate = make_mesh("Dark Backing Plate", [
    (plate_outline, [], 0.012, 0.192, [(land_surround, -0.126)])
], charcoal, 0.035)

# An elongated octagonal badge with each corner clipped: exactly 16 perimeter edges.
# The rings use the same 8 broad facets + 8 short corner facets construction.
def clip_corners(loop, distance):
    result = []
    for i, raw in enumerate(loop):
        p = Vector(raw)
        before, after = Vector(loop[i - 1]), Vector(loop[(i + 1) % len(loop)])
        result.extend([tuple(p + (before - p).normalized() * distance),
                       tuple(p + (after - p).normalized() * distance)])
    return result

def inset_convex(loop, distance):
    # Pixel-space loops are clockwise on screen, positive in mathematical XY.
    result = []
    for i, p_raw in enumerate(loop):
        a, p, b = Vector(loop[i - 1]), Vector(p_raw), Vector(loop[(i + 1) % len(loop)])
        e0, e1 = (p-a).normalized(), (b-p).normalized()
        n0, n1 = Vector((-e0.y,e0.x)), Vector((-e1.y,e1.x))
        bisector = n0+n1
        result.append(tuple(p + bisector * (distance / bisector.dot(n0))))
    return result

badge8 = [(214,300),(1686,300),(1848,462),(1848,584),
          (1763,669),(137,669),(52,584),(52,462)]
band_outer = clip_corners(badge8, 1.5)
band_inner = clip_corners(inset_convex(badge8, 36.0), 1.5)
band = make_mesh("Orange Outer Band", [(band_outer, [band_inner], -0.104, -0.010)], orange, 0.022)
band["perimeter_sides"] = 16
band["closed_loop"] = True
band["construction"] = "One continuous 16-sided annular solid, including the span concealed behind LAND."

def segment_distance(p, a, b):
    p, a, b = Vector(p), Vector(a), Vector(b)
    delta = b-a
    t = max(0.0,min(1.0,(p-a).dot(delta)/delta.length_squared))
    return (p-(a+delta*t)).length

for name, cx in [("Polygonal Ring Left",170.0),("Polygonal Ring Right",1730.0)]:
    cy, apothem, wheel_sides = 539.0, 54.0, 12
    radius = apothem / math.cos(math.pi / wheel_sides)
    outer = [(cx+radius*math.cos(math.pi/wheel_sides+2*math.pi*i/wheel_sides),
              cy+radius*math.sin(math.pi/wheel_sides+2*math.pi*i/wheel_sides))
             for i in range(wheel_sides)]
    assert all(inside(p,band_inner) for p in outer), "Ring outside the border"
    gap = min(segment_distance(p,a,b) for p in outer for a,b in zip(band_inner,band_inner[1:]+band_inner[:1]))
    assert gap > 10.0, (name,gap)
    print("RING BORDER CLEARANCE",name,round(gap,2),"reference pixels")
    inner = [(cx+(x-cx)*0.49,cy+(y-cy)*0.49) for x,y in outer]
    ring = make_mesh(name, [(outer, [inner], -0.160, -0.014)], orange, 0.020)
    ring["perimeter_sides"] = wheel_sides
    ring["construction"] = "Twelve even facets suggest a track drive wheel; shallow extrusion and flat rim bevel."
    ring["closed_loop"] = True

scene["asset"] = "LAND CARRIER | angular vector relief logo"
scene["style"] = "Flat face tones, twelve-sided drive-wheel rings, sharp joins and diagonal-cut lettering."
scene["reference"] = "User-supplied gold/silver LAND CARRIER badge image."
scene["orientation"] = "Front view is -Y; X horizontal; Z up; no perspective distortion."
scene["parts"] = "LAND, CARRIER, Dark Backing Plate, Orange Outer Band, Polygonal Ring Left, Polygonal Ring Right"
scene["band_topology"] = "Continuous outer annulus with 16 sides on each base perimeter. Wheel rings have 12 even facets."
print("BUILT", [(o.name,len(o.data.vertices),len(o.data.polygons)) for o in model.objects])


# Render setup and final topology verification.
import bpy
import math
from mathutils import Vector, Quaternion
scene = bpy.context.scene
old_studio=bpy.data.collections.get("STUDIO | orthographic camera and soft lights")
if old_studio:
    for old_ob in list(old_studio.objects):
        bpy.data.objects.remove(old_ob, do_unlink=True)
    bpy.data.collections.remove(old_studio)
studio = bpy.data.collections.new("STUDIO | orthographic camera and soft lights")
scene.collection.children.link(studio)
cam_data = bpy.data.cameras.new("Front orthographic")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 19.8
cam = bpy.data.objects.new("CAMERA | Front", cam_data)
studio.objects.link(cam)
cam.location = (0.0, -32.0, 0.0)
cam.rotation_euler = ((Vector((0,0,0)) - cam.location).to_track_quat("-Z","Y")).to_euler()
scene.camera = cam

def area(name, pos, energy, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.size, data.color = energy, size, color
    ob = bpy.data.objects.new(name, data)
    studio.objects.link(ob)
    ob.location = pos
    ob.rotation_euler = ((Vector((0,0,0)) - ob.location).to_track_quat("-Z","Y")).to_euler()
    return ob
area("Key | upper left softbox", (-5.0,-8.0,7.0), 1100.0, 7.0, (1.0,0.93,0.79))
area("Fill | upper right", (6.0,-6.0,3.5), 500.0, 6.0, (0.80,0.89,1.0))
area("Front | broad reflection", (0.0,-10.0,1.0), 200.0, 8.0, (1.0,0.98,0.93))

world = bpy.data.worlds.new("Studio charcoal")
world.use_nodes = True
background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
background.inputs["Color"].default_value = (0.11,0.11,0.11,1.0)
background.inputs["Strength"].default_value = 0.28
scene.world = world
scene.render.resolution_x = 1920
scene.render.resolution_y = 830
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = "C:/Godot projects/Project-Flight/art_work/land_carrier_logo/Land_Carrier_Logo_preview.png"
# Keep the currently registered color transform; do not depend on a version-specific name.
scene.view_settings.exposure = 0.0
scene.view_settings.gamma = 1.0
scene.render.engine = "CYCLES"
scene.cycles.samples = 48
scene.cycles.use_denoising = True
for ob in bpy.context.selected_objects:
    ob.select_set(False)
bpy.context.view_layer.objects.active = bpy.data.objects["LAND"]
for screen in bpy.data.screens:
    for ar in screen.areas:
        if ar.type == "VIEW_3D":
            ar.spaces.active.region_3d.view_rotation = Quaternion((1.0,0.0,0.0), math.pi/2)
            ar.spaces.active.region_3d.view_perspective = "ORTHO"
            ar.spaces.active.region_3d.view_location = Vector((0,0,0))
            ar.spaces.active.region_3d.view_distance = 20.0
            ar.spaces.active.overlay.show_floor = False
            ar.spaces.active.overlay.show_axis_x = False
            ar.spaces.active.overlay.show_axis_y = False
            ar.spaces.active.shading.color_type = "MATERIAL"
            ar.spaces.active.shading.light = "STUDIO"
            ar.spaces.active.shading.show_shadows = True
            ar.spaces.active.clip_end = 1000
print("STUDIO READY", scene.view_settings.view_transform)

import bpy
import bmesh
import json
from mathutils import Vector, Quaternion
def components(bm):
    todo=set(bm.verts)
    count=0
    while todo:
        count+=1
        todo_root=todo.pop()
        stack=[todo_root]
        while stack:
            v=stack.pop()
            for e in v.link_edges:
                other=e.other_vert(v)
                if other in todo:
                    todo.remove(other)
                    stack.append(other)
    return count
def inspect(mesh):
    bm=bmesh.new()
    bm.from_mesh(mesh)
    info={
        "vertices":len(bm.verts),
        "faces":len(bm.faces),
        "triangles":sum(len(f.verts)-2 for f in bm.faces),
        "nonmanifold_edges":sum(not e.is_manifold for e in bm.edges),
        "degenerate_faces":sum(f.calc_area()<1e-10 for f in bm.faces),
        "components":components(bm),
        "signed_volume":round(bm.calc_volume(signed=True),6)
    }
    bm.free()
    return info
report={}
graph=bpy.context.evaluated_depsgraph_get()
model=bpy.data.collections["LAND CARRIER | six editable meshes"]
assert len(model.objects)==6
for ob in model.objects:
    report[ob.name]={"base":inspect(ob.data), "with_bevel":inspect(ob.evaluated_get(graph).data)}
    for kind in report[ob.name].values():
        assert kind["nonmanifold_edges"]==0, (ob.name,kind)
        assert kind["degenerate_faces"]==0, (ob.name,kind)
        assert kind["signed_volume"]>0
    if "Ring" in ob.name or "Band" in ob.name:
        assert report[ob.name]["base"]["components"]==1
        expected_sides=12 if "Ring" in ob.name else 16
        assert len(ob.data.vertices)==4*expected_sides
        # Each depth plane has two closed polygonal silhouette loops.
        bm=bmesh.new();bm.from_mesh(ob.data)
        front=min(v.co.y for v in bm.verts)
        perimeter=[e for e in bm.edges if all(abs(v.co.y-front)<1e-6 for v in e.verts) and e.calc_face_angle(0)>0.2]
        assert len(perimeter)==2*expected_sides
        assert len({v for e in perimeter for v in e.verts})==2*expected_sides
        todo=set(perimeter)
        lengths=[]
        while todo:
            edge=todo.pop();found={edge};stack=list(edge.verts)
            while stack:
                v=stack.pop()
                for e in v.link_edges:
                    if e in todo:
                        todo.remove(e);found.add(e);stack.extend(e.verts)
            lengths.append(len(found))
        assert sorted(lengths)==[expected_sides,expected_sides], (ob.name,lengths)
        report[ob.name]["front_perimeter_loops"]=sorted(lengths)
        bm.free()
assert all(not p.use_smooth for ob in model.objects for p in ob.data.polygons)
print("ANGULAR_LOGO_MESH_VALIDATION_PASS")
print(json.dumps(report,indent=2))
scene=bpy.context.scene
scene.render.resolution_percentage=100
scene.cycles.samples=96
scene.render.filepath="C:/Godot projects/Project-Flight/art_work/land_carrier_logo/Land_Carrier_Logo_preview.png"
for ob in bpy.context.selected_objects:
    ob.select_set(False)
bpy.context.view_layer.objects.active=bpy.data.objects["LAND"]
for screen in bpy.data.screens:
    for ar in screen.areas:
        if ar.type=="VIEW_3D":
            ar.spaces.active.overlay.show_extras=False
            ar.spaces.active.overlay.show_cursor=False
            ar.spaces.active.region_3d.view_rotation=Quaternion((1.0,0.0,0.0),1.5707963267948966)
            ar.spaces.active.region_3d.view_perspective="ORTHO"
            ar.spaces.active.region_3d.view_location=Vector((0,0,0))
            ar.spaces.active.region_3d.view_distance=14.0
            ar.spaces.active.shading.type="MATERIAL"
bpy.ops.wm.save_as_mainfile(filepath="C:/Godot projects/Project-Flight/art_work/land_carrier_logo/Land_Carrier_Logo.blend")
