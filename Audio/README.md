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

## Helicopter profiles

The six helicopters now use separate five-speed banks from the local
`D:/Game audio/Helicopter Engine Sounds` pack: Bumblebee (9) uses B, Dune Skimmer
(10) F, Hummingbird (11) A, Huntsman (12) C, Dragonfly (13) D, and medium attack
(15) G. These initial assignments use measured spectral differences; they still
need an in-game listening pass. The source sets are named A–H and do not identify
real helicopter models or certify electric-only propulsion recordings.

`CounterRotatingRotor.gd` blends adjacent recordings using actual rotor speed,
including coast-down. The pack's `0x` recording is an audible idle, so a stopped
rotor explicitly stops playback. At most two layers play per rotor. Existing
cockpit filtering, spatial attenuation and audio budget controls remain in use.

`tools/prepare_helicopter_audio.py` rebuilds the 30 mono Vorbis loops (4.76 MB)
under `engine/helicopter/profiles/`. It applies a 30 Hz high-pass, an 80 ms seam
overlap and one common gain per family, preserving relative levels across speeds.
`helicopter_audio_sources.json` records source paths, hashes and processing.
The original recordings and legacy three-layer fallback are retained. Sets E/H
and the pack's authored acceleration/deceleration one-shots remain available for
future review; those one-shots are not played over the live RPM-driven blends.

The comparison page at
`artifacts/audio_inventory_2026_10_05/helicopter_update_2026_10_06/report.html`
contains all eight profiles and synthesized spool demonstrations. These previews
are not captures of the final in-game mix. `Tests/HelicopterAudioSmoketest.gd`
checks all six scenes, five layer assignments, mixer output, loop wrap, stopped
and budget-suppressed silence, and cockpit routing.

`cockpit/canopy_sand_ticks.wav` and `canopy_sand_rattle.wav` are original synthetic
stereo grain-impact loops, rebuilt by `tools/generate_canopy_sand_audio.py` without
external recordings. `Weather/CanopySandAudio.gd` mixes them according to local
dust exposure, storm strength and visual airflow speed. They play through Master
only in active cockpit views, pause with the simulation, and stop on exterior
view switches or leaving the dust. The two loop lengths differ to reduce obvious
repetition. `Tests/CanopySandAudioSmoketest.gd` checks actual mixer output, strength
scaling and exterior silence; subjective mix balance still needs in-flight review.

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
