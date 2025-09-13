extends Node3D

# Nodes/paths
@export var shuttle_path: NodePath            # Node3D that moves along +Z (forward)
@export var shuttle_area_path: NodePath       # Area3D on the shuttle that detects nose gear collider
@export var start_z: float = -25.0             # launch position z (meters, carrier space)
@export var end_z: float = -2.0               # end of stroke z (release point)
@export var align_x: float = 0.0
@export var align_y: float = 0.0
@export var start_marker_path: NodePath        # Optional Node3D that defines exact start pose

# Timing and forces
@export var shuttle_speed: float = 30.0        # m/s constant for first pass
@export var latch_distance: float = 0.5        # m, proximity to latch
@export var immobilize_force: float = 60000.0  # N, downward or rear-wheel hold

# Input
@export var launch_action: String = "fire_weapon" # temporary binding for launch
@export var align_action: String = "catapult_align" # button to align aircraft to start and begin sequence
@export var aircraft_path: NodePath                     # optional explicit aircraft

# Pickup-align settings (smooth slide/rotate to start without teleport)
@export var use_pickup_align: bool = true
@export var force_face_minus_z: bool = true
@export var deck_reference_path: NodePath
@export var pickup_speed_mps: float = 10.0
@export var pickup_turn_rate_deg: float = 90.0
@export var pickup_stop_dist: float = 0.15
@export var pickup_stop_yaw_deg: float = 3.0
@export var deck_snap_mask: int = (1 << 0) | (1 << 9)
@export var deck_snap_only_down: bool = true
@export var deck_clearance: float = 0.2
@export var allow_raise_from_penetration: bool = true
@export var max_raise_per_frame: float = 0.25

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

func _ready():
	_shuttle = get_node_or_null(shuttle_path) as Node3D
	_shuttle_area = get_node_or_null(shuttle_area_path) as Area3D
	_start_marker = get_node_or_null(start_marker_path) as Node3D
	_deck_ref = get_node_or_null(deck_reference_path) as Node3D
	if not _deck_ref:
		_deck_ref = get_parent() as Node3D
	if not _deck_ref:
		_deck_ref = self
	# Try to find carrier root by name if still ambiguous
	if _deck_ref == self:
		var carrier = _find_node_named(get_tree().root, "LandCarrier")
		if carrier and carrier is Node3D:
			_deck_ref = carrier as Node3D
	print("[Catapult] Deck reference: ", _deck_ref.name if _deck_ref else "null")
	if _deck_ref:
		var deck_fwd = (_deck_ref.global_transform.basis * Vector3(0,0,-1)).normalized()
		print("[Catapult] Deck forward: ", deck_fwd, " (flattened: ", Vector3(deck_fwd.x, 0.0, deck_fwd.z).normalized(), ")")
	if not _start_marker:
		_start_marker = get_tree().get_first_node_in_group("catapult_start") as Node3D
	if _shuttle_area:
		_shuttle_area.area_entered.connect(_on_shuttle_area_entered)
	_move_shuttle_to(Vector3(align_x, align_y, start_z))

func _physics_process(delta: float) -> void:
	if not _shuttle:
		return

	if _aligning and _aircraft:
		_update_pickup_align(delta)

	if _launching and _latched and _aircraft:
		# Move shuttle forward
		var g = _shuttle.global_transform
		g.origin.z = min(end_z, g.origin.z + shuttle_speed * delta)
		_shuttle.global_transform = g
		_drag_aircraft_to_shuttle()
		if g.origin.z >= end_z - 0.01:
			_release()
			_return_shuttle()
	elif _moving_to_latch and _aircraft and not _latched:
		# Move shuttle to align with aircraft nose gear at start position
		var g2 = _shuttle.global_transform
		var target = Vector3(align_x, align_y, start_z)
		var dz = target.z - g2.origin.z
		var step = clamp(dz, -shuttle_speed * delta, shuttle_speed * delta)
		g2.origin.z += step
		_shuttle.global_transform = g2
		# Auto latch when close in Z
		if abs(dz) <= latch_distance:
			_try_latch()

