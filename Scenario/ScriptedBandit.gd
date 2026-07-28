extends Node
class_name ScriptedBandit

# Drives a bandit aircraft along a prescribed flight path for the dogfight test. Attached as a
# child of a frozen Aircraft (RigidBody3D). The aircraft's own AI/physics are disabled; this
# script moves its transform kinematically each physics frame so the friendly gun-fighter has a
# predictable target to try to hit. Two motion patterns:
#   STRAIGHT  - constant heading and altitude
#   WEAVE     - gentle sinusoidal left/right heading changes (easy S-turns)

enum Pattern { STRAIGHT, WEAVE }

var pattern: int = Pattern.STRAIGHT
var speed_mps: float = 90.0
var weave_amplitude_deg: float = 20.0       # peak heading deviation for WEAVE
var weave_period_s: float = 8.0             # time for one full left-right cycle
var loop_bounds_radius_m: float = 1800.0    # turn back toward center beyond this from the arena center
var arena_center: Vector3 = Vector3.ZERO

var _aircraft: RigidBody3D = null
var _heading_rad: float = 0.0               # current base heading (yaw), radians
var _age_s: float = 0.0
var _velocity: Vector3 = Vector3.ZERO

func setup(aircraft: RigidBody3D, start_heading_rad: float) -> void:
	_aircraft = aircraft
	_heading_rad = start_heading_rad
	# Anchor the patrol box on the actual spawn position so containment is always relative to where
	# the bandit (and the nearby friendly) started, regardless of the arena_center passed in.
	if aircraft != null and is_instance_valid(aircraft):
		arena_center = aircraft.global_position

func _physics_process(delta: float) -> void:
	if _aircraft == null or not is_instance_valid(_aircraft):
		return
	_age_s += delta

	# Base heading: straight holds; weave adds an eased sinusoidal offset around the base heading.
	var heading: float = _heading_rad
	if pattern == Pattern.WEAVE and weave_period_s > 0.0:
		var phase: float = TAU * _age_s / weave_period_s
		heading += deg_to_rad(weave_amplitude_deg) * sin(phase)

	# Keep the fight in a bounded box: once past the bounds radius, firmly curve the BASE heading
	# back toward the arena center. A gentle blend let the bandit fly straight out of the arena
	# faster than it turned around; use a strong rate so it actually comes back within a lap.
	var pos: Vector3 = _aircraft.global_position
	var from_center: Vector3 = Vector3(pos.x - arena_center.x, 0.0, pos.z - arena_center.z)
	if from_center.length() > loop_bounds_radius_m:
		var inbound: float = atan2(-from_center.x, -from_center.z)
		# Turn toward home at up to ~45 deg/s so it reliably curves back, not a lazy drift.
		_heading_rad = _lerp_angle(_heading_rad, inbound, clampf(delta * 3.0, 0.0, 1.0))
		heading = _heading_rad
		if pattern == Pattern.WEAVE and weave_period_s > 0.0:
			heading += deg_to_rad(weave_amplitude_deg) * sin(TAU * _age_s / weave_period_s)

	# Forward direction from heading (aircraft forward is +Z, per _basis_from_heading).
	var forward: Vector3 = Vector3(sin(heading), 0.0, cos(heading))
	_velocity = forward * speed_mps
	var new_pos: Vector3 = pos + _velocity * delta

	var basis: Basis = _basis_from_heading(heading)
	_aircraft.global_transform = Transform3D(basis, new_pos)
	# Keep the frozen body's reported velocity in sync so the friendly's lead/CCIP sees motion.
	_aircraft.linear_velocity = _velocity

func get_velocity_vector() -> Vector3:
	return _velocity

func _basis_from_heading(heading_rad: float) -> Basis:
	# Yaw-only basis with the aircraft's +Z pointing along the heading, wings level.
	var forward: Vector3 = Vector3(sin(heading_rad), 0.0, cos(heading_rad))
	var up: Vector3 = Vector3.UP
	var right: Vector3 = up.cross(forward).normalized()
	up = forward.cross(right).normalized()
	return Basis(right, up, forward)

func _lerp_angle(from: float, to: float, weight: float) -> float:
	var diff: float = fmod(to - from + PI, TAU) - PI
	return from + diff * weight
