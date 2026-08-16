extends Node
class_name EjectionSequence

const FlightDirectorScript = preload("res://AirOps/FlightDirector.gd")
@export var canopy_path: NodePath
@export var cockpit_canopy_visibility_path: NodePath
@export var ejection_seat_path: NodePath
@export var cockpit_pilot_path: NodePath
@export var cockpit_camera_rig_path: NodePath
@export var auto_start_on_critical_damage: bool = true
@export var auto_start_on_destroyed: bool = true
@export var canopy_upward_speed_mps: float = 28.0
@export var canopy_rearward_speed_mps: float = 4.0
@export var canopy_spin_rad_s: Vector3 = Vector3(3.0, 6.0, 2.0)
@export var canopy_mass_kg: float = 18.0
@export var canopy_lifetime_s: float = 20.0
@export var seat_launch_delay_s: float = 0.5
@export var seat_burn_duration_s: float = 1.0
## Time from seat launch until the pilot and seat physically separate.
@export var seat_separation_delay_s: float = 3.0
@export var seat_mass_kg: float = 125.0
@export var seat_launch_angle_deg: float = 75.0
@export var seat_rearward_bias: float = 1.0
@export var seat_rocket_acceleration_mps2: float = 38.0
@export var seat_guidance_acceleration_mps2: float = 55.0
@export var seat_target_upward_velocity_mps: float = 42.0
@export var seat_lifetime_s: float = 45.0
@export_group("Parachute")
@export var parachute_scene: PackedScene = preload("res://Aircraft/Visuals/Parachute.tscn")
## Freefall time after seat separation before the canopy opens.
@export var parachute_deploy_delay_s: float = 1.0
@export var parachute_local_offset: Vector3 = Vector3.ZERO
@export var parachute_local_rotation_deg: Vector3 = Vector3.ZERO
@export var parachute_local_scale: Vector3 = Vector3.ONE
@export var parachute_harness_node_name: StringName = &"Harness"
@export var parachute_pilot_mount_node_name: StringName = &"PilotMount"
@export var parachute_head_camera_mount_node_name: StringName = &"HeadCameraMount"
@export var parachute_physics_origin_node_name: StringName = &"PhysicsOrigin"
@export var parachute_pilot_mass_node_name: StringName = &"PilotMass"
@export var parachute_pilot_collision_node_name: StringName = &"PilotCollision"
@export var align_parachute_harness_to_pilot: bool = true
@export var parachute_descent_speed_mps: float = 6.0
@export var parachute_rope_length_m: float = 6.0
@export var parachute_vertical_spring_n_per_mps: float = 120.0
@export var parachute_horizontal_drag_n_per_mps: float = 20.0
@export var parachute_angular_damp: float = 1.5
@export_group("Parachute Wind")
@export var wind_velocity: Vector3 = Vector3(4.0, 0.5, 0.0)   ## Persistent world-space wind (x/z = horizontal drift, y = lift)
@export var wind_gust_speed_mps: float = 3.0                   ## Extra speed added by gusts on top of base wind
@export var wind_gust_time_scale: float = 0.2                  ## How fast gusts cycle (higher = choppier)
@export var wind_gust_impulse_n: float = 5.0                   ## Impulse strength of each sway-causing gust (N·s)
@export var wind_gust_impulse_min_interval_s: float = 1.5      ## Minimum time between sway gusts
@export var wind_gust_impulse_max_interval_s: float = 5.0      ## Maximum time between sway gusts
@export_group("")
## Legacy — unused, kept so saved scenes don't lose data
@export var parachute_drag_strength: float = 4.0
@export var parachute_horizontal_drag_strength: float = 1.4
@export var pilot_landing_clearance_m: float = 0.15
@export var pilot_landing_probe_mask: int = 513
@export_group("Seat Separation")
@export var separated_seat_mass_kg: float = 35.0
@export var separated_seat_downward_speed_mps: float = 5.0
@export var separated_seat_rearward_speed_mps: float = 1.5
@export var separated_seat_spin_rad_s: Vector3 = Vector3(2.5, 4.0, -1.5)
@export var separated_seat_lifetime_s: float = 30.0
@export_group("Input")
@export var dpad_ejection_enabled: bool = true
@export var dpad_ejection_button_index: int = JOY_BUTTON_DPAD_UP
@export var dpad_ejection_required_presses: int = 3
@export var dpad_ejection_window_s: float = 1.0

var _has_started: bool = false
var _wind_time: float = 0.0
var _next_gust_impulse_s: float = 0.0
var _pilot_body: RigidBody3D = null
var _seat_launch_direction: Vector3 = Vector3.UP
var _seat_burn_elapsed_s: float = 0.0
var _seat_burn_active: bool = false
var _seat_separated: bool = false
var _parachute_deploy_scheduled: bool = false
var _parachute_deployed: bool = false
var _parachute_force_offset_local: Vector3 = Vector3.ZERO
var _pilot_landed: bool = false
var _pilot_focus_node: Node3D = null
var _pilot_audio_listener: AudioListener3D = null
var _dpad_ejection_press_times_ms: Array[int] = []
var _ejection_seat_available: bool = false


func _ready() -> void:
	_ejection_seat_available = _has_ejection_seat()
	set_physics_process(false)
	if not _ejection_seat_available:
		set_process_input(false)
		return
	call_deferred("_connect_aircraft_signals")


func _connect_aircraft_signals() -> void:
	var aircraft := get_parent()
	if aircraft == null:
		return
	if auto_start_on_critical_damage and aircraft.has_signal("damaged"):
		aircraft.connect("damaged", Callable(self, "_on_aircraft_damaged"))
	if auto_start_on_destroyed and aircraft.has_signal("destroyed"):
		aircraft.connect("destroyed", Callable(self, "start_ejection"))


