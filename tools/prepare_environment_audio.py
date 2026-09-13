"""Prepare compact game derivatives; source packs remain untouched.

Requires numpy and ffmpeg. Provenance and technical metrics are written alongside
the outputs. Candidate timbre/final mix still requires listening review.
"""
from pathlib import Path
import json, shutil, subprocess, tempfile, wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path('D:/Game audio')
GM = SOURCE / 'Gamemaster Audio - Pro Sound Collection v1.3 - 16bit 48k'
FFMPEG = next(Path('C:/Users/jonto/AppData/Local/Microsoft/WinGet/Packages').glob('Gyan.FFmpeg*/ffmpeg*/bin/ffmpeg.exe'))
RATE = 48000
records = []

def find(name):
    return next(SOURCE.rglob(name))

def read(path, channels, filters):
    command = [str(FFMPEG), '-v', 'error', '-i', str(path), '-ac', str(channels), '-ar', str(RATE)]
    if filters:
        command += ['-af', filters]
    raw = subprocess.check_output(command + ['-f', 'f32le', 'pipe:1'])
    return np.frombuffer(raw, dtype='<f4').reshape(-1, channels).copy()

def loop_seam(x):
    n = min(int(.15 * RATE), len(x)//8)
    t = np.linspace(0, 1, n, dtype=np.float32)[:, None]
    # Cycle: middle -> blend tail into head -> middle. Endpoint slopes preserved.
    return np.concatenate([x[n:-n], x[-n:]*(1-t) + x[:n]*t])

def prepare(destination, sources, loop=False, channels=1, rms_db=-22, filters=''):
    arrays=[]
    for name, weight in sources:
        x=read(find(name),channels,filters)
        if loop:x=loop_seam(x)
        x *= 10**(rms_db/20)/max(float(np.sqrt(np.mean(x*x))),1e-8)
        arrays.append(x*weight)
    size=max(len(a) for a in arrays)
    x=sum(np.tile(a,(int(np.ceil(size/len(a))),1))[:size] for a in arrays)
    if len(arrays)>1 and loop:x=loop_seam(x)
    if not loop:
        # Preserve the attack, remove excessive leading silence, fade the tail.
        active=np.where(np.max(np.abs(x),axis=1)>0.001)[0]
        if len(active):x=x[max(0,int(active[0]) - 96):min(len(x),int(active[-1])+480)]
        n=min(240,len(x)//4)
        x[:48] *= np.linspace(0,1,48)[:,None]
        x[-n:] *= np.linspace(1,0,n)[:,None]
    peak=float(np.max(np.abs(x)))
    if peak>0.7:x *= .7/peak
    path=ROOT/'Audio'/destination
    path.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        wav=Path(directory)/'prepared.wav'
        with wave.open(str(wav),'wb') as w:
            w.setnchannels(channels);w.setsampwidth(2);w.setframerate(RATE)
            w.writeframes((x*32767).astype('<i2').tobytes())
        if path.suffix=='.ogg':
            subprocess.run([str(FFMPEG),'-v','error','-y','-i',str(wav),'-c:a','libvorbis','-q:a','5',str(path)],check=True)
        else:shutil.copyfile(wav,path)
    records.append(dict(file=str(path.relative_to(ROOT)),sources=[str(find(n)) for n,_ in sources],
        loop=loop,channels=channels,seconds=round(len(x)/RATE,3),rms_db=round(float(20*np.log10(np.sqrt(np.mean(x*x)))),2),
        peak_db=round(float(20*np.log10(np.max(np.abs(x)))),2),bytes=path.stat().st_size,
        loop_endpoint_delta=round(float(np.max(np.abs(x[-1]-x[0]))),6) if loop else None,
        processing=filters,review='Technically checked; subjective listening review pending'))

prepare('Carrier/track_links.ogg',[('Tank Tread Loop A.wav',1)],True,filters='highpass=f=90,lowpass=f=5000')
prepare('Carrier/interior_ventilation.ogg',[('background_room_interior_hum_loop_02.wav',.65),('background_air_vent_fan_loop_02.wav',.35)],True,2,filters='highpass=f=70,lowpass=f=4500')
prepare('cockpit/cabin_systems.ogg',[('background_air_vent_fan_loop_02.wav',.65),('hum_motor_elec_neon_loop_02.wav',.18)],True,2,filters='highpass=f=100,lowpass=f=3800')
prepare('mechanisms/electric_servo.ogg',[('Mechanism Turning Loop.wav',1)],True,filters='highpass=f=150,lowpass=f=4500')
prepare('mechanisms/door_slide.wav',[('hydraulic_strut_air_gas_shock_door_02.wav',1)],filters='highpass=f=140,lowpass=f=6000')
for i in range(1,9):
    prepare(f'footsteps/metal_{i:02}.wav',[(f'footstep_metal_low_walk_{i:02}.wav',1)],rms_db=-18,filters='highpass=f=90,lowpass=f=6500')
prepare('UI/click.wav',[('ui_button_simple_click_02.wav',1)],rms_db=-22)
prepare('UI/confirm.wav',[('ui_menu_button_beep_03.wav',1)],rms_db=-24)
prepare('UI/cancel.wav',[('ui_menu_button_cancel_01.wav',1)],rms_db=-24)
(ROOT/'Audio/environment_audio_sources.json').write_text(json.dumps(records,indent=2)+'\n')
print('AUDIO_PREPARED',len(records),'assets',sum(r['bytes'] for r in records),'bytes')
