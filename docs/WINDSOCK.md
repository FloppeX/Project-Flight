# Carrier windsock

`LandCarrier/Windsock.tscn` wraps the authored `Models/LandCarrier/Wind sock.glb`. It is mounted at carrier-local (-18, 0, -20), beside the island. The source model is preserved. The reusable scene also works on a stationary mount.

The mast-side cuff remains in its authored position. Beyond that fixed attachment, the four fabric meshes share a continuous shader bend from mouth to tail, so the rest of the sock rises and falls without gaps between its sections. Their original transforms and red/white materials are retained; the pole stays rigid. Runtime discovery uses mesh position, so the corrected section names do not need a code mapping. The shader bounds include the drooping cloth to avoid premature culling.

Direction follows horizontal local atmospheric airflow minus carrier velocity, including carrier yaw motion at the mount. The tail points downwind. Calm air retains the last direction and lets the sock hang. Gusts feed the existing wind field; heading and extension respond smoothly with light tail flutter. This is a cosmetic approximation, not cloth physics or an aerodynamic obstacle.

Inspector controls on the Windsock node:

- `full_extension_speed_mps`: 8 m/s by default.
- `response_s`: 0.8 seconds of smoothing.
- `flutter_enabled`: toggle the small animated tail movement.
- `fixed_cuff_fraction`: fraction of the sock held rigid at the mast, 0.12 by default.

`Tests/WindsockSmoketest.gd` checks four fabric materials, calm/strong-wind response, a rotated mount, and airflow from a moving carrier. A rendered run captures calm, 3 m/s, and 10 m/s examples. Add `-- --carrier-preview` to render its saved placement against the carrier visual model. Both rendered views were inspected; the updated GLB import checksum matched its source and the focused test passed after the section-name update. The placement render is a visual fixture, not a full mission flight test.
