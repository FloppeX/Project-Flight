extends Node3D

# Catapult controller: aligns an aircraft to the deck, settles it onto gear,
# then moves the shuttle to latch the nose gear and launch along the deck.

signal launch_sequence_complete
signal launch_sequence_aborted

@export var debug_enabled: bool = false

# Nodes
@export var shuttle: Node3D            # Shuttle Node3D (moves along deck axis)
@export var shuttle_area: Area3D       # Area3D on shuttle that detects nose gear collider
@export var latch_marker: Marker3D       # Marker for the latch/start position — also the abort limit when returning
@export var release_marker: Marker3D     # Marker for the release/end position
@export var deck_ref: Node3D     # Node whose +Z/-Z defines deck forward

# Timing and forces
@export var shuttle_speed: float = 30.0       # Constant shuttle speed (m/s)
@export var respect_aircraft_min_control_speed: bool = true
@export var launch_control_speed_margin_mps: float = 8.0
@export var approach_speed_mps: float = 2.0   # Slow approach speed when moving to latch
@export var return_speed_mps: float = 35.0    # Speed shuttle moves back after launch
@export var latch_proximity_m: float = 0.1    # Distance at which shuttle latches nose gear (proximity fallback)
@export var tow_position_gain: float = 12.0   # Converts nose-position error to corrective target velocity
@export var tow_force_max: float = 250000.0   # Caps tow force to avoid instability (overridden by mass-based calc)
@export var engine_start_wait_s: float = 0.75 # Time to wait for engine to fire before spooling
@export var spool_duration_s: float = 2.0     # Time to ramp throttle from 0 → 100%
@export var hold_duration_s: float = 2.5      # Time to hold at full power before stroke
@export var settle_duration_s: float = 0.2    # Physics settle time after alignment

# Input
@export var launch_action: String = "fire_weapon"
@export var align_action: String = "catapult_align"

# Deck snap / elevation configuration used by teleport path
@export var deck_snap_mask: int = (1 << 0) | (1 << 9) # default + terrain
@export var deck_clearance: float = 0.2               # clearance above deck on settle
@export var teleport_snap_to_deck: bool = false       # optional deck ray-snap for generic alignment path
@export var launch_teleport_max_below_carrier_m: float = 30.0  # reject a launch teleport target this far below the carrier (guards the "teleported underground on launch" bug)
@export var launch_teleport_max_horizontal_carrier_distance_m: float = 400.0  # reject stale latch positions displaced from the carrier by an origin shift
@export var retrieval_handoff_max_latch_distance_m: float = 120.0  # only bypass teleport when retrieval really ended beside the live catapult
@export var retrieval_handoff_max_vertical_error_m: float = 30.0
@export var heading_offset_deg: float = 0.0           # compensate model yaw misalignment
@export var deck_forward_is_plus_z: bool = true       # carrier now uses +Z as forward

# State
var _aircraft: RigidBody3D
var _latched: bool = false
var _moving_to_latch: bool = false
var _launching: bool = false
var _start_marker: Marker3D # DEPRECATED - Manager now provides the transform
var _latch_marker: Marker3D
var _release_marker: Marker3D
var _saved_gravity_scale: float = 1.0
var _saved_collision_layer: int = 0
var _saved_collision_mask: int = 0
var _settling: bool = false
var _settle_timer: float = 0.0
var _finalizing: bool = false
var _pin_at_connect_point: bool = true
var _returning_to_connect: bool = false
var _alignment_pending: bool = false
var _latch_target_position: Vector3
var _spooling_up: bool = false
var _engine_starting: bool = false
var _engine_start_timer: float = 0.0
var _hold_at_power: bool = false
var _spool_timer: float = 0.0
var _hold_timer: float = 0.0
var _wheel_latches: Array[PinJoint3D] = [] # kept for cleanup of any legacy joints
var _saved_freeze_state: bool = false
var _launch_acceleration: float = 0.0
var _shuttle_current_velocity: Vector3 = Vector3.ZERO
var _last_shuttle_global_position: Vector3 = Vector3.ZERO
var _actual_shuttle_velocity: Vector3 = Vector3.ZERO
var _spool_fallback_timer: float = 0.0
var _effective_tow_force_max: float = 0.0  # Computed from aircraft mass at latch time
var _carrier_node: Node3D = null
var _aircraft_carrier_local_basis: Basis = Basis.IDENTITY
var _has_aircraft_carrier_local_basis: bool = false

var _is_ready: bool = false

