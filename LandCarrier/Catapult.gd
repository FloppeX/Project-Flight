extends Node3D

# Catapult controller: aligns an aircraft to the deck, settles it onto gear,
# then moves the shuttle to latch the nose gear and launch along the deck.

# Nodes/paths
@export var shuttle_path: NodePath            # Shuttle Node3D (moves along deck axis)
@export var shuttle_area_path: NodePath       # Area3D on shuttle that detects nose gear collider
@export var start_z: float = -25.0            # Legacy start Z (local), still used for defaults
@export var end_z: float = -2.0               # Launch end Z (local)
@export var align_x: float = 0.0              # Shuttle track X (local)
@export var align_y: float = 0.0              # Shuttle track Y (local)
@export var start_marker_path: NodePath       # Optional precise start pose (global)

# Timing and forces
@export var shuttle_speed: float = 30.0       # Constant shuttle speed (m/s)
@export var latch_distance: float = 0.5       # Proximity threshold (disabled for Area-only latching)
@export var immobilize_force: float = 60000.0 # Reserved: force placeholder if needed

# Input
@export var launch_action: String = "fire_weapon"
@export var align_action: String = "catapult_align"
@export var aircraft_path: NodePath           # Optional explicit aircraft

# Pickup-align settings (disabled by default; we use teleport+settle for robustness)
@export var use_pickup_align: bool = false
@export var force_face_minus_z: bool = true   # Kept for legacy; replaced by deck_forward_is_plus_z
@export var deck_reference_path: NodePath     # Node whose +Z/-Z defines deck forward
@export var pickup_speed_mps: float = 10.0
@export var pickup_turn_rate_deg: float = 90.0
@export var pickup_stop_dist: float = 0.15
@export var pickup_stop_yaw_deg: float = 3.0

# Deck snap / elevation configuration used by both pickup and teleport paths
@export var deck_snap_mask: int = (1 << 0) | (1 << 9) # default + terrain
@export var deck_snap_only_down: bool = true          # do not lift unless penetrating
@export var deck_clearance: float = 0.2               # clearance above deck on settle
@export var allow_raise_from_penetration: bool = true
@export var max_raise_per_frame: float = 0.25
@export var max_pickup_duration: float = 3.0          # safety timeout if align doesn't converge
@export var teleport_snap_to_deck: bool = true        # snap teleport height to deck
@export var teleport_clearance: float = 0.1           # unused now (deck_clearance used instead)
@export var heading_offset_deg: float = 0.0           # compensate model yaw misalignment

# Nose gear homing / approach tuning for smooth latching
@export var nose_gear_target_path: NodePath           # Node3D at nose gear (Area3D or marker)
@export var approach_offset_m: float = 3.0            # start this far behind the target
@export var approach_slow_zone_m: float = 1.0         # slow down in last meter
@export var approach_slow_factor: float = 0.3         # slow zone speed multiplier
@export var deck_forward_is_plus_z: bool = true       # carrier now uses +Z as forward

# State
var _shuttle: Node3D
var _shuttle_area: Area3D
var _aircraft: RigidBody3D
var _nose_gear: CollisionShape3D
var _latched: bool = false
var _moving_to_latch: bool = false
var _launching: bool = false
var _start_marker: Node3D
var _aligning: bool = false
var _target_align: Transform3D
var _saved_gravity_scale: float = 1.0
var _saved_collision_layer: int = 0
var _saved_collision_mask: int = 0
var _saved_linear_damp: float = 0.0
var _saved_angular_damp: float = 0.0
var _deck_ref: Node3D
var _settling: bool = false                        # true while letting suspension settle
var _settle_duration: float = 1.5                  # time to settle visually
var _settle_timer: float = 0.0
var _pickup_elapsed: float = 0.0
var _saved_lock_ang_x: bool = false
var _saved_lock_ang_y: bool = false
var _saved_lock_ang_z: bool = false
var _finalizing: bool = false                      # reentry guard for finalize
var _latch_target_z: float = 0.0                   # fixed Z target captured at begin_sequence
var _nose_target: Node3D