func _input(event):
	if _latched and not _launching and Input.is_action_just_pressed(launch_action):
		print("[Catapult] Launch action pressed!")
		_launching = true
	elif not _aligning and not _latched and Input.is_action_just_pressed(align_action):
		var ac = _get_aircraft()
		print("[Catapult] align pressed; ac=", ac, " marker=", _start_marker)
		if ac:
			if use_pickup_align:
				_begin_pickup_align(ac)
			else:
				_align_aircraft_to_start(ac)
				begin_sequence(ac)
		else:
			print("[Catapult] No aircraft found to align")

func begin_sequence(aircraft: RigidBody3D) -> void:
	# Called to start: places shuttle and approaches nose gear
	_aircraft = aircraft
	_latched = false
	_launching = false
	_moving_to_latch = true
	# Start shuttle slightly behind the start z so it can move forward to latch
	_move_shuttle_to(Vector3(align_x, align_y, start_z - 3.0))

func _on_shuttle_area_entered(area: Area3D) -> void:
	if _latched or _launching or not _moving_to_latch:
		return
	
	# Nose gear collider is a CollisionShape3D under the aircraft; accept by name/group
	if area.name.to_lower().find("gear") != -1 or area.is_in_group("nose_gear"):
		print("[Catapult] Shuttle area detected nose gear: ", area.name)
		var ac = _find_aircraft(area)
		if ac and ac == _aircraft:
			_try_latch()

func _try_latch() -> void:
	if not _aircraft or not _shuttle or _latched:
		return
	
	print("[Catapult] LATCHED with aircraft.")
	_latched = true
	_moving_to_latch = false

	# Snap aircraft nose to shuttle position to ensure alignment
	var g = _aircraft.global_transform
	var s = _shuttle.global_transform
	g.origin.x = s.origin.x
	g.origin.y = s.origin.y
	_aircraft.global_transform = g
	
	# Immobilize rear wheels via friction/damp increase if module present
	var gear_modules = _aircraft.find_children("LandingGear", "AircraftModule_LandingGear")
	for gear in gear_modules:
		if "is_nose_gear" in gear and gear.is_nose_gear:
			continue
		# Not a nose gear, so likely a main/rear gear. Immobilize it.
		if gear.get("sideways_friction"):
			gear.set("sideways_friction", 1000.0) # High friction to prevent sliding
		if gear.get("friction_force_multiplier"):
			gear.set("friction_force_multiplier", 10.0)


func _drag_aircraft_to_shuttle() -> void:
	if not _aircraft or not _shuttle:
		return
	# Hard tether: position aircraft nose with shuttle; apply forward impulse
	var a = _aircraft.global_transform
	var s = _shuttle.global_transform
	# Pull toward shuttle orientation/position at the nose
	var toward = s.origin - a.origin
	var pull = toward * 10.0
	_aircraft.apply_central_force(pull)
	# Add forward push
	_aircraft.apply_central_force(Vector3(0,0,shuttle_speed * 2000.0))

func _release() -> void:
	print("[Catapult] Releasing aircraft.")
	_latched = false
	_launching = false
	# Restore gear friction
	if is_instance_valid(_aircraft):
		var gear_modules = _aircraft.find_children("LandingGear", "AircraftModule_LandingGear")
		for gear in gear_modules:
			# This part needs to restore the *original* values, which we should save first.
			# For now, we'll just set them to a reasonable default.
			if "is_nose_gear" in gear and gear.is_nose_gear:
				continue
			
			if gear.get("sideways_friction"):
				gear.set("sideways_friction", 1.0) 
			if gear.get("friction_force_multiplier"):
				gear.set("friction_force_multiplier", 1.0)
	
	_aircraft = null

func _return_shuttle() -> void:
	# Return to start
	var g = _shuttle.global_transform
	g.origin.z = start_z
	_shuttle.global_transform = g

func _move_shuttle_to(pos: Vector3) -> void:
	if _shuttle:
		var g = _shuttle.global_transform
		g.origin = pos
		_shuttle.global_transform = g

