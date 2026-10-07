"""Wire generated damage meshes and explicit engine/tail hit regions in scenes."""
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]
# body path, tail cut in aircraft coordinates, engine centre, engine dimensions
CONFIG = {
1: ('aircraft_1/fuselage', -2.55, (0,-.15,3.35), (1.45,1.5,1.5)),
2: ('Aircraft 2 body/main fuselage', -3.05, (0,.6,-4.35), (1.5,1.5,1.6)),
3: ('Aircraft 3/tail_002', -2.15, (0,-.05,2.8), (1.4,1.4,1.1)),
4: ('aircraft_4/aircraft_4/fuselage', -2.55, (0,-.1,3.7), (1.5,1.6,1.5)),
5: ('aircraft_5/world_001/body', -2.55, (0,-.1,3.95), (1.5,1.5,1.5)),
6: ('aircraft_6/Airframe', -3.45, (0,1.5,1.15), (1.0,1.2,1.3)),
7: ('aircraft_7/world/fuselage', -3.15, (0,0,6.05), (1.5,1.6,1.7)),
8: ('aircraft_8/world/fuselage_001', -3.25, (0,0,4.9), (1.5,1.6,1.5)),
14: ('aircraft_14/fuselage', -.8, (0,0,3.4), (1.3,1.4,1.5)),
16: ('Model/fuselage', -3.25, (0,0,3.5), (1.25,1.4,1.5)),
}
def vec(values):
    return 'Vector3(' + ', '.join(str(v) for v in values) + ')'
def paths(values):
    return 'Array[NodePath]([' + ', '.join('NodePath("../'+v+'")' for v in values) + '])'
for number,(body,cut,engine,size) in CONFIG.items():
    path=ROOT/f'Aircraft/Aircraft_{number}.tscn'
    text=path.read_text(encoding='utf-8')
    pattern = r'\[ext_resource type="PackedScene"[^\n]*path="res://Models/Aircraft_'+str(number)+r'/[^\n]+?\]'
    matches=list(re.finditer(pattern,text))
    # The first aircraft-specific asset is the main model, before any wreck.
    assert matches, number
    original=matches[0].group(0)
    replacement=re.sub(r' uid="[^"]+"', '', original)
    replacement=re.sub(r'path="[^"]+"', f'path="res://Models/Aircraft_{number}/aircraft_{number}_damage.glb"', replacement)
    text=text.replace(original,replacement,1)
    if 'id="BoxShape3D_engine_damage"' not in text:
        insert='[sub_resource type="BoxShape3D" id="BoxShape3D_engine_damage"]\nsize = '+vec(size)+'\n\n'
        insert+='[sub_resource type="BoxShape3D" id="BoxShape3D_tail_core_damage"]\nsize = Vector3(1.3, 1.1, 1.5)\n\n'
        text=text.replace('[node name=',insert+'[node name=',1)
        collider='[node name="EngineDamageCollider" type="CollisionShape3D" parent="."]\nposition = '+vec(engine)+'\nshape = SubResource("BoxShape3D_engine_damage")\n\n'
        collider+='[node name="TailDamageCollider" type="CollisionShape3D" parent="."]\nposition = '+vec((0,0,cut-.65))+'\nshape = SubResource("BoxShape3D_tail_core_damage")\n\n'
        text=text.replace('[node name="FuselageDamageCollider"',collider+'[node name="FuselageDamageCollider"',1)
    match=re.search(r'\[node name="PartDamageModel"[^\n]*\]\n[^\[]*(?=\[|$)',text)
    # Properties contain array brackets; delimit by the next node header.
    start=text.index('[node name="PartDamageModel"')
    end=text.find('\n[node ',start+1)
    if end < 0: end=len(text)
    block=text[start:end]
    def prop(key,value):
        global block
        block=re.sub(r'^'+key+r' = .*\n', '', block, flags=re.M)
        block=block.rstrip()+'\n'+key+' = '+value+'\n'
    tail=[body+'/TailBreakaway']
    attached=[]
    if number==2: attached+=['Aircraft 2 body/Aircraft 2 propeller']
    if number==14: attached+=['aircraft_14/tail']
    if number==16: attached+=['Model/horizontal stabiliser','Model/fuselage/rudder','Model/TailGear']
    prop('tail_section_visual_paths',paths(tail))
    prop('tail_section_attached_visual_paths',paths(attached))
    if number==2: prop('engine_attached_to_tail','true')
    prop('tail_cut_local_z',str(cut))
    if number in [4,7,8]:
        prop('left_wing_visual_paths',paths([body+'/WingBreakawayLeft']))
        prop('right_wing_visual_paths',paths([body+'/WingBreakawayRight']))
    text=text[:start]+block+'\n'+text[end:]
    path.write_text(text,encoding='utf-8',newline='\n')
    print('DAMAGE_SCENE_CONFIGURED',number)
