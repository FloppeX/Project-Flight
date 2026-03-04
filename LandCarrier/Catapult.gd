extends Node3D

# Catapult controller: aligns an aircraft to the deck, settles it onto gear,
# then moves the shuttle to latch the nose gear and launch along the deck.

signal launch_sequence_complete
signal launch_sequence_aborted

@export var debug_enabled: bool = false

# Nodes
@export var shuttle: Node3D            # Shuttle Node3D (moves along deck axis)
@export var shuttle_area: Area3D       # Area3D on shuttle that detects nose gear collider
@export var latch_marker: Marker3D       # Marker for the latch/start position
@export var release_marker: Marker3D     # Marker for the release/end position
@export var deck_ref: Node3D     # Node whose +Z/-Z defines deck forward

# Timing and forces
@export var shuttle_speed: float = 30.0       # Constant shuttle speed (m/s)
@export var approach_speed_mps: float = 2.0   # Slow approach speed when moving to latch
@export var return_speed_mps: float = 10.0 # Speed shuttle moves back after launch

# Input
@export var launch_action: String = "fire_weapon"
@export var align_action: String = "catapult_align"

# Deck snap / elevation configuration used by teleport path
@export var deck_snap_mask: int = (1 << 0) | (1 << 9) # default + terrain
@export var deck_clearance: float = 0.2               # clearance above deck on settle
@export var teleport_snap_to_deck: bool = true        # snap teleport height to deck
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
var _settle_duration: float = 1.5
var _settle_timer: float = 0.0
var _finalizing: bool = false
var _pin_at_release_point: bool = true
var _alignment_pending: bool = false
var _latch_target_position: Vector3
var _spooling_up: bool = false
var _engine_starting: bool = false
var _engine_start_timer: float = 0.0
var _hold_at_power: bool = false
var _spool_timer: float = 0.0
var _hold_timer: float = 0.0
var _spool_duration: float = 3.0
var _hold_duration: float = 3.0
var _wheel_latches: Array[PinJoint3D] = []
var _launch_acceleration: float = 0.0
var _shuttle_current_velocity: Vector3 = Vector3.ZERO
var _spool_fallback_timer: float = 0.0

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
		
	# Start shuttle at release point and pin it there.
	shuttle.global_position = release_marker.global_position
	_pin_at_release_point = true
	
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

func _physics_process(delta: float):
	# Highest priority: handle pending finalization from the previous frame.
	if _alignment_pending:
		# Important: Do nothing else this frame to let the transform "settle"
		# before physics processing resumes.
		_finalize_alignment_and_settle()
		_alignment_pending = false
		return
		
	if not _is_ready or not is_instance_valid(_aircraft):
		return
		
	# State machine
	if _settling and is_instance_valid(_aircraft):
		_settle_timer -= delta
		if _settle_timer <= 0.0:
			if debug_enabled: print("[CATAPULT] Settle timer finished.")
			_settling = false
			begin_sequence(_aircraft)
		# While settling, do nothing else.
		return

	# If not settling, check if the shuttle should be pinned at its idle spot.
	if _pin_at_release_point:
		if debug_enabled: print("[CATAPULT] Shuttle is pinned at release point.")
		if is_instance_valid(shuttle) and is_instance_valid(release_marker):
			shuttle.global_position = release_marker.global_position
		return

	# If not settling and not pinned, proceed with approach or launch logic.
	if _moving_to_latch and not _latched:
		if debug_enabled: print("[CATAPULT] Approaching latch point at: ", _latch_target_position)
		shuttle.global_position = shuttle.global_position.move_toward(_latch_target_position, approach_speed_mps * delta)
		if shuttle.global_position.is_equal_approx(_latch_target_position):
			# Snap to final position
			shuttle.global_position = _latch_target_position
			# Failsafe: If we've reached the destination and haven't latched, force it.
			if debug_enabled: print("[CATAPULT] Shuttle reached latch point. Forcing latch.")
			_try_latch()
	
	elif _engine_starting:
		# Waiting for the engine to physically start up before spooling
		_engine_start_timer -= delta
		if _engine_start_timer <= 0.0:
			if debug_enabled: print("[CATAPULT] Engine start timer finished. Now spooling up.")
			_engine_starting = false
			_spooling_up = true
			_spool_timer = 0.0
			
	elif _spooling_up and not _launching:
		if debug_enabled: print("[CATAPULT] In spooling up state. Timer: ", _spool_timer)
		# Gradually increase throttle over _spool_duration
		_spool_timer += delta
		var throttle_ratio = min(_spool_timer / _spool_duration, 1.0)
		_command_throttle(throttle_ratio)

		if _spool_timer >= _spool_duration:
			if debug_enabled: print("[CATAPULT] Spool up complete. Holding at max power for ", _hold_duration, "s.")
			_spooling_up = false
			_hold_at_power = true
			_hold_timer = _hold_duration

	elif _hold_at_power and not _launching:
		# Hold at full power for a few seconds before launch
		_hold_timer -= delta
		if _hold_timer <= 0.0:
			if debug_enabled: print("[CATAPULT] Hold complete. Launching!")
			_hold_at_power = false
			_release_wheels()
			_launching = true
			_shuttle_current_velocity = Vector3.ZERO
			# Ensure shuttle starts exactly at the latch point for the run.
			shuttle.global_position = _latch_target_position
			
	elif _launching and _latched:
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
	# -- The following is now handled by FlightDeckManager --
	# elif Input.is_action_just_pressed(align_action):
	# 	var ac = _get_aircraft()
	# 	if ac and not _finalizing and not _settling:
	# 		if debug_enabled: print("[CATAPULT] Align action pressed.")
	# 		_align_aircraft_to_start(ac)

