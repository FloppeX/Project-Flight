# Land Carrier Project

A strategic action game inspired by Armourgeddon and Carrier Command, featuring tactical air combat and commanding a massive mobile base.

## ⚠️ CURRENT STATUS: FILE PERMISSIONS (If applicable)

**If you see import errors:** The project may have file permission errors preventing Godot from importing assets.

👉 **See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for fix instructions** 👈

## 🎮 CONTROLLER SETUP

**This project uses a game controller (Xbox/PlayStation) for flight controls.**

👉 **See [CONTROLLER_GUIDE.md](CONTROLLER_GUIDE.md) for complete controller layout** 👈

**AI Pilot is now DISABLED by default** - you have full manual control!

## Quick Start (After Fixing Permissions)

1. **Prerequisites:**
   - Godot Engine v4.4.1 or later
   - 2GB+ free disk space
   - Windows 10/11, Linux, or macOS

2. **Opening the Project:**
   - Ensure you have write permissions on the project folder
   - Open Godot Engine
   - Click "Import" and select `project.godot`
   - Wait for all assets to import (5-10 minutes first time)

3. **Running the Game:**
   - Press F5 or click the "Play" button
   - Use WASD for aircraft control
   - Mouse to look around
   - G to toggle landing gear
   - Space to fire weapons

## Project Structure

```
Land-Carrier-Project/
├── addons/                   # Godot addons (terrain_3d, flight sim)
├── Aircraft/                 # Player aircraft models and scripts
├── demo/                     # Demo scenes and assets
├── example/                  # Example implementations
├── Enemies/                  # Enemy units and AI
├── Environment/              # Terrain, weather, lighting
├── LandCarrier/              # Main carrier systems
├── Projectiles/              # Weapons and ammunition
├── Weapons/                  # Weapon systems
├── .godot/                   # Cache folder (DO NOT COMMIT)
└── project.godot             # Main project file
```

## Key Documentation

- **[Land Carrier Project description.md](Land%20Carrier%20Project%20description.md)** - Full project overview, systems, and changelog
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Fix file permission errors and other issues
- **[GLB_Integration_Guide.md](GLB_Integration_Guide.md)** - 3D model integration guide

## Current Features

### ✅ Implemented
- Flight physics with simplified aerodynamics
- AI pilot system with autonomous flight
- Catapult launch system
- Arresting cable landing system
- Elevator and hangar operations
- Tractor bot aircraft handling
- Targeting and weapon systems
- HUD with radar and instruments
- Enemy detection and combat
- Flight deck lighting
- Terrain system with dynamic LOD
- Landing gear with suspension
- Tailhook mechanism

### 🚧 In Progress
- File permission issues (BLOCKING)
- Enhanced enemy AI
- Resource management
- Carrier defense systems

### 📋 Planned
- Additional aircraft types
- Ground vehicles
- Strategic map view
- Territory control
- Weather systems
- Campaign progression

## Controls

### 🎮 Game Controller (Primary)
**This project is designed for game controllers!**

**Flight:**
- **Left Stick** - Pitch and Roll
- **Right Stick** - Look around
- **LT/RT (L2/R2)** - Rudder left/right
- **LB/RB (L1/R1)** - Throttle up/down

**Combat:**
- **A/X button** - Fire weapon
- **X/Square button** - Switch weapons
- **D-pad Up/Down** - Target next/previous

**Systems:**
- **B/Circle button** - Landing gear
- **Y/Triangle button** - Switch camera
- **D-pad Left/Right** - Flaps

### ⌨️ Keyboard (Limited)
- **R** or **1** - Retrieve aircraft from hangar
- **S** - Store aircraft in hangar
- **A** - Toggle AI pilot on/off (currently OFF)
- **ESC** - Quit game

👉 **See [CONTROLLER_GUIDE.md](CONTROLLER_GUIDE.md) for detailed controller layout**

## Technical Requirements

- **Engine:** Godot 4.4.1 or later
- **GPU:** Vulkan 1.4+ compatible
- **RAM:** 4GB minimum, 8GB recommended
- **Storage:** 2GB free space for cache

## Known Issues

1. **File Permission Errors** (CRITICAL - see TROUBLESHOOTING.md)
   - Cannot create imported files
   - Assets fail to load
   - **Solution:** Fix folder permissions and delete `.godot` folder

2. **Performance**
   - Large terrain may cause FPS drops on low-end systems
   - Adjust LOD settings in project settings

3. **Asset Loading**
   - First load takes 5-10 minutes to import all assets
   - Subsequent loads are much faster

## Development Status

This is an active development project. Current session focus:
- Resolving file permission issues
- Stabilizing core flight mechanics
- Refining AI pilot behavior

See [Land Carrier Project description.md](Land%20Carrier%20Project%20description.md) for detailed development log and upcoming features.

## License

[Specify your license here]

## Contributing

This is currently a single-player development project. AI assistants helping with development should:
1. Read the project description thoroughly
2. Follow established code patterns
3. Document all changes
4. Test incrementally
5. Confirm before major structural changes

---

**Last Updated:** 2025-02-15
**Godot Version:** 4.4.1.stable.official.49a5bc7b6
**Platform:** Windows/Linux/macOS