func _ready():
	if not shuttle or not latch_marker or not release_marker:
		print("ERROR: Catapult requires shuttle, latch_marker, and release_marker to be assigned in the Inspector!")
		emit_signal("launch_sequence_aborted")
		set_physics_process(false)
		return

	if not deck_ref:
		deck_ref = get_parent() as Node3D

	if shuttle_area:
		shuttle_area.area_entered.connect(_on_shuttle_area_entered)
		shuttle_area.body_entered.connect(_on_shuttle_body_entered)
		
	# Start shuttle at the latch/connect point so the next aircraft can hook up quickly.
	shuttle.global_position = latch_marker.global_position
	_last_shuttle_global_position = shuttle.global_position
	_pin_at_connect_point = true
	
	# Calculate the required acceleration for the launch sequence
	var launch_distance = latch_marker.global_position.distance_to(release_marker.global_position)
	if launch_distance > 0.01:
		# Using kinematic equation: a = v^2 / (2 * s)
		_launch_acceleration = (shuttle_speed * shuttle_speed) / (2.0 * launch_distance)
		if debug_enabled: print("[CATAPULT] Calculated launch acceleration: ", _launch_acceleration, " m/s^2 for a ", launch_distance, "m track.")
	else:
		_launch_acceleration = 200.0 # A high fallback value for safety
		if debug_enabled: print("[CATAPULT] WARNING: Catapult track has no distance. Using fallback acceleration.")

	if debug_enabled: print("[CATAPULT] Ready.")

	_is_ready = true
	set_physics_process(true)

var _dbg_frame: int = 0
func _physics_process(delta: float):
	if debug_enabled and is_instance_valid(_aircraft) and (not _pin_at_connect_point) and not _launching:
		_dbg_frame += 1
		if _dbg_frame % 10 == 0:  # every ~10 physics frames
			var lm_pos := latch_marker.global_position if is_instance_valid(latch_marker) else Vector3.ZERO
			var ac_pos := _aircraft.global_position
			var offset := Vector2(ac_pos.x - lm_pos.x, ac_pos.z - lm_pos.z)
			print("[CAT DBG] frozen=", _aircraft.freeze,
				"  vel=", snapped(_aircraft.linear_velocity.length(), 0.01),
				"  ac=(", snapped(ac_pos.x,0.1), ",", snapped(ac_pos.z,0.1), ")",
				"  latch=(", snapped(lm_pos.x,0.1), ",", snapped(lm_pos.z,0.1), ")",
				"  offset=", snapped(offset.length(), 0.1), "m",
				"  state=", "settle" if _settling else ("approach" if _moving_to_latch else ("latched" if _latched else "?")),
				"  brake=", _aircraft.has_meta("parking_brake"),
				"  cdis=", _aircraft.has_meta("controls_disabled"))

	# Highest priority: handle pending finalization from the previous frame.
	if _alignment_pending:
		# Important: Do nothing else this frame to let the transform "settle"
		# before physics processing resumes.
		_finalize_alignment_and_settle()
		_alignment_pending = false
		return
		
	if not _is_ready:
		return
		
	# State machine
	if _settling and is_instance_valid(_aircraft):
		_sync_aircraft_rotation_to_carrier()
		_settle_timer -= delta
		if _settle_timer <= 0.0:
			if debug_enabled: print("[CATAPULT] Settle timer finished.")
			_settling = false
			begin_sequence(_aircraft)
		# While settling, do nothing else.
		return

	# If not settling, check if the shuttle should be pinned at its idle spot.
	if _pin_at_connect_point:
		if is_instance_valid(shuttle) and is_instance_valid(latch_marker):
			shuttle.global_position = latch_marker.global_position
			_last_shuttle_global_position = shuttle.global_position
		return

	if _returning_to_connect:
		if not is_instance_valid(shuttle) or not is_instance_valid(latch_marker):
			return
		shuttle.global_position = shuttle.global_position.move_toward(latch_marker.global_position, return_speed_mps * delta)
		if shuttle.global_position.distance_to(latch_marker.global_position) <= 0.05:
			shuttle.global_position = latch_marker.global_position
			_last_shuttle_global_position = shuttle.global_position
			_returning_to_connect = false
			_pin_at_connect_point = true
		return

	if not is_instance_valid(_aircraft):
		return

	# If not settling and not pinned, proceed with approach or launch logic.
	if _moving_to_latch and not _latched:
		_sync_aircraft_rotation_to_carrier()
		# Track latch_marker live so the target follows the moving carrier.
		_latch_target_position = latch_marker.global_position
		
		# Override with exact nose gear position when possible
		var nose_gear = _find_nose_gear_collider(_aircraft)
		if is_instance_valid(nose_gear):
			_latch_target_position = nose_gear.global_position
			
		_latch_target_position.y = shuttle.global_position.y

		shuttle.global_position = shuttle.global_position.move_toward(_latch_target_position, approach_speed_mps * delta)

		# Proximity check — more reliable than area signals when the shuttle parent
		# is a Node3D moved via direct global_position assignment each frame.
		if is_instance_valid(nose_gear):
			var s_pos = shuttle.global_position
			var g_pos = nose_gear.global_position
			var dist = Vector2(s_pos.x, s_pos.z).distance_to(Vector2(g_pos.x, g_pos.z))
			if dist <= latch_proximity_m:
				if debug_enabled: print("[CATAPULT] Proximity latch triggered at dist=", snappedf(dist, 0.01), "m")
				_try_latch()
				return

		if shuttle.global_position.is_equal_approx(_latch_target_position):
			# Shuttle reached latch_marker without a nose-gear contact — launch failed.
			print("[CATAPULT] Shuttle reached latch_marker with no latch. Aborting launch.")
			_abort_launch()
	
	elif _engine_starting:
		_sync_aircraft_rotation_to_carrier()
		# Waiting for the engine to physically start up before spooling
		_engine_start_timer -= delta
		if _engine_start_timer <= 0.0:
			if debug_enabled: print("[CATAPULT] Engine start timer finished. Now spooling up.")
			_engine_starting = false
			_spooling_up = true
			_spool_timer = 0.0
			
	elif _spooling_up and not _launching:
		_sync_aircraft_rotation_to_carrier()
			# Gradually increase throttle over _spool_duration
		_spool_timer += delta
		var throttle_ratio = min(_spool_timer / spool_duration_s, 1.0)
		_command_throttle(throttle_ratio)

		if _spool_timer >= spool_duration_s:
			if debug_enabled: print("[CATAPULT] Spool up complete. Holding at max power for ", hold_duration_s, "s.")
			_spooling_up = false
			_hold_at_power = true
			_hold_timer = hold_duration_s

	elif _hold_at_power and not _launching:
		_sync_aircraft_rotation_to_carrier()
		# Hold at full power for a few seconds before launch
		_hold_timer -= delta
		if _hold_timer <= 0.0:
			if debug_enabled: print("[CATAPULT] Hold complete. Launching!")
			_hold_at_power = false
			_release_wheels()
			_launching = true
			_shuttle_current_velocity = Vector3.ZERO
			_last_shuttle_global_position = shuttle.global_position
			# No position reset needed — shuttle is a child of the carrier and already
			# sits at the nose gear position it stopped at when latching.
			
	elif _launching and _latched:
		_sync_aircraft_rotation_to_carrier()
		# Move shuttle with constant acceleration
		var launch_direction = (release_marker.global_position - latch_marker.global_position).normalized()
		_shuttle_current_velocity += launch_direction * _launch_acceleration * delta
		shuttle.global_position += _shuttle_current_velocity * delta
		
		_drag_aircraft_to_shuttle()

		# Check if we are close to the release marker
		var distance_to_release = shuttle.global_position.distance_to(release_marker.global_position)
		if distance_to_release < 1.0: # Release 1.0 meter before the end
			# Release the aircraft cleanly before the shuttle stops.
			_release()
		else:
			# Check if we've passed the release marker (failsafe)
			var dir_to_release = release_marker.global_position - shuttle.global_position
			if dir_to_release.dot(launch_direction) < 0:
				# Snap to final position to avoid overshooting and release
				shuttle.global_position = release_marker.global_position
				_release()

