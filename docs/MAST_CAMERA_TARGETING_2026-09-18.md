# Unattended mast-camera targeting

Priority is enemies recently fired on by the carrier's turrets, other enemies,
then live friendly aircraft or ground units within carrier observation range.
Successful weapon shots hold priority for 2.5 seconds to bridge burst gaps;
assigning or aiming at a target alone does not count as firing. Within a priority
tier the camera retains its current live subject to avoid repeated switching.

Without a target, the mast holds its authored forward heading, level with the
horizon and zoomed out. It follows carrier heading changes but does not rotate
on a timer. Manual target cycling/free look remains authoritative. Friendly
monitor contacts never enter hostile sensor results or turret target allocation.
Stored, transported, frozen, destroyed and queued units are excluded.

CarrierMonitorAutomationSmoketest covers real turret shot-report success/failure
and expiry, selection priorities, friendly patrol/ground fallback, target loss,
twenty seconds without idle rotation, heading alignment, manual control and low
light. CarrierTargetCameraSmoketest, DefenseOpsMonitorSmoketest and the updated
DefenseOpsSensorSmoketest pass. CarrierTargetCameraRenderedProbe passes in
Forward+; a captured monitor frame was inspected. Shutdown ObjectDB warnings
remain. This is focused verification rather than a full campaign battle run.