func start_ejection() -> void:
	if _has_started:
		return
	if not _ejection_seat_available and not _has_ejection_seat():
		return
	_has_started = true
	_jettison_canopy()
	if seat_launch_delay_s <= 0.0:
		_launch_ejection_seat()
	else:
		var timer := get_tree().create_timer(seat_launch_delay_s)
		timer.timeout.connect(_launch_ejection_seat)


func _input(event: InputEvent) -> void:
	if not _ejection_seat_available:
		return
	if not dpad_ejection_enabled or _has_started:
		return
	if not _should_accept_player_ejection_input():
		return
	if not (event is InputEventJoypadButton):
		return
	var button_event := event as InputEventJoypadButton
	if not button_event.pressed:
		return
	if button_event.button_index != dpad_ejection_button_index:
		return

	var now_ms := Time.get_ticks_msec()
	var window_ms := int(maxf(dpad_ejection_window_s, 0.05) * 1000.0)
	_dpad_ejection_press_times_ms.append(now_ms)
	for i in range(_dpad_ejection_press_times_ms.size() - 1, -1, -1):
		if now_ms - _dpad_ejection_press_times_ms[i] > window_ms:
			_dpad_ejection_press_times_ms.remove_at(i)

	if _dpad_ejection_press_times_ms.size() >= max(1, dpad_ejection_required_presses):
		_dpad_ejection_press_times_ms.clear()
		start_ejection()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _pilot_body == null or not is_instance_valid(_pilot_body):
		_seat_burn_active = false
		_parachute_deployed = false
		set_physics_process(false)
		return
	if not _seat_burn_active and not _parachute_deployed:
		set_physics_process(false)
		return
	if _seat_burn_active:
		_update_seat_rocket_burn(delta)
	if _parachute_deployed:
		_wind_time += delta * wind_gust_time_scale
		_update_parachute_descent(delta)


func _update_seat_rocket_burn(delta: float) -> void:
	_seat_burn_elapsed_s += delta
	var burn_duration := maxf(seat_burn_duration_s, 0.001)
	var burn_ratio := clampf(_seat_burn_elapsed_s / burn_duration, 0.0, 1.0)
	var guided_direction := _seat_launch_direction.slerp(Vector3.UP, burn_ratio).normalized()
	_pilot_body.apply_central_force(guided_direction * seat_rocket_acceleration_mps2 * _pilot_body.mass)

	var desired_velocity := Vector3.UP * seat_target_upward_velocity_mps
	var velocity_error := desired_velocity - _pilot_body.linear_velocity
	var correction := velocity_error.limit_length(seat_guidance_acceleration_mps2 * delta)
	_pilot_body.linear_velocity += correction

	if _seat_burn_elapsed_s >= seat_burn_duration_s:
		_seat_burn_active = false


func _on_aircraft_damaged(_damage_amount: float, current_health: float) -> void:
	if current_health <= 0.0:
		start_ejection()


func _jettison_canopy() -> void:
	var canopy := get_node_or_null(canopy_path) as Node3D
	if canopy == null:
		var aircraft_root := get_parent()
		if aircraft_root != null:
			canopy = aircraft_root.find_child("canopy", true, false) as Node3D
	if canopy == null:
		push_warning("[EjectionSequence] Canopy node not found: %s" % canopy_path)
		return

	var aircraft := get_parent() as Node3D
	if aircraft == null:
		return

	var canopy_global := canopy.global_transform
	_release_canopy_from_cockpit_visibility(canopy)

	var canopy_body := RigidBody3D.new()
	canopy_body.name = "%s_JettisonedCanopy" % aircraft.name
	canopy_body.mass = maxf(canopy_mass_kg, 0.01)
	canopy_body.collision_layer = 0
	canopy_body.collision_mask = 0

	var detached_parent := aircraft.get_parent()
	if detached_parent == null:
		detached_parent = get_tree().current_scene
	if detached_parent == null:
		detached_parent = get_tree().root
	detached_parent.add_child(canopy_body)
	canopy_body.global_transform = canopy_global

	var old_parent := canopy.get_parent()
	if old_parent != null:
		old_parent.remove_child(canopy)
	canopy_body.add_child(canopy)
	canopy.transform = Transform3D.IDENTITY
	canopy.visible = true

	var aircraft_body := aircraft as RigidBody3D
	var inherited_velocity := aircraft_body.linear_velocity if aircraft_body != null else Vector3.ZERO
	var local_up := aircraft.global_transform.basis.y.normalized()
	var local_rear := aircraft.global_transform.basis.z.normalized()
	canopy_body.linear_velocity = inherited_velocity + local_up * canopy_upward_speed_mps + local_rear * canopy_rearward_speed_mps
	canopy_body.angular_velocity = canopy_spin_rad_s

	if canopy_lifetime_s > 0.0:
		var timer := get_tree().create_timer(canopy_lifetime_s)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(canopy_body):
				canopy_body.queue_free()
		)