func _input(event):
	if _latched and not _launching and not _spooling_up and Input.is_action_just_pressed(launch_action):
		# Manual override for launch if auto-spool fails, for debug.
		if debug_enabled: print("[CATAPULT] Manual launch override pressed.")
		_release_wheels()
		_spooling_up = false
		_launching = true
		_shuttle_current_velocity = Vector3.ZERO
		shuttle.global_position = _latch_target_position
		_last_shuttle_global_position = shuttle.global_position
	# -- The following is now handled by FlightDeckManager --
	# elif Input.is_action_just_pressed(align_action):
	# 	var ac = _get_aircraft()
	# 	if ac and not _finalizing and not _settling:
	# 		if debug_enabled: print("[CATAPULT] Align action pressed.")
	# 		_align_aircraft_to_start(ac)

func begin_sequence(aircraft: RigidBody3D) -> void:
	if debug_enabled: print("[CATAPULT] Begin sequence called. Unpinning shuttle and starting approach.")
	_aircraft = aircraft
	_configure_launch_acceleration_for_aircraft(aircraft)
	_capture_aircraft_carrier_rotation()
	_latched = false
	_launching = false
	_moving_to_latch = true
	_pin_at_connect_point = false
	_returning_to_connect = false
	# Freeze the aircraft solid while the shuttle approaches.
	# _release_wheels() will unfreeze for the launch stroke.
	aircraft.freeze = true
	print("[CATAPULT][DBG] begin_sequence — frozen=", aircraft.freeze, " vel=", snapped(aircraft.linear_velocity.length(), 0.01), "m/s")
	# _latch_target_position is updated live each frame from latch_marker (see _physics_process).
	# Set an initial value now.
	_latch_target_position = latch_marker.global_position
	_latch_target_position.y = shuttle.global_position.y
	_last_shuttle_global_position = shuttle.global_position
	if debug_enabled: print("[CATAPULT] Shuttle approaching latch_marker. Will abort if no latch by then.")

