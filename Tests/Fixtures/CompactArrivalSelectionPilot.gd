extends "res://AI/AIPilot.gd"

var built := 0
var installed: Array[Dictionary] = []
var reject_all := false
var equal_cost := false
func _is_inside_compact_recovery_field(_frame: Dictionary = {}) -> bool: return true
func _get_compact_recovery_side(_frame: Dictionary) -> float: return 1.0
func _build_compact_recovery_candidate(_frame: Dictionary, side: float,
		_max_raise: float, entry_fraction: float = -1.0) -> Dictionary:
	built += 1
	return {"valid": not reject_all, "assessment": {"estimated_time_s": 90.0 if equal_cost or side > 0 else 65.0},
		"metadata": {"side": side, "entry_fraction": entry_fraction}}
func _install_compact_recovery_candidate(candidate: Dictionary) -> void:
	installed.append(candidate)

