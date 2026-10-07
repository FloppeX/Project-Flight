"""Read-only source analysis; writes private review excerpts beside this script."""
from pathlib import Path
import json, subprocess, concurrent.futures, math, wave, sys
import numpy as np

OUT=Path(__file__).resolve().parent
PROJECT=OUT.parents[1]
FF=next(Path('C:/Users/jonto/AppData/Local/Microsoft/WinGet/Packages').glob('Gyan.FFmpeg*/ffmpeg*/bin/ffmpeg.exe'))
PROBE=FF.with_name('ffprobe.exe')
paths=[Path(p) for p in (OUT/'all_paths.txt').read_text(encoding='utf-8-sig').splitlines() if Path(p).suffix.lower() in {'.wav','.ogg','.mp3','.aif','.aiff'}]
paths=[p if p.is_absolute() else PROJECT/p for p in paths]
specs=[]
def add(label,match,role,kind,note,exclude=''):
    found=[p for p in paths if match.lower() in str(p).lower() and (not exclude or exclude.lower() not in str(p).lower())]
    if len(found)!=1: raise ValueError((match,len(found),[str(p) for p in found]))
    specs.append(dict(id=f'S{len(specs)+1:02}',label=label,path=str(found[0]),role=role,kind=kind,note=note))

add('Electric motorcycle drivetrain','VEHElec_Electric Motorcycle','Electric engines','loop','Strong source hypothesis for loaded motor whine and acceleration; motorcycle road/tire contamination must be checked.')
add('Long electric motor','3maze - Electric Motors\\motor_long_006.wav','Electric engines','loop','Electric motor identity is explicit in the pack; extract steady power regions, retain acceleration separately.')
add('Medium electric motor','3maze - Electric Motors\\motor_med_011.wav','Electric engines','loop','Alternate motor character for lighter aircraft or robots; recording may contain several gestures.')
add('Rotator motor','3maze - Electric Motors\\rotator_motor_005.wav','Electric engines','loop','Candidate gearbox/rotating mechanism layer; check for recognizable appliance character.')
add('Isolated electric mower','Electric_Mower_Engine_Isolated_running','Electric engines','loop','Useful electric motor plus blade interaction source; needs processing to avoid sounding like garden equipment.')
add('Kia electric drive','Kia Niro Hybrid - t11','Electric engines','loop','Explicitly labeled ELECTRIC; candidate heavy drivetrain, but road noise is not clean aircraft propulsion.')
add('Electromagnetic rotary tool','Electrical motor - Rotary tool - Steadies','Electric engines','loop','Pickup recording is a designed inverter/harmonic layer, not airborne motor sound; blend quietly.')
add('Smooth propeller exterior','S019C-Aircraft\\Mono\\PropSmoothExt.wav','Propellers and rotors','loop','Compare with the current shared prop recording; useful aerodynamic bed if no combustion character survives.')
add('Low smooth propeller','S019C-Aircraft\\Mono\\PropSmoothLow.wav','Propellers and rotors','loop','Candidate low-RPM or heavy-prop layer; needs consistent RPM transitions.')
add('Slow prop hummer','S019C-Aircraft\\Mono\\PropHummerSlow.wav','Propellers and rotors','loop','Alternative blade-pulse texture; separate it from the electrical tone.')
add('Propeller clatter','S019C-Aircraft\\Mono\\PropClatter.wav','Propellers and rotors','loop','Possible rough/old airframe or damaged-prop accent; not automatically a clean electrical motor.')
add('Helicopter blade loop','helicopter_blades_spinning_loop_01.wav','Propellers and rotors','loop','Alternative blade texture to distinguish the light helicopters from the common Helicopter3 set.')
add('Helicopter interior medium','S019C-Aircraft\\Mono\\Helicopter3MedInt.wav','Propellers and rotors','loop','Interior counterpart to the exterior set; compare with existing filtering before adding another full-volume layer.')
add('Current fixed-wing engine','Audio\\engine\\fixed_wing\\airplane_propeller 3.wav','Current game comparison','loop','Current common fixed-wing loop. Baseline only; file name does not establish an electric motor source.','D:\\Game audio')
add('Current helicopter medium','Project-Flight\\Audio\\engine\\helicopter\\Helicopter3MedExt.wav','Current game comparison','loop','Current medium rotor layer shared by six authored helicopters.')
add('Ventilation fan','background_air_vent_fan_loop_02.wav','Carrier and cockpit ambience','loop','Already contributes to both installed ventilation mixes; reuse source family for consistent room zoning.')
add('Interior room hum','background_room_interior_hum_loop_02.wav','Carrier and cockpit ambience','loop','Already in carrier interior mix; useful bridge/hangar base, not a distinct machine event.')
add('Electric hum','hum_motor_elec_neon_loop_03.wav','Carrier and cockpit ambience','loop','Alternative electrical room layer; avoid stationary mains hum as the entire aircraft engine.')
add('Lighthouse motor room','MOTOR Electric Lighthouse, 4th Floor','Carrier and cockpit ambience','loop','Long real electrical machinery ambience; promising large carrier machinery room bed.')
add('Current deck ambience','Project-Flight\\Audio\\Carrier\\carrier_deck_sound_mono.wav','Current game comparison','loop','Installed deck bed; compare level and spectral masking against wind and deck machinery.')
add('Gusty deck wind','wind_general_gusty_low_loop_02.wav','Wind and weather','loop','Candidate outdoor deck wind layer; driven by relative wind and shelter, not permanent maximum volume.')
add('Strong gust wind','wind_general_gusty_high_loop_02.wav','Wind and weather','loop','Higher exposure/storm layer; needs crossfade against calm wind.')
add('Aircraft wind','S019C-Aircraft\\Mono\\AircraftWind.wav','Wind and weather','loop','Alternative speed-dependent external air rush; keep cockpit and exposed deck perspectives distinct.')
add('Elevator loop 1','elevator_loop_01.wav','Elevators and locks','loop','Candidate dedicated lift travel layer; compare to existing elevator motor instead of assuming a missing file.')
add('Elevator loop 2','elevator_loop_02.wav','Elevators and locks','loop','Alternative motor for island lift versus heavy deck lift.')
add('Interior heavy mechanism','Vehicles Heavy\\Mechanisms\\Interior Mechanism Moving Loop.wav','Elevators and locks','loop','Candidate hangar/deck cover travel layer; keep independent from platform motor.')
add('Heavy mechanism movement','Vehicles Heavy\\Mechanisms\\Heavy Mechanism Move A.wav','Elevators and locks','event','Potential start/stop mechanical body; trim individual events before reuse.')
add('Gate bolt latch','Exterior Metal Door Gate Bolt Latch 7.wav','Elevators and locks','event','Good literal source for the missing elevator locking pin; may need body impact layering for scale.')
add('Barrel bolt handling','Metal_Barrel_Bolt_Lock_Loose_Handling_03.wav','Elevators and locks','event','Alternative bolt/ratchet detail; isolate clean lock and release gestures.')
add('Current elevator motor','Project-Flight\\Audio\\Carrier\\elevator_moving_mono.wav','Current game comparison','loop','Installed on deck and island lifts; technical validity does not establish audibility in play.')
add('Tank tread A','Vehicles Heavy\\Tank\\Tank Tread Loop A.wav','Tracks and ground contact','loop','Existing track_links.ogg source; first choice for consistency, with independent left/right speeds.')
add('Tank tread B','Vehicles Heavy\\Tank\\Tank Tread Loop B.wav','Tracks and ground contact','loop','Alternative clatter layer for load, turns or terrain variation; compare repetition with A.')
add('Tank tread event','Vehicles Heavy\\Tank\\Tank Tread.wav','Tracks and ground contact','event','Possible engagement/stop punctuation; use selected transient, not the entire recording.')
add('Current track derivative','Project-Flight\\Audio\\Carrier\\track_links.ogg','Current game comparison','loop','Installed filtered mono loop derived from Tank Tread Loop A.')
add('Deep metal scrape','metal_scrape_deep_grind_squeak_03.wav','Damage and crash landing','loop','Belly-slide abrasive layer; finite gesture may need granular assembly/crossfades rather than whole-file looping.')
add('Metal drag into smash','EFX INT Metal Drag Slide Fast In Smash 02 A.wav','Damage and crash landing','event','Separate scrape body from final impact; useful crash start/end but not directly a sustained loop.')
add('Screeching metal friction','METLFric_Screeching Metal Rub-11','Damage and crash landing','event','Promising deformation/part-tear accent; a friction recording alone is not a complete wing break.')
add('Metal debris fall','METLCrsh_Drop Fall Metal Rattle Scrap Debris_06','Damage and crash landing','event','Candidate secondary debris hits after breakaway or touchdown; randomize distinct events.')
add('Sheet metal crash','Metal,Crash,Concrete,Sheet Metal,20 Gauge,Slow,Complex.wav','Damage and crash landing','event','Possible tearing/crumpling body layer; inspect for heavy reverb and multiple impacts.')
add('Chassis drop and bounce','Car_Destruction_Chassis_Impact_t36','Damage and crash landing','event','Heavy airframe impact candidate; extract a single impact plus debris tail.')
add('Gravel slide','footstep_gravel_slide_06.wav','Damage and crash landing','event','Small gritty texture only: layer many variations under a heavier crash, not a full aircraft slide.')
add('Concrete scrape','Electric_Mower_moving_over_concrete_dragging','Damage and crash landing','loop','Useful dry abrasive source; deliberately a motor-off movement recording by filename, still needs listening.')
add('Metal rattle','METLMvmt_Metal Rattle 11_JSE','Damage and crash landing','event','Loose-panel/cockpit rattle or post-impact debris; avoid repetitive per-frame retriggering.')
add('Electric spark texture','hum_electric_sparks_interference_loop_01.wav','Damage and crash landing','loop','Damage arcing layer for disabled motor/battery systems; only while the corresponding damage state exists.')
add('Touchdown impact','S019C-Aircraft\\Mono\\Touchdown.wav','Damage and crash landing','event','Candidate normal landing thump before constructing violent crash variants.')
add('Robot servo','ROBTMvmt_Robot Servo 02','Deck operations and machinery','event','Recovery robot arm/clamp or harvester articulation; isolate gestures and match motion duration.')
add('Machine wind-down','MECHMisc_Sci Fi Wind Downs Servo Motor Stop','Deck operations and machinery','event','Motor spin-down/braking source; processing may sound stylized.')
add('3D printer heavy servo','3DPrinter.Heavy.Servo.Sequence1.wav','Deck operations and machinery','event','Replicator arm source; sequence should be divided into motion-synchronized pieces.')
add('Motorized hatch','S019C-Aircraft\\Mono\\OpenMotorisedHatch.wav','Deck operations and machinery','event','Aircraft canopy/vehicle bay/elevator cover candidate; use different scale and filtering by object.')
add('Ejection event','S019C-Aircraft\\Mono\\Eject.wav','Warnings and interactions','event','Candidate ejection transient; add distinct canopy, seat and parachute stages.')
add('Cockpit alarm','S019C-Aircraft\\Mono\\CockpitAlarm1.wav','Warnings and interactions','event','Possible critical warning; assign a single meaning and priority, avoid generic continuous alarm spam.')
add('Target lock','S019C-Aircraft\\Mono\\HUDTargetLock.wav','Warnings and interactions','event','Candidate only for targeting states actually modeled in the game; do not imply a sensor capability.')