func _configure_launch_acceleration_for_aircraft(aircraft: RigidBody3D) -> void:
	var required_release_speed_mps: float = maxf(shuttle_speed, 1.0)
	if respect_aircraft_min_control_speed and is_instance_valid(aircraft):
		var aero: Node = aircraft.find_child("SimpleAero", true, false)
		if is_instance_valid(aero):
			var min_control_variant: Variant = aero.get("min_control_speed")
			if min_control_variant is float or min_control_variant is int:
				required_release_speed_mps = maxf(
					required_release_speed_mps,
					float(min_control_variant) + maxf(launch_control_speed_margin_mps, 0.0)
				)
	var launch_distance_m: float = latch_marker.global_position.distance_to(release_marker.global_position) \
		if is_instance_valid(latch_marker) and is_instance_valid(release_marker) else 0.0
	if launch_distance_m > 0.01:
		_launch_acceleration = required_release_speed_mps * required_release_speed_mps / (2.0 * launch_distance_m)
	else:
		_launch_acceleration = 200.0
	if debug_enabled:
		print("[CATAPULT] Configured release speed %.1fm/s acceleration %.1fm/s^2" % [
			required_release_speed_mps,
			_launch_acceleration,
		])


func _on_shuttle_area_entered(area: Area3D) -> void:
	if _latched or _launching or not _moving_to_latch:
		return
	if debug_enabled:
		print("[CATAPULT] Shuttle area entered by Area3D: ", area.name)
	if area.name.to_lower().find("gear") != -1 or area.is_in_group("nose_gear"):
		var ac = _find_aircraft(area)
		if ac and ac == _aircraft:
			var s_pos = shuttle.global_position
			var g_pos = area.global_position
			var dist = Vector2(s_pos.x, s_pos.z).distance_to(Vector2(g_pos.x, g_pos.z))
			if dist <= latch_proximity_m:
				if debug_enabled: print("[CATAPULT] Shuttle area detected nose gear (area).")
				_try_latch()

func _on_shuttle_body_entered(body: Node3D) -> void:
	# The nose gear is a CollisionShape3D on the aircraft RigidBody3D, so it
	# triggers body_entered rather than area_entered.
	if _latched or _launching or not _moving_to_latch:
		return
	if debug_enabled:
		print("[CATAPULT] Shuttle area entered by body: ", body.name)
	if body == _aircraft:
		var nose_gear = _find_nose_gear_collider(_aircraft)
		if is_instance_valid(nose_gear):
			var s_pos = shuttle.global_position
			var g_pos = nose_gear.global_position
			var dist = Vector2(s_pos.x, s_pos.z).distance_to(Vector2(g_pos.x, g_pos.z))
			if dist <= latch_proximity_m:
				if debug_enabled: print("[CATAPULT] Shuttle area detected aircraft body — latching.")
				_try_latch()

func _try_latch() -> void:
	if not _aircraft or _latched: return
	if debug_enabled: print("[CATAPULT] Latching to aircraft.")
	_aircraft.set_meta("controls_disabled", true) # Disable player throttle input
	_latched = true
	_moving_to_latch = false
	_capture_aircraft_carrier_rotation()
	_immobilize_wheels()

	# Scale tow force to the aircraft's mass so heavier planes get the same
	# launch speed regardless of weight.  Required force = mass × acceleration,
	# with 4× headroom so the tow-bar PID can track the shuttle cleanly.
	_effective_tow_force_max = _aircraft.mass * _launch_acceleration * 4.0
	if tow_force_max > 0.0:
		_effective_tow_force_max = max(_effective_tow_force_max, tow_force_max)
	if debug_enabled:
		print("[CATAPULT] Aircraft mass: %.0f kg — tow force cap: %.0f N" % [_aircraft.mass, _effective_tow_force_max])
	
	var engine = _find_engine(_aircraft)
	if is_instance_valid(engine):
		# Explicitly start the engine if it's not already running
		if engine.has_method("is_running") and not engine.is_running():
			if debug_enabled: print("[CATAPULT] Engine is not running. Commanding start...")
			if engine.has_method("engine_start"):
				engine.engine_start()
				# Set a timer to wait for the engine to start
				_engine_starting = true
				_engine_start_timer = engine_start_wait_s
		else:
			# If engine is already running, go straight to spool up
			_spooling_up = true
			_spool_timer = 0.0
			# Instantly command a bit of throttle to ensure it's not zero
			_command_throttle(0.05)
	else:
		# No engine found, go straight to spool up (which will use its own fallback)
		_spooling_up = true
		_spool_timer = 0.0
		if debug_enabled: print("[CATAPULT] WARNING: Could not find engine.")

