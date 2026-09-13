extends "res://Tests/GroundAttackDiagnostic.gd"

## Experimental existing direct-intercept path, not a production default.
func _collect_weapons(node: Node) -> void:
	super._collect_weapons(node)
	if node == craft:
		pilot.ground_attack_direct_intercept_enabled = true
		pilot.ground_attack_direct_fire_intercept_max_bank_deg = 65.0