func begin_sequence(aircraft: RigidBody3D) -> void:
	if debug_enabled: print("[CATAPULT] Begin sequence called. Unpinning shuttle and starting approach.")
	_aircraft = aircraft
	_latched = false
	_launching = false
	_moving_to_latch = true
	_pin_at_release_point = false
	
	# Find the nose gear and set its position as the precise target.
	var nose_gear = _find_nose_gear_collider(aircraft)
	if is_instance_valid(nose_gear):
		_latch_target_position = nose_gear.global_position
		# Keep the shuttle on its current Y plane to prevent it from moving up/down.
		_latch_target_position.y = shuttle.global_position.y
		if debug_enabled: print("[CATAPULT] Nose gear found. Target latch pos: ", _latch_target_position)
	else:
		# Fallback to the marker if nose gear can't be found.
		_latch_target_position = latch_marker.global_position
		if debug_enabled: print("[CATAPULT] WARNING: Could not find nose gear collider. Falling back to latch_marker position.")


func _on_shuttle_area_entered(area: Area3D) -> void:
	if _latched or _launching or not _moving_to_latch:
		return
		
	if debug_enabled:
		print("[CATAPULT] Shuttle area entered by: ", area.name, " (owner: ", area.owner.name if area.owner else "null", ")")
		
	if area.name.to_lower().find("gear") != -1 or area.is_in_group("nose_gear"):
		var ac = _find_aircraft(area)
		if ac and ac == _aircraft:
			if debug_enabled: print("[CATAPULT] Shuttle area detected nose gear.")
			_try_latch()

func _try_latch() -> void:
	if not _aircraft or _latched: return
	if debug_enabled: print("[CATAPULT] Latching to aircraft.")
	_aircraft.set_meta("controls_disabled", true) # Disable player throttle input
	_latched = true
	_moving_to_latch = false
	_immobilize_wheels()
	
	var engine = _find_engine(_aircraft)
	if is_instance_valid(engine):
		# Explicitly start the engine if it's not already running
		if engine.has_method("is_running") and not engine.is_running():
			if debug_enabled: print("[CATAPULT] Engine is not running. Commanding start...")
			if engine.has_method("engine_start"):
				engine.engine_start()
				# Set a timer to wait for the engine to start
				_engine_starting = true
				_engine_start_timer = 1.2
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
		if debug_enabled: print("[CATAPULT] Commanded engine throttle: ", throttle_value)
	else:
		if debug_enabled: print("[CATAPULT] WARNING: Could not find engine to command throttle.")


func _drag_aircraft_to_shuttle() -> void:
	if not _aircraft or not shuttle: return

	# Instead of a rigid velocity lock, apply a strong corrective force.
	# This simulates a stiff tow bar but allows the aircraft's own physics to operate.
	var desired_velocity = _shuttle_current_velocity
	var current_velocity = _aircraft.linear_velocity
	var velocity_error = desired_velocity - current_velocity
	
	# Calculate the required force using F = m * a, where a = dv / dt
	var force = velocity_error * _aircraft.mass / get_physics_process_delta_time()
	
	# Apply this force at the nose gear's position for a more realistic pull.
	var nose_gear = _find_nose_gear_collider(_aircraft)
	if is_instance_valid(nose_gear):
		var force_position = nose_gear.global_position - _aircraft.global_position
		_aircraft.apply_force(force, force_position)
	else:
		# Fallback to applying a central force if the nose gear isn't found
		_aircraft.apply_central_force(force)


func _release() -> void:
	if debug_enabled: print("[CATAPULT] Releasing aircraft.")
	if is_instance_valid(_aircraft):
		# Perform a clean handover to the aircraft's own engine controller.
		# Set its target power to 1.0 so it doesn't immediately shut down the engine.
		var engine_controller = _find_engine_controller(_aircraft)
		if is_instance_valid(engine_controller):
			engine_controller.set("target_power", 1.0)
			if debug_enabled: print("[CATAPULT] Handed over throttle control to ControlEngine module.")
		
		_aircraft.remove_meta("controls_disabled") # Restore player throttle input
		
	# The aircraft will continue with the velocity it had on the last frame.
	_latched = false
	_launching = false
	_aircraft = null
	_pin_shuttle_at_end()
	emit_signal("launch_sequence_complete")
	