func _command_throttle(throttle_value: float):
	var engine = _find_engine(_aircraft)
	if is_instance_valid(engine) and engine.has_method("set_throttle_input"):
		engine.set_throttle_input(throttle_value)
	else:
		if debug_enabled: print("[CATAPULT] WARNING: Could not find engine to command throttle.")


func _drag_aircraft_to_shuttle() -> void:
	if not _aircraft or not shuttle: return
	var dt := maxf(get_physics_process_delta_time(), 0.001)
	_actual_shuttle_velocity = (shuttle.global_position - _last_shuttle_global_position) / dt
	_last_shuttle_global_position = shuttle.global_position

	# Stiff tow-bar style pull:
	# match shuttle velocity plus a position-error correction so nose gear is
	# constrained in all axes (including vertical) relative to shuttle.
	var nose_gear = _find_nose_gear_collider(_aircraft)
	if is_instance_valid(nose_gear):
		var position_error: Vector3 = shuttle.global_position - nose_gear.global_position
		var desired_velocity: Vector3 = _actual_shuttle_velocity + position_error * tow_position_gain
		var current_velocity: Vector3 = _aircraft.linear_velocity
		var velocity_error: Vector3 = desired_velocity - current_velocity
		var force: Vector3 = velocity_error * _aircraft.mass / dt
		var cap := _effective_tow_force_max if _effective_tow_force_max > 0.0 else tow_force_max
		if cap > 0.0 and force.length() > cap:
			force = force.normalized() * cap
		var force_position = nose_gear.global_position - _aircraft.global_position
		_aircraft.apply_force(force, force_position)
	else:
		# Fallback to applying a central force if the nose gear isn't found
		var desired_velocity: Vector3 = _actual_shuttle_velocity
		var current_velocity: Vector3 = _aircraft.linear_velocity
		var velocity_error: Vector3 = desired_velocity - current_velocity
		var force: Vector3 = velocity_error * _aircraft.mass / dt
		var cap := _effective_tow_force_max if _effective_tow_force_max > 0.0 else tow_force_max
		if cap > 0.0 and force.length() > cap:
			force = force.normalized() * cap
		_aircraft.apply_central_force(force)


func _release() -> void:
	if debug_enabled: print("[CATAPULT] Releasing aircraft.")
	if is_instance_valid(_aircraft):
		_sync_aircraft_rotation_to_carrier()
		# Perform a clean handover to the aircraft's own engine controller.
		# Set its target power to 1.0 so it doesn't immediately shut down the engine.
		var engine_controller = _find_engine_controller(_aircraft)
		if is_instance_valid(engine_controller):
			engine_controller.set("target_power", 1.0)
			if debug_enabled: print("[CATAPULT] Handed over throttle control to ControlEngine module.")
		
		_aircraft.remove_meta("controls_disabled") # Restore player throttle input
		_aircraft.angular_velocity = Vector3.ZERO
		
	# The aircraft will continue with the velocity it had on the last frame.
	_latched = false
	_launching = false
	_aircraft = null
	_has_aircraft_carrier_local_basis = false
	_carrier_node = null
	_return_shuttle_to_connect()
	emit_signal("launch_sequence_complete")
	
func _return_shuttle_to_connect() -> void:
	if debug_enabled: print("[CATAPULT] Returning shuttle to connect point.")
	_pin_at_connect_point = false
	_returning_to_connect = true

func _find_aircraft(from_node: Node) -> RigidBody3D:
	var n: Node = from_node
	while n:
		if n is RigidBody3D: return n
		n = n.get_parent()
	return null

func _immobilize_wheels():
	# Aircraft is already frozen by begin_sequence(); just record the pre-sequence
	# state so _release_wheels() restores it correctly.
	if not is_instance_valid(_aircraft): return
	_saved_freeze_state = false  # we always want to unfreeze on launch
	_aircraft.freeze = true
	if debug_enabled: print("[CATAPULT] Aircraft frozen for spool-up.")

