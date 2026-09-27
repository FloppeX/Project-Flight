extends "res://AI/AIPilot.gd"
## Paired-test baseline: ordinary compact arcs previously bypassed all three
## vector safeguards. Only use with the production compact-break entry probe.
func _uses_compact_recovery_vector_control() -> bool:
	return false
