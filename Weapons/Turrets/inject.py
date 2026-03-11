import re
import os

SCENES = [
    r'c:\Godot projects\Project-Flight\GroundVehicle\vehicle_friendly_light.tscn',
    r'c:\Godot projects\Project-Flight\GroundVehicle\GroundVehicle.tscn',
    r'c:\Godot projects\Project-Flight\Enemies\EnemyAircraft.tscn' 
]

for path in SCENES:
    try:
        if not os.path.exists(path):
            print(f'Skipping {path}, file not found.')
            continue
            
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        if 'TurretController' in content:
            print(f'Skipping {path}, TurretController already present.')
            continue
            
        lines = content.split('\n')
        
        highest_id = 0
        ext_idx = 0
        for i, line in enumerate(lines):
            if line.startswith('[ext_resource'):
                ext_idx = i
                match = re.search(r'id="(\d+)_?[^"]*"', line)
                if match:
                    val = int(match.group(1))
                    if val > highest_id:
                        highest_id = val
            if line.startswith('[node') or line.startswith('[sub_resource'):
                if ext_idx == 0:
                    ext_idx = i - 1
                break
                
        turret_ctrl_id = f'{highest_id+1}_tctrl'
        turret_scene_id = f'{highest_id+2}_tscn'
        bullet_wpn_id = f'{highest_id+3}_bwpn'
        
        resources_to_insert = f'''[ext_resource type="Script" path="res://Weapons/Turrets/turret_controller.gd" id="{turret_ctrl_id}"]
[ext_resource type="PackedScene" uid="uid://turret_custom_id123" path="res://Weapons/Turrets/turret.tscn" id="{turret_scene_id}"]
[ext_resource type="PackedScene" uid="uid://bullet_weapon_id123" path="res://Weapons/Turrets/bullet_weapon.tscn" id="{bullet_wpn_id}"]'''
        
        lines.insert(ext_idx + 1, resources_to_insert)
        
        content_new = '\n'.join(lines)
        
        nodes_to_append = f'''
[node name="TurretController" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.0, 0)
script = ExtResource("{turret_ctrl_id}")
weapon_scene = ExtResource("{bullet_wpn_id}")

[node name="TurretScene" parent="TurretController" instance=ExtResource("{turret_scene_id}")]
'''
        content_new += nodes_to_append
        
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content_new)
            
        print(f'Successfully injected TurretController into {path}')
    except Exception as e:
        print(f'Failed {path}: {e}')