func _ready():
	_shuttle = get_node_or_null(shuttle_path) as Node3D
	_shuttle_area = get_node_or_null(shuttle_area_path) as Area3D
	_start_marker = get_node_or_null(start_marker_path) as Node3D
	_deck_ref = get_node_or_null(deck_reference_path) as Node3D
	if not _deck_ref:
		_deck_ref = get_parent() as Node3D
	if not _deck_ref:
		_deck_ref = self
	# Auto-find a deck reference by name as a fallback
	if _deck_ref == self:
		var carrier = _find_node_named(get_tree().root, "LandCarrier")
		if carrier and carrier is Node3D:
			_deck_ref = carrier as Node3D
	print("[Catapult] Deck reference: ", _deck_ref.name if _deck_ref else "null")
	if _deck_ref:
		var deck_fwd = (_deck_ref.global_transform.basis * (Vector3(0,0,1) if deck_forward_is_plus_z else Vector3(0,0,-1))).normalized()
		print("[Catapult] Deck forward: ", deck_fwd, " (flattened: ", Vector3(deck_fwd.x, 0.0, deck_fwd.z).normalized(), ")")
	if not _start_marker:
		_start_marker = get_tree().get_first_node_in_group("catapult_start") as Node3D
	if _shuttle_area:
		# Latch only via Area3D overlap for precise engagement on nose gear
		_shuttle_area.area_entered.connect(_on_shuttle_area_entered)
	_move_shuttle_to(Vector3(align_x, align_y, start_z))

func _physics_process(delta: float) -> void:
	if not _shuttle:
		return

	# Pickup-align path (optional)
	if _aligning and _aircraft:
		_update_pickup_align(delta)
	# After teleport align, wait for suspension to settle before moving shuttle
	elif _settling and is_instance_valid(_aircraft):
		_settle_timer -= delta
		if _settle_timer <= 0.0:
			_settling = false
			print("[Catapult] Aircraft settled, beginning latch sequence.")
			begin_sequence(_aircraft)
	# Approach the nose gear along fixed deck track
	elif _moving_to_latch and _aircraft and not _latched:
		# Home to the captured latch Z; keep X/Y fixed to track
		var target_pos_local = Vector3(align_x, align_y, _latch_target_z)
		var current_pos_local = global_transform.affine_inverse() * _shuttle.global_position
		var dz = target_pos_local.z - current_pos_local.z
		var step_mag = min(shuttle_speed * delta, abs(dz))
		# Ease in near the target to prevent overshoot and latch gently
		if abs(dz) < approach_slow_zone_m:
			step_mag *= clamp(approach_slow_factor, 0.05, 1.0)
		var step = step_mag * sign(dz)
		current_pos_local.z += step
		current_pos_local.x = align_x
		current_pos_local.y = align_y
		_shuttle.global_position = global_transform * current_pos_local
		print("[Catapult] Shuttle move: curZ=", current_pos_local.z, " tgtZ=", target_pos_local.z, " dz=", dz, " step=", step)

	# Launch stroke
	if _launching and _latched and _aircraft:
		var g = _shuttle.global_transform
		g.origin.z = min(end_z, g.origin.z + shuttle_speed * delta)
		_shuttle.global_transform = g
		_drag_aircraft_to_shuttle()
		if g.origin.z >= end_z - 0.01:
			_release()
			_return_shuttle()

func _input(event):
	if _latched and not _launching and Input.is_action_just_pressed(launch_action):
		print("[Catapult] Launch action pressed!")
		_launching = true
	elif not _aligning and not _latched and Input.is_action_just_pressed(align_action):
		var ac = _get_aircraft()
		print("[Catapult] align pressed; ac=", ac, " marker=", _start_marker)
		if ac:
			# Ignore aligns while finalizing/settling to avoid reentry
			if _finalizing or _settling:
				print("[Catapult] Align ignored: currently finalizing/settling")
				return
			# Teleport + settle path for robust placement without physics fights
			_aligning = false
			_settling = false
			_settle_timer = 0.0
			_align_aircraft_to_start(ac)
			# begin_sequence will start after settle
		else:
			print("[Catapult] No aircraft found to align")
	# Manual finalize/unfreeze (debug)
	elif event is InputEventKey and event.pressed and not event.echo:
		var keycode: int = event.physical_keycode
		if keycode == KEY_U:
			if is_instance_valid(_aircraft):
				print("[Catapult] Manual finalize (U): stopping align and calling _finalize_alignment_and_settle")
				_aligning = false
				call_deferred("_finalize_alignment_and_settle")
			else:
				print("[Catapult] Manual finalize requested but no aircraft is assigned.")

func begin_sequence(aircraft: RigidBody3D) -> void:
	# Capture nose gear target and start shuttle a bit behind; keep angular locks restored
	_aircraft = aircraft
	_latched = false
	_launching = false
	_moving_to_latch = true
	if is_instance_valid(_aircraft):
		_aircraft.axis_lock_angular_x = _saved_lock_ang_x
		_aircraft.axis_lock_angular_y = _saved_lock_ang_y
		_aircraft.axis_lock_angular_z = _saved_lock_ang_z
	_nose_target = get_node_or_null(nose_gear_target_path) as Node3D
	var target_global: Vector3 = _aircraft.global_position
	if _nose_target and is_instance_valid(_nose_target):
		target_global = _nose_target.global_position
	var target_local = global_transform.affine_inverse() * target_global
	_latch_target_z = target_local.z
	var shuttle_start_pos = Vector3(align_x, align_y, target_local.z - approach_offset_m)
	print("[Catapult] Moving shuttle to start sequence at local pos: ", shuttle_start_pos)
	_move_shuttle_to(shuttle_start_pos)

