"""Prepare local helicopter bank derivatives and private comparison clips.

One gain per family preserves the five source speeds' relative levels. Originals
are never changed. Requires numpy and the installed FFmpeg; no network access.
"""
from pathlib import Path
import json, math, subprocess, hashlib, wave, argparse
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
SOURCE=Path('D:/Game audio/Helicopter Engine Sounds')
REVIEW=ROOT/'artifacts/audio_inventory_2026_10_05/helicopter_update_2026_10_06'
FF=Path('C:/Users/jonto/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.1-full_build/bin/ffmpeg.exe')
RATE=48000
PROFILES={9:'b',10:'f',11:'a',12:'c',13:'d',15:'g'}
NAMES={9:'Bumblebee',10:'Dune Skimmer',11:'Hummingbird',12:'Huntsman',13:'Dragonfly',15:'Medium attack'}

def db(x):return round(20*math.log10(max(float(x),1e-12)),3)
def decode(path):
    b=subprocess.check_output([str(FF),'-v','error','-i',str(path),'-ac','1','-ar',str(RATE),'-af','highpass=f=30','-f','f32le','pipe:1'])
    return np.frombuffer(b,dtype='<f4').copy()
def loop_seam(x):
    n=int(.08*RATE)
    # Middle -> smooth overlap of tail and head -> middle on the next cycle.
    t=np.linspace(0,1,n,dtype=np.float32);t=t*t*(3-2*t)
    return np.concatenate([x[n:-n],x[-n:]*(1-t)+x[:n]*t])
def encode(x,path):
    path.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run([str(FF),'-v','error','-y','-f','f32le','-ar',str(RATE),'-ac','1','-i','pipe:0','-c:a','libvorbis','-q:a','5',str(path)],input=x.astype('<f4').tobytes(),check=True)

def prepare():
    REVIEW.mkdir(parents=True,exist_ok=True)
    manifest=[];banks={}
    for letter in 'abcdefgh':
        paths=[SOURCE/f'helicopter_{letter}_engine_loop_{i}x.wav' for i in range(5)]
        arrays=[loop_seam(decode(p)) for p in paths]
        gain=min(10**(-18/20)/float(np.sqrt(np.mean(arrays[4]**2))),.7/max(float(np.max(abs(a))) for a in arrays))
        aircraft=next((i for i,l in PROFILES.items() if l==letter),None)
        bank=[]
        for i,(p,x) in enumerate(zip(paths,arrays)):
            x=x*gain
            destination=ROOT/'Audio/engine/helicopter/profiles'/letter/f'rotor_{i}.ogg' if aircraft else REVIEW/'reserve_profiles'/letter/f'rotor_{i}.ogg'
            encode(x,destination)
            encoded=decode(destination)
            preview=REVIEW/'previews'/f'{letter}_{i}.ogg'
            encode(x[:8*RATE],preview)
            row=dict(family=letter,speed_label=f'{i}x',aircraft=aircraft,source=str(p),source_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),file=str(destination.relative_to(ROOT)).replace('\\','/'),preview=str(preview.relative_to(REVIEW)).replace('\\','/'),duration_s=len(x)/RATE,bytes=destination.stat().st_size,gain_db=db(gain),rms_dbfs=db(np.sqrt(np.mean(x*x))),peak_dbfs=db(np.max(abs(x))),decoded_peak_dbfs=db(np.max(abs(encoded))),endpoint_step=float(abs(encoded[-1]-encoded[0])),processing='48 kHz mono, 30 Hz high-pass, 80 ms smooth tail/head overlap, common family gain to -18 dBFS fast-loop RMS (peak cap -3.1 dBFS), Vorbis q5',review='Signal analyzed; subjective in-game balance still requires listening.')
            manifest.append(row);bank.append(x)
        banks[letter]=bank
        print('PREPARED',letter,'aircraft',aircraft,'gain',db(gain),flush=True)
    # Audition actual bank mix formula: 6s spool up, 5s running, 8s coast down.
    for letter,bank in banks.items():
        t=np.arange(19*RATE)/RATE
        rpm=np.where(t<6,t/6,np.where(t<11,1,1-(t-11)/8))
        position=np.clip((rpm-.05)/.95,0,1)*4
        envelope=10**((-24+30*np.sqrt(np.clip(rpm,0,1)))/20)
        mix=np.zeros(len(t),dtype=np.float32)
        low=np.floor(position).astype(int);alpha=position-low;alpha=alpha*alpha*(3-2*alpha)
        for index,x in enumerate(bank):
            weight=np.where(low==index,np.cos(alpha*np.pi/2),np.where(low+1==index,np.sin(alpha*np.pi/2),0))
            mix+=x[np.arange(len(t))%len(x)]*weight*envelope
        mix[rpm<=.01]=0
        encode(mix,REVIEW/'previews'/f'{letter}_spool.ogg')
    (ROOT/'Audio/helicopter_audio_sources.json').write_text(json.dumps(dict(profiles=PROFILES,files=manifest),indent=2)+'\n',encoding='utf-8')
    (REVIEW/'prepared_banks.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print('HELICOPTER_AUDIO_PREPARED',len(manifest),'loops; game',sum(r['bytes'] for r in manifest if r['aircraft'] is not None),'bytes',flush=True)

if __name__=='__main__':prepare()
