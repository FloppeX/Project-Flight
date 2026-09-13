# Audio layout

- `Music/`: non-diegetic music.
- `Voices/Citadel/`: runtime Citadel radio clips.
- `Voices/Pilots/<voice>/`: runtime pilot radio clips, grouped by voice.
- `Voices/SourcePacks/`: original numbered and alternate voice exports retained as source material.
- `cockpit/`: cockpit ambience, wind, and buffet sounds.
- `engine/fixed_wing/`: propeller and fixed-wing engine sounds.
- `engine/helicopter/`: helicopter rotor sounds.
- `guns/`, `rockets/`, `impacts/`, and `explosion/`: weapon and damage effects.
- `Carrier/`, `flaps/`, and `landing_gear/`: vehicle and mechanism effects.
- `footsteps/`: officer boots on plasteel, eight metal-step variants.
- `UI/`: quiet button click, confirmation and cancellation cues.
- `mechanisms/`: electric turret movement and carrier door actuators.

Runtime voice discovery intentionally scans only `Voices/Citadel/` and `Voices/Pilots/`; files in `Voices/SourcePacks/` are archival inputs, not in-game clips.

## Electric vehicle and interior pass

`environment_audio_sources.json` records exact local source files, processing,
levels and sizes for the 16 new derivatives (under 1 MB total). Originals under
`D:/Game audio` are untouched. `tools/prepare_environment_audio.py` rebuilds them.
Most selections are from Gamemaster Audio; the dedicated tread and mechanism
loops come from `Game effects/Vehicles Heavy`. No diesel/combustion source was
deliberately selected. File labels and signal checks guided selection; subjective
listening and final in-game mix review remain pending. `ListeningPreview.html`
provides individual playback, not a recording of the final game mix.

- Carrier treads use mono mechanical track loops, following each tread's movement
  (including turns). Idle and distant loops stop; randomized start offsets avoid
  synchronized playback across tread units.
- Aircraft gain a stereo ventilation/electrical layer through AudioManager3D,
  in addition to existing airflow and rotor sound. Only the authoritative cockpit
  plays it; leaving the cockpit, ejection and destruction silence it.
- Commander interior ambience combines ventilation and room hum. A ceiling check
  suppresses that layer on the open deck and fades on view changes.
- Footsteps use actual carrier-local walking distance, not input or world travel.
  Vertical elevator motion and teleports produce no steps.
- UI activation uses a bounded, throttled player. Buttons can set `silent_ui`
  metadata or `audio_cue` (`click`, `confirm`, `cancel`). Tactical order buttons
  use the confirmation/cancellation cues. Hover remains silent.
- Door movement and reversals trigger a positional actuator sound. Turret servo
  loops follow local yaw/pitch motion, update at 10 Hz, and stop when idle/distant.

Validation: `Tests/EnvironmentAudioSmoketest.gd`,
`Tests/CarrierSoundscapeSmoketest.gd`, and the carrier interior route tests.