func _on_shuttle_area_entered(area: Area3D) -> void:
	# Nose-gear-only latch is recommended (set group on Area3D)
	if _latched or _launching or not _moving_to_latch:
		return
	if area.name.to_lower().find("gear") != -1 or area.is_in_group("nose_gear"):
		print("[Catapult] Shuttle area detected nose gear: ", area.name)
		var ac = _find_aircraft(area)
		if ac and ac == _aircraft:
			_try_latch()

func _try_latch() -> void:
	# Latch: snap X/Y to shuttle and stiffen rear gear to prevent fishtailing
	if not _aircraft or not _shuttle or _latched:
		return
	print("[Catapult] LATCHED with aircraft.")
	_latched = true
	_moving_to_latch = false
	var g = _aircraft.global_transform
	var s = _shuttle.global_transform
	g.origin.x = s.origin.x
	g.origin.y = s.origin.y
	_aircraft.global_transform = g
	var gear_modules = _aircraft.find_children("LandingGear", "AircraftModule_LandingGear")
	for gear in gear_modules:
		if "is_nose_gear" in gear and gear.is_nose_gear:
			continue
		if gear.get("sideways_friction"):
			gear.set("sideways_friction", 1000.0)
		if gear.get("friction_force_multiplier"):
			gear.set("friction_force_multiplier", 10.0)

func _drag_aircraft_to_shuttle() -> void:
	# During launch stroke, pull aircraft forward and toward shuttle to keep rigid
	if not _aircraft or not _shuttle:
		return
	var a = _aircraft.global_transform
	var s = _shuttle.global_transform
	var toward = s.origin - a.origin
	var pull = toward * 10.0
	_aircraft.apply_central_force(pull)
	_aircraft.apply_central_force(Vector3(0,0,shuttle_speed * 2000.0))

func _release() -> void:
	# Release cable and restore gear grip after stroke
	print("[Catapult] Releasing aircraft.")
	_latched = false
	_launching = false
	if is_instance_valid(_aircraft):
		var gear_modules = _aircraft.find_children("LandingGear", "AircraftModule_LandingGear")
		for gear in gear_modules:
			if "is_nose_gear" in gear and gear.is_nose_gear:
				continue
			if gear.get("sideways_friction"):
				gear.set("sideways_friction", 1.0)
			if gear.get("friction_force_multiplier"):
				gear.set("friction_force_multiplier", 1.0)
	_aircraft = null

func _return_shuttle() -> void:
	# Return to start Z on track; next sequence will recapture target
	var return_pos_local = Vector3(align_x, align_y, start_z)
	_move_shuttle_to(return_pos_local)

func _move_shuttle_to(pos: Vector3) -> void: # local to catapult
	if _shuttle:
		_shuttle.global_position = global_transform * pos

func _find_aircraft(from_node: Node) -> RigidBody3D:
	# Crawl up tree to find the RigidBody3D owning the Area
	var n: Node = from_node
	while n:
		if n is RigidBody3D:
			return n
		n = n.get_parent()
	return null

func _get_aircraft() -> RigidBody3D:
	# Resolve aircraft via explicit path, then group
	if _aircraft and is_instance_valid(_aircraft):
		return _aircraft
	if aircraft_path != NodePath():
		var n = get_node_or_null(aircraft_path)
		if n is RigidBody3D:
			return n
	var g = get_tree().get_first_node_in_group("aircraft")
	return g as RigidBody3D

func _find_node_named(root: Node, target_name: String) -> Node:
	# Simple DFS by name (fallback deck reference)
	if not root:
		return null
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found = _find_node_named(child, target_name)
		if found:
			return found
	return null

