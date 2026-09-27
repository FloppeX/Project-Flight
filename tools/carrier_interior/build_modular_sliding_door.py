"""Create a reusable carrier sliding-door .blend from the unified carrier source.

Run with Blender opening the source first. The source file is never overwritten.
"""
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


SOURCE_DOOR = "SD_00_LockerCorridor"
OUTPUT_BLEND = Path(r"D:\3D printing files\Carrier sliding door modular.blend")
PREVIEW_PNG = OUTPUT_BLEND.with_name("Carrier sliding door modular preview.png")
FRAME_OVERLAP_M = 0.003


def fail(message):
    raise RuntimeError(message)


def root_bounds(obj, root):
    points = [root.matrix_world.inverted() @ obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        Vector(min(point[i] for point in points) for i in range(3)),
        Vector(max(point[i] for point in points) for i in range(3)),
    )


def look_at(obj, target):
    obj.rotation_euler = ((Vector(target) - obj.location).to_track_quat("-Z", "Y")).to_euler()


def square_inner_corners(leaf, root, side):
    """Remove only the top/bottom chamfers that open holes along the center seam."""
    low, high = root_bounds(leaf, root)
    root_from_object = root.matrix_world.inverted() @ leaf.matrix_world
    object_from_root = root_from_object.inverted()
    changed = 0
    for vertex in leaf.data.vertices:
        point = root_from_object @ vertex.co
        at_end = abs(point.z - low.z) < 0.00001 or abs(point.z - high.z) < 0.00001
        at_inner_corner = point.x > -0.1 if side == "left" else point.x < 0.1
        if at_end and at_inner_corner:
            point.x = 0.0
            vertex.co = object_from_root @ point
            changed += 1
    if changed != 4:
        fail(f"Expected four inner corner vertices on {leaf.name}, changed {changed}")


def seal_outer_perimeter(leaf, root, side):
    """Extend the base panel behind the jamb, header, and sill to prevent light leaks."""
    low, high = root_bounds(leaf, root)
    root_from_object = root.matrix_world.inverted() @ leaf.matrix_world
    object_from_root = root_from_object.inverted()
    half_width = float(root["opening_width_m"]) * 0.5 + FRAME_OVERLAP_M
    bottom = -FRAME_OVERLAP_M
    top = float(root["opening_height_m"]) + FRAME_OVERLAP_M
    changed = 0
    for vertex in leaf.data.vertices:
        point = root_from_object @ vertex.co
        at_bottom = point.z <= low.z + 0.04001
        at_top = point.z >= high.z - 0.04001
        if not (at_bottom or at_top):
            continue
        point.z = bottom if at_bottom else top
        if side == "left" and point.x < -0.1:
            point.x = -half_width
        elif side == "right" and point.x > 0.1:
            point.x = half_width
        vertex.co = object_from_root @ point
        changed += 1
    if changed != 16:
        fail(f"Expected sixteen perimeter vertices on {leaf.name}, changed {changed}")


root = bpy.data.objects.get(SOURCE_DOOR)
if root is None or root.get("door_type") != "center_split_sliding":
    fail(f"Missing authored source door {SOURCE_DOOR}")

children = list(root.children)
frame = next((obj for obj in children if obj.name.endswith("_Frame")), None)
left = next((obj for obj in children if obj.name.endswith("_LeftLeaf")), None)
right = next((obj for obj in children if obj.name.endswith("_RightLeaf")), None)
if not all((frame, left, right)):
    fail("Source door must contain frame, left leaf, and right leaf")
child_local_matrices = {
    child: root.matrix_world.inverted() @ child.matrix_world for child in (frame, left, right)
}

# Remove the carrier while keeping one complete authored door assembly.
keep = {root, frame, left, right}
for obj in list(bpy.data.objects):
    if obj not in keep:
        bpy.data.objects.remove(obj, do_unlink=True)

# Put the reusable assembly at the file origin without changing child-local geometry.
root.matrix_world = Matrix.Identity(4)
for child, local_matrix in child_local_matrices.items():
    child.matrix_world = local_matrix
bpy.context.view_layer.update()
root.name = "CarrierSlidingDoor"
frame.name = "CarrierSlidingDoor_Frame"
left.name = "CarrierSlidingDoor_LeftLeaf"
right.name = "CarrierSlidingDoor_RightLeaf"

# Close the authored 12 mm center gap by moving both intact leaves equally inward.
left_low, left_high = root_bounds(left, root)
right_low, right_high = root_bounds(right, root)
gap = right_low.x - left_high.x
if not 0.0001 < gap < 0.05:
    fail(f"Unexpected source center gap: {gap:.6f} m")
left_matrix = left.matrix_local.copy()
right_matrix = right.matrix_local.copy()
left_matrix.translation.x += gap * 0.5
right_matrix.translation.x -= gap * 0.5
left.matrix_local = left_matrix
right.matrix_local = right_matrix
bpy.context.view_layer.update()

