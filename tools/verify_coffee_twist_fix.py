import bpy,json,hashlib,math
from pathlib import Path
paths=['D:/3D printing files/Officer mug review/before_forearm_twist_fix.blend','D:/3D printing files/Officer female - coffee mug.blend']
samples=[]
for path in paths:
 bpy.ops.wm.open_mainfile(filepath=path)
 r=bpy.data.objects['rig'];r.animation_data.action=bpy.data.actions['Coffee_Sip']
 data={'mesh':{},'poses':[],'max_twist':0}
 for n in ['Officer female.001','sunglasses','CoffeeMug','CoffeeMug_Coffee','CoffeeMug_Insignia']:
  o=bpy.data.objects[n];data['mesh'][n]=hashlib.sha256(repr([tuple(v.co)for v in o.data.vertices]).encode()).hexdigest()
 for f in range(1,122):
  bpy.context.scene.frame_set(f);bpy.context.view_layer.update()
  data['poses'].append([r.pose.bones['hand.r'].matrix.copy(),bpy.data.objects['CoffeeMug'].matrix_world.copy()])
  a=r.pose.bones['forearm_stretch.r'].matrix.to_quaternion();b=r.pose.bones['forearm_twist.r'].matrix.to_quaternion()
  angle=(a.inverted()@b).angle
  data['max_twist']=max(data['max_twist'],math.degrees(min(angle,math.tau-angle)))
 samples.append(data)
assert samples[0]['mesh']==samples[1]['mesh']
error=max(abs(a[i][j]-b[i][j])for old,new in zip(samples[0]['poses'],samples[1]['poses'])for a,b in zip(old,new)for i in range(4)for j in range(4))
assert error<.0001,error
assert samples[1]['max_twist']<75,samples[1]['max_twist']
result={'mesh_unchanged':True,'hand_and_mug_motion_error':error,'before_max_twist_degrees':samples[0]['max_twist'],'after_max_twist_degrees':samples[1]['max_twist']}
Path('D:/3D printing files/Officer mug review/twist_fix_verification.json').write_text(json.dumps(result,indent=2))
print('TWIST_FIX_VERIFIED',result)
