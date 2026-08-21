# Controller Guide - Land Carrier Project

> **Document status:** Player/control reference last fully audited on 2026-03-17. Core controls remain useful, but debug keys and newer tactical-map interactions may have drifted. Use the [README](../README.md) for current project status.

**Updated:** 2026-03-17  
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
| **D-pad Up** | Start engine |
| **D-pad Down** | Stop engine |
| **D-pad Left** | Flaps down |
| **D-pad Right** | Flaps up |

### Combat
| Button | Action |
|--------|--------|
| **A / X** | Fire weapon |
| **X / Square** | Change weapon |
| **D-pad Up/Down** | Target next/previous enemy |

### Camera
| Button | Action |
|--------|--------|
| **Y / Triangle** | Switch camera view |
| **Start / Options** | Toggle spectator / pilot mode |
| **LB / L1** | Previous spectate target (spectator mode only) |
| **RB / R1** | Next spectate target (spectator mode only) |

---

## Keyboard Commands (Limited)

| Key | Action |
|-----|--------|
| **R** or **1** | Retrieve aircraft from hangar |
| **S** | Store aircraft in hangar |
| **L** | Order the nearest eligible friendly aircraft to begin its landing approach |
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