func _launch_ejection_seat() -> void:
	if _pilot_body != null and is_instance_valid(_pilot_body):
		return

	var aircraft := get_parent() as Node3D
	if aircraft == null:
		return

	var seat := _find_aircraft_child(ejection_seat_path, "EjectionSeat") as Node3D
	if seat == null:
		push_warning("[EjectionSequence] Ejection seat node not found: %s" % ejection_seat_path)
		return

	var seat_global := seat.global_transform
	var aircraft_body := aircraft as RigidBody3D
	var inherited_velocity := aircraft_body.linear_velocity if aircraft_body != null else Vector3.ZERO
	var should_take_player_view := _should_take_player_view(aircraft)

	var seat_body := RigidBody3D.new()
	seat_body.name = "%s_PilotBody" % aircraft.name
	seat_body.mass = maxf(seat_mass_kg, 0.01)
	seat_body.collision_layer = 0
	seat_body.collision_mask = 0
	seat_body.linear_damp = 0.05
	seat_body.angular_damp = 1.5

	var detached_parent := aircraft.get_parent()
	if detached_parent == null:
		detached_parent = get_tree().current_scene
	if detached_parent == null:
		detached_parent = get_tree().root
	detached_parent.add_child(seat_body)
	seat_body.global_transform = seat_global
	seat_body.contact_monitor = true
	seat_body.max_contacts_reported = maxi(seat_body.max_contacts_reported, 4)
	seat_body.body_entered.connect(_on_pilot_body_entered)
	if should_take_player_view:
		_prepare_ejected_pilot_camera_target(aircraft, seat_body)

	_reparent_preserve_global(seat, seat_body)
	seat.transform = Transform3D.IDENTITY

	var pilot := _find_aircraft_child(cockpit_pilot_path, "CockpitPilot") as Node3D
	if pilot != null:
		_reparent_preserve_global(pilot, seat_body)
		_set_pilot_ejection_pose(pilot, &"seat_firing", 0.12)

	var camera_rig := _find_aircraft_child(cockpit_camera_rig_path, "CameraCockpit") as Node3D
	if camera_rig != null:
		if should_take_player_view:
			_prepare_camera_for_ejection(camera_rig)
		_reparent_preserve_global(camera_rig, seat_body)

	_pilot_body = seat_body
	_pilot_focus_node = _get_pilot_focus_node(camera_rig, pilot)
	if should_take_player_view:
		_focus_cameras_on_ejected_pilot(seat_body, _pilot_focus_node)
		_enable_ejected_pilot_audio(_pilot_focus_node)
	_seat_launch_direction = _calculate_seat_launch_direction(aircraft)
	_seat_burn_elapsed_s = 0.0
	_seat_burn_active = seat_burn_duration_s > 0.0
	_seat_separated = false
	_parachute_deploy_scheduled = false
	_parachute_deployed = false
	_parachute_force_offset_local = Vector3.UP * maxf(parachute_rope_length_m, 0.1)
	set_physics_process(_seat_burn_active)
	seat_body.linear_velocity = inherited_velocity + _seat_launch_direction * 8.0
	_schedule_seat_separation()

	if seat_lifetime_s > 0.0:
		var timer := get_tree().create_timer(seat_lifetime_s)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(seat_body) and not bool(seat_body.get_meta("ejected_pilot_camera_target", false)):
				seat_body.queue_free()
		)
	# From this point on the seat, pilot, cameras, and timing sequence are all
	# independent of the source aircraft. Retire that aircraft immediately so it
	# cannot remain as a stale camera target after a manual ejection.
	_detach_sequence_from_aircraft()
	_retire_source_aircraft(aircraft)


func _schedule_seat_separation() -> void:
	var delay := maxf(maxf(seat_separation_delay_s, seat_burn_duration_s), 0.0)
	if delay <= 0.0:
		_separate_seat_from_pilot()
		return
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(_separate_seat_from_pilot)


func _schedule_parachute_deploy() -> void:
	if _parachute_deploy_scheduled or _parachute_deployed:
		return
	_parachute_deploy_scheduled = true
	var delay := maxf(parachute_deploy_delay_s, 0.0)
	if delay <= 0.0:
		_deploy_parachute()
		return
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(_deploy_parachute)


func _deploy_parachute() -> void:
	if _parachute_deployed:
		return
	if _pilot_body == null or not is_instance_valid(_pilot_body):
		return
	if not _seat_separated:
		_separate_seat_from_pilot()
		return
	if parachute_scene == null:
		return
	var pilot := _get_ejected_pilot()
	_stabilize_pilot_body_orientation(1.0)
	_pilot_body.angular_velocity = Vector3.ZERO
	_pilot_body.angular_damp = maxf(parachute_angular_damp, _pilot_body.angular_damp)

	var parachute := parachute_scene.instantiate() as Node3D
	if parachute == null:
		return
	parachute.name = "Parachute"
	_pilot_body.add_child(parachute)
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(parachute_local_rotation_deg.x),
		deg_to_rad(parachute_local_rotation_deg.y),
		deg_to_rad(parachute_local_rotation_deg.z)
	)).scaled(parachute_local_scale)
	parachute.transform = _get_parachute_transform(parachute, basis)
	_set_pilot_hanging_transform(pilot, parachute)
	_rebase_pilot_body_to_parachute_origin(parachute)
	_configure_parachute_mass_properties(parachute)
	_set_pilot_ejection_pose(pilot, &"parachute", 0.3)
	_set_head_camera_mount_transform(parachute)
	_parachute_deployed = true
	set_physics_process(true)


