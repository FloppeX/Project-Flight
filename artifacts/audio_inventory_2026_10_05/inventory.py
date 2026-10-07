from pathlib import Path
import json, os, re, collections, wave

OUT = Path(__file__).resolve().parent
PROJECT = OUT.parents[1]
ROOTS = [Path('D:/Game audio'), Path('D:/Downloads/Soniss'), PROJECT/'Audio']
EXTS = {'.wav','.ogg','.mp3','.aif','.aiff','.flac','.m4a','.opus','.wma'}
inventory=[]
errors=[]
for root in ROOTS:
    for directory, dirs, files in os.walk(root, onerror=lambda e: errors.append(str(e))):
        for name in files:
            p=Path(directory)/name
            if p.suffix.lower() not in EXTS: continue
            try:
                rel=p.relative_to(root)
                pack=str(rel.parts[0]) if root.name != 'Soniss' else '/'.join(rel.parts[:2])
                row=dict(path=str(p),root=str(root),relative=str(rel),pack=pack,bytes=p.stat().st_size,extension=p.suffix.lower())
                if p.suffix.lower()=='.wav':
                    try:
                        with wave.open(str(p),'rb') as w:
                            row.update(duration_s=round(w.getnframes()/w.getframerate(),3),rate=w.getframerate(),channels=w.getnchannels(),bits=w.getsampwidth()*8)
                    except Exception: pass
                inventory.append(row)
            except OSError as e: errors.append(str(e))
refs=collections.defaultdict(list)
hooks=[]
for directory, dirs, files in os.walk(PROJECT):
    dirs[:]=[d for d in dirs if d not in {'.git','.godot','Archive','artifacts','run_archives','logs','captures','screenshots','tmp','art_work','node_modules'}]
    for name in files:
        p=Path(directory)/name
        if p.suffix not in {'.gd','.tscn','.tres','.godot'}: continue
        rel=str(p.relative_to(PROJECT)).replace('\\','/')
        if rel.startswith(('addons/godot_ai/','addons/terrain_3d/')): continue
        text=p.read_text(encoding='utf-8-sig',errors='replace')
        for n,line in enumerate(text.splitlines(),1):
            for asset in re.findall(r'res://[^"\n]+?\.(?:wav|ogg|mp3|aiff|aif|flac)',line,re.I):
                refs[asset].append(dict(file=rel,line=n,text=line.strip(),test=rel.startswith(('Tests/','tools/'))))
            if re.search(r'AudioStreamPlayer|AudioStream\b|_play_\w*sound',line):
                hooks.append(dict(file=rel,line=n,text=line.strip()))
for row in inventory:
    if row['root']==str(PROJECT/'Audio'):
        key='res://Audio/'+row['relative'].replace('\\','/')
        row['references']=refs.get(key,[])
        if row['relative'].startswith('Voices\\SourcePacks\\'): row['reference_status']='Archived voice source'
        elif row['relative'].startswith(('Voices\\Citadel\\','Voices\\Pilots\\')): row['reference_status']='Runtime voice folder (dynamic discovery)'
        elif any(not r['test'] for r in row['references']): row['reference_status']='Code/scene reference (audibility unverified)'
        elif row['references']: row['reference_status']='Tests/tools references only'
        else: row['reference_status']='No literal reference found (not proof unused)'
missing=[dict(path=k,references=v) for k,v in refs.items() if not (PROJECT/k.replace('res://','')).exists()]
summary=[]
for root in ROOTS:
    rows=[r for r in inventory if r['root']==str(root)]
    summary.append(dict(root=str(root),files=len(rows),bytes=sum(r['bytes'] for r in rows),wav_metadata=len([r for r in rows if 'duration_s' in r])))
for name,data in [('inventory.json',inventory),('references.json',refs),('hooks.json',hooks),('scan_summary.json',dict(roots=summary,errors=errors,missing_references=missing))]:
    (OUT/name).write_text(json.dumps(data,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(dict(roots=summary,errors=errors,missing_references=missing),indent=2))
print('PROJECT AUDIO CATEGORIES')
print(json.dumps(dict(collections.Counter(r['pack'] for r in inventory if r['root']==str(PROJECT/'Audio'))),indent=2))
