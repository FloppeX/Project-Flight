# Controller Guide - Land Carrier Project

> **Document status:** Player/control reference last fully audited on 2026-03-17; tactical-map navigation was refreshed on 2026-09-04. Core controls remain useful, but debug keys and other newer interactions may have drifted. Use the [README](../README.md) for current project status.

**Updated:** 2026-09-04
**Default Control:** Spectator mode with AI active

---

## Getting Started

1. **Plug in your Xbox/PlayStation controller**
2. **Press F5** to start the game
3. **Press R** (keyboard) to retrieve aircraft from hangar
4. Wait for the elevator and tractor bots to position the aircraft
5. **Press Start/Options** to take over the nearest friendly aircraft when you want to fly

---

## Controller Layout (Xbox/PlayStation Style)

### Flight Control
| Control | Action |
|---------|--------|
| **Left Stick** | Pitch (up/down) and Roll (left/right) |
| **Right Stick** | Look around (camera) |
| **LT / L2** | Yaw left (rudder) |
| **RT / R2** | Yaw right (rudder) |
| **LB / L1** | Throttle up |
| **RB / R1** | Throttle down |

### Aircraft Systems
| Button | Action |
|--------|--------|
| **B / Circle** | Toggle landing gear |
| **D-pad Up** | Flaps up / request launch (contextual) |

### Combat
| Button | Action |
|--------|--------|
| **A / X** | Fire weapon |
| **X / Square** | Change weapon |
| **D-pad Left/Right** | Select previous/next hostile visible on radar |
| **D-pad Down** | Select closest radar-known hostile in the forward cone |

### Camera
| Button | Action |
|--------|--------|
| **Y / Triangle** | Switch camera view |
| **Start / Options** | Toggle spectator / pilot mode |
| **LB / L1** | Previous spectate target (spectator mode only) |
| **RB / R1** | Next spectate target (spectator mode only) |

### Tactical Map
| Control | Action |
|---------|--------|
| **RT / R2** or **left mouse button** | Zoom in toward the map cursor |
| **LT / L2** or **right mouse button** | Zoom out from the map cursor |
| **Bottom / right scrollbars** | Pan horizontally / vertically while zoomed in |

The map supports `1x` through `8x` zoom. While an order is being drafted, mouse clicks keep their target and waypoint-editing roles; the controller triggers continue to zoom.

---

## Keyboard Commands (Limited)

| Key | Action |
|-----|--------|
| **R** or **1** | Retrieve aircraft from hangar |
| **S** | Store aircraft in hangar |
| **L** | Order the friendly fixed-wing nearest the active player camera to return to the carrier |
| **Shift+L** | Debug enemy landing shortcut |
| **V** | Play the Citadel radio test call |
| **ESC** | Quit game |

---

## Flight Tips

### Taking Off
1. Retrieve aircraft (press **R**)
2. Wait for positioning on catapult
3. Press **Start/Options** to enter pilot mode if you are still spectating
4. Hold **LB/L1** to increase throttle
5. Catapult will launch you automatically
6. Pull back on **left stick** to climb
7. Press **B/Circle** to retract landing gear once airborne

### Flying
- **Gentle turns:** Small left stick movements
- **Sharp turns:** Full left stick deflection + pull back
- **Level flight:** Keep throttle around 50-70%
- **Speed control:** Use **LB/L1** (up) and **RB/R1** (down)

### Landing on Carrier
1. Approach from behind the carrier
2. Lower throttle with **RB/R1**
3. Press **B/Circle** to deploy landing gear
4. Line up with the deck
5. Aim for the back section (arresting cables)
6. Tailhook will catch the cable and stop you

### Combat
1. Press **X/Square** to cycle weapons (guns, bombs, and rocket pods)
2. Point at enemy
3. Press **A/X** to fire
4. Use **right stick** to look and aim

---

## Troubleshooting

### "Nothing happens when I press buttons"
- Make sure your controller is plugged in BEFORE starting the game
- Try unplugging and replugging the controller
- Check Windows/system settings to confirm controller is detected

### "Aircraft doesn't appear"
- Press **R** (keyboard) to retrieve aircraft from hangar
- Aircraft start stored below deck, not on the flight deck

### "AI is flying for me"
- Press **Start/Options** to leave spectator mode and take over the nearest friendly aircraft
- Press **Start/Options** again to return that aircraft to AI control

### "Controller not working"
- Godot supports Xbox and PlayStation controllers natively
- Some generic controllers may not work properly
- Try testing controller in Windows Game Controllers settings first

---

## AI Pilot (Optional)

If you want the AI to fly for you:
- Leave the game in spectator mode
- Press **Start/Options** to take over the nearest friendly aircraft
- Press **Start/Options** again to hand it back to AI

**Current default:** AI is **ON** and the player starts in spectator mode

---

## Advanced: Carrier Operations

### Mast Camera Monitors

- Look directly at the monitor screen and press **A** to focus it (keyboard **E** also enters).
- Each session starts in **Free Look**. Use the **right stick** to pan and tilt.
- Hold **RT** to zoom in or **LT** to zoom out, in either free look or target tracking.
- **D-pad left/right** cycles live hostile contacts and friendly aircraft returning for landing within the carrier's radar radius (currently 5 km), with Free Look included in the cycle. Contacts remain selectable even outside turret range, outside firing arcs, or with no guns engaging them.
- **B** backs away and restores the standing camera.

All monitors show one shared 640 x 360 mast-camera feed, updated at up to 15 Hz while a screen is in view. After the A-button zoom-in finishes, the mast camera takes over the main view at the game's rendering resolution and frame rate, with sharp on-screen controls. The small preview pauses during full-screen use; B restores the physical monitor, resumes the preview and backs away. No second full-resolution scene is rendered. Camera target selection is observation only; it does not command the guns.

When unattended, the mast automatically tracks the closest available contact. With none available, it scans clockwise, level with the horizon and zoomed out, completing one revolution every 20 seconds. Player control always takes precedence. Friendly returning/holding/approaching aircraft leave the list once they resume another mission or are settled/stored on deck; they never become turret targets.

Automatic light enhancement uses the aircraft HUD night-vision shader in both the physical monitor and full-resolution view. It turns on in darkness and off in daylight, with separate dusk/dawn thresholds to prevent flicker. It affects only the mast-camera image, not the room or other cameras.

### Automatic Carrier Defense

DefenseOps reviews turret assignments four times per second. It allocates guns with fewer reachable targets first, spreads fire across available threats, and favors keeping useful assignments. Range, team, firing-arc and host-plane limits still apply; each gun retains its existing aiming, line-of-sight and firing checks. Destroyed or lost contacts are removed automatically. This is a first-pass allocator, not predictive threat assessment or missile interception planning.

Its separate monitor contact list uses AirOps' live carrier radar settings, not turret target lists or previously explored map cells. Aircraft, ground units and hostile structures within that radius can be observed without authorizing a gun to fire. The list updates even if the carrier has no turrets; contacts drop out when they leave the radar radius or are destroyed.

### Hangar System
- **R** or **1** = Retrieve aircraft from hangar
- **S** = Store landed aircraft in hangar
- Hangar can hold up to 12 aircraft
- Aircraft are spawned with the elevator system

### Catapult Launch
- Happens automatically when aircraft is positioned
- Tractor bots move aircraft to catapult
- Engine spools up automatically
- Launch occurs after spool-up sequence

### Arresting Cable Landing
- Catch the cable with your tailhook
- Brings aircraft to a quick stop
- Tractor bots then move it to elevator or hangar

---

*For technical details and full project documentation, see [README](../README.md)*