func _separate_seat_from_pilot() -> void:
	if _seat_separated or _pilot_body == null or not is_instance_valid(_pilot_body):
		return
	var seat := _pilot_body.get_node_or_null("EjectionSeat") as Node3D
	if seat == null:
		push_warning("[EjectionSequence] Seat separation requested without an EjectionSeat child")
	else:
		var separated_body := RigidBody3D.new()
		separated_body.name = "%s_SeparatedSeat" % _pilot_body.name
		separated_body.mass = maxf(separated_seat_mass_kg, 0.01)
		separated_body.collision_layer = 0
		separated_body.collision_mask = 0
		separated_body.linear_damp = 0.02
		separated_body.angular_damp = 0.1

		var detached_parent := _pilot_body.get_parent()
		if detached_parent == null:
			detached_parent = get_tree().current_scene
		if detached_parent == null:
			detached_parent = get_tree().root
		detached_parent.add_child(separated_body)
		separated_body.global_transform = seat.global_transform
		separated_body.contact_monitor = true
		separated_body.max_contacts_reported = maxi(separated_body.max_contacts_reported, 4)
		separated_body.body_entered.connect(func(body: Node) -> void:
			if _is_terrain_body(body) and is_instance_valid(separated_body):
				separated_body.queue_free()
		)

		_reparent_preserve_global(seat, separated_body)
		seat.transform = Transform3D.IDENTITY

		var rear := _pilot_body.global_transform.basis.z.normalized()
		var inherited_velocity := _pilot_body.linear_velocity
		separated_body.linear_velocity = Vector3(
			inherited_velocity.x,
			minf(inherited_velocity.y - separated_seat_downward_speed_mps, -separated_seat_downward_speed_mps),
			inherited_velocity.z
		) + rear * separated_seat_rearward_speed_mps
		separated_body.angular_velocity = separated_seat_spin_rad_s
		_pilot_body.mass = maxf(seat_mass_kg - separated_seat_mass_kg, 0.01)

		if separated_seat_lifetime_s > 0.0:
			var timer := get_tree().create_timer(separated_seat_lifetime_s)
			timer.timeout.connect(func() -> void:
				if is_instance_valid(separated_body):
					separated_body.queue_free()
			)

	_seat_separated = true
	_seat_burn_active = false
	_set_pilot_ejection_pose(_get_ejected_pilot(), &"falling", 0.25)
	_schedule_parachute_deploy()


func _update_parachute_descent(delta: float) -> void:
	var vel := _pilot_body.linear_velocity
	var mass := _pilot_body.mass

	# The rigid-body origin is at the canopy top while its center of mass is down at
	# the pilot. Applying canopy force at the origin therefore creates pendulum torque.
	var canopy_offset := _pilot_body.global_transform.basis * _parachute_force_offset_local

	# Vertical: gravity compensation + spring toward terminal descent speed.
	# At terminal velocity the spring term is zero and lift exactly cancels gravity.
	var target_vy := -absf(parachute_descent_speed_mps)
	var lift := mass * 9.8 + (target_vy - vel.y) * parachute_vertical_spring_n_per_mps
	lift = maxf(lift, 0.0)  # canopy pulls up only

	# Horizontal: drag opposes velocity relative to the air mass (wind).
	# Pilot is pushed toward wind speed; force at canopy point still creates pendulum torque.
	var wind := _get_wind_velocity()
	var rel_x := vel.x - wind.x
	var rel_z := vel.z - wind.z
	lift += maxf(wind.y, 0.0) * mass  # upward wind adds lift; downdrafts don't pull through the canopy
	var force := Vector3(
		-rel_x * parachute_horizontal_drag_n_per_mps,
		lift,
		-rel_z * parachute_horizontal_drag_n_per_mps,
	)
	_apply_canopy_force(force, canopy_offset)
	_apply_gust_impulse(delta)
	_check_parachute_landing(delta)


func _check_parachute_landing(delta: float) -> void:
	if _pilot_landed or _pilot_body == null or not is_instance_valid(_pilot_body):
		return
	var pilot_pos := _get_pilot_ground_reference_position()
	var surface_point: Variant = _get_nearby_landing_surface_point(pilot_pos, _pilot_body.linear_velocity, delta)
	if surface_point != null:
		_land_pilot(surface_point)
		return

	var ground_y := _sample_landing_height(pilot_pos)
	if _is_valid_landing_height(ground_y) and pilot_pos.y <= ground_y + pilot_landing_clearance_m:
		_land_pilot(Vector3(pilot_pos.x, ground_y, pilot_pos.z))


func _get_pilot_ground_reference_position() -> Vector3:
	var pilot := _get_ejected_pilot()
	if pilot != null and is_instance_valid(pilot):
		return pilot.global_position
	if _pilot_body != null and is_instance_valid(_pilot_body) \
			and _pilot_body.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
		return _pilot_body.to_global(_pilot_body.center_of_mass)
	return _pilot_body.global_position if _pilot_body != null else Vector3.ZERO


func _apply_gust_impulse(delta: float) -> void:
	_next_gust_impulse_s -= delta
	if _next_gust_impulse_s > 0.0:
		return
	_next_gust_impulse_s = randf_range(wind_gust_impulse_min_interval_s, wind_gust_impulse_max_interval_s)
	if wind_gust_impulse_n <= 0.0:
		return
	var angle := randf() * TAU
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	var strength := randf_range(wind_gust_impulse_n * 0.5, wind_gust_impulse_n)
	var canopy_offset := _pilot_body.global_transform.basis * _parachute_force_offset_local
	_apply_canopy_impulse(direction * strength, canopy_offset)


func _apply_canopy_force(force: Vector3, canopy_offset_world: Vector3) -> void:
	_pilot_body.apply_central_force(force)
	var mass_offset_world := _pilot_body.global_transform.basis * _pilot_body.center_of_mass
	var lever_arm := canopy_offset_world - mass_offset_world
	_pilot_body.apply_torque(lever_arm.cross(force))


func _apply_canopy_impulse(impulse: Vector3, canopy_offset_world: Vector3) -> void:
	_pilot_body.apply_central_impulse(impulse)
	var mass_offset_world := _pilot_body.global_transform.basis * _pilot_body.center_of_mass
	var lever_arm := canopy_offset_world - mass_offset_world
	_pilot_body.apply_torque_impulse(lever_arm.cross(impulse))


func _get_wind_velocity() -> Vector3:
	var t := _wind_time
	# Multi-frequency sine noise — no FastNoiseLite needed
	var gust := Vector3(
		sin(t * 1.31) * cos(t * 0.73),
		sin(t * 0.47) * 0.25,
		cos(t * 1.17) * sin(t * 0.89),
	) * wind_gust_speed_mps
	return wind_velocity + gust