(OUT/'candidate_selection.json').write_text(json.dumps(specs,indent=2),encoding='utf-8')
(OUT/'previews').mkdir(exist_ok=True)
RATE=24000
def db(x): return round(20*math.log10(max(float(x),1e-12)),2)
def decode(path,start,duration):
    raw=subprocess.check_output([str(FF),'-v','error','-ss',str(start),'-i',path,'-t',str(duration),'-ac','2','-ar',str(RATE),'-f','f32le','pipe:1'])
    return np.frombuffer(raw,dtype='<f4').reshape(-1,2).copy()
def analyse(s):
    meta=json.loads(subprocess.check_output([str(PROBE),'-v','error','-show_streams','-show_format','-of','json',s['path']]))
    stream=next(z for z in meta['streams'] if z['codec_type']=='audio')
    duration=float(meta['format']['duration'])
    starts=[0.] if duration<=36 else [0.,duration*.35,duration*.7]
    windows=[]
    for start in starts:
        a=decode(s['path'],start,min(36 if len(starts)==1 else 16,duration-start))
        if not len(a):continue
        windows.append((start,a))
    if not windows:raise ValueError('no decoded samples')
    # Select an energetic event window, or the steadiest audible eight-second loop source region.
    choices=[]
    for start,a in windows:
        size=min(len(a),int((8 if s['kind']=='loop' else 10)*RATE))
        for offset in range(0,max(1,len(a)-size+1),RATE//2):
            b=a[offset:offset+size]
            n=(len(b)//1200)*1200
            env=np.sqrt(np.mean(b[:n].reshape(-1,1200,2)**2,axis=(1,2))) if n else np.array([0.])
            rms=float(np.sqrt(np.mean(b*b)))
            score=-(float(np.std(env))/max(float(np.mean(env)),1e-9)) if s['kind']=='loop' else rms
            if rms<.001:score-=100
            choices.append((score,start+offset/RATE,b))
    _,start,x=max(choices,key=lambda z:z[0])
    mono=x.mean(axis=1); rms=float(np.sqrt(np.mean(x*x))); peak=float(np.max(np.abs(x)))
    n=(len(x)//1200)*1200
    env=np.sqrt(np.mean(x[:n].reshape(-1,1200,2)**2,axis=(1,2)))
    fftn=4096
    frames=np.lib.stride_tricks.sliding_window_view(mono,fftn)[::2048] if len(mono)>=fftn else mono[None,:]
    power=np.mean(np.abs(np.fft.rfft(frames*np.hanning(frames.shape[1]),axis=1))**2,axis=0)
    freq=np.fft.rfftfreq(frames.shape[1],1/RATE)
    bands={name:round(float(power[(freq>=lo)&(freq<hi)].sum()/max(power.sum(),1e-12)*100),1) for name,lo,hi in [('below_20',0,20),('low_20_200',20,200),('mid_200_2000',200,2000),('high_2000_12000',2000,12001)]}
    corr=float(np.corrcoef(x.T)[0,1]) if np.std(x[:,0])>1e-8 and np.std(x[:,1])>1e-8 else 1.
    full=(len(starts)==1)
    allx=np.concatenate([a for _,a in windows])
    active_env=env[env>.0001]
    dynamic=db(np.percentile(active_env,95)/max(np.percentile(active_env,10),1e-9)) if len(active_env) else 0
    metrics=dict(duration_s=round(duration,3),rate=int(stream['sample_rate']),channels=stream['channels'],codec=stream['codec_name'],bits=stream.get('bits_per_raw_sample',stream.get('bits_per_sample')),bytes=Path(s['path']).stat().st_size,
        analyzed_windows=[dict(start_s=round(t,3),duration_s=round(len(a)/RATE,3)) for t,a in windows],full_source_decoded=full,
        excerpt_start_s=round(start,3),excerpt_duration_s=round(len(x)/RATE,3),excerpt_rms_dbfs=db(rms),excerpt_peak_dbfs=db(peak),crest_db=db(peak/max(rms,1e-12)),
        excerpt_envelope_spread_db=dynamic,dc_offset=round(float(abs(x.mean())),6),near_full_scale_pct=round(float(np.mean(np.abs(allx)>=.999)*100),5),stereo_correlation=round(corr,3),mono_fold_change_db=db(np.sqrt(np.mean(mono*mono))/max(rms,1e-9)),energy_percent=bands,
        raw_excerpt_endpoint_step=round(float(np.max(np.abs(x[-1]-x[0]))),5))
    flags=[]
    if metrics['dc_offset']>.01:flags.append('Substantial DC offset in the excerpt: remove DC / high-pass before production use.')
    if bands['below_20']>20:flags.append('More than 20% of measured spectral power is below 20 Hz (including DC); inspect before boosting level.')
    if s['kind']=='loop' and dynamic>12:flags.append('Large level variation: isolate a steadier segment or use as a transition.')
    if s['kind']=='loop' and duration<4:flags.append('Short source: repetition risk for sustained playback.')
    if metrics['near_full_scale_pct']>.01:flags.append('Near-full-scale samples detected in analyzed windows; inspect for clipping.')
    if corr<0:flags.append('Negative stereo correlation; check mono conversion before positional use.')
    if metrics['mono_fold_change_db'] < -6:flags.append('Substantial mono fold-down loss; choose channel or repair phase.')
    if s['kind']=='loop':flags.append('Excerpt is not a finished seamless loop; edit boundaries and audition several repetitions.')
    if not full:flags.append('Only three source windows decoded; unexamined sections may contain other material.')
    gain=min(12.,-4-db(peak))
    preview=x*10**(gain/20)
    fade=min(240,len(preview)//4)
    preview[:fade]*=np.linspace(0,1,fade)[:,None];preview[-fade:]*=np.linspace(1,0,fade)[:,None]
    dest=OUT/'previews'/f"{s['id']}.mp3"
    subprocess.run([str(FF),'-v','error','-y','-f','f32le','-ar',str(RATE),'-ac','2','-i','pipe:0','-c:a','libmp3lame','-b:a','160k',str(dest)],input=preview.astype('<f4').tobytes(),check=True)
    return dict(**s,**metrics,flags=flags,preview=f'previews/{s["id"]}.mp3',preview_gain_db=round(gain,2),analysis_basis='Filename/context plus decoded signal analysis; not perceptually auditioned')

requested=set(sys.argv[1:])
results=json.loads((OUT/'candidate_analysis.json').read_text()) if requested else []
work=[s for s in specs if not requested or s['id'] in requested]
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    for s,r in zip(work,pool.map(analyse,work)):
        results=[x for x in results if x['id']!=r['id']]+[r]
        results.sort(key=lambda x:x['id'])
        print(r['id'],r['label'],r['duration_s'],'s',r['excerpt_rms_dbfs'],'dBFS',flush=True)
        (OUT/'candidate_analysis.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
print('ANALYZED',len(results),flush=True)