func _release_wheels():
	# Clean up any legacy PinJoint3D nodes (safety), then unfreeze the aircraft
	# so engine forces apply at launch.
	for joint in _wheel_latches:
		if is_instance_valid(joint):
			joint.queue_free()
	_wheel_latches.clear()
	if is_instance_valid(_aircraft):
		_aircraft.freeze = _saved_freeze_state
		if debug_enabled: print("[CATAPULT] Aircraft unfrozen for launch.")

func _find_nose_gear_collider(root: Node) -> Node3D:
	# A robust way to find the nose gear. It checks for a specific group first,
	# then falls back to searching for a common name. For best results, add your
	# nose gear's Area3D or CollisionShape3D to the "nose_gear_latch_point" group.
	var nodes_in_group = root.get_tree().get_nodes_in_group("nose_gear_latch_point")
	for node in nodes_in_group:
		if node.get_owner() == root:
			return node

	# Fallback search by name
	var found = root.find_child("CenterGearCollider", true, false)
	if is_instance_valid(found):
		return found
		
	# Broader search
	found = root.find_child("*NoseGear*", true, false)
	if is_instance_valid(found):
		return found

	return null

func _find_engine_controller(root: Node) -> Node:
	# Finds the engine controller module on the aircraft
	var controller_nodes = _find_nodes_by_script(root, "ControlEngine.gd")
	if not controller_nodes.is_empty():
		return controller_nodes[0]
	return null

func _find_engine(root: Node) -> Node:
	# Finds the engine module on the aircraft
	var engine_nodes = _find_nodes_by_script(root, "Engine.gd")
	if not engine_nodes.is_empty():
		return engine_nodes[0]
	return null

func _find_nodes_by_script(root: Node, script_name: String) -> Array[Node]:
	var found_nodes: Array[Node] = []
	for child in root.get_children():
		if child.get_script() and child.get_script().resource_path.ends_with(script_name):
			found_nodes.append(child)
		found_nodes.append_array(_find_nodes_by_script(child, script_name))
	return found_nodes

func _get_aircraft() -> RigidBody3D:
	# For debug/manual use
	# This is intended to find a nearby aircraft if one isn't passed in.
	# The FlightDeckManager now handles this, so this is mostly a fallback.
	if _aircraft and is_instance_valid(_aircraft): return _aircraft
	return get_tree().get_first_node_in_group("aircraft") as RigidBody3D

