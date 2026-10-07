"""Build the local October 6 library update and audition page; no source edits."""
from pathlib import Path
import collections, html, json, math, wave
import numpy as np

BASE=Path(__file__).resolve().parent
OUT=BASE/'helicopter_update_2026_10_06'
ROOT=BASE.parents[1]
new=json.loads((BASE/'new_packs_inventory.json').read_text(encoding='utf-8'))
banks=json.loads((OUT/'prepared_banks.json').read_text(encoding='utf-8'))
old=json.loads((BASE/'inventory.json').read_text(encoding='utf-8'))
sources={r['path'].lower().replace('\\','/'):r for r in old if r['path'].lower().startswith('d:')}
sources.update({r['path'].lower().replace('\\','/'):r for r in new})
(OUT/'updated_source_inventory.json').write_text(json.dumps(list(sources.values()),indent=2),encoding='utf-8')

# Exact filename selections, matched only within this pack.
choices=[
('ELEVATOR_Movement_Loop_05_loop_mono.wav','Lift motion','Alternative motor bed; compare with the existing elevator motor in context.'),
('ELEVATOR_Construction_Site_Industrial_01_mono_loop.wav','Heavy lift motion','Candidate for the large deck lift; listen for repetitive cycle detail before adopting.'),
('LOCK_Metal_Sliding_02_Dark_Short_mono.wav','Elevator locking pin','Short end-stop/locking accent; trigger once after the platform settles.'),
('LOCK_Metal_Clasp_01_mono.wav','Latch engagement','Small restraint, access panel or rotor-fold latch; scale the event, not just loudness.'),
('COOLING_AC_Airconditioner_01_loop_mono.wav','Carrier ventilation','Alternative interior bed; compare with the ventilation already integrated.'),
('MOTOR_Smooth_01_loop_mono.wav','Electric motor layer','Candidate tonal layer beneath fixed-wing propeller recordings; separate motor tone from blade beat.'),
('MOTOR_Industrial_01_loop_mono.wav','Heavy electric machinery','Candidate for heavy vehicle or carrier equipment; filename does not establish propulsion type.'),
('GENERATOR_Whining_01_loop_mono.wav','Electrical load','Candidate charger or loaded actuator texture; assess whether it implies combustion before use.'),
('SCRAPE_Concrete_Slab_on_Concrete_Slab_Long_mono.wav','Crash landing ground slide','Grit component only; blend with metal contact and vary by speed/surface.'),
('SCRAPE_Metal_on_Metal_Cling_Long_mono.wav','Crash landing deck slide','Metal scrape candidate; contact-driven loop needs editing and smooth release.'),
('ELECTRICITY_Subtle_loop_mono.wav','Damaged electronics','Quiet intermittent fault layer; avoid making it a constant warning tone.'),
('ELECTRICITY_Spark_01_mono.wav','Electrical short','Damage or component failure one-shot, positioned at the affected part.'),
('MECHANICS_Chain_Pull_01_loop_mono.wav','Recovery winch / track detail','Possible mechanical rattle layer, not a complete track sound by itself.'),
('RIP_Tear_01_mono.wav','Part detachment texture','Material is unspecified. Audition before combining with metal fracture and fasteners; do not assume a metal tear.'),
('ROBOTIC_Servo_Large_Slow_Rotation_loop_mono.wav','Tractor arm / heavy turret','Alternative moving servo loop; compare with existing turret audio and stop when stationary.'),
('ROBOTIC_Servo_Large_Slow_Rotation_Release_mono.wav','Actuator release','Pair with movement or recovery-robot disengagement; inspect the tail.'),
('ROBOTIC_Servo_Medium_Malfunction_04_Damaged_Movement_mono.wav','Damaged actuator','Intermittent damaged gear, flap or robot movement; do not play on a healthy mechanism.'),
]
def db(x):return round(20*math.log10(max(float(x),1e-12)),2)
universal=[]
for i,(name,role,note) in enumerate(choices,1):
    matches=[r for r in new if r['pack']=='Universal Sound FX' and Path(r['path']).name==name]
    assert len(matches)==1,(name,len(matches))
    r=matches[0].copy()
    with wave.open(r['path'],'rb') as w:
        rate=w.getframerate();channels=w.getnchannels();bits=w.getsampwidth()*8
        assert bits==16,(name,bits)
        x=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.float32).reshape(-1,channels)/32768
    mono=x.mean(axis=1);rms=np.sqrt(np.mean(x*x));peak=np.max(abs(x))
    preview=mono[:min(len(mono),int(rate*8))]
    gain=min(10**(-20/20)/max(float(np.sqrt(np.mean(preview**2))),1e-12),.7/max(float(np.max(abs(preview))),1e-12),4)
    preview=preview*gain
    filename=f'previews/U{i:02}.wav'
    with wave.open(str(OUT/filename),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes((np.clip(preview,-1,1)*32767).astype('<i2').tobytes())
    r.update(id=f'U{i:02}',name=name,role=role,note=note,duration_s=round(len(x)/rate,3),rate=rate,channels=channels,bits=bits,rms_dbfs=db(rms),peak_dbfs=db(peak),preview_gain_db=db(gain),preview=filename,preview_duration_s=round(len(preview)/rate,3),endpoint_step=round(float(abs(mono[-1]-mono[0])),6),clipped_samples=int(np.sum(abs(x)>=.9999)))
    universal.append(r)
(OUT/'universal_candidates.json').write_text(json.dumps(universal,indent=2),encoding='utf-8')

names={'a':'Hummingbird · aircraft 11','b':'Bumblebee · aircraft 9','c':'Huntsman · aircraft 12','d':'Dragonfly · aircraft 13','e':'Reserve option','f':'Dune Skimmer · aircraft 10','g':'Medium attack · aircraft 15','h':'Reserve option'}
reasons={'a':'Lower envelope-pulse estimate; lighter utility candidate. This is not proof of quiet real-world operation.','b':'Strongest low-frequency share in the fastest source: a heavy utility starting point.','c':'Low spectral centroid and substantial bass: a heavy attack starting point.','d':'Lowest bass share: separates the ultralight from the heavy types.','e':'Moderate bass and brightness; available if a current assignment is unsuitable.','f':'Brightest spectrum and fastest envelope-pulse estimate: light attack candidate.','g':'More bass than F with a similar centroid: medium attack candidate.','h':'Bass-rich alternative, held back to preserve another distinct option.'}
e=html.escape
cards=[]
for letter in 'abcdefgh':
    entries=[r for r in banks if r['family']==letter]
    fastest=next(r for r in new if r['pack']=='Helicopter Engine Sounds' and Path(r['path']).name==f'helicopter_{letter}_engine_loop_4x.wav')
    players=''.join(f'<label>{j}x source speed<audio controls preload="none" aria-label="Profile {letter.upper()} speed {j}" src="{r["preview"]}"></audio></label>' for j,r in enumerate(entries))
    cards.append(f'''<article class="card"><div class="tag">{'IN GAME' if entries[0]['aircraft'] else 'RESERVE'} · PROFILE {letter.upper()}</div><h3>{e(names[letter])}</h3><p>{e(reasons[letter])}</p><div class="stats"><span>{fastest['low_pct']}% bass</span><span>{fastest['centroid_hz']} Hz centroid</span><span>{fastest['pulse_hz']} Hz pulse estimate</span></div><label>Spool up → run → coast down · 19 seconds<audio controls preload="none" aria-label="Profile {letter.upper()} spool" src="previews/{letter}_spool.ogg"></audio></label><details><summary>Compare five recordings</summary>{players}</details><details><summary>Source and preparation</summary><p class="path">{e(entries[0]['source'])}</p><p>Same family, loop_0x through loop_4x. Each prepared loop is {entries[0]['duration_s']:.2f} s. Family gain {entries[0]['gain_db']:.2f} dB; 48 kHz mono; 30 Hz high-pass; 80 ms seam overlap; Vorbis q5.</p></details></article>''')
ucards=[]
for r in universal:
    ucards.append(f'''<article class="card candidate" data-search="{e((r['role']+' '+r['name']+' '+r['note']).lower())}"><div class="tag">{r['id']} · AUDITION CANDIDATE</div><h3>{e(r['role'])}</h3><p>{e(r['note'])}</p><audio controls preload="none" aria-label="{r['id']} {e(r['role'])}" src="{r['preview']}"></audio><p class="path">{e(r['path'])}</p><p class="small">Source {r['duration_s']:.2f} s · {r['rate']/1000:g} kHz · {r['channels']} ch · RMS {r['rms_dbfs']:.1f} dBFS · peak {r['peak_dbfs']:.1f} dBFS.<br>Preview {r['preview_duration_s']:.2f} s, gain {r['preview_gain_db']:+.1f} dB. Endpoint step {r['endpoint_step']:.4f}; {r['clipped_samples']} near-full-scale samples.</p></article>''')
categories=collections.Counter(r['category'] for r in new if r['pack']=='Universal Sound FX')
catrows=''.join(f'<tr><td>{e(k.replace("_"," ").title())}</td><td>{v:,}</td></tr>' for k,v in sorted(categories.items()))
data=json.dumps([dict(pack=r['pack'],category=r['category'],path=r['path'],bytes=r['bytes'],url=Path(r['path']).as_uri()) for r in new]).replace('</','<\\/')
page='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Project Flight — helicopter sound comparison</title><style>
:root{color-scheme:dark;--bg:#101b22;--panel:#192a34;--text:#edf3f1;--muted:#b5c6cb;--line:#38505b;--accent:#86dfc6}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:16px/1.55 system-ui,sans-serif}header,main{max-width:1260px;margin:auto;padding:32px}h1{font-size:clamp(2rem,4vw,3.4rem);line-height:1.1;margin:12px 0 20px;max-width:930px}h2{font-size:1.7rem;margin-top:42px}h3{font-size:1.23rem;margin:10px 0}p{color:var(--muted)}a{color:var(--accent)}.tag{font-size:.75rem;letter-spacing:.1em;color:var(--accent);font-weight:750}.metrics{display:flex;flex-wrap:wrap;gap:15px;margin:25px 0}.metric{padding:18px 24px;background:var(--panel);border:1px solid var(--line);border-radius:12px;min-width:170px}.metric strong{display:block;font-size:1.9rem}.callout{padding:18px 22px;border-left:4px solid var(--accent);background:#20343d;color:#d2e4e7}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(330px,1fr));gap:18px}.card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:22px}.stats{display:flex;flex-wrap:wrap;gap:8px;font-size:.78rem;margin:18px 0}.stats span{padding:5px 8px;background:#283e48;border-radius:5px}audio{display:block;width:100%;height:38px;margin:10px 0 17px}label{display:block;color:var(--muted);font-size:.86rem}summary{cursor:pointer;color:var(--accent);padding:8px 0}.path{font:12px/1.6 ui-monospace,monospace;overflow-wrap:anywhere}.small{font-size:.82rem}nav{display:flex;gap:20px;flex-wrap:wrap;margin:22px 0}input,select,button{font:inherit;border:1px solid var(--line);border-radius:7px;background:#203741;color:var(--text);padding:10px 13px}input{flex:1;min-width:220px}button{cursor:pointer}button:hover{background:#355660}.filters{display:flex;gap:12px;flex-wrap:wrap;margin:22px 0}table{border-collapse:collapse;width:100%}td,th{text-align:left;border-bottom:1px solid var(--line);padding:10px;vertical-align:top}.scroll{overflow:auto}.pathcell{max-width:760px;overflow-wrap:anywhere;font-size:.78rem}.candidate[hidden]{display:none}footer{padding:35px 0;color:var(--muted);font-size:.85rem}@media(max-width:600px){header,main{padding:20px 16px}.grid{grid-template-columns:1fr}.metric{min-width:140px}.card{padding:18px}}
</style></head><body><header><div class="tag">PROJECT FLIGHT / AUDIO UPDATE / 06 OCTOBER 2026</div><h1>Eight helicopter voices.<br>Six distinct aircraft.</h1><p>Compare the new rotor banks and promising effects from Universal Sound FX. Nothing plays automatically; starting a clip pauses the previous one.</p><div class="metrics"><div class="metric"><strong>8 × 5</strong>helicopter speed loops</div><div class="metric"><strong>6</strong>profiles integrated</div><div class="metric"><strong>4.76 MB</strong>game audio added</div><div class="metric"><strong>10,101</strong>Universal FX recordings</div></div><nav><a href="#helicopters">Helicopter comparison</a><a href="#universal">Universal shortlist</a><a href="#library">New library inventory</a><a href="../report.html">Original 5 October audit</a><button id="stop">Stop all playback</button></nav><div class="callout"><strong>What is verified:</strong> all 40 helicopter source loops were measured; all six game profiles passed mixer, speed selection, loop-wrap, stopped/budget-suppressed silence and cockpit-routing checks.<br><strong>What remains subjective:</strong> identity and final mix balance. These selections were not judged by ear. The spool previews are synthesized demonstrations without distance attenuation, cockpit filtering or surrounding game sounds. Spectral figures describe the fastest source and do not identify real rotor RPM or a helicopter model.</div></header><main>
<h2 id="helicopters">Listen across all eight profiles</h2><p>The pack contains 168 WAVs: five 16-second loops plus sixteen transition/acceleration/deceleration recordings per family. The game blends adjacent speed loops with actual rotor speed, including coast-down; at most two layers play. The source label “0x” means the lowest audible loop, so stopped rotors are explicitly silent. No independent electric-motor layer has been inferred from these combined recordings.</p><div class="grid">__HELICOPTERS__</div>
<h2 id="universal">Seventeen promising effects to audition next</h2><p>These are review candidates, not additional game imports. Existing carrier ambience, tracks, doors and servos already have recent integrations; compare these alternatives before replacing them. Locking events, failure detail and sustained crash contact remain useful areas to assess. Loopability and material character still require listening; a filename and a small endpoint discontinuity do not prove a seamless or suitable loop.</p><div class="filters"><input id="candidate-search" aria-label="Search audition candidates" placeholder="Search role, material or filename"><span id="candidate-count"></span></div><div class="grid">__UNIVERSAL__</div>
<h2 id="library">Inventory of the two additions</h2><p><strong>10,269 new WAV files · __NEWGB__ GB.</strong> Combined with the previous source inventory: <strong>__TOTAL__ source files · __TOTALGB__ GB</strong>. Counts exclude Unity .meta sidecars and represent files, not unique performances. The combined count carries forward the 5 October source scan; other folders were not rescanned for changes.</p><p><a href="updated_source_inventory.json">Combined source inventory (JSON)</a> · <a href="prepared_banks.json">Helicopter preparation measurements</a> · <a href="universal_candidates.json">Universal candidate measurements</a></p><details><summary>Universal Sound FX category counts</summary><table><thead><tr><th>Category</th><th>WAV files</th></tr></thead><tbody>__CATEGORIES__</tbody></table></details><div class="filters"><input id="library-search" aria-label="Search new source inventory" placeholder="Search all 10,269 new recordings"><select id="pack" aria-label="Filter source pack"><option value="">Both packs</option><option>Helicopter Engine Sounds</option><option>Universal Sound FX</option></select></div><p id="library-count"></p><div class="scroll"><table><thead><tr><th>Pack / category</th><th>Exact source path</th><th>KB</th></tr></thead><tbody id="library-rows"></tbody></table></div><footer>Originals remain under D:\\Game audio. Only 30 helicopter derivatives were added to game audio. E/H reserves and audition excerpts are inside the ignored review-artifact directory. Godot test passed with sandbox certificate-store and user-log warnings; no audio assertion failed. The original 5 October audit remains a historical snapshot.</footer>
</main><script>
const sourceFiles=__DATA__;
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
document.addEventListener('play',event=>{if(event.target.tagName==='AUDIO')document.querySelectorAll('audio').forEach(a=>{if(a!==event.target)a.pause()})},true);
document.getElementById('stop').onclick=()=>document.querySelectorAll('audio').forEach(a=>a.pause());
function candidates(){const q=document.getElementById('candidate-search').value.toLowerCase();let n=0;document.querySelectorAll('.candidate').forEach(c=>{c.hidden=!c.dataset.search.includes(q);if(!c.hidden)n++});document.getElementById('candidate-count').textContent=n+' of 17 candidates'}
function library(){
  const q=document.getElementById('library-search').value.toLowerCase(),p=document.getElementById('pack').value;
  const rows=sourceFiles.filter(r=>(!p||r.pack===p)&&r.path.toLowerCase().includes(q));
  const table=document.getElementById('library-rows');
  table.querySelectorAll('audio').forEach(audio=>audio.pause());
  document.getElementById('library-count').textContent=rows.length.toLocaleString()+' matches · showing first '+Math.min(rows.length,120)+' · playback uses the original recordings at their original levels';
  table.innerHTML=rows.slice(0,120).map(r=>`<tr><td>${esc(r.pack)}<br><small>${esc(r.category)}</small></td><td class="pathcell">${esc(r.path)}</td><td>${(r.bytes/1000).toFixed(1)}</td><td><audio hidden preload="none" aria-label="${esc(r.path.split(/[\\\\/]/).pop())}" src="${esc(r.url)}"></audio></td></tr>`).join('');
  document.dispatchEvent(new Event('library-rendered'));
}
document.getElementById('candidate-search').addEventListener('input',candidates);document.getElementById('library-search').addEventListener('input',library);document.getElementById('pack').addEventListener('change',library);candidates();library();
</script></body></html>'''
page=page.replace('<div class="grid">__HELICOPTERS__</div>', '<details><summary>Previous shared rotor recording for comparison</summary><p>Legacy Helicopter3 medium exterior loop, 2.91 s. This earlier audit preview has its own review gain and is not loudness-matched to the new spool demonstrations.</p><audio controls preload="none" aria-label="Previous shared helicopter medium loop" src="../previews/S15.mp3"></audio></details><div class="grid">__HELICOPTERS__</div>')
page=page.replace('ignored review-artifact directory', 'review-artifact directory excluded from Godot imports')
for key,val in {'__HELICOPTERS__':''.join(cards),'__UNIVERSAL__':''.join(ucards),'__CATEGORIES__':catrows,'__DATA__':data,'__NEWGB__':f'{sum(r["bytes"] for r in new)/1e9:.3f}','__TOTAL__':f'{len(sources):,}','__TOTALGB__':f'{sum(r["bytes"] for r in sources.values())/1e9:.3f}'}.items():page=page.replace(key,val)
page=page.replace('<label>', '<div class="sound-label">').replace('</label>', '</div>')
page=page.replace('<th>KB</th>', '<th>KB</th><th>Listen</th>')
page=page.replace('</head>', '<style>.sound-label{color:var(--muted);font-size:.86rem}.sound-controls{display:flex;align-items:center;gap:12px;margin:12px 0 5px}.sound-play{min-width:110px;min-height:44px;background:var(--accent);color:#10241e;font-weight:750}.sound-play:hover{background:#b2f1df}.sound-play:focus-visible{outline:3px solid white;outline-offset:3px}.sound-status{font-size:.8rem;color:#ffce9c}</style></head>')
page=page.replace('</body>', '<script src="playback.js"></script></body>')
(OUT/'report.html').write_text(page,encoding='utf-8')
# Preserve the original audit as a dated snapshot, with a prominent update link.
banner='<div class="callout"><strong>6 October update:</strong> <a href="helicopter_update_2026_10_06/report.html">Eight helicopter sets, six integrated profiles and the Universal Sound FX shortlist.</a> This page remains the original 5 October snapshot; subsequent game audio work is not reflected below.</div>'
for target in [BASE/'report.html',BASE/'build_report.py']:
    text=target.read_text(encoding='utf-8')
    if '6 October update:' not in text:text=text.replace('<main>','<main>'+banner,1)
    target.write_text(text,encoding='utf-8')
print('REVIEW_BUILT',OUT/'report.html','sources',len(sources),'universal_candidates',len(universal))