left_low, left_high = root_bounds(left, root)
right_low, right_high = root_bounds(right, root)
closed_gap = right_low.x - left_high.x
if abs(closed_gap) > 0.00001:
    fail(f"Corrected leaves do not meet: {closed_gap:.6f} m")
square_inner_corners(left, root, "left")
square_inner_corners(right, root, "right")
seal_outer_perimeter(left, root, "left")
seal_outer_perimeter(right, root, "right")
left.data.update()
right.data.update()
bpy.context.view_layer.update()
left_low, left_high = root_bounds(left, root)
right_low, right_high = root_bounds(right, root)
expected_half_width = float(root["opening_width_m"]) * 0.5 + FRAME_OVERLAP_M
expected_bottom = -FRAME_OVERLAP_M
expected_top = float(root["opening_height_m"]) + FRAME_OVERLAP_M
if (
    abs(left_low.x + expected_half_width) > 0.00001
    or abs(right_high.x - expected_half_width) > 0.00001
    or abs(left_low.z - expected_bottom) > 0.00001
    or abs(right_low.z - expected_bottom) > 0.00001
    or abs(left_high.z - expected_top) > 0.00001
    or abs(right_high.z - expected_top) > 0.00001
):
    fail("Corrected leaves do not overlap the frame opening on every outer edge")

# Keep the Godot-facing metadata and add provenance for future manual reuse.
root["asset_name"] = "Carrier modular center-split sliding door"
root["source_blend"] = r"D:\3D printing files\Land carrier - unified.blend"
root["closed_seam_m"] = 0.0
root["frame_overlap_m"] = FRAME_OVERLAP_M
root["reuse_note"] = "Append collection CARRIER_SLIDING_DOOR, then position and rotate CarrierSlidingDoor."

# Give the asset one obvious collection and discard empty source collections.
asset_collection = bpy.data.collections.new("CARRIER_SLIDING_DOOR")
bpy.context.scene.collection.children.link(asset_collection)
for obj in (root, frame, left, right):
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    asset_collection.objects.link(obj)
for collection in list(bpy.data.collections):
    if collection != asset_collection and not collection.objects and not collection.children:
        bpy.data.collections.remove(collection)

notes = bpy.data.texts.get("README_CarrierSlidingDoor") or bpy.data.texts.new("README_CarrierSlidingDoor")
notes.clear()
notes.write(
    "Reusable carrier center-split sliding door\n"
    "==========================================\n"
    "Append Collection > CARRIER_SLIDING_DOOR into the carrier file.\n"
    "Move and rotate the CarrierSlidingDoor root; leave its three children parented.\n"
    "Nominal clear opening: 1.10 m wide x 2.06 m high.\n"
    "The leaves meet at x=0 and overlap the frame by 3 mm on the other edges when closed.\n"
    "Signed open_offset_x_m properties are retained.\n"
    "Derived from D:/3D printing files/Land carrier - unified.blend without changing that source.\n"
)

# Save the clean reusable file before adding temporary preview objects.
OUTPUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), check_existing=False)

# Render a front three-quarter verification image, then remove preview-only objects.
preview_collection = bpy.data.collections.new("TEMP_PREVIEW")
bpy.context.scene.collection.children.link(preview_collection)

camera_data = bpy.data.cameras.new("PreviewCamera")
camera = bpy.data.objects.new("PreviewCamera", camera_data)
preview_collection.objects.link(camera)
camera.location = (2.65, -5.4, 2.65)
camera.data.type = "ORTHO"
camera.data.ortho_scale = 3.15
look_at(camera, (0.0, 0.0, 1.08))
bpy.context.scene.camera = camera

key_data = bpy.data.lights.new("PreviewKey", "AREA")
key_data.energy = 850.0
key_data.shape = "DISK"
key_data.size = 4.0
key = bpy.data.objects.new("PreviewKey", key_data)
preview_collection.objects.link(key)
key.location = (-2.5, -3.8, 4.8)
look_at(key, (0.0, 0.0, 1.0))

fill_data = bpy.data.lights.new("PreviewFill", "AREA")
fill_data.energy = 500.0
fill_data.size = 3.0
fill = bpy.data.objects.new("PreviewFill", fill_data)
preview_collection.objects.link(fill)
fill.location = (3.0, -2.0, 2.0)
look_at(fill, (0.0, 0.0, 1.0))

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1000
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(PREVIEW_PNG)
scene.render.film_transparent = False
scene.world.color = (0.025, 0.035, 0.055)
PREVIEW_PNG.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.render.render(write_still=True)

for obj in list(preview_collection.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
bpy.data.collections.remove(preview_collection)
scene.camera = None
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), check_existing=False)

print(
    "MODULAR_CARRIER_DOOR_OK",
    f"source_gap_m={gap:.6f}",
    f"closed_gap_m={closed_gap:.6f}",
    f"output={OUTPUT_BLEND}",
    f"preview={PREVIEW_PNG}",
)
