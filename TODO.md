# TODO

- Investigate lightweight terrain material variation using vertex colors or splat-map style data to blend simple terrain textures.
- Roadmap: add checkpoint-style game-state saving/loading. Start with robust strategic persistence rather than exact frame-perfect simulation resume: scenario seed, carrier transform, pilot roster/career stats, hangar/stored aircraft, active aircraft transform/velocity/health/fuel/loadout, destroyed bases/buildings, and simple ground-platoon objective state. Treat volatile systems such as projectiles, particles, deck/elevator in-progress actions, async path jobs, and radio queues as reset/reissued on load unless a later exact-resume design is justified.
