"""Add an editable IK sip to the current saved coffee officer; never rebuild the mug."""
import bpy, math, shutil
from pathlib import Path
from mathutils import Matrix, Vector

source = Path(bpy.data.filepath)
review = source.parent / 'Officer mug review'
backup = review / 'before_coffee_animations.blend'
if not backup.exists():
    shutil.copy2(source, backup)
scene = bpy.context.scene
rig = bpy.data.objects['rig']
scene.render.fps = 30
scene.frame_set(1)
bpy.context.view_layer.update()
hold = rig.animation_data.action
assert hold.name == 'Coffee_Hold', 'Start from the approved holding action'
hold.use_fake_user = True
# User-authored finger adjustments may be unkeyed. Snapshot the entire approved
# pose before creating another action, so glTF action switching cannot reset them.
for bone in rig.pose.bones:
    for channel in ['location','scale', 'rotation_quaternion' if bone.rotation_mode == 'QUATERNION' else 'rotation_axis_angle' if bone.rotation_mode == 'AXIS_ANGLE' else 'rotation_euler']:
        bone.keyframe_insert(channel,frame=1)
    for key in bone.keys():
        if isinstance(bone[key],(int,float)):
            bone.keyframe_insert(data_path='["%s"]' % key,frame=1)
hand = rig.pose.bones['c_hand_ik.r']
pole = rig.pose.bones['c_arms_pole.r']
initial = hand.matrix.copy()
pole_initial = pole.matrix.copy()
twist_rotation = rig.pose.bones['forearm_twist.r'].constraints['Copy Rotation']
twist_rotation.influence = 1.0
twist_rotation.keyframe_insert('influence',frame=1)
sleeve_roll = rig.pose.bones['forearm_twist.r'].constraints.get('CoffeeSleeveRoll')
if sleeve_roll is None:
    sleeve_roll = rig.pose.bones['forearm_twist.r'].constraints.new('COPY_ROTATION')
    sleeve_roll.name = 'CoffeeSleeveRoll'
sleeve_roll.target = rig
sleeve_roll.subtarget = 'forearm_stretch.r'
sleeve_roll.owner_space = 'WORLD'
sleeve_roll.target_space = 'WORLD'
sleeve_roll.influence = 0.0
sleeve_roll.keyframe_insert('influence',frame=1)
mug = bpy.data.objects['CoffeeMug']
verts = [mug.matrix_world @ v.co for v in mug.data.vertices]
top = max(v.z for v in verts)
# The lip-facing point of the circular rim (exclude the handle).
rim = Vector((mug.matrix_world.translation.x, mug.matrix_world.translation.y + .043, top))
rim = rig.matrix_world.inverted() @ rim
mouth = Vector((0, -.087, 1.652))
print('SIP_CONTACT', list(rim), 'TARGET', list(mouth))
if bpy.data.actions.get('Coffee_Sip'):
    bpy.data.actions.remove(bpy.data.actions['Coffee_Sip'])
sip = hold.copy()
sip.name = 'Coffee_Sip'
sip.use_fake_user = True
rig.animation_data.action = sip
# Keep the original grip throughout: the whole hand and mug rotate together.
# Lift, settle at the mouth, tip the mug, untilt, lower, and return exactly.
for frame, lift, tilt in [(1,0,0),(12,0,0),(40,1,0),(49,1,12),(68,1,18),(77,1,0),(108,0,0),(121,0,0)]:
    scene.frame_set(frame)
    rotation = Matrix.Rotation(math.radians(-tilt),4,'X')
    m = rotation @ initial
    contact = rim.lerp(mouth, lift)
    m.translation = contact + rotation.to_3x3() @ (initial.translation - rim)
    hand.matrix = m
    pm = pole_initial.copy()
    pm.translation = pole_initial.translation.lerp(Vector((-.47,-.04,1.40)),lift)
    pole.matrix = pm
    # A half-twist sleeve helper spreads roll between elbow and wrist. Full
    # hand roll here pinches linear-skinned exports at the middle of the sleeve.
    # Preserve the authored standing grip exactly at both ends of the action.
    twist_rotation.influence = 1.0
    twist_rotation.keyframe_insert('influence',frame=frame)
    sleeve_roll.influence = 0.5 * lift
    sleeve_roll.keyframe_insert('influence',frame=frame)
    for p in (hand,pole):
        p.keyframe_insert('location',frame=frame)
        p.keyframe_insert('rotation_euler',frame=frame)
    bpy.context.view_layer.update()
for layer in sip.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for curve in bag.fcurves:
                for key in curve.keyframe_points:
                    key.handle_left_type = 'AUTO_CLAMPED'
                    key.handle_right_type = 'AUTO_CLAMPED'
scene.frame_start = 1
scene.frame_end = 121
rig.animation_data.action = hold
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(source))
print('COFFEE_SIP_AUTHORED', source)

# Review camera and lighting are temporary and never saved into the asset.
rig.animation_data.action = sip
scene.frame_set(58)
for modifier in bpy.data.objects['Officer female.001'].modifiers:
    if modifier.type == 'ARMATURE':
        modifier.use_deform_preserve_volume = False  # Review as Godot skins it.
scene.render.engine = 'CYCLES'
scene.cycles.samples = 24
scene.world.color = (.22,.22,.22)
def area(name,pos,power,size):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
    obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj);obj.location=pos
    obj.rotation_euler=(Vector((0,0,1.4))-obj.location).to_track_quat('-Z','Y').to_euler()
area('ReviewKey',(-3,-4,5),450,4)
area('ReviewFill',(3,-2,3),240,3)
area('ReviewRim',(0,3,4),450,3)
data=bpy.data.cameras.new('Review');camera=bpy.data.objects.new('Review',data);scene.collection.objects.link(camera)
camera.location=(-1.9,-3,2.0)
camera.rotation_euler=(Vector((0,-.04,1.48))-camera.location).to_track_quat('-Z','Y').to_euler()
data.type='ORTHO';data.ortho_scale=.85;scene.camera=camera
scene.render.resolution_x=900;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.filepath=str(review/'sip_blender.png')
bpy.ops.render.render(write_still=True)