func _get_nearby_landing_surface_point(seat_pos: Vector3, velocity: Vector3, delta: float) -> Variant:
	var space_state := _pilot_body.get_world_3d().direct_space_state
	if space_state == null:
		return null
	var probe_depth := maxf(1.0 + pilot_landing_clearance_m, absf(velocity.y) * delta + 0.75 + pilot_landing_clearance_m)
	var from := seat_pos + Vector3.UP * 0.25
	var to := seat_pos - Vector3.UP * probe_depth
	var query := PhysicsRayQueryParameters3D.create(from, to, pilot_landing_probe_mask)
	query.exclude = [_pilot_body.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var body := hit.get("collider", null) as Node
	if not _is_terrain_body(body):
		return null
	return hit.get("position", seat_pos)


func _sample_landing_height(world_pos: Vector3) -> float:
	var h: float = TerrainNavGrid.sample_height(world_pos.x, world_pos.z)
	if _is_valid_landing_height(h):
		return h
	var terrain := get_tree().get_first_node_in_group("terrain_provider")
	if terrain != null and terrain.has_method("get_height"):
		var sampled: Variant = terrain.call("get_height", world_pos)
		if sampled is float:
			h = sampled
		elif sampled is int:
			h = float(sampled)
		if _is_valid_landing_height(h):
			return h
	return TerrainNavGrid.IMPASSABLE


func _is_valid_landing_height(height: float) -> bool:
	return not is_nan(height) and height > TerrainNavGrid.IMPASSABLE * 0.5


func _calculate_seat_launch_direction(aircraft: Node3D) -> Vector3:
	var local_up := aircraft.global_transform.basis.y.normalized()
	var local_rear := aircraft.global_transform.basis.z.normalized() * seat_rearward_bias
	var angle_from_up := deg_to_rad(90.0 - clampf(seat_launch_angle_deg, 1.0, 89.0))
	var local_launch := (local_up * cos(angle_from_up) + local_rear.normalized() * sin(angle_from_up)).normalized()
	if local_launch.dot(Vector3.UP) < 0.0:
		local_launch = local_launch.slerp(Vector3.UP, 0.45).normalized()
	return local_launch


func _get_parachute_transform(parachute: Node3D, basis: Basis) -> Transform3D:
	var origin := parachute_local_offset
	if align_parachute_harness_to_pilot:
		var pilot := _get_ejected_pilot()
		var harness_lowest_point: Variant = _get_harness_lowest_point(parachute)
		if pilot != null and harness_lowest_point != null:
			var pilot_local := _pilot_body.to_local(pilot.global_position)
			var harness_offset := basis * (harness_lowest_point as Vector3)
			origin = Vector3(
				pilot_local.x + parachute_local_offset.x,
				pilot_local.y + parachute_local_offset.y - harness_offset.y,
				pilot_local.z + parachute_local_offset.z
			)
	return Transform3D(basis, origin)


func _rebase_pilot_body_to_parachute_origin(parachute: Node3D) -> void:
	if _pilot_body == null or not is_instance_valid(_pilot_body):
		return
	var physics_origin := parachute.find_child(
		str(parachute_physics_origin_node_name), true, false
	) as Node3D
	var origin_global := _pilot_body.global_position \
		+ _pilot_body.global_transform.basis.y * maxf(parachute_rope_length_m, 0.1)
	if physics_origin != null:
		origin_global = physics_origin.global_position

	# Moving the body origin must not move any of its visuals, pilot, or camera.
	var saved_children: Array[Dictionary] = []
	for child_variant in _pilot_body.get_children():
		var child := child_variant as Node3D
		if child != null:
			saved_children.append({"node": child, "global_transform": child.global_transform})
	var rebased_transform := _pilot_body.global_transform
	rebased_transform.origin = origin_global
	_pilot_body.global_transform = rebased_transform
	for saved in saved_children:
		var child := saved["node"] as Node3D
		if child != null and is_instance_valid(child):
			var saved_transform: Transform3D = saved["global_transform"]
			child.global_transform = saved_transform

	# Canopy forces are applied at the new body origin. Keep this as a local offset
	# so force calls continue to work if a fallback marker is used later.
	_parachute_force_offset_local = _pilot_body.to_local(origin_global)


func _configure_parachute_mass_properties(parachute: Node3D) -> void:
	if _pilot_body == null or not is_instance_valid(_pilot_body):
		return
	var pilot_mass := parachute.find_child(
		str(parachute_pilot_mass_node_name), true, false
	) as Node3D
	var mass_global := _pilot_body.global_position \
		- _pilot_body.global_transform.basis.y * maxf(parachute_rope_length_m, 0.1)
	if pilot_mass != null:
		mass_global = pilot_mass.global_position
	var mass_local := _pilot_body.to_local(mass_global)
	if mass_local.length_squared() < 0.01:
		mass_local = Vector3.DOWN * maxf(parachute_rope_length_m, 0.1)
	_pilot_body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	_pilot_body.center_of_mass = mass_local
	var suspension_length := maxf(mass_local.length(), 0.1)
	var pendulum_inertia := _pilot_body.mass * suspension_length * suspension_length
	_pilot_body.inertia = Vector3.ONE * pendulum_inertia

	# A direct collision shape gives the physics solver the pilot-sized inertia it
	# needs. It remains non-colliding because the ejected body uses layer/mask zero.
	var pilot_collision := parachute.find_child(
		str(parachute_pilot_collision_node_name), true, false
	) as CollisionShape3D
	if pilot_collision != null and pilot_collision.get_parent() != _pilot_body:
		_reparent_preserve_global(pilot_collision, _pilot_body)


func _get_harness_lowest_point(parachute: Node3D) -> Variant:
	var harness := parachute.find_child(str(parachute_harness_node_name), true, false) as Node3D
	if harness == null:
		return null
	var lowest_point: Variant = null
	for child in _get_mesh_nodes(harness):
		var mesh_instance := child as MeshInstance3D
		var aabb := mesh_instance.get_aabb()
		var corners := [
			aabb.position,
			aabb.position + Vector3(aabb.size.x, 0.0, 0.0),
			aabb.position + Vector3(0.0, aabb.size.y, 0.0),
			aabb.position + Vector3(0.0, 0.0, aabb.size.z),
			aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0),
			aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z),
			aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z),
			aabb.position + aabb.size,
		]
		for corner in corners:
			var point := parachute.to_local(mesh_instance.to_global(corner))
			if lowest_point == null or point.y < (lowest_point as Vector3).y:
				lowest_point = point
	return lowest_point


