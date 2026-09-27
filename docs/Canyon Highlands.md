# Open Canyons - Highlands

Select **OPEN CANYONS - HIGHLANDS** in a new game. Open Canyons remains the default.

The raised areas follow the base map's domain-warped canyon noise. Highlands
widens the natural valley floors and expands landforms horizontally, leaving
irregular plateaus and winding paths between them. There is no periodic road
grid, central spire or fixed central landform.

Most raised ground has one or two 180 m levels; third levels are occasional and
fourth levels rare. Valley-floor relief spans about 52 m, within the carrier's
existing low-ground height tolerance. Nine seeded approaches connect natural
valley anchors to broad first-level plateaus for small vehicles. Not every
plateau is connected to a ramp. The carrier stays in the valley network.

Restart into a new Highlands game to regenerate terrain and navigation caches.
The default Open Canyons profile is unchanged.

## Implementation

`Environment/HighlandsProfile.gd` defines levels and relief.
`Environment/LowPolyTerrain.gd` scales the existing canyon fields and selects ramps.
`AI/NavGraph.gd` permits elevated small-vehicle routes and protects cliff shoulders.

## Verification

- `HighlandsRegionalSmoketest.gd` checks the 48 km map's height distribution and
  sampled 500 m usable footprints. Current seed: 6,808 first-level samples,
  1,593 second-level samples, 340 third-level samples and 35 fourth-level samples.
  All four levels include usable footprints; about 40% of flat first/second-level
  samples satisfy the 500 m footprint check.
- `HighlandsRegionalNavigationSmoketest.gd` selects actual valley anchors near
  four district sides and checks carrier routes, low-ground eligibility and
  stable 320 m radius footprints, plus nine small-vehicle ramps. Each bake covers
  12 km so paths can detour around irregular plateaus between the test anchors.
- `HighlandsCarrierStartupSmoketest.gd` loads the real main scene, waits for
  carrier placement, checks routes to nearby natural valleys and submits a player
  order. It uses a 12 km bake, not the full 50 km campaign bake.
- `HighlandsRenderedProbe.gd -- --regional` renders four distant regions.
- `TerrainSurfaceParitySmoketest.gd` checks 972 mesh/query/collision comparisons.

These checks do not replace a full driving or building-placement playtest.