func _align_aircraft_to_start(ac: RigidBody3D) -> void:
	# Teleport + snap to deck with clearance; disable collisions while placing
	_aircraft = ac
	var target_t: Transform3D
	if _start_marker:
		target_t = _start_marker.global_transform
		if force_face_minus_z:
			var origin = target_t.origin
			var deck_fwd = (_deck_ref.global_transform.basis * (Vector3(0,0,1) if deck_forward_is_plus_z else Vector3(0,0,-1))).normalized()
			deck_fwd = Vector3(deck_fwd.x, 0.0, deck_fwd.z).normalized()
			print("[Catapult] Teleport align - deck_fwd: ", deck_fwd)
			target_t = Transform3D(Basis(), origin).looking_at(origin + deck_fwd, Vector3.UP)
		print("[Catapult] Using start marker transform:", target_t)
	else:
		var local = Vector3(align_x, align_y, start_z)
		var origin = global_transform.origin + global_transform.basis * local
		var desired_fwd = (_deck_ref.global_transform.basis * (Vector3(0,0,1) if deck_forward_is_plus_z else Vector3(0,0,-1))).normalized() if force_face_minus_z else (global_transform.basis * Vector3(0,0,-1)).normalized()
		desired_fwd = Vector3(desired_fwd.x, 0.0, desired_fwd.z).normalized()
		var up = Vector3.UP
		target_t = Transform3D(Basis(), origin).looking_at(origin + desired_fwd, up)
		# Apply heading offset to compensate model yaw
		target_t.basis = Basis(Vector3.UP, deg_to_rad(heading_offset_deg)) * target_t.basis
	# Snap height to deck with shared clearance setting
	if teleport_snap_to_deck:
		var from = target_t.origin + Vector3.UP * 5.0
		var to = target_t.origin + Vector3.DOWN * 10.0
		var ss = get_world_3d().direct_space_state
		var q = PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = deck_snap_mask
		q.collide_with_areas = false
		var hit = ss.intersect_ray(q)
		if hit:
			var o = target_t.origin
			o.y = hit.position.y + deck_clearance
			target_t.origin = o
	# Place with collisions disabled; finalize next frame restores physics
	_saved_gravity_scale = ac.gravity_scale
	_saved_collision_layer = ac.collision_layer
	_saved_collision_mask = ac.collision_mask
	_saved_linear_damp = ac.linear_damp
	_saved_angular_damp = ac.angular_damp
	ac.freeze = true
	ac.gravity_scale = 0.0
	ac.collision_layer = 0
	ac.collision_mask = 0
	ac.linear_velocity = Vector3.ZERO
	ac.angular_velocity = Vector3.ZERO
	ac.global_transform = target_t
	print("[Catapult] Teleport align placed ", ac.name, " at ", target_t.origin, ", scheduling _finalize_alignment_and_settle")
	call_deferred("_finalize_alignment_and_settle")

func _finalize_alignment_and_settle() -> void:
	# One-shot: restore physics, snap final yaw to deck axis, unfreeze, and begin settle
	if not is_instance_valid(_aircraft):
		print("[Catapult] _finalize_alignment_and_settle: no aircraft; aborting")
		return
	if _finalizing:
		print("[Catapult] _finalize_alignment_and_settle: already finalizing; skipping")
		return
	_finalizing = true
	print("[Catapult] _finalize_alignment_and_settle: starting for ", _aircraft.name)
	var final_t = _aircraft.global_transform
	var deck_fwd = (_deck_ref.global_transform.basis * (Vector3(0,0,1) if deck_forward_is_plus_z else Vector3(0,0,-1))).normalized()
	final_t.basis = Transform3D().looking_at(final_t.origin + deck_fwd, Vector3.UP).basis
	final_t.basis = Basis(Vector3.UP, deg_to_rad(heading_offset_deg)) * final_t.basis
	_aircraft.global_transform = final_t
	print("[Catapult] Finalize: snapped orientation. pos=", final_t.origin, " fwd=", deck_fwd)
	# Restore physics defaults if saved were zeroed
	var restored_gravity: float = _saved_gravity_scale if _saved_gravity_scale != 0.0 else 1.0
	var restored_layer: int = _saved_collision_layer if _saved_collision_layer != 0 else 1
	var restored_mask: int = _saved_collision_mask if _saved_collision_mask != 0 else 1
	_aircraft.gravity_scale = restored_gravity
	_aircraft.collision_layer = restored_layer
	_aircraft.collision_mask = restored_mask
	_aircraft.linear_damp = _saved_linear_damp
	_aircraft.angular_damp = _saved_angular_damp
	_aircraft.linear_velocity = Vector3.ZERO
	_aircraft.angular_velocity = Vector3.ZERO
	# Lock rotation during settle to prevent yaw snaps, then unfreeze and wake
	_saved_lock_ang_x = _aircraft.axis_lock_angular_x
	_saved_lock_ang_y = _aircraft.axis_lock_angular_y
	_saved_lock_ang_z = _aircraft.axis_lock_angular_z
	_aircraft.axis_lock_angular_x = true
	_aircraft.axis_lock_angular_y = true
	_aircraft.axis_lock_angular_z = true
	_aircraft.freeze = false
	_aircraft.sleeping = false
	print("[Catapult] Finalize: restored physics. freeze=", _aircraft.freeze, " sleeping=", _aircraft.sleeping, " grav=", _aircraft.gravity_scale, " layer=", _aircraft.collision_layer, " mask=", _aircraft.collision_mask)
	_settling = true
	_settle_timer = _settle_duration
	print("[Catapult] Finalize: settling for ", _settle_duration, "s")

# Pickup-align has been disabled in this build; keep a no-op to satisfy references
func _update_pickup_align(delta: float) -> void:
	_aligning = false