func _get_mesh_nodes(root: Node) -> Array[MeshInstance3D]:
	var nodes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		nodes.append(root as MeshInstance3D)
	for child_variant in root.get_children():
		var child := child_variant as Node
		if child != null:
			nodes.append_array(_get_mesh_nodes(child))
	return nodes


func _find_aircraft_child(path: NodePath, fallback_name: StringName) -> Node:
	var node: Node = get_node_or_null(path) if path != NodePath() else null
	if node != null:
		return node
	var aircraft := get_parent()
	if aircraft == null:
		return null
	return aircraft.find_child(str(fallback_name), true, false)


func _has_ejection_seat() -> bool:
	return _find_aircraft_child(ejection_seat_path, "EjectionSeat") is Node3D


func _reparent_preserve_global(node: Node3D, new_parent: Node) -> void:
	var saved_global := node.global_transform
	var old_parent := node.get_parent()
	if old_parent != null:
		old_parent.remove_child(node)
	new_parent.add_child(node)
	node.global_transform = saved_global


func _stabilize_pilot_body_orientation(weight: float) -> void:
	if _pilot_body == null or not is_instance_valid(_pilot_body):
		return
	var clamped_weight := clampf(weight, 0.0, 1.0)
	if clamped_weight <= 0.0:
		return
	var velocity_flat := Vector3(_pilot_body.linear_velocity.x, 0.0, _pilot_body.linear_velocity.z)
	var forward := _pilot_body.global_transform.basis.z
	forward.y = 0.0
	if velocity_flat.length_squared() > 0.25:
		forward = velocity_flat.normalized()
	elif forward.length_squared() > 0.001:
		forward = forward.normalized()
	else:
		forward = Vector3.BACK
	var desired := Transform3D(Basis.looking_at(-forward, Vector3.UP), _pilot_body.global_position)
	_pilot_body.global_transform = _pilot_body.global_transform.interpolate_with(desired, clamped_weight)


func _set_pilot_hanging_transform(pilot: Node3D, parachute: Node3D = null) -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	if parachute != null and is_instance_valid(parachute):
		var pilot_mount := parachute.find_child(str(parachute_pilot_mount_node_name), true, false) as Node3D
		if pilot_mount != null:
			pilot.transform = _get_marker_transform_in_pilot_body(pilot_mount)
			return
	pilot.transform = Transform3D.IDENTITY


func _set_head_camera_mount_transform(parachute: Node3D) -> void:
	if parachute == null or not is_instance_valid(parachute):
		return
	if _pilot_focus_node == null or not is_instance_valid(_pilot_focus_node):
		return
	var camera_marker := _get_head_camera_marker(parachute)
	if camera_marker == null:
		return
	var target: Node3D = null
	if _pilot_focus_node is Camera3D:
		target = _pilot_focus_node.get_parent() as Node3D
	else:
		var focus_name := String(_pilot_focus_node.name).to_lower()
		if focus_name.contains("camera"):
			target = _pilot_focus_node
	if target == null:
		return
	var marker_transform := _get_marker_transform_in_pilot_body(camera_marker)
	if _pilot_focus_node is Camera3D and _pilot_focus_node.get_parent() == target:
		target.transform = marker_transform * _pilot_focus_node.transform.affine_inverse()
	else:
		target.transform = marker_transform
	_sync_cockpit_camera_base_transform(target)


func _get_head_camera_marker(parachute: Node3D) -> Node3D:
	var camera_mount := parachute.find_child(str(parachute_head_camera_mount_node_name), true, false) as Node3D
	if camera_mount == null:
		return null
	var preview_camera := camera_mount.find_child("Camera3D", true, false) as Node3D
	if preview_camera != null:
		return preview_camera
	return camera_mount


func _sync_cockpit_camera_base_transform(camera_rig: Node3D) -> void:
	if camera_rig == null or not is_instance_valid(camera_rig):
		return
	if "base_position" in camera_rig:
		camera_rig.set("base_position", camera_rig.position)
	if "base_rotation" in camera_rig:
		camera_rig.set("base_rotation", camera_rig.rotation)
	if "current_look" in camera_rig:
		camera_rig.set("current_look", Vector3.ZERO)
	if "g_force_offset" in camera_rig:
		camera_rig.set("g_force_offset", Vector3.ZERO)


func _get_marker_transform_in_pilot_body(marker: Node3D) -> Transform3D:
	if _pilot_body == null or not is_instance_valid(_pilot_body):
		return marker.global_transform
	return _pilot_body.global_transform.affine_inverse() * marker.global_transform


func _detach_sequence_from_aircraft() -> void:
	var old_parent := get_parent()
	var new_parent: Node = get_tree().current_scene
	if new_parent == null:
		new_parent = get_tree().root
	if old_parent == null or new_parent == null or old_parent == new_parent:
		return
	old_parent.remove_child(self)
	new_parent.add_child(self)


