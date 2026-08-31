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

Runtime voice discovery intentionally scans only `Voices/Citadel/` and `Voices/Pilots/`; files in `Voices/SourcePacks/` are archival inputs, not in-game clips.