func align_aircraft(ac: RigidBody3D) -> void:
	if not _is_ready:
		print("ERROR [CATAPULT]: Align called but catapult is not ready. Aborting.")
		emit_signal("launch_sequence_aborted")
		return

	if not is_instance_valid(ac):
		print("ERROR [CATAPULT]: Invalid aircraft instance passed to align.")
		emit_signal("launch_sequence_aborted")
		return

	_aircraft = ac
	_capture_aircraft_carrier_rotation()
	_refresh_launch_transforms()

	# Lock controls immediately so AIPilot/ControlEngine can't run the engine
	# before the shuttle connects. Released on launch (line with remove_meta).
	ac.set_meta("controls_disabled", true)

	# Retrieval launch handoff: plane is already at marker and physics-stable,
	# so skip teleport/freeze once and go straight to shuttle approach.
	if ac.has_meta("catapult_skip_teleport_once") and bool(ac.get_meta("catapult_skip_teleport_once")):
		ac.remove_meta("catapult_skip_teleport_once")
		if _can_use_retrieval_handoff(ac):
			if debug_enabled:
				print("[CATAPULT] Retrieval handoff: aircraft is at the live latch; starting sequence directly.")
			begin_sequence(ac)
			return
		var latch_distance_m: float = _horizontal_distance(ac.global_position, latch_marker.global_position)
		push_warning(
			"[CATAPULT] Rejected stale retrieval handoff %.0fm from the live latch; using safe catapult alignment."
			% latch_distance_m
		)

	var target_transform = latch_marker.global_transform
	
	# Orient aircraft to face launch direction (latch → release)
	# Aircraft model forward is +Z (basis.z), so atan2 directly gives the correct yaw
	var launch_dir = (release_marker.global_position - latch_marker.global_position)
	launch_dir.y = 0.0
	launch_dir = launch_dir.normalized()
	var yaw_angle = atan2(launch_dir.x, launch_dir.z) + deg_to_rad(heading_offset_deg)
	target_transform.basis = Basis(Vector3.UP, yaw_angle)
	
	if debug_enabled: print("[CATAPULT] align_aircraft called. Launch dir: ", launch_dir, " Yaw: ", rad_to_deg(yaw_angle))
	if debug_enabled: print("[CATAPULT] Aircraft transform BEFORE teleport: ", ac.global_transform)
	
	# --- Prepare aircraft for teleport ---
	# Save state and freeze the physics body to ensure a clean teleport.
	_saved_gravity_scale = ac.gravity_scale
	_saved_collision_layer = ac.collision_layer
	_saved_collision_mask = ac.collision_mask
	ac.freeze = true
	ac.gravity_scale = 0.0
	ac.collision_layer = 0
	ac.collision_mask = 0
	
	var final_transform = target_transform
	if teleport_snap_to_deck:
		# Snap Y to deck to account for marker height
		var from = final_transform.origin + Vector3.UP * 5.0
		var to = final_transform.origin + Vector3.DOWN * 10.0
		var space = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(from, to, 1) # Assume mask 1 is ground
		var hit = space.intersect_ray(query)
		if hit:
			final_transform.origin.y = hit.position.y + deck_clearance

	# SANITY GUARD: never teleport the aircraft far below or horizontally far away from the carrier.
	# A latch_marker global transform read during an origin shift can retain the old world translation
	# while still having a plausible height. Rebuild it from its parent's current transform whenever
	# either axis is implausible.
	var carrier := _find_carrier_node()
	if is_instance_valid(carrier):
		var y_below_carrier: float = carrier.global_position.y - final_transform.origin.y
		var horizontal_delta: Vector3 = final_transform.origin - carrier.global_position
		horizontal_delta.y = 0.0
		var horizontal_distance_m: float = horizontal_delta.length()
		var bad_vertical_target: bool = y_below_carrier > launch_teleport_max_below_carrier_m
		var bad_horizontal_target: bool = horizontal_distance_m > launch_teleport_max_horizontal_carrier_distance_m
		if bad_vertical_target or bad_horizontal_target:
			# Recompute the marker's world position from its parent's CURRENT transform (authoritative --
			# the marker is a child of the carrier/deck, so parent.global_transform * marker.local_origin
			# gives the real deck spot even if the marker's cached global_transform was stale).
			var safe_origin: Vector3 = final_transform.origin
			var hierarchy_origin: Vector3 = _get_descendant_world_origin(latch_marker, carrier)
			if hierarchy_origin != Vector3.INF:
				safe_origin = hierarchy_origin
			push_warning(
				"[CATAPULT] Rejected bad launch teleport (horizontal=%.0fm, below=%.0fm) — using recomputed deck position."
				% [horizontal_distance_m, y_below_carrier]
			)
			if debug_enabled:
				print("[CATAPULT] bad target=%s carrier=%s -> safe=%s" % [final_transform.origin, carrier.global_position, safe_origin])
			final_transform.origin = safe_origin

	ac.global_transform = final_transform
	PhysicsServer3D.body_set_state(ac.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, ac.global_transform)
	_capture_aircraft_carrier_rotation()
	if debug_enabled: print("[CATAPULT] Aircraft transform AFTER teleport: ", ac.global_transform)
	
	if debug_enabled: print("[CATAPULT] Aircraft teleported by manager. Flagging for finalize on next frame.")
		
	# Defer the finalization to the next physics frame to avoid crashes
	_alignment_pending = true

	
func _finalize_alignment_and_settle() -> void:
	if not is_instance_valid(_aircraft):
		print("ERROR [CATAPULT]: Aircraft became invalid before finalize. Aborting.")
		emit_signal("launch_sequence_aborted")
		_reset_state()
		return
		
	if _finalizing:
		print("[CATAPULT] ERROR: Finalize called when not pending. This shouldn't happen.")
		return
	_finalizing = true
	if debug_enabled: print("[CATAPULT] Finalizing alignment and starting settle timer.")
	
	# Restore physics state and unfreeze
	_aircraft.gravity_scale = _saved_gravity_scale if _saved_gravity_scale != 0.0 else 1.0
	_aircraft.collision_layer = _saved_collision_layer if _saved_collision_layer != 0 else 1
	_aircraft.collision_mask = _saved_collision_mask if _saved_collision_mask != 0 else 1
	_aircraft.freeze = false
	_aircraft.sleeping = false
	print("[CATAPULT][DBG] finalize_alignment — unfrozen for settle. vel=", snapped(_aircraft.linear_velocity.length(), 0.01), "m/s  parking_brake=", _aircraft.has_meta("parking_brake"), " transport=", _aircraft.has_meta("carrier_transport_mode"))

	_settling = true
	_settle_timer = settle_duration_s
	_finalizing = false

func _abort_launch() -> void:
	# Shuttle reached its limit without connecting — clean up and signal failure.
	if is_instance_valid(_aircraft):
		if _aircraft.has_meta("controls_disabled"):
			_aircraft.remove_meta("controls_disabled")
		if _aircraft.has_meta("parking_brake"):
			_aircraft.remove_meta("parking_brake")
	_release_wheels()
	_latched = false
	_launching = false
	_moving_to_latch = false
	_spooling_up = false
	_hold_at_power = false
	_engine_starting = false
	_aircraft = null
	_has_aircraft_carrier_local_basis = false
	_carrier_node = null
	_return_shuttle_to_connect()
	emit_signal("launch_sequence_aborted")

