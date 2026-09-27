extends TurretController
class Host extends Node3D:
	var team := 2
	var defense_capability := 1.0
	func get_team() -> int: return team
	func get_system_capability(_system: String, _part: Node) -> float: return defense_capability

class AlignedTurret extends Turret:
	var aim_angle := 0.0
	var arc_available := true
	func get_aim_angle_to_target() -> float: return aim_angle
	func is_point_within_yaw_arc(_point: Vector3) -> bool: return arc_available

var sight_clear := true
var above_plane := true

# Keep the real aim/noise/burst loop; isolate visibility and target selection.
func find_and_set_best_target() -> void: pass
func _get_cached_line_of_sight(_delta: float, _point: Vector3, _target: Node3D) -> bool: return sight_clear
func _is_target_above_host_plane(_point: Vector3) -> bool: return above_plane
func _get_ai_darkness_factor() -> float: return 0.0
