# Tailhook extension

The shared `TailhookSimple` visual now extends from an aircraft-local belly mount
at `(0, -0.65, 0)` to the existing deployed hook-tip position. Mount position and
deployment duration are exposed for per-aircraft adjustment. The default duration
is 0.8 seconds; stowing reverses the extension and interrupted commands continue
from the current fraction. The technical-index preview uses the same geometry.

The authored mesh is retained. Its shaft length follows extension while its
width remains unchanged. The hook scene root, wire-detection area, collision
shapes and deploy/stow physics timing retain their existing behavior; this is a
visual deployment change, not new arresting dynamics.

Validation includes rendered stowed/half/full views on Aircraft_1, timed extension
and reversal, and mount/tip checks across all seven scenes using the shared hook.
WireReachabilitySmoketest passes. This does not establish a full landing cycle.
TechnicalIndexSmoketest stops earlier at an Aircraft_1 instrument-panel visibility
assertion; the same failure was reproduced with the original hook script.
