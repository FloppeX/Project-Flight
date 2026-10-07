from pathlib import Path
import json, wave, collections, math
import numpy as np

OUT=Path(__file__).resolve().parent
LIB=Path('D:/Game audio')
rows=[]
for name in ['Helicopter Engine Sounds','Universal Sound FX']:
    root=LIB/name
    for p in sorted(root.rglob('*.wav')):
        row=dict(path=str(p),pack=name,category=p.relative_to(root).parts[0] if name=='Universal Sound FX' else p.stem.split('_')[1],bytes=p.stat().st_size)
        if name=='Helicopter Engine Sounds':
            with wave.open(str(p),'rb') as w:
                row.update(rate=w.getframerate(),channels=w.getnchannels(),bits=w.getsampwidth()*8,duration_s=w.getnframes()/w.getframerate())
                if '_loop_' in p.name:
                    assert w.getsampwidth()==2
                    x=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.float32).reshape(-1,w.getnchannels())/32768
                    mono=x.mean(axis=1);n=4096
                    frames=np.lib.stride_tricks.sliding_window_view(mono,n)[::2048]
                    power=np.mean(abs(np.fft.rfft(frames*np.hanning(n),axis=1))**2,axis=0)
                    freq=np.fft.rfftfreq(n,1/w.getframerate());total=max(power.sum(),1e-12)
                    rms=float(np.sqrt(np.mean(x*x)));peak=float(np.max(abs(x)))
                    env=np.sqrt(np.mean(mono[:len(mono)//441*441].reshape(-1,441)**2,axis=1))
                    mod=abs(np.fft.rfft(env-env.mean()))**2;hz=np.fft.rfftfreq(len(env),.01);valid=(hz>=4)&(hz<40)
                    pulse=float(hz[valid][np.argmax(mod[valid])])
                    row.update(rms_db=round(20*math.log10(max(rms,1e-12)),2),peak_db=round(20*math.log10(max(peak,1e-12)),2),low_pct=round(float(power[(freq>=20)&(freq<200)].sum()/total*100),1),centroid_hz=round(float((power*freq).sum()/total)),pulse_hz=round(pulse,2),dc=round(float(abs(x.mean())),6),mono_loss_db=round(20*math.log10(max(float(np.sqrt(np.mean(mono*mono))),1e-12)/max(rms,1e-12)),2),endpoint_step=round(float(np.max(abs(x[-1]-x[0]))),5))
        rows.append(row)
(OUT/'new_packs_inventory.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
for name in ['Helicopter Engine Sounds','Universal Sound FX']:
    items=[r for r in rows if r['pack']==name]
    print(name,len(items),'files',round(sum(r['bytes'] for r in items)/1e9,3),'GB',flush=True)
    if name=='Universal Sound FX':print('CATEGORIES',json.dumps(dict(collections.Counter(r['category'] for r in items))),flush=True)
for letter in 'abcdefgh':
    items=[r for r in rows if r['pack']=='Helicopter Engine Sounds' and r['category']==letter and 'rms_db' in r]
    print(letter,[(Path(r['path']).stem[-2:],round(r['duration_s'],2),r['rms_db'],r['low_pct'],r['centroid_hz'],r['pulse_hz'],r['mono_loss_db']) for r in items],flush=True)
