"""Bind preserved damage derivatives and the helicopter regional model."""
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]
for n in [9,10,11,12,13,15]:
    p=ROOT/f'Aircraft/Aircraft_{n}.tscn'
    text=p.read_text(encoding='utf-8')
    text=re.sub(r'\[ext_resource type="PackedScene"[^\n]* id="3_model"\]',
        f'[ext_resource type="PackedScene" path="res://Models/Aircraft_{n}/aircraft_{n}_damage.glb" id="3_model"]',text)
    if 'HelicopterDamageModel.gd' not in text:
        index=text.index('[sub_resource')
        text=text[:index]+'[ext_resource type="Script" path="res://Aircraft/HelicopterDamageModel.gd" id="helicopter_damage"]\n\n'+text[index:]
        text += f'\n[node name="PartDamageModel" type="Node" parent="."]\nscript = ExtResource("helicopter_damage")\naircraft_number = {n}\n'
        text=re.sub(r'load_steps=(\d+)',lambda m:f'load_steps={int(m[1])+1}',text,count=1)
    p.write_text(text,encoding='utf-8')
    print('HELICOPTER_DAMAGE_CONFIGURED',n)
