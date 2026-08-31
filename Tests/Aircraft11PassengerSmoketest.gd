extends SceneTree

const PresentationDormancy := preload("res://Aircraft/AircraftPresentationDormancy.gd")
const PILOT_PALETTES: Array[Dictionary] = [
	{
		"main_color": Color(0.16, 0.47, 0.20),
		"main_color_dark": Color(0.17, 0.18, 0.20),
		"helmet_color_1": Color(0.78, 0.16, 0.16),
		"helmet_color_2": Color(0.96, 0.93, 0.82),
	},
	{
		"main_color": Color(0.73, 0.60, 0.44),
		"main_color_dark": Color(0.37, 0.24, 0.15),
		"helmet_color_1": Color(0.20, 0.33, 0.73),
		"helmet_color_2": Color(0.90, 0.66, 0.18),
	},
	{
		"main_color": Color(0.36, 0.40, 0.44),
		"main_color_dark": Color(0.09, 0.13, 0.30),
		"helmet_color_1": Color(0.48, 0.32, 0.64),
		"helmet_color_2": Color(0.17, 0.62, 0.67),
	},
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft_scene := load("res://Aircraft/Aircraft_11.tscn") as PackedScene
	if aircraft_scene == null:
		_fail("Aircraft_11 scene could not be loaded")
		return
	var aircraft := aircraft_scene.instantiate() as RigidBody3D
	if aircraft == null:
		_fail("Aircraft_11 scene did not instantiate as a RigidBody3D")
		return
	var helicopter_pilot := aircraft.get_node_or_null("HelicopterPilot")
	if helicopter_pilot == null:
		aircraft.free()
		_fail("Aircraft_11 has no HelicopterPilot")
		return
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(aircraft)
	await process_frame
	helicopter_pilot.set("aircraft", aircraft)
	var pilot_pool := root.get_node_or_null("CockpitPilotPool")
	if pilot_pool == null or not pilot_pool.has_method("get_pool_stats"):
		aircraft.free()
		_fail("cockpit pilot reserve is unavailable")
		return
	var passenger_mounts: Array[Node3D] = []

	for index in range(3):
		var rescued_pilot := Node3D.new()
		rescued_pilot.set_meta("pilot_callsign", "Passenger %d" % (index + 1))
		rescued_pilot.set_meta("pilot_livery_colors", PILOT_PALETTES[index].duplicate(true))
		if not bool(helicopter_pilot.call("add_passenger", rescued_pilot)):
			rescued_pilot.free()
			aircraft.free()
			_fail("passenger %d was rejected before the cabin was full" % (index + 1))
			return
		rescued_pilot.free()
		var marker := aircraft.get_node_or_null("Passenger%d" % (index + 1)) as Node3D
		var passenger_mount := marker.get_node_or_null("SeatedPassenger%d" % (index + 1)) as Node3D if marker != null else null
		if passenger_mount == null or not passenger_mount.transform.is_equal_approx(Transform3D.IDENTITY):
			aircraft.free()
			_fail("passenger %d was not seated at its authored marker transform" % (index + 1))
			return
		if str(passenger_mount.get_meta("pilot_callsign", "")) != "Passenger %d" % (index + 1):
			aircraft.free()
			_fail("passenger metadata was not retained on the seated visual")
			return
		if passenger_mount.get_meta("pilot_livery_colors", {}) != PILOT_PALETTES[index]:
			aircraft.free()
			_fail("passenger appearance was not retained on its seat record")
			return
		if passenger_mount.call("get_pilot_visual") != null:
			aircraft.free()
			_fail("unseen passenger %d checked out an animated body" % (index + 1))
			return
		passenger_mounts.append(passenger_mount)

	var dormant_stats: Dictionary = pilot_pool.call("get_pool_stats")
	if int(dormant_stats.get("created", 0)) != 2 \
			or int(dormant_stats.get("available", 0)) != 2:
		aircraft.free()
		_fail("unseen passengers consumed the two-pilot reserve")
		return

	var presentation = PresentationDormancy.new(aircraft)
	var presentation_started_usec := Time.get_ticks_usec()
	presentation.restore()
	var presentation_ms := float(Time.get_ticks_usec() - presentation_started_usec) / 1000.0
	var visible_stats: Dictionary = pilot_pool.call("get_pool_stats")
	if int(visible_stats.get("created", 0)) != 4 \
			or int(visible_stats.get("checked_out", 0)) != 4:
		aircraft.free()
		_fail("viewed transport did not present its pilot and three passengers")
		return
	var passenger_root_height := -INF
	var passenger_knee_bend_angle := -INF
	for index in range(passenger_mounts.size()):
		var passenger_visual := passenger_mounts[index].call("get_pilot_visual") as Node3D
		if passenger_visual == null:
			aircraft.free()
			_fail("viewed passenger %d has no pooled body" % (index + 1))
			return
		var expected_palette: Dictionary = PILOT_PALETTES[index]
		if not _find_pilot_material_color(passenger_visual, "main color").is_equal_approx(
			expected_palette["main_color"] as Color
		) or not _find_pilot_material_color(passenger_visual, "main color dark").is_equal_approx(
			expected_palette["main_color_dark"] as Color
		) or not _find_pilot_material_color(passenger_visual, "helmet color").is_equal_approx(
			expected_palette["helmet_color_1"] as Color
		) or not _find_pilot_material_color(passenger_visual, "helmet color 2").is_equal_approx(
			expected_palette["helmet_color_2"] as Color
		):
			aircraft.free()
			_fail("passenger %d did not receive their own helmet colors" % (index + 1))
			return
		var animation_player := passenger_visual.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer
		if animation_player == null \
				or animation_player.assigned_animation != &"piloting" \
				or animation_player.is_playing():
			aircraft.free()
			_fail(
				"seated passenger %d did not retain a frozen piloting pose"
				% (index + 1)
			)
			return
		var skeleton := _find_skeleton(passenger_visual)
		var root_bone_index := skeleton.find_bone("root.x") if skeleton != null else -1
		if root_bone_index < 0:
			aircraft.free()
			_fail("seated passenger %d has no root.x bone" % (index + 1))
			return
		var root_bone_global := skeleton.global_transform \
				* skeleton.get_bone_global_pose(root_bone_index)
		var root_in_mount := passenger_mounts[index].global_transform.affine_inverse() \
				* root_bone_global
		if index == 0:
			passenger_root_height = root_in_mount.origin.y
		if absf(root_in_mount.origin.y - 0.592) > 0.04:
			aircraft.free()
			_fail(
				"seated passenger %d retained the displaced rigAction root (height=%.3f)"
				% [index + 1, root_in_mount.origin.y]
			)
			return
		var leg_geometry := _seated_leg_geometry(skeleton, ".l")
		var knee_bend_angle := float(leg_geometry.get("knee_bend_degrees", INF))
		if index == 0:
			passenger_knee_bend_angle = knee_bend_angle
		if absf(knee_bend_angle - 45.0) > 0.25:
			aircraft.free()
			_fail(
				"seated passenger %d knee bend is %.2f degrees instead of 45"
				% [index + 1, knee_bend_angle]
			)
			return
		if float(leg_geometry.get("foot_forward_m", -INF)) <= 0.0:
			aircraft.free()
			_fail("seated passenger %d foot is not ahead of the knee" % (index + 1))
			return
		var toe_up_angle := float(leg_geometry.get("toe_up_degrees", INF))
		if absf(toe_up_angle - 15.0) > 0.25:
			aircraft.free()
			_fail(
				"seated passenger %d toe lift is %.2f degrees instead of 15"
				% [index + 1, toe_up_angle]
			)
			return

	var overflow_pilot := Node3D.new()
	var overflow_accepted := bool(helicopter_pilot.call("add_passenger", overflow_pilot))
	overflow_pilot.free()
	if overflow_accepted or bool(helicopter_pilot.call("can_accept_passenger")) \
			or int(helicopter_pilot.call("get_passenger_count")) != 3:
		aircraft.free()
		_fail("Aircraft_11 did not enforce its three-passenger cabin capacity")
		return

	if int(presentation.detach()) <= 0:
		aircraft.free()
		_fail("passenger presentation did not enter dormancy")
		return
	var returned_stats: Dictionary = pilot_pool.call("get_pool_stats")
	if int(returned_stats.get("created", 0)) != 2 \
			or int(returned_stats.get("available", 0)) != 2 \
			or int(returned_stats.get("checked_out", 0)) != 0:
		aircraft.free()
		_fail("passenger bodies did not return to the two-pilot reserve")
		return
	for passenger_mount in passenger_mounts:
		if passenger_mount.call("get_pilot_visual") != null:
			aircraft.free()
			_fail("dormant passenger retained a pooled body")
			return
	presentation.discard_detached()
	aircraft.free()
	await process_frame
	print("[Aircraft11PassengerSmoketest] PASS capacity=3 dormant_records=3 viewed_occupants=4 presentation_ms=%.3f root_height=%.3f knee_bend=%.1fdeg toe_up=15deg feet_ahead=true distinct_helmets=true reserve_returned=2 overflow_rejected=true" % [presentation_ms, passenger_root_height, passenger_knee_bend_angle])
	quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _seated_leg_geometry(skeleton: Skeleton3D, suffix: String) -> Dictionary:
	var thigh_index := skeleton.find_bone("thigh_stretch" + suffix)
	var shin_index := skeleton.find_bone("leg_stretch" + suffix)
	var foot_index := skeleton.find_bone("foot" + suffix)
	var toe_index := skeleton.find_bone("toes_01" + suffix)
	if thigh_index < 0 or shin_index < 0 or foot_index < 0 or toe_index < 0:
		return {}
	skeleton.force_update_all_bone_transforms()
	var hip := skeleton.get_bone_global_pose(thigh_index).origin
	var knee := skeleton.get_bone_global_pose(shin_index).origin
	var ankle := skeleton.get_bone_global_pose(foot_index).origin
	var toe := skeleton.get_bone_global_pose(toe_index).origin
	var upper := Vector2(knee.y - hip.y, knee.z - hip.z).normalized()
	var lower := Vector2(ankle.y - knee.y, ankle.z - knee.z).normalized()
	var foot_vector := toe - ankle
	var rest_foot := skeleton.get_bone_global_rest(foot_index)
	var rest_toe := skeleton.get_bone_global_rest(toe_index)
	var rest_foot_vector := rest_toe.origin - rest_foot.origin
	return {
		"knee_bend_degrees": rad_to_deg(acos(clampf(upper.dot(lower), -1.0, 1.0))),
		"foot_forward_m": ankle.z - knee.z,
		"toe_up_degrees": rad_to_deg(
			atan2(-rest_foot_vector.y, rest_foot_vector.z)
			- atan2(-foot_vector.y, foot_vector.z)
		),
	}


func _find_pilot_material_color(node: Node, material_name: String) -> Color:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.mesh.surface_get_material(surface_index)
			if source == null:
				continue
			var normalized := String(source.resource_name).to_lower().replace("_", " ")
			var suffix_separator := normalized.rfind(".")
			if suffix_separator >= 0 and normalized.substr(suffix_separator + 1).is_valid_int():
				normalized = normalized.substr(0, suffix_separator)
			if normalized != material_name:
				continue
			var override := mesh_instance.get_surface_override_material(surface_index) as StandardMaterial3D
			if override != null:
				return override.albedo_color
	for child: Node in node.get_children():
		var found := _find_pilot_material_color(child, material_name)
		if found.r >= 0.0:
			return found
	return Color(-1.0, -1.0, -1.0, -1.0)


func _fail(reason: String) -> void:
	push_error("[Aircraft11PassengerSmoketest] FAIL %s" % reason)
	quit(1)
