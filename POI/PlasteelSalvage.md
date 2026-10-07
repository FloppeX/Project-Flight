# Plasteel salvage

The harvester recovers finite plasteel from loose metal beside physical wrecks
and ruins. Materials remain in its cargo until it returns to the carrier.

Live destruction registers one salvage source per building: barracks/general
buildings (180), turbines (220), gun emplacements (65), observation outposts
(300), and vehicle bays (220). Ground vehicle wrecks provide 35; eligible
ground-level aircraft wrecks provide 65. Repeated destruction and save restore
do not grant the same salvage twice. The existing authored destroyed models
remain in place, with their collection point outside the building footprint.

The region also receives twelve scattered sites, placed once:

| Type | Count | Plasteel each |
| --- | --- | --- |
| Abandoned building | 4 | 240 |
| Wrecked vehicle | 4 | 80 |
| Ruined building | 4 | 320 |

The two ambient building variants use `Models/Ruins/ruin 1.blend` and
`Models/Ruins/ruin 2.blend`, copied from `D:\3D printing files` on 2026-10-04.
Godot imports these Blender files directly. Edit the project copies for future
automatic reimports; changes to the originals on D: need to be copied over.
Their authored scale and materials are preserved. `Ruin1Site.tscn` lifts the
first model by 0.5377893 m to seat its lowest geometry on the ground; the second
already starts at ground level. Both use mesh-shaped collision via
`BuildingWreck.gd`. Existing saved variant indices, stock and collection
positions remain valid, using the same conservative placement radii.

Six sites lie 1.8–7 km from the placement anchor, and six 7–18 km away. Scouts
discover them through the existing resource discovery rules. These supplement
the starter machinery ruin and salvage at relevant POIs. Placement checks the
ruin's footprint, collection area, separation and a ground route. It alternates
with corium placement, at most one candidate per frame.

Their stock, model variant, orientation, ruin position, collection position and
placement progress persist across saves and origin shifts. An exhausted loose
metal pile disappears; the inert ruin remains. Exhausted sites still occupy
their generation slots and never replenish or get replaced. Existing saves
without this distribution gain it once, retaining all existing salvage stock.

The harvester panel shows discovered plasteel stock, site distance and estimated
loads. Sites never credit stores remotely, and lost cargo remains recoverable.

Validation: `PlasteelSalvageSmoketest.gd`, `ScatteredSalvageSmoketest.tscn`
(`-- --rendered` for screenshots), `HarvesterSmoketest.tscn`, and
`CoriumDistributionSmoketest.tscn -- --terrain` for terrain/navigation placement.