func _pin_shuttle_at_end() -> void:
	if debug_enabled: print("[CATAPULT] Pinning shuttle at release point.")
	_pin_at_release_point = true

func _find_aircraft(from_node: Node) -> RigidBody3D:
	var n: Node = from_node
	while n:
		if n is RigidBody3D: return n
		n = n.get_parent()
	return null

func _immobilize_wheels():
	if not is_instance_valid(_aircraft): return
	
	# Find the landing gear controller module, which holds the references.
	var gear_controller_nodes = _find_nodes_by_script(_aircraft, "ControlLandingGear.gd")
	if gear_controller_nodes.is_empty():
		if debug_enabled: print("[CATAPULT] WARNING: Could not find ControlLandingGear module to latch wheels.")
		return
		
	var gear_controller = gear_controller_nodes[0]
	
	# Get the main gear colliders using the paths already defined in the controller.
	var left_gear_path = gear_controller.get("left_main_gear_collider_path")
	var right_gear_path = gear_controller.get("right_main_gear_collider_path")
	
	var gear_nodes_to_latch: Array[Node3D] = []
	if left_gear_path and not left_gear_path.is_empty():
		gear_nodes_to_latch.append(gear_controller.get_node_or_null(left_gear_path))
	if right_gear_path and not right_gear_path.is_empty():
		gear_nodes_to_latch.append(gear_controller.get_node_or_null(right_gear_path))

	if debug_enabled: print("[CATAPULT] Found %d main gear nodes to latch." % gear_nodes_to_latch.size())
	
	for gear_node in gear_nodes_to_latch:
		if is_instance_valid(gear_node):
			var pin_joint = PinJoint3D.new()
			# Place the joint at the wheel's global position
			pin_joint.global_position = gear_node.global_position
			# Add the joint as a child of the world, not the aircraft
			get_tree().current_scene.add_child(pin_joint)
			# Pin the aircraft (Node A) to the static world (Node B is empty)
			pin_joint.set_node_a(_aircraft.get_path())
			_wheel_latches.append(pin_joint)
			if debug_enabled: print("[CATAPULT] Latched wheel at: ", gear_node.global_position)
			
func _release_wheels():
	if debug_enabled: print("[CATAPULT] Releasing %d wheel latches." % _wheel_latches.size())
	for joint in _wheel_latches:
		if is_instance_valid(joint):
			joint.queue_free()
	_wheel_latches.clear()

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

	# Lock controls immediately so AIPilot/ControlEngine can't run the engine
	# before the shuttle connects. Released on launch (line with remove_meta).
	ac.set_meta("controls_disabled", true)

	var target_transform = latch_marker.global_transform
	
	# Orient aircraft to face launch direction (latch → release)
	# Aircraft model forward is +Z (basis.z), so atan2 directly gives the correct yaw
	var launch_dir = (release_marker.global_position - latch_marker.global_position)
	launch_dir.y = 0.0
	launch_dir = launch_dir.normalized()
	var yaw_angle = atan2(launch_dir.x, launch_dir.z) + deg_to_rad(heading_offset_deg)
	target_transform.basis = Basis(Vector3.UP, yaw_angle)
	
	print("[CATAPULT] align_aircraft called. Launch dir: ", launch_dir, " Yaw: ", rad_to_deg(yaw_angle))
	print("[CATAPULT] Aircraft transform BEFORE teleport: ", ac.global_transform)
	
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
	# Snap Y to deck to account for marker height
	var from = final_transform.origin + Vector3.UP * 5.0
	var to = final_transform.origin + Vector3.DOWN * 10.0
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to, 1) # Assume mask 1 is ground
	var hit = space.intersect_ray(query)
	if hit:
		final_transform.origin.y = hit.position.y + deck_clearance

	ac.global_transform = final_transform
	print("[CATAPULT] Aircraft transform AFTER teleport: ", ac.global_transform)
	
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
	
	_settling = true
	_settle_timer = _settle_duration
	_finalizing = false

func _reset_state():
	# Resets all state variables to their defaults
	_aircraft = null
	_finalizing = false
	_alignment_pending = false
	_settling = false
	_settle_timer = 0.0
	_latched = false
	_launching = false
	_pin_at_release_point = true

# --- Helpers ---

func _get_deck_forward_vector() -> Vector3:
	if not is_instance_valid(deck_ref):
		return Vector3.FORWARD if deck_forward_is_plus_z else Vector3.BACK
		
	var local_forward = Vector3.FORWARD if deck_forward_is_plus_z else Vector3.BACK
	return (deck_ref.global_transform.basis * local_forward).normalized()
