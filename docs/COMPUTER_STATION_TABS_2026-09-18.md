# Computer station tab memory

Each physical computer remembers its last console tab independently and opens that tab when used again. Unattended screens display that page. Supported pages are Tactical, Air Wing, Personnel, Ground Bay, Carrier, and Replicator.

Tab choices are saved in the carrier checkpoint by relative station path. Lower-room computers default to Carrier; upper-room computers default to Tactical Map. Saves without station tab entries preserve these authored defaults; saved tab choices take precedence. Pages share a render target between stations showing the same tab; unused non-map feeds stop processing and rendering. Screen rendering is limited to 10 Hz. Preview pages accept no input.

Operational pages refresh from their existing managers. Replicator mirrors the console's temporary concept state; it remains a concept rather than live manufacturing. The existing tactical-map preview pauses while the full console is open and resumes when it closes.

Validation: ComputerStationSmoketest covers station entry/exit and map viewport restoration. ComputerStationTabsSmoketest covers independent tab memory, reopening, all page feeds, input isolation, shared textures, and unused-feed cleanup. SaveStateSmoketest also checks distinct station tabs through save/load. Forward+ captures were inspected for all five non-map pages; the isolated carrier preview has no live carrier telemetry.

All three test suites passed their assertions. The rendered run still reports existing imported-scene node warnings and an ObjectDB shutdown leak warning; the headless save test also reports renderer cleanup warnings. These runs are not warning-free. A scene-tree guard fixes the tread recording lookup encountered while building the preview schematic.
