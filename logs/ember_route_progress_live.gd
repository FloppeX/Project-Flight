extends Node

var elapsed := 0.0

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.2: return
	elapsed = 0.0
	var platoon := get_parent()
	if not platoon.has_active_objective(): return
	var members: Array = platoon.get_members()
	if members.is_empty(): return
	var lead: Node3D = members[0]
	var points: Array = platoon.get("_route_preview_positions")
	var index: int = platoon.get("_route_preview_index")
	if index < 0 or index + 1 >= points.size(): return
	var reach := maxf(float(platoon.get("contact_waypoint_reach_distance_m")), float(lead.get("waypoint_reach_distance")) + 1.0)
	var distance := Vector2(lead.global_position.x - points[index].x, lead.global_position.z - points[index].z).length()
	if distance > reach: return
	platoon.set("_route_preview_index", index + 1)
	for member in members:
		member.set("_arrived_at_destination", false)
