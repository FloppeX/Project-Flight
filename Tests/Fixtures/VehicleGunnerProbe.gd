extends TurretController
class Host extends Node3D:
	var team := 2
	func get_team() -> int: return team

class AlignedTurret extends Turret:
	func get_aim_angle_to_target() -> float: return 0.0

# Keep the real aim/noise/burst loop; isolate visibility and target selection.
func find_and_set_best_target() -> void: pass
func _get_cached_line_of_sight(_delta: float, _point: Vector3, _target: Node3D) -> bool: return true
func _get_ai_darkness_factor() -> float: return 0.0