func _find_aircraft(from_node: Node) -> RigidBody3D:
	var n: Node = from_node
	while n:
		if n is RigidBody3D:
			return n
		n = n.get_parent()
	return null

func _get_aircraft() -> RigidBody3D:
	if _aircraft and is_instance_valid(_aircraft):
		return _aircraft
	if aircraft_path != NodePath():
		var n = get_node_or_null(aircraft_path)
		if n is RigidBody3D:
			return n
	# fallback: first in group
	var g = get_tree().get_first_node_in_group("aircraft")
	return g as RigidBody3D

func _find_node_named(root: Node, target_name: String) -> Node:
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
	# Place aircraft at a robust marker if provided; else compute from catapult local
	var target_t: Transform3D
	if _start_marker:
		target_t = _start_marker.global_transform
		if force_face_minus_z:
			var origin = target_t.origin
			var deck_fwd = (_deck_ref.global_transform.basis * Vector3(0,0,-1)).normalized()
			deck_fwd = Vector3(deck_fwd.x, 0.0, deck_fwd.z).normalized()
			print("[Catapult] Teleport align - deck_fwd: ", deck_fwd)
			target_t = Transform3D(Basis(), origin).looking_at(origin - deck_fwd, Vector3.UP)
		print("[Catapult] Using start marker transform:", target_t)
	else:
		var local = Vector3(align_x, align_y, start_z)
		var origin = global_transform.origin + global_transform.basis * local
		var desired_fwd = (_deck_ref.global_transform.basis * Vector3(0,0,-1)).normalized() if force_face_minus_z else (global_transform.basis * Vector3(0,0,-1)).normalized()
		desired_fwd = Vector3(desired_fwd.x, 0.0, desired_fwd.z).normalized()
		var up = Vector3.UP
		target_t = Transform3D(Basis(), origin).looking_at(origin - desired_fwd, up)
	# Zero velocities and apply
	ac.freeze = true
	ac.linear_velocity = Vector3.ZERO
	ac.angular_velocity = Vector3.ZERO
	ac.global_transform = target_t
	# Unfreeze next frame to avoid physics fighting the teleport
	call_deferred("_finalize_align", ac, target_t)

func _finalize_align(ac: RigidBody3D, t: Transform3D) -> void:
	if not is_instance_valid(ac):
		return
	ac.global_transform = t
	ac.freeze = false

func _begin_pickup_align(ac: RigidBody3D) -> void:
	# Compute target pose similar to teleport align, but move smoothly
	var target_t: Transform3D
	if _start_marker:
		target_t = _start_marker.global_transform
		if force_face_minus_z:
			var origin = target_t.origin
			var deck_fwd = (_deck_ref.global_transform.basis * Vector3(0,0,-1)).normalized()
			deck_fwd = Vector3(deck_fwd.x, 0.0, deck_fwd.z).normalized()
			print("[Catapult] Pickup align - deck_fwd: ", deck_fwd)
			target_t = Transform3D(Basis(), origin).looking_at(origin - deck_fwd, Vector3.UP)
		print("[Catapult] Pickup target marker transform:", target_t)
	else:
		var local = Vector3(align_x, align_y, start_z)
		var origin = global_transform.origin + global_transform.basis * local
		var desired_fwd = (_deck_ref.global_transform.basis * Vector3(0,0,-1)).normalized() if force_face_minus_z else (global_transform.basis * Vector3(0,0,-1)).normalized()
		desired_fwd = Vector3(desired_fwd.x, 0.0, desired_fwd.z).normalized()
		var up = Vector3.UP
		target_t = Transform3D(Basis(), origin).looking_at(origin - desired_fwd, up)
	_aircraft = ac
	_target_align = target_t
	_aligning = true
	_saved_gravity_scale = ac.gravity_scale
	_saved_collision_layer = ac.collision_layer
	_saved_collision_mask = ac.collision_mask
	_saved_linear_damp = ac.linear_damp
	_saved_angular_damp = ac.angular_damp
	# Freeze and disable collisions to prevent physics impulses while we slide/rotate
	ac.freeze = true
	ac.gravity_scale = 0.0
	ac.collision_layer = 0
	ac.collision_mask = 0
	ac.linear_damp = max(ac.linear_damp, 5.0)
	ac.angular_damp = max(ac.angular_damp, 5.0)
	ac.linear_velocity = Vector3.ZERO
	ac.angular_velocity = Vector3.ZERO

