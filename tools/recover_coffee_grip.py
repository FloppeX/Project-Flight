"""Recover the authored grip from the retained Blender autosave, then rebuild sip."""
import bpy,shutil,json,hashlib
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1]
source=Path('D:/3D printing files/Officer female - coffee mug.blend')
review=source.parent/'Officer mug review'
autosave=Path('C:/Users/jonto/AppData/Local/Temp/Officer female - coffee mug_38972_autosave.blend')
backup=review/'before_grip_recovery_with_animations.blend'
assert not backup.exists(), 'Recovery already executed; do not replace the backup'
shutil.copy2(source,backup)
shutil.copy2(autosave,review/'recovered_user_grip_autosave.blend')
bpy.ops.wm.open_mainfile(filepath=str(autosave))
bpy.context.scene.frame_set(1)
r=bpy.data.objects['rig']
assert (r.pose.bones['hand.r'].tail-r.pose.bones['hand.r'].head).y < -.03
fingerprint=hashlib.sha256(repr([tuple(v.co)for v in bpy.data.objects['CoffeeMug'].data.vertices]).encode()).hexdigest()
bpy.ops.wm.save_as_mainfile(filepath=str(source))
exec(compile((root/'tools/author_officer_coffee_sip.py').read_text(),str(root/'tools/author_officer_coffee_sip.py'),'exec'))
assert hashlib.sha256(repr([tuple(v.co)for v in bpy.data.objects['CoffeeMug'].data.vertices]).encode()).hexdigest()==fingerprint
r.animation_data.action=bpy.data.actions['Coffee_Hold']
scene.frame_set(1)
camera.location=(-1.9,-3,2.0)
camera.rotation_euler=(Vector((0,-.04,1.38))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.ortho_scale=1.1
scene.render.filepath=str(review/'recovered_hold.png')
bpy.ops.render.render(write_still=True)
print('RECOVERED_GRIP_MUG_PRESERVED',fingerprint)