func _retire_source_aircraft(aircraft: Node3D) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	aircraft.set_meta("ejection_source_retired", true)
	for group_name in ["aircraft", "ai_aircraft", "friendlies", "enemies"]:
		if aircraft.is_in_group(group_name):
			aircraft.remove_from_group(group_name)

	var aircraft_body := aircraft as RigidBody3D
	var flight_director := get_node_or_null("/root/FlightDirector") as FlightDirectorScript
	if flight_director != null and aircraft_body != null:
		flight_director.retire_aircraft_after_ejection(aircraft_body)

	if aircraft.has_meta("arresting_cable"):
		var cable: Variant = aircraft.get_meta("arresting_cable")
		if is_instance_valid(cable) and cable.has_method("manual_release"):
			cable.call("manual_release")
	aircraft.queue_free()


func _prepare_camera_for_ejection(camera_rig: Node3D) -> void:
	camera_rig.set_process(true)
	camera_rig.set_physics_process(true)
	var cockpit_camera := camera_rig.find_child("Camera3D", true, false) as Camera3D
	if cockpit_camera != null:
		cockpit_camera.current = true


func _get_pilot_focus_node(camera_rig: Node3D, pilot: Node3D) -> Node3D:
	if camera_rig != null:
		var cockpit_camera := camera_rig.find_child("Camera3D", true, false) as Node3D
		if cockpit_camera != null:
			return cockpit_camera
		return camera_rig
	if pilot != null:
		return pilot
	return _pilot_body


func _focus_cameras_on_ejected_pilot(ejected_body: RigidBody3D, pilot_focus: Node3D) -> void:
	var aircraft := get_parent()
	if aircraft == null:
		return
	if not _should_take_player_view(aircraft):
		return
	var camera_controller := aircraft.find_child("CameraController", true, false)
	if camera_controller != null and camera_controller.has_method("focus_ejected_pilot"):
		camera_controller.call("focus_ejected_pilot", ejected_body, pilot_focus)
	var aircraft_body := aircraft as RigidBody3D
	if aircraft_body != null:
		_notify_flight_director_ejected_pilot_took_over(aircraft_body, ejected_body)


func _prepare_ejected_pilot_camera_target(aircraft: Node, ejected_body: RigidBody3D) -> void:
	if ejected_body == null:
		return
	ejected_body.add_to_group("ejected_pilots")
	ejected_body.set_meta("ejected_pilot_camera_target", true)
	ejected_body.set_meta("player_control_locked", true)
	ejected_body.set_meta("non_aircraft_body", true)
	for group_name in ["aircraft", "ai_aircraft", "friendlies", "enemies"]:
		if ejected_body.is_in_group(group_name):
			ejected_body.remove_from_group(group_name)
	if aircraft == null:
		return
	aircraft.set_meta("player_ejection_camera_takeover", true)
	aircraft.set_meta("camera_abandoned", true)
	aircraft.set_meta("camera_replaced_by_ejected_pilot", true)
	aircraft.set_meta("ejected_pilot_body", ejected_body.get_path())
	ejected_body.set_meta("source_aircraft_name", aircraft.name)
	for key in ["pilot_display_name", "pilot_rank", "pilot_callsign", "pilot_name"]:
		if aircraft.has_meta(key):
			ejected_body.set_meta(key, aircraft.get_meta(key))


func _notify_flight_director_ejected_pilot_took_over(old_aircraft: RigidBody3D, ejected_body: RigidBody3D) -> void:
	var flight_director := get_node_or_null("/root/FlightDirector") as FlightDirectorScript
	if flight_director != null:
		flight_director.replace_aircraft_with_ejected_pilot(old_aircraft, ejected_body)


func _should_take_player_view(aircraft: Node) -> bool:
	if aircraft == null:
		return false
	if aircraft.is_in_group("enemies"):
		return false
	var flight_director := get_node_or_null("/root/FlightDirector") as FlightDirectorScript
	if flight_director != null:
		if flight_director.is_player_controlling and flight_director.player_controlled_plane == aircraft:
			return true
		if flight_director.current_viewed_aircraft == aircraft:
			return true
	return not aircraft.is_in_group("ai_aircraft")


func _should_accept_player_ejection_input() -> bool:
	var aircraft := get_parent()
	if aircraft == null:
		return false
	if aircraft.is_in_group("enemies"):
		return false
	var flight_director := get_node_or_null("/root/FlightDirector") as FlightDirectorScript
	if flight_director == null:
		return _aircraft_has_current_camera(aircraft)
	var controlled_aircraft := flight_director.player_controlled_plane
	if flight_director.is_player_controlling and is_instance_valid(controlled_aircraft):
		return controlled_aircraft == aircraft
	var viewed_aircraft := flight_director.current_viewed_aircraft
	if is_instance_valid(viewed_aircraft) and viewed_aircraft == aircraft:
		return true
	var target := flight_director._get_toggle_target_aircraft()
	if is_instance_valid(target):
		return target == aircraft
	return _aircraft_has_current_camera(aircraft)


func _aircraft_has_current_camera(aircraft: Node) -> bool:
	if aircraft == null:
		return false
	for child in aircraft.find_children("*", "Camera3D", true, false):
		var camera := child as Camera3D
		if camera != null and camera.current:
			return true
	return false


func _enable_ejected_pilot_audio(pilot_focus: Node3D) -> void:
	# Do NOT create an AudioListener3D here. In Godot 4 the active Camera3D already
	# acts as the 3D audio listener when viewport.audio_listener_enable_3d = true.
	# A separate AudioListener3D overrides that and positions audio relative to the
	# listener node rather than the camera — which silences all distant 3D sounds
	# (carrier engines, wind, etc.) as the seat flies away.
	var aircraft := get_parent()
	if aircraft == null:
		return
	var audio_manager := aircraft.find_child("AudioManager3D", true, false)
	if audio_manager != null and audio_manager.has_method("set_ejected_pilot_audio_active"):
		audio_manager.call("set_ejected_pilot_audio_active", true)