func _update_pickup_align(delta: float) -> void:
	if not _aircraft or not _aligning:
		return
	var a: Transform3D = _aircraft.global_transform
	var pos: Vector3 = a.origin
	var tgt: Vector3 = _target_align.origin
	# Slide in XZ toward target
	var dx = tgt.x - pos.x
	var dz = tgt.z - pos.z
	var dist = sqrt(dx*dx + dz*dz)
	if dist > 0.0001:
		var step = min(pickup_speed_mps * delta, dist)
		var inv = 1.0 / dist
		pos.x += dx * inv * step
		pos.z += dz * inv * step
	# Snap Y to deck via raycast directly below
	var from = pos + Vector3.UP * 5.0
	var to = pos + Vector3.DOWN * 10.0
	var ss = get_world_3d().direct_space_state
	var q = PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = deck_snap_mask
	q.collide_with_areas = false
	var ex = []
	if _aircraft and _aircraft is CollisionObject3D:
		ex.append((_aircraft as CollisionObject3D).get_rid())
	if _shuttle and _shuttle is CollisionObject3D:
		ex.append((_shuttle as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit = ss.intersect_ray(q)
	if hit:
		var target_y = hit.position.y + deck_clearance
		if deck_snap_only_down:
			if pos.y > target_y:
				# Lower onto deck
				pos.y = target_y
			elif allow_raise_from_penetration and pos.y < target_y:
				# Gently lift out of penetration without popping upward
				pos.y = min(target_y, pos.y + max_raise_per_frame)
		else:
			pos.y = target_y
	# Rotate toward target yaw only
	var cur_fwd = (-a.basis.z).normalized()
	var tgt_fwd = (-_target_align.basis.z).normalized()
	var cross_y = cur_fwd.x * tgt_fwd.z - cur_fwd.z * tgt_fwd.x
	var dot = clamp(cur_fwd.dot(tgt_fwd), -1.0, 1.0)
	var yaw_err = atan2(cross_y, dot)
	var max_yaw_step = deg_to_rad(pickup_turn_rate_deg) * delta
	var step_yaw = clamp(yaw_err, -max_yaw_step, max_yaw_step)
	var new_basis = Basis(Vector3.UP, step_yaw) * a.basis
	new_basis = new_basis.orthonormalized()
	# Apply incremental transform
	a.basis = new_basis
	a.origin = pos
	_aircraft.global_transform = a
	_aircraft.linear_velocity = Vector3.ZERO
	_aircraft.angular_velocity = Vector3.ZERO
	# Stop condition
	if dist <= pickup_stop_dist and abs(rad_to_deg(yaw_err)) <= pickup_stop_yaw_deg:
		_aligning = false
		if is_instance_valid(_aircraft):
			# Snap final orientation exactly to deck -Z to remove any residual yaw error
			var final_t = _aircraft.global_transform
			var deck_fwd = (_deck_ref.global_transform.basis * Vector3(0,0,-1)).normalized()
			final_t.basis = Transform3D().looking_at(final_t.origin - deck_fwd, Vector3.UP).basis
			_aircraft.global_transform = final_t
			# Restore physics/collisions and unfreeze cleanly
			_aircraft.gravity_scale = _saved_gravity_scale
			_aircraft.collision_layer = _saved_collision_layer
			_aircraft.collision_mask = _saved_collision_mask
			_aircraft.linear_damp = _saved_linear_damp
			_aircraft.angular_damp = _saved_angular_damp
			_aircraft.linear_velocity = Vector3.ZERO
			_aircraft.angular_velocity = Vector3.ZERO
			_aircraft.freeze = false
			begin_sequence(_aircraft)

func align_and_begin():
	var ac = _get_aircraft()
	if ac:
		_align_aircraft_to_start(ac)
		begin_sequence(ac)
	else:
		print("[Catapult] align_and_begin: No aircraft found")
