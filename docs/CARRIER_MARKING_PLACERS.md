# Carrier marking placers

Both `LandCarrier/LandCarrier2.tscn` (gameplay and menu) and the older
`LandCarrier/LandCarrier.tscn` now use the same cylinder insignia placers as
aircraft 5. Existing marker positions are retained. Rotation and per-marker
diameter/depth now determine the generated decal; the right-facing marker uses
a non-mirrored, upright basis. The setup camera recognizes the new node type.

## Editing

- Select `InsigniaHull` or `InsigniaHullR`: move/rotate it and edit **Diameter**,
  **Depth**, and optionally **Cross Diameter**.
- Select `ShipNameMarker`: move/rotate the rectangular volume and edit **Width**,
  **Height**, **Depth**, and **Text Color**. Duplicate it for the opposite side.
- For both placers, local **-Y projects into the surface**, **-Z is lettering up**,
  and **+X is lettering right**. The volume must intersect the surface.
- The name placer's editor box and readable text are authoring helpers only.
  **Preview Name** is shown in the editor; runtime uses `carrier_display_name`
  from the campaign, with `GameSession.carrier_name` as fallback. **Text Override**
  can replace this with an authored name.
- New-game name edits refresh the preview lettering without recoloring the ship.

Lettering is baked into a transparent, mipmapped decal texture only when its
text or aspect changes. It is projected onto the hull, not floating geometry.
Like the existing insignia, this requires Godot's Forward+ or Mobile renderer;
see the [Decal reference](https://docs.godotengine.org/en/stable/classes/class_decal.html).

## Verification

`Tests/CarrierMarkingSmoketest.gd` checks both scenes, marker orientation,
rotation/size transfer, hidden runtime helpers, campaign-name resolution,
long-name fitting and text override. Run with `-- --render` in a rendered Godot
instance to additionally inspect lettering, verify projection reaches the outer
hull and write `captures/carrier_markings/ship_name.png` and `name_texture.png`.
The carrier's operational scripts are excluded from this focused visual test;
it does not start a scenario or exercise ship navigation.
