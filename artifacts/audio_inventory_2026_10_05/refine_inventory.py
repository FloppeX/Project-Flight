from pathlib import Path
import json, collections, re
OUT=Path(__file__).resolve().parent
PROJECT=OUT.parents[1]
inv=json.loads((OUT/'inventory.json').read_text(encoding='utf-8'))
refs=json.loads((OUT/'references.json').read_text(encoding='utf-8'))
summary=json.loads((OUT/'scan_summary.json').read_text(encoding='utf-8'))
refs={k:[r for r in v if not r['file'].startswith('addons/.godot_ai_update/')] for k,v in refs.items() if k.startswith('res://Audio/')}
refs={k:v for k,v in refs.items() if v}
patterns={k:v for k,v in refs.items() if '%' in k}
for pattern,locations in patterns.items():
    # Verified range(1, 9) in ProjectileNew._ensure_sounds_loaded.
    if pattern.startswith('res://Audio/impacts/') and '%02d' in pattern:
        for index in range(1,9):refs.setdefault(pattern % index,[]).extend([dict(r,dynamic_pattern=pattern) for r in locations])
for row in inv:
    if row['root']!=str(PROJECT/'Audio'):continue
    key='res://Audio/'+row['relative'].replace('\\','/')
    row['references']=refs.get(key,[])
    if row['relative'].startswith('Voices\\SourcePacks\\'):row['reference_status']='Archived voice source'
    elif row['relative'].startswith(('Voices\\Citadel\\','Voices\\Pilots\\')):row['reference_status']='Runtime voice folder (dynamic discovery)'
    elif any(not r['test'] for r in row['references']):row['reference_status']='Code/scene reference (audibility unverified)'
    elif row['references']:row['reference_status']='Tests/tools references only'
    else:row['reference_status']='No literal reference found (not proof unused)'
summary['missing_references']=[dict(path=k,references=v,metadata_only=all('metadata/__load_path__' in r['text'] for r in v)) for k,v in refs.items() if '%' not in k and not (PROJECT/k.replace('res://','')).exists()]
summary['dynamic_patterns']=[dict(path=k,references=v) for k,v in patterns.items()]
summary['scope']='Recursive scan of D:/Game audio, D:/Downloads/Soniss, and Project-Flight/Audio. Not a forensic scan of every drive/archive/cloud folder. No content hashing or deduplication; mono/stereo versions count separately.'
fleet=[]
for i in range(1,17):
    p=PROJECT/'Aircraft'/f'Aircraft_{i}.tscn'
    if not p.exists():continue
    t=p.read_text(encoding='utf-8-sig')
    resources={m[1]:m[0] for m in re.findall(r'\[ext_resource [^\n]*path="([^"]+)" id="([^"]+)"\]',t)}
    row=dict(aircraft=i,scene=str(p.relative_to(PROJECT)),assignments={})
    for field in ['EngineSoundLoop','EngineSoundStart','EngineSoundStop','rotor_audio_slow_stream','rotor_audio_medium_stream','rotor_audio_fast_stream','cockpit_interior_sound','FlapSoundLoop']:
        m=re.search(r'^'+field+r' = (.+)$',t,re.M)
        if m:
            val=m[1]; ext=re.search(r'ExtResource\("([^"]+)"\)',val)
            row['assignments'][field]=resources.get(ext[1],val) if ext else val
    fleet.append(row)
for name,data in [('inventory.json',inv),('references.json',refs),('scan_summary.json',summary),('fleet_audio.json',fleet)]:
    (OUT/name).write_text(json.dumps(data,indent=2,ensure_ascii=False),encoding='utf-8')
project=[r for r in inv if r['root']==str(PROJECT/'Audio')]
print('Project statuses',dict(collections.Counter(r['reference_status'] for r in project)))
print('Source packs',dict(collections.Counter(r['pack'] for r in inv if r['root']=='D:\\Game audio')))
print('Fixed wing loops',dict(collections.Counter(r['assignments'].get('EngineSoundLoop') for r in fleet)))
print('Source sizes: GB decimal / GiB binary',sum(r['bytes'] for r in inv if r['root']!=str(PROJECT/'Audio'))/1e9,sum(r['bytes'] for r in inv if r['root']!=str(PROJECT/'Audio'))/2**30)