func _release_canopy_from_cockpit_visibility(canopy: Node3D) -> void:
	var visibility_controller := get_node_or_null(cockpit_canopy_visibility_path)
	if visibility_controller == null:
		var aircraft_root := get_parent()
		if aircraft_root != null:
			visibility_controller = aircraft_root.find_child("CockpitCanopyVisibility", true, false)
	if visibility_controller != null and visibility_controller.has_method("release_canopy"):
		visibility_controller.call("release_canopy", canopy)


func _get_ejected_pilot() -> Node3D:
	if _pilot_body == null or not is_instance_valid(_pilot_body):
		return null
	return _pilot_body.find_child("CockpitPilot", true, false) as Node3D


func _set_pilot_ejection_pose(pilot: Node3D, pose_name: StringName, blend_time_s: float) -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	if pilot.has_method("set_ejection_pose"):
		pilot.call("set_ejection_pose", pose_name, blend_time_s)


func _is_terrain_body(body: Node) -> bool:
	if body == null:
		return false
	if body.is_in_group("terrain") or body.is_in_group("ground") or body.is_in_group("runway_surface"):
		return true
	var body_name: String = body.name.to_lower()
	if "terrain" in body_name or "ground" in body_name:
		return true
	if body is StaticBody3D:
		return true
	return false


func _on_pilot_body_entered(body: Node) -> void:
	if not _parachute_deployed or _pilot_landed:
		return
	if not _is_terrain_body(body):
		return
	_land_pilot()


func _land_pilot(surface_position: Variant = null) -> void:
	_pilot_landed = true
	_parachute_deployed = false
	_seat_burn_active = false
	set_physics_process(false)
	if _pilot_body == null or not is_instance_valid(_pilot_body):
		return

	var land_pos := _get_pilot_ground_reference_position()
	if surface_position is Vector3:
		land_pos = surface_position
	else:
		var h := _sample_landing_height(land_pos)
		if _is_valid_landing_height(h):
			land_pos.y = h
	land_pos.y += pilot_landing_clearance_m

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root

	# Spawn the new DownedPilot character scene
	var downed_pilot_scene := load("res://Models/Characters/DownedPilot.tscn") as PackedScene
	var dp: Node3D = null
	if downed_pilot_scene != null:
		dp = downed_pilot_scene.instantiate() as Node3D
		
	if dp != null:
		# Copy metadata from pilot body
		for key in ["ejected_pilot_camera_target", "player_control_locked", "non_aircraft_body", 
					"pilot_display_name", "pilot_rank", "pilot_callsign", "pilot_name", "source_aircraft_name"]:
			if _pilot_body.has_meta(key):
				dp.set_meta(key, _pilot_body.get_meta(key))
		
		# Put downed pilot on ground
		dp.global_transform = Transform3D(Basis.IDENTITY, land_pos)
		scene_root.add_child(dp)
		dp.add_to_group("ejected_pilots")
		dp.add_to_group("downed_pilot")
		
		# Transfer camera nodes
		var camera_rig := _pilot_body.find_child("CameraCockpit", true, false) as Node3D
		if camera_rig == null:
			camera_rig = _pilot_body.find_child("CameraChase", true, false) as Node3D
		if camera_rig != null:
			_reparent_preserve_global(camera_rig, dp)
			_position_landed_camera_at_head(camera_rig, dp)
			
			# Call focus_ejected_pilot on all camera controllers
			var ccs := get_tree().get_nodes_in_group("camera_controller")
			for cc in ccs:
				if cc != null and cc.has_method("focus_ejected_pilot"):
					cc.call("focus_ejected_pilot", dp, dp)
		
		# Exclude the old parachute body from camera cycling before registering dp.
		# queue_free() doesn't remove it from scene groups immediately, so it would
		# pollute _get_friendly_aircraft() and push dp's friendly_index out of range.
		_pilot_body.set_meta("camera_abandoned", true)
		_pilot_body.remove_from_group("ejected_pilots")

		# Register the downed pilot and clean up the old body from FlightDirector
		var flight_director := get_node_or_null("/root/FlightDirector") as FlightDirectorScript
		if flight_director != null:
			flight_director.register_aircraft(dp)
			if flight_director.current_viewed_aircraft == _pilot_body:
				flight_director.current_viewed_aircraft = dp
				flight_director._select_friendly_index_for(dp)
			flight_director.unregister_aircraft(_pilot_body)
			flight_director._activate_view()
				
		print("[EjectionSequence] Downed pilot character spawned successfully at: ", land_pos)

		# Ask AirOpsManager to dispatch a rescue helicopter.
		var air_ops := get_node_or_null("/root/AirOpsManager")
		if air_ops != null and air_ops.has_method("request_rescue_for"):
			air_ops.call("request_rescue_for", dp)
	else:
		push_error("[EjectionSequence] Failed to load/instantiate DownedPilot.tscn!")

	# Clean up the old seat/body/parachute
	var seat_ref := _pilot_body
	_pilot_body = null
	if is_instance_valid(seat_ref):
		seat_ref.queue_free()


func _position_landed_camera_at_head(camera_rig: Node3D, downed_pilot: Node3D) -> void:
	if camera_rig == null or downed_pilot == null:
		return
	var head_mount := downed_pilot.find_child("HeadCameraMount", true, false) as Node3D
	if head_mount == null:
		return
	var camera := camera_rig.find_child("Camera3D", true, false) as Camera3D
	if camera == null:
		camera_rig.global_transform = head_mount.global_transform
	else:
		var camera_from_rig := camera_rig.global_transform.affine_inverse() * camera.global_transform
		camera_rig.global_transform = head_mount.global_transform * camera_from_rig.affine_inverse()
	_sync_cockpit_camera_base_transform(camera_rig)