func _reset_state():
	# Resets all state variables to their defaults
	if is_instance_valid(_aircraft):
		if _aircraft.has_meta("controls_disabled"):
			_aircraft.remove_meta("controls_disabled")
		if _aircraft.has_meta("parking_brake"):
			_aircraft.remove_meta("parking_brake")
		_release_wheels()
	_aircraft = null
	_finalizing = false
	_alignment_pending = false
	_settling = false
	_settle_timer = 0.0
	_latched = false
	_launching = false
	_moving_to_latch = false
	_spooling_up = false
	_hold_at_power = false
	_engine_starting = false
	_pin_at_connect_point = true
	_returning_to_connect = false
	_effective_tow_force_max = 0.0
	_has_aircraft_carrier_local_basis = false
	_carrier_node = null

# --- Helpers ---

func _capture_aircraft_carrier_rotation() -> void:
	if not is_instance_valid(_aircraft):
		return
	_carrier_node = _find_carrier_node()
	if not is_instance_valid(_carrier_node):
		_has_aircraft_carrier_local_basis = false
		return
	_aircraft_carrier_local_basis = _carrier_node.global_transform.basis.inverse() * _aircraft.global_transform.basis
	_has_aircraft_carrier_local_basis = true


func _sync_aircraft_rotation_to_carrier() -> void:
	if not _has_aircraft_carrier_local_basis or not is_instance_valid(_aircraft) or not is_instance_valid(_carrier_node):
		return
	var transform := _aircraft.global_transform
	transform.basis = (_carrier_node.global_transform.basis * _aircraft_carrier_local_basis).orthonormalized()
	_aircraft.global_transform = transform
	PhysicsServer3D.body_set_state(_aircraft.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _aircraft.global_transform)
	_aircraft.angular_velocity = Vector3.ZERO


func _find_carrier_node() -> Node3D:
	var node: Node = self
	while node != null:
		if node is Node3D and (node.is_in_group("carrier") or node.name.to_lower().find("landcarrier") != -1):
			return node as Node3D
		node = node.get_parent()
	var carrier := get_tree().get_first_node_in_group("carrier")
	return carrier as Node3D


func _refresh_launch_transforms() -> void:
	var carrier := _find_carrier_node()
	if is_instance_valid(carrier):
		carrier.force_update_transform()
	force_update_transform()
	if is_instance_valid(latch_marker):
		latch_marker.force_update_transform()
	if is_instance_valid(release_marker):
		release_marker.force_update_transform()
	if is_instance_valid(shuttle):
		shuttle.force_update_transform()


func _can_use_retrieval_handoff(ac: RigidBody3D) -> bool:
	if not is_instance_valid(ac) or not is_instance_valid(latch_marker):
		return false
	var carrier := _find_carrier_node()
	if not is_instance_valid(carrier):
		return false
	var latch_distance_m: float = _horizontal_distance(ac.global_position, latch_marker.global_position)
	var carrier_distance_m: float = _horizontal_distance(ac.global_position, carrier.global_position)
	var vertical_error_m: float = absf(ac.global_position.y - latch_marker.global_position.y)
	return (
		latch_distance_m <= maxf(retrieval_handoff_max_latch_distance_m, 1.0)
		and carrier_distance_m <= maxf(launch_teleport_max_horizontal_carrier_distance_m, 1.0)
		and vertical_error_m <= maxf(retrieval_handoff_max_vertical_error_m, 1.0)
	)


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _get_descendant_world_origin(descendant: Node3D, ancestor: Node3D) -> Vector3:
	if not is_instance_valid(descendant) or not is_instance_valid(ancestor):
		return Vector3.INF
	var relative_transform := Transform3D.IDENTITY
	var cursor: Node = descendant
	while cursor != null and cursor != ancestor:
		if not (cursor is Node3D):
			return Vector3.INF
		relative_transform = (cursor as Node3D).transform * relative_transform
		cursor = cursor.get_parent()
	if cursor != ancestor:
		return Vector3.INF
	return ancestor.global_transform * relative_transform.origin


func _get_deck_forward_vector() -> Vector3:
	if not is_instance_valid(deck_ref):
		return Vector3.FORWARD if deck_forward_is_plus_z else Vector3.BACK
		
	var local_forward = Vector3.FORWARD if deck_forward_is_plus_z else Vector3.BACK
	return (deck_ref.global_transform.basis * local_forward).normalized()
