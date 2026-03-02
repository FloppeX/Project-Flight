extends Node3D

@export var spawn_altitude: float = 600.0
@export var spawn_speed: float = 60.0
@export var respawn_delay: float = 3.0
@export var patrol_side_length: float = 2000.0
@export var max_ai_planes: int = 10

var _aircraft_scene: PackedScene
var _active_ai_planes: Array[RigidBody3D] = []

func _ready():
	_aircraft_scene = load("res://CompleteFighterJet.tscn")
	if not _aircraft_scene:
		push_error("[EnemyAircraftSpawner] Failed to load CompleteFighterJet.tscn")

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			_spawn_enemy()
		elif event.keycode == KEY_O:
			_toggle_ai_attack_mode()

func _spawn_enemy():
	if not _aircraft_scene:
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() >= max_ai_planes:
		print("[EnemyAircraftSpawner] Max AI planes reached: ", max_ai_planes)
		return

	var aircraft = _aircraft_scene.instantiate() as RigidBody3D
	if not aircraft:
		push_error("[EnemyAircraftSpawner] Failed to instantiate enemy aircraft")
		return

	aircraft.name = "FriendlyAI"
	get_tree().current_scene.add_child(aircraft)

	var spawn_pos = _get_carrier_position()
	spawn_pos.y += spawn_altitude
	aircraft.global_position = spawn_pos

	var forward_dir = _get_carrier_forward()
	var yaw = atan2(forward_dir.x, forward_dir.z)
	aircraft.global_rotation = Vector3(0, yaw, 0)
	aircraft.linear_velocity = forward_dir * spawn_speed

	# aircraft._ready() awaits process_frame before add_to_group("aircraft"), so we must
	# remove after it completes (next frame)
	await get_tree().process_frame
	await get_tree().process_frame  # Extra frame to ensure aircraft._ready() has finished
	aircraft.remove_from_group("aircraft")
	aircraft.add_to_group("friendlies")
	aircraft.add_to_group("ai_aircraft")

	# Friendly AI: keep ControlWeapons enabled for ground attack; disable player UI/targeting
	var disable_nodes = [
		"CameraController", "HeadsUpDisplay", "InstrumentPanel",
		"ControlTargeting"
	]
	for node_name in disable_nodes:
		var node = aircraft.find_child(node_name, true, false)
		if node:
			node.set_process(false)
			node.set_physics_process(false)
			node.set_process_input(false)
			if node is CanvasItem:
				node.visible = false
			elif node is Node3D:
				node.visible = false
	
	# Ensure camera tripods stay enabled so player can switch to view this AI plane
	for cam_name in ["CameraCockpit", "CameraChase", "CameraCinematic"]:
		var tripod = aircraft.get_node_or_null(cam_name)
		if tripod:
			tripod.set_process(true)
			tripod.set_physics_process(true)

	# AI planes spawn airborne - stow gear immediately
	var control_gear = aircraft.find_child("ControlLandingGear", true, false)
	if control_gear and control_gear.has_method("send_to_landing_gears"):
		control_gear.send_to_landing_gears("stow")
		control_gear.send_to_tailhooks("stow")
		if control_gear.has_method("send_to_tailhook_simple"):
			control_gear.send_to_tailhook_simple(false)
		if "gear_down_state" in control_gear:
			control_gear.gear_down_state = false
		if control_gear.has_method("_set_collider_disabled"):
			control_gear._set_collider_disabled(true)

	if aircraft.has_signal("crashed"):
		aircraft.crashed.connect(_on_enemy_crashed.bind(aircraft))
	if aircraft.has_signal("destroyed"):
		aircraft.destroyed.connect(_on_enemy_destroyed.bind(aircraft))

	_active_ai_planes.append(aircraft)
	pass

	await get_tree().create_timer(0.5).timeout
	_configure_ai_patrol(aircraft)

