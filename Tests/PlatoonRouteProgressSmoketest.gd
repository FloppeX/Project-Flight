extends Node

class Member:
	extends Node3D
	var waypoint_reach_distance := 25.0

class Platoon:
	extends "res://GroundVehicle/ground_vehicle_platoon.gd"
	func _ready() -> void:
		set_process(false)
	func get_contact_position() -> Vector3:
		return Vector3(-60, 0, -60)
	func _project_contact_to_ground(point: Vector3) -> Vector3:
		return point

class Friendly:
	extends "res://GroundVehicle/vehicle_friendly_light.gd"
	var follow := Vector3(100, 0, 0)
	func _ready() -> void:
		set_physics_process(false)
		set_process(false)
	func _has_navigation_destination() -> bool: return true
	func _get_raw_navigation_destination() -> Vector3: return Vector3(0, 0, 500)
	func _get_follow_navigation_destination() -> Vector3: return follow
	func _apply_platoon_cohesion(_destination: Vector3) -> Vector3: return Vector3(0, 0, 500)

class Enemy:
	extends "res://GroundVehicle/vehicle_enemy_light.gd"
	var follow := Vector3(100, 0, 0)
	func _ready() -> void:
		set_physics_process(false)
		set_process(false)
	func _has_navigation_destination() -> bool: return true
	func _get_raw_navigation_destination() -> Vector3: return Vector3(0, 0, 500)
	func _get_follow_navigation_destination() -> Vector3: return follow
	func _apply_platoon_cohesion(_destination: Vector3) -> Vector3: return Vector3(0, 0, 500)

func _ready() -> void:
	var failures: Array[String] = []
	var p := Platoon.new()
	add_child(p)
	var lead := Member.new()
	add_child(lead)
	p._members.assign([lead])
	p.objective_type = p.ObjectiveType.MOVE_TO_POSITION
	p._route_preview_origin = Vector3.ZERO
	p._route_preview_positions.assign([Vector3(0, 0, 50), Vector3(0, 0, 200)])
	lead.position = Vector3(0, 0, 10)
	if p._get_route_navigation_anchor() != Vector3(0, 0, 50): failures.append("advanced before lead arrived")
	lead.position = Vector3(0, 0, 25.1)
	if p._get_route_navigation_anchor() != Vector3(0, 0, 200): failures.append("offset map marker stalled arrived lead")
	for v in [Friendly.new(), Enemy.new()]:
		add_child(v)
		v._refresh_drive_command(0.1)
		if v._drive_command_steer < 0.5: failures.append("formation replaced terrain detour")
		v.follow = Vector3.ZERO
		v._refresh_drive_command(0.1)
		if v._drive_command_has_destination or v._drive_command_throttle != 0.0: failures.append("missing path drove directly toward formation")
		v.free()
	p._members.clear()
	lead.free()
	p.free()
	for message in failures: push_error(message)
	print("PLATOON_ROUTE_PROGRESS ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