func _configure_ai_patrol(aircraft: RigidBody3D):
	if not is_instance_valid(aircraft):
		return

	var ai_toggle = aircraft.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("enable_ai"):
		ai_toggle.enable_ai()

	var ai_pilot = aircraft.find_child("AIPilot", true, false)
	if not ai_pilot:
		push_error("[EnemyAircraftSpawner] No AIPilot found on enemy aircraft")
		return

	var center = _get_carrier_position()
	ai_pilot.carrier_position = center
	ai_pilot.target_altitude = 600.0
	ai_pilot.patrol_altitude_m = 600.0
	ai_pilot.target_speed = spawn_speed

	# Build a square patrol: 4 corners, each side = patrol_side_length, centered on carrier
	var half = patrol_side_length / 2.0
	var alt: float = 600.0
	ai_pilot.waypoints.clear()
	ai_pilot.waypoints.append(center + Vector3( half, alt,  half))
	ai_pilot.waypoints.append(center + Vector3(-half, alt,  half))
	ai_pilot.waypoints.append(center + Vector3(-half, alt, -half))
	ai_pilot.waypoints.append(center + Vector3( half, alt, -half))
	# Start at the waypoint most ahead of the aircraft (avoids flying away from first target)
	ai_pilot.current_waypoint_index = _waypoint_most_ahead(aircraft, ai_pilot.waypoints)

	ai_pilot.change_state(AIPilot.State.SEARCH)

func _on_enemy_crashed(_impact_velocity: float, aircraft: RigidBody3D):
	_schedule_respawn(aircraft)

func _on_enemy_destroyed(aircraft: RigidBody3D):
	# Notify camera switcher so it can linger on this plane before switching.
	var switcher = get_tree().get_first_node_in_group("standalone_camera_switcher")
	if switcher and switcher.has_method("notify_plane_destroyed"):
		switcher.notify_plane_destroyed(aircraft)
	_schedule_respawn(aircraft)

func _schedule_respawn(aircraft: RigidBody3D):
	if is_instance_valid(aircraft):
		if aircraft.crashed.is_connected(_on_enemy_crashed):
			aircraft.crashed.disconnect(_on_enemy_crashed)
		if aircraft.destroyed.is_connected(_on_enemy_destroyed):
			aircraft.destroyed.disconnect(_on_enemy_destroyed)

	await get_tree().create_timer(respawn_delay).timeout

	if is_instance_valid(aircraft):
		aircraft.queue_free()
	_active_ai_planes.erase(aircraft)
	_prune_active_ai_planes()

	if _active_ai_planes.size() < max_ai_planes:
		_spawn_enemy()

func _prune_active_ai_planes():
	_active_ai_planes = _active_ai_planes.filter(func(p): return is_instance_valid(p))

func _toggle_ai_attack_mode():
	"""Toggle all AI planes between patrol mode and attack mode (O key)."""
	var ai_planes = get_tree().get_nodes_in_group("ai_aircraft")
	var pilots: Array[AIPilot] = []
	for node in ai_planes:
		if not is_instance_valid(node):
			continue
		var pilot = node.find_child("AIPilot", true, false)
		if pilot and pilot is AIPilot:
			pilots.append(pilot)
	if pilots.is_empty():
		return
	var new_mode: bool = not pilots[0].ground_attack_enabled
	for pilot in pilots:
		pilot.ground_attack_enabled = new_mode
	var mode_str: String = "ATTACK" if new_mode else "PATROL"
	print("[EnemyAircraftSpawner] AI mode: ", mode_str, " (", pilots.size(), " plane(s))")

func _waypoint_most_ahead(aircraft: Node3D, waypoints: Array) -> int:
	"""Return index of waypoint that is most ahead of aircraft (largest forward dot product)."""
	if waypoints.is_empty():
		return 0
	var fwd := aircraft.global_transform.basis.z
	var best_idx := 0
	var best_dot := -INF
	for i in range(waypoints.size()):
		var wp: Vector3 = waypoints[i]
		var to_wp := (wp - aircraft.global_position).normalized()
		var dot_val := to_wp.dot(fwd)
		if dot_val > best_dot:
			best_dot = dot_val
			best_idx = i
	return best_idx

func _get_carrier_position() -> Vector3:
	var carriers = get_tree().get_nodes_in_group("carrier")
	if carriers.size() > 0 and carriers[0] is Node3D:
		return (carriers[0] as Node3D).global_position
	return Vector3.ZERO

func _get_carrier_forward() -> Vector3:
	var carriers = get_tree().get_nodes_in_group("carrier")
	if carriers.size() > 0 and carriers[0] is Node3D:
		return (carriers[0] as Node3D).global_transform.basis.z.normalized()
	return Vector3(0, 0, 1)
