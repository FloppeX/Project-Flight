class_name Aircraft
extends RigidBody3D

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")
const ROCKET_CCIP_TARGET_ALONG_MARGIN_M: float = 35.0
const ROCKET_CCIP_MIN_GROUND_NORMAL_Y: float = 0.42
const PROJECTILE_SPEED_CAP_SETTING_KEYS: Array[String] = [
	"physics/jolt_3d/simulation/limits/max_linear_velocity",
	"physics/jolt_physics_3d/simulation/limits/max_linear_velocity",
	"physics/jolt_3d/limits/max_linear_velocity",
	"physics/jolt_physics_3d/limits/max_linear_velocity",
	"physics/3d/max_linear_velocity",
]

signal crashed(impact_velocity)
signal parked
signal moved
signal damaged(damage_amount, current_health)
signal destroyed

# Health/Damage System
@export var max_health: float = 100.0
@export var explosion_scene: PackedScene  # Explosion effect when aircraft is destroyed
@export var wreck_scene: PackedScene  # Wreck scene spawned on destruction
@export var deathcam_scene: PackedScene = preload("res://Camera/Deathcam.tscn")
@export var wreck_base_impulse: float = 400.0
@export var wreck_random_spread: float = 0.35
@export var wreck_extra_spin: float = 25.0
@export var wreck_spawn_max_agl_m: float = 120.0
@export var team: int = 1
@export var damage_cooldown_s: float = 0.01  # Reduced from 0.05 to allow more bullet hits
@export var debug_damage: bool = false
@export_group("Critical Damage")
@export var bleed_damage_min_per_s: float = 10.0
@export var bleed_damage_max_per_s: float = 20.0
@export var explosion_health_threshold: float = -100.0
# Procedural chunks are the default destruction representation. The legacy
# exploded-model path remains available only as an explicit rollback option;
# normal aircraft scenes no longer load or assign those GLBs.
@export var legacy_exploded_model_breakup_enabled: bool = false
@export var exploded_model_scene: PackedScene = null
@export var critical_debris_chunk_min_count: int = 6
@export var critical_debris_chunk_max_count: int = 10
@export var critical_debris_chunk_min_size_m: float = 0.55
@export var critical_debris_chunk_max_size_m: float = 2.0
@export var critical_debris_chunk_impulse_min_mps: float = 20.0
@export var critical_debris_chunk_impulse_max_mps: float = 70.0
@export var staged_critical_debris_enabled: bool = true
@export_range(0.0, 0.6, 0.01) var critical_debris_spread_duration_s: float = 0.28
@export var prevent_below_terrain: bool = true 
@export var ground_clearance: float = 0.25
@export var ground_probe_up: float = 50.0
@export var ground_probe_down: float = 2000.0
## Heightmap safety is disabled near abrupt cliff lips so canyon entries do not
## falsely crash while the visible/physical terrain is still clear.
@export var terrain_safety_cliff_guard_radius_m: float = 24.0
@export var terrain_safety_max_height_variation_m: float = 18.0
@export var terrain_safety_cliff_guard_cache_frames: int = 6
@export var terrain_safety_cliff_guard_cache_distance_m: float = 18.0
@export var belly_land_max_vertical_speed: float = 6.0
@export var belly_land_max_total_speed: float = 80.0
@export var belly_align_tolerance_deg: float = 25.0
@export var hard_crash_vertical_speed: float = 10.0
@export var steep_slope_min_up_dot: float = 0.7
@export_group("Safe Gear Landing")
@export var safe_gear_terrain_land_max_vertical_speed: float = 8.0
@export var safe_gear_terrain_land_max_total_speed: float = 35.0
@export var safe_gear_terrain_hard_vertical_speed: float = 14.0
@export var safe_gear_terrain_damage_per_mps: float = 8.0
@export_group("Carrier Contact Damage")
@export var carrier_body_contact_min_damage: float = 35.0
@export var carrier_body_contact_damage_per_mps: float = 3.0
@export var carrier_body_contact_destroy_speed_mps: float = 28.0

var _last_damage_ms: int = 0
var _current_health: float
var current_health: float:
	get:
		return _current_health
	set(value):
		if _current_health != value:
			var damage_amount = _current_health - value
			_current_health = value
			emit_signal("damaged", damage_amount, _current_health)


@export var max_landing_force: float = 3.0
@export var gravity_factor: float = 1.0 # Normalized to Earth average at sea level
@export var sea_level_from_origin: float = 0.0
@export var altitude_enabled: bool = true
@export var carrier_deck_reference_altitude_m: float = 40.0
@export var carrier_deck_extent_x_m: float = 90.0
@export var carrier_deck_extent_z_m: float = 140.0
@export var carrier_deck_altitude_zone_margin_y_m: float = 120.0
@export var g_force_factor: float = 1.0
@export var WorldOrientationReference: NodePath
@onready var world_ref : Node3D = get_node_or_null(WorldOrientationReference)
var internal_world_reference : Node3D

const EARTH_GRAVITY = 9.8 # for g-force calculation
const DEFAULT_COCKPIT_PILOT_SCENE: PackedScene = preload("res://Aircraft/CockpitPilot.tscn")
const DEFAULT_COCKPIT_PILOT_POSE_SCRIPT: Script = preload("res://Aircraft/PilotPose.gd")
const COCKPIT_PILOT_NODE_NAME: StringName = &"CockpitPilot"
const AIRCRAFT_DEBRIS_BURST_SCRIPT: Script = preload("res://Aircraft/AircraftDebrisBurst.gd")
const TERRAIN_SAFETY_SAMPLE_DIRECTIONS := [
	Vector2(1.0, 0.0),
	Vector2(-1.0, 0.0),
	Vector2(0.0, 1.0),
	Vector2(0.0, -1.0),
	Vector2(0.70710678, 0.70710678),
	Vector2(-0.70710678, 0.70710678),
	Vector2(0.70710678, -0.70710678),
	Vector2(-0.70710678, -0.70710678),
]

@export_group("Cockpit Pilot")
@export var spawn_cockpit_pilot: bool = true
@export var cockpit_pilot_scene: PackedScene = DEFAULT_COCKPIT_PILOT_SCENE
@export var cockpit_pilot_pose_script: Script = DEFAULT_COCKPIT_PILOT_POSE_SCRIPT
@export var cockpit_pilot_camera_path: NodePath = NodePath("CameraCockpit")
@export var cockpit_pilot_local_offset: Vector3 = Vector3(0.0, -0.65, 0.05)
@export var cockpit_pilot_local_rotation_deg: Vector3 = Vector3(0.0, 180.0, 0.0)
@export var cockpit_pilot_uniform_scale: float = 1.0

##############################################################################
#  SYSTEM SETUP
# ----------------------------------------------------------------------------

var modules = []
var energy_containers = []
var energy_containers_by_type = {}
var available_energy = {
	"fuel": 0.0
}
var energy_budget_frame = {}
var safe_colliders = []

# Shake system
var shake_intensity: float = 0.0
var shake_decay_rate: float = 500.0
var shake_frequency: float = 8.0
var shake_time: float = 0.0

var last_linear_velocity = null
var last_angular_velocity = null
var is_velocity_nonzero = false
const AAM_TARGETING_SCRIPT := preload("res://Weapons/AA_Missile/ControlTargeting_AAM.gd")

# Flight data
var air_velocity = 0.0
var forward_air_speed = 0.0
var local_altitude = 0.0
var local_g_force = 1.0
var local_load_factor = 1.0
var _critical_damage_active: bool = false
var _critical_damage_timer_s: float = 0.0
var _payload_mass_initialized: bool = false
var _base_mass_kg: float = 0.0
var _payload_mass_by_source: Dictionary = {}
var _jam_roll_input: float = 0.0
var _jam_pitch_input: float = 0.0
var _jam_steering_module: Node = null
var _jam_simple_aero: Node = null
var _has_exploded: bool = false
var _terrain_safety_cache_frame: int = -1000000
var _terrain_safety_cache_pos: Vector3 = Vector3.INF
var _terrain_safety_cache_center_ground_y: float = NAN
var _terrain_safety_cache_result: bool = true
var _effective_agl_cache_physics_frame: int = -1
var _effective_agl_cache_value_m: float = NAN

func _ready():
	# Register before the startup-frame await. FloatingOrigin may shift as soon as
	# the active camera is placed on a large map; without this early registration,
	# a freshly-instantiated aircraft can miss the physics transform sync and snap
	# back to its pre-shift position on the following physics tick.
	add_to_group("origin_shifter")
	await get_tree().process_frame
	
	# Force-set health to maximum at startup to override any scene file issues
	_current_health = max_health
	
	# Initialize health system
	current_health = max_health
	
	# Add to aircraft group for easy finding
	add_to_group("aircraft")
	add_to_group("weather_affected")
	add_to_group("team_" + str(team))
	
	# Create world reference (for compatibility)
	var internal_world_reference = get_node_or_null("/root/WorldOrientationReference")
	if not internal_world_reference:
		internal_world_reference = Node3D.new()
		internal_world_reference.name = "WorldOrientationReference"
		get_node("/root/").add_child(internal_world_reference)
	
	connect("body_shape_entered", Callable(self, "_on_Aircraft_body_shape_entered"))
	connect("body_shape_exited", Callable(self, "_on_Aircraft_body_shape_exited"))
	
	# Find all modules
	for child in get_children():
		if (child is AircraftModule) or (child is AircraftModuleSpatial):
			modules.append(child)
			
			if child is AircraftModule_EnergyContainer:
				energy_containers.append(child)
				
				if not child.EnergyType in energy_containers_by_type:
					energy_containers_by_type[child.EnergyType] = []
				energy_containers_by_type[child.EnergyType].append(child)
				
				if not child.EnergyType in available_energy:
					available_energy[child.EnergyType] = 0.0
	
	gravity_scale = 1.0
	linear_damp = 0.0
	angular_damp = 0.0
	continuous_cd = true
	# Ensure we collide with both default (layer 1) and terrain (layer 10)
	var mask: int = get_collision_mask()
	mask |= (1 << 0) | (1 << 9)
	set_collision_mask(mask)

	# Preserve the editor-authored loadout, but still bootstrap support modules
	# that some weapon types depend on to function.
	_ensure_weapon_support_modules()
	_ensure_cockpit_pilot()
	
	setup()
	_cache_control_jam_targets()

	# Apply team livery colors/insignia (player and enemies).
	var livery_node: Node = get_node_or_null("/root/Livery")
	if livery_node != null and livery_node.has_method("apply"):
		livery_node.call("apply", self)

	physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_ON


func apply_origin_shift(_offset: Vector3) -> void:
	# FloatingOrigin sets our node global_position -= offset, but for a RigidBody3D the PHYSICS SERVER
	# holds the authoritative transform. If we don't push the shifted transform into the physics server,
	# the server keeps the pre-shift position and on the next physics step the body snaps back by ~offset
	# -- a multi-km teleport (this was flinging airborne aircraft ~30km on carrier-driven origin shifts).
	# The old code only synced when frozen; airborne (non-frozen) bodies MUST sync too. Velocity is
	# preserved (we only overwrite the transform state).
	var rid := get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)


func _ensure_cockpit_pilot() -> void:
	if not spawn_cockpit_pilot:
		return
	if cockpit_pilot_scene == null:
		return
	if get_node_or_null(str(COCKPIT_PILOT_NODE_NAME)) != null:
		return

	var cockpit_node: Node3D = get_node_or_null(cockpit_pilot_camera_path) as Node3D
	if cockpit_node == null:
		cockpit_node = find_child("CameraCockpit", true, false) as Node3D
	if cockpit_node == null:
		return

	var pilot_node: Node3D = cockpit_pilot_scene.instantiate() as Node3D
	if pilot_node == null:
		return

	pilot_node.name = str(COCKPIT_PILOT_NODE_NAME)
	if cockpit_pilot_pose_script != null:
		pilot_node.set_script(cockpit_pilot_pose_script)
	add_child(pilot_node)

	var uniform_scale: float = maxf(cockpit_pilot_uniform_scale, 0.01)
	var local_rotation_rad: Vector3 = Vector3(
		deg_to_rad(cockpit_pilot_local_rotation_deg.x),
		deg_to_rad(cockpit_pilot_local_rotation_deg.y),
		deg_to_rad(cockpit_pilot_local_rotation_deg.z)
	)
	var local_basis: Basis = Basis.from_euler(local_rotation_rad).scaled(Vector3.ONE * uniform_scale)
	var local_transform: Transform3D = Transform3D(local_basis, cockpit_pilot_local_offset)
	pilot_node.global_transform = cockpit_node.global_transform * local_transform

func _ensure_weapon_support_modules() -> void:
	if _has_weapon_type("AAMissile") and not find_child("ControlTargeting_AAM", true, false):
		var aam_targeting := AAM_TARGETING_SCRIPT.new()
		aam_targeting.name = "ControlTargeting_AAM"
		add_child(aam_targeting)
		modules.append(aam_targeting)

func _has_weapon_type(weapon_name: String) -> bool:
	for child in get_children():
		if child is Hardpoint:
			var hardpoint := child as Hardpoint
			if hardpoint.weapon_instance and hardpoint.weapon_instance.weapon_name == weapon_name:
				return true
		for grandchild in child.get_children():
			if grandchild is Hardpoint:
				var nested_hardpoint := grandchild as Hardpoint
				if nested_hardpoint.weapon_instance and nested_hardpoint.weapon_instance.weapon_name == weapon_name:
					return true
	return false

func setup():
	for module in modules:
		module.setup(self)

func _ensure_payload_mass_tracking() -> void:
	if _payload_mass_initialized:
		return
	_base_mass_kg = mass
	_payload_mass_by_source.clear()
	_payload_mass_initialized = true

func _refresh_payload_mass() -> void:
	var total_payload_mass_kg: float = 0.0
	for payload_mass in _payload_mass_by_source.values():
		total_payload_mass_kg += float(payload_mass)
	mass = _base_mass_kg + total_payload_mass_kg

func set_payload_mass(source: Object, payload_mass_kg: float) -> void:
	if source == null:
		return
	_ensure_payload_mass_tracking()
	var key: int = source.get_instance_id()
	var clamped_mass_kg: float = maxf(payload_mass_kg, 0.0)
	if clamped_mass_kg <= 0.0:
		_payload_mass_by_source.erase(key)
	else:
		_payload_mass_by_source[key] = clamped_mass_kg
	_refresh_payload_mass()

func clear_payload_mass(source: Object) -> void:
	if not _payload_mass_initialized or source == null:
		return
	_payload_mass_by_source.erase(source.get_instance_id())
	_refresh_payload_mass()

func _unhandled_input(event):
	if _critical_damage_active:
		return
	for module in modules:
		if module.ReceiveInput:
			module.receive_input(event)

func _physics_process(delta):
	if freeze:
		var rid := get_rid()
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)

	var _profiler_start: int = FrameProfiler.begin("Aircraft.physics")
	prepare_energy_system()
	apply_shake_forces(delta)
	calculate_flight_data(delta)
	
	# Let modules do their physics
	for module in modules:
		if module.ProcessPhysics:
			module.process_physic_frame(delta)

	if _critical_damage_active:
		_update_critical_damage_state(delta)
		if _has_exploded:
			FrameProfiler.end("Aircraft.physics", _profiler_start)
			return
	
	# Safety: never allow aircraft below terrain height (fallback against streaming holes)
	if prevent_below_terrain:
		_enforce_above_terrain()
	
	# Clean up energy budget and check movement state
	consume_energy_budget()
	check_movement_state()
	
	last_linear_velocity = linear_velocity
	last_angular_velocity = angular_velocity
	FrameProfiler.end("Aircraft.physics", _profiler_start)

func _process(delta):
	var _profiler_start: int = FrameProfiler.begin("Aircraft.process")
	for module in modules:
		if module.ProcessRender:
			module.process_render_frame(delta)
	FrameProfiler.end("Aircraft.process", _profiler_start)

##############################################################################
#  COLLISION HANDLING
# ----------------------------------------------------------------------------

func _on_Aircraft_body_shape_entered(body_rid, body, body_shape_index, local_shape_index):
	# If the colliding body is a projectile, let the projectile's script handle the damage.
	if body is ProjectileNew:
		return
	var collider_shape = shape_owner_get_owner(local_shape_index)
	var impact_force = linear_velocity.length()
	_record_collision_diagnostics(body, impact_force)
	if _is_runway_surface(body):
		if collider_shape in safe_colliders:
			var landing_force = linear_velocity.dot(global_transform.basis.y)
			land(landing_force, impact_force)
		else:
			_evaluate_terrain_impact()
		return
	if _is_carrier_body(body):
		if collider_shape in safe_colliders:
			var landing_force = linear_velocity.dot(global_transform.basis.y)
			land(landing_force, impact_force)
		else:
			_handle_carrier_body_contact(body)
		return
	# Terrain-specific handling
	if _is_ground_or_terrain(body):
		if collider_shape in safe_colliders and _handle_safe_gear_terrain_contact():
			return
		_evaluate_terrain_impact()
		return
	
	if collider_shape in safe_colliders:
		var landing_force = linear_velocity.dot(global_transform.basis.y)
		land(landing_force, impact_force)
	else:
		crash(impact_force)

func _record_collision_diagnostics(body: Node, impact_speed_mps: float) -> void:
	set_meta("last_collision_time_msec", Time.get_ticks_msec())
	set_meta("last_collision_position", global_position)
	set_meta("last_collision_impact_speed_mps", impact_speed_mps)
	if body == null or not is_instance_valid(body):
		set_meta("last_collision_body_name", "unknown")
		set_meta("last_collision_body_path", "")
		return
	set_meta("last_collision_body_name", body.name)
	set_meta("last_collision_body_path", str(body.get_path()) if body.is_inside_tree() else "")
	var ancestry: Array[String] = []
	var cursor: Node = body
	while cursor != null and ancestry.size() < 5:
		ancestry.append(cursor.name)
		cursor = cursor.get_parent()
	set_meta("last_collision_ancestry", "/".join(ancestry))

func _on_Aircraft_body_shape_exited(body_rid, body, body_shape_index, local_shape_index):
	pass

func register_safe_collider(collider: CollisionShape3D):
	if not collider in safe_colliders:
		safe_colliders.append(collider)

func unregister_safe_collider(collider: CollisionShape3D):
	if collider in safe_colliders:
		safe_colliders.erase(collider)

func land(landing_velocity: float, impact_velocity: float):
	if landing_velocity > max_landing_force:
		crash(landing_velocity)

func _handle_carrier_body_contact(body: Node) -> void:
	if _is_managed_by_carrier_deck_ops():
		if debug_damage:
			print("[Aircraft] ignored carrier body contact during deck ops body=", body.name if body != null else "?")
		return
	var carrier_velocity := _get_carrier_contact_velocity(body)
	var relative_speed := (linear_velocity - carrier_velocity).length()
	emit_signal("crashed", relative_speed)
	if relative_speed >= maxf(carrier_body_contact_destroy_speed_mps, 0.0):
		explode()
		return
	var damage_amount := maxf(carrier_body_contact_min_damage, 0.0) \
			+ relative_speed * maxf(carrier_body_contact_damage_per_mps, 0.0)
	if damage_amount > 0.0:
		take_damage(damage_amount)
	if debug_damage:
		print("[Aircraft] carrier body contact body=", body.name if body != null else "?",
				" rel_speed=", snapped(relative_speed, 0.1),
				" damage=", snapped(damage_amount, 0.1))


func _is_managed_by_carrier_deck_ops() -> bool:
	if has_meta("carrier_transport_mode") and bool(get_meta("carrier_transport_mode")):
		return true
	if has_meta("helicopter_deck_takeoff_ready") and bool(get_meta("helicopter_deck_takeoff_ready")):
		return true
	if has_meta("controls_disabled") and bool(get_meta("controls_disabled")):
		var fdm := get_tree().get_first_node_in_group("flight_deck_manager")
		if fdm != null:
			return true
	return false


func _get_carrier_contact_velocity(body: Node) -> Vector3:
	var carrier_node := _find_carrier_ancestor(body)
	if carrier_node != null:
		return VelocityFrame.get_node_velocity(carrier_node)
	return Vector3.ZERO


func _find_carrier_ancestor(body: Node) -> Node:
	var node := body
	while node != null:
		if node.is_in_group("carrier") or node.name.to_lower().find("landcarrier") != -1:
			return node
		node = node.get_parent()
	return null


func _handle_safe_gear_terrain_contact() -> bool:
	var vertical_speed_down: float = -linear_velocity.dot(Vector3.UP)
	var total_speed: float = linear_velocity.length()
	if vertical_speed_down > safe_gear_terrain_hard_vertical_speed:
		explode()
		return true
	if vertical_speed_down <= safe_gear_terrain_land_max_vertical_speed and total_speed <= safe_gear_terrain_land_max_total_speed:
		return true
	var excess_vertical: float = maxf(vertical_speed_down - safe_gear_terrain_land_max_vertical_speed, 0.0)
	var excess_total: float = maxf(total_speed - safe_gear_terrain_land_max_total_speed, 0.0)
	var damage_amount: float = (excess_vertical + excess_total * 0.35) * safe_gear_terrain_damage_per_mps
	if damage_amount > 0.0:
		take_damage(damage_amount)
	return true

func crash(impact_velocity: float):
	emit_signal("crashed", impact_velocity)
	# If we are already under terrain, force destruction instead of ignoring impact.
	# This prevents the aircraft from tunneling through ground and recovering later.
	var is_below_ground: bool = _is_below_terrain()
	if is_below_ground:
		explode()
		return
	# Apply a mild crash damage if speed is high
	if impact_velocity > 10.0:
		var damage_amount = (impact_velocity - 10.0) * 2.0
		take_damage(damage_amount)

func _is_below_terrain() -> bool:
	var ground_y: float = _get_ground_height_at_position(global_position)
	if is_nan(ground_y):
		return false
	if global_position.y >= ground_y - 0.01:
		return false
	return _is_heightmap_ground_stable_for_safety(global_position, ground_y)

func _evaluate_terrain_impact_normal() -> Vector3:
	# Try to get terrain normal beneath aircraft by raycast down
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * ground_probe_up
	var to: Vector3 = global_position - Vector3.UP * ground_probe_down
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self]
	# Use all physics layers so terrain checks work with any Terrain3D layer setup.
	params.collision_mask = 0xFFFFFFFF
	var hit: Dictionary = space_state.intersect_ray(params)
	if hit and hit.has("normal"):
		return (hit.normal as Vector3).normalized()
	return Vector3.UP

func _evaluate_terrain_impact():
	# Determine velocities and alignment
	var total_speed: float = linear_velocity.length()
	var vertical_speed_down: float = -linear_velocity.dot(Vector3.UP)
	var ground_normal: Vector3 = _evaluate_terrain_impact_normal()
	var up_dot: float = ground_normal.dot(Vector3.UP)
	# Ground and aircraft-up normals point the same way for an upright belly
	# contact. Comparing the downward belly normal with the upward ground normal
	# made every upright contact read as 180 degrees misaligned.
	var aircraft_up: Vector3 = global_transform.basis.y
	var align_dot: float = clamp(aircraft_up.normalized().dot(ground_normal), -1.0, 1.0)
	var align_angle_deg: float = rad_to_deg(acos(align_dot))
	
	# Steep slope crash
	if up_dot < steep_slope_min_up_dot and total_speed > 20.0:
		explode()
		return
	# Hard vertical crash
	if vertical_speed_down > hard_crash_vertical_speed:
		explode()
		return
	# Safe belly landing window
	if (vertical_speed_down <= belly_land_max_vertical_speed) and (total_speed <= belly_land_max_total_speed) and (align_angle_deg <= belly_align_tolerance_deg):
		# Considered a belly landing, no damage
		return
	# Otherwise, unsafe terrain contact
	explode()

func _is_runway_surface(body: Node) -> bool:
	return body != null and body.is_in_group("runway_surface")

func _is_carrier_body(body: Node) -> bool:
	return _find_carrier_ancestor(body) != null

func _is_ground_or_terrain(body: Node) -> bool:
	if body.name == "Aircraft" or "aircraft" in body.name.to_lower():
		return false
	if body.get_class() == "Terrain3D" or "terrain3d" in body.name.to_lower():
		return true
	if body.is_in_group("terrain") or body.is_in_group("ground"):
		return true
	if "ground" in body.name.to_lower() or "terrain" in body.name.to_lower():
		return true
	if body is StaticBody3D:
		return true
	return false

func _enforce_above_terrain():
	# FlightDeckManager sets this while the aircraft is moved inside carrier/elevator.
	# During that phase, terrain safety checks would be false positives.
	if has_meta("carrier_transport_mode") and bool(get_meta("carrier_transport_mode")):
		return
	var ground_y: float = _get_ground_height_at_position(global_position)
	if is_nan(ground_y):
		return
	var min_y: float = ground_y + ground_clearance
	if global_position.y < min_y:
		if not _is_heightmap_ground_stable_for_safety(global_position, ground_y):
			return
		# Aircraft penetrated terrain - crash (no more rescuing by snapping back up)
		explode()

func _get_cached_terrain_node() -> Node:
	return TerrainReference.get_terrain_node()

func _get_ground_height_at_position(world_pos: Vector3) -> float:
	# Prefer Terrain3D height API (works even when physics collider misses),
	# then fallback to a raycast.
	var terrain: Node = _get_cached_terrain_node()
	if terrain:
		var terrain_h: float = _get_terrain_height_api(terrain, world_pos)
		if not is_nan(terrain_h):
			return terrain_h

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = world_pos + Vector3.UP * ground_probe_up
	var to: Vector3 = world_pos - Vector3.UP * ground_probe_down
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self]
	params.collision_mask = 0xFFFFFFFF
	var hit: Dictionary = space_state.intersect_ray(params)
	if hit and hit.has("position"):
		return float(hit.position.y)
	return NAN

func _get_terrain_height_api(terrain: Node, world_pos: Vector3) -> float:
	if terrain == null:
		return NAN
	if terrain.has_method("get_height"):
		var h = terrain.get_height(world_pos)
		if (typeof(h) == TYPE_FLOAT or typeof(h) == TYPE_INT) and not is_nan(float(h)):
			return float(h)
	if "data" in terrain and terrain.data and terrain.data.has_method("get_height"):
		var h2 = terrain.data.get_height(world_pos)
		if (typeof(h2) == TYPE_FLOAT or typeof(h2) == TYPE_INT) and not is_nan(float(h2)):
			return float(h2)
	return NAN

func _is_heightmap_ground_stable_for_safety(world_pos: Vector3, center_ground_y: float) -> bool:
	var radius: float = maxf(terrain_safety_cliff_guard_radius_m, 0.0)
	if radius <= 0.0:
		return true
	var terrain: Node = _get_cached_terrain_node()
	if terrain == null:
		return true
	var frame: int = Engine.get_physics_frames()
	var cache_frames: int = maxi(terrain_safety_cliff_guard_cache_frames, 0)
	var cache_dist_sq: float = terrain_safety_cliff_guard_cache_distance_m * terrain_safety_cliff_guard_cache_distance_m
	if frame - _terrain_safety_cache_frame <= cache_frames:
		var dx: float = world_pos.x - _terrain_safety_cache_pos.x
		var dz: float = world_pos.z - _terrain_safety_cache_pos.z
		if dx * dx + dz * dz <= cache_dist_sq and absf(center_ground_y - _terrain_safety_cache_center_ground_y) <= terrain_safety_max_height_variation_m:
			return _terrain_safety_cache_result
	if TerrainNavGrid.has_query_grid():
		var result_from_query: bool = TerrainNavGrid.is_heightmap_safe_for_aircraft(
			world_pos.x,
			world_pos.z,
			terrain_safety_max_height_variation_m
		)
		_terrain_safety_cache_frame = frame
		_terrain_safety_cache_pos = world_pos
		_terrain_safety_cache_center_ground_y = center_ground_y
		_terrain_safety_cache_result = result_from_query
		return result_from_query
	var min_h: float = center_ground_y
	var max_h: float = center_ground_y
	var result: bool = true
	for dir in TERRAIN_SAFETY_SAMPLE_DIRECTIONS:
		var sample_pos := Vector3(
			world_pos.x + dir.x * radius,
			world_pos.y,
			world_pos.z + dir.y * radius
		)
		var sample_h: float = _get_terrain_height_api(terrain, sample_pos)
		if is_nan(sample_h):
			result = false
			break
		min_h = minf(min_h, sample_h)
		max_h = maxf(max_h, sample_h)
		if max_h - min_h > terrain_safety_max_height_variation_m:
			result = false
			break
	_terrain_safety_cache_frame = frame
	_terrain_safety_cache_pos = world_pos
	_terrain_safety_cache_center_ground_y = center_ground_y
	_terrain_safety_cache_result = result
	return result

func _get_carrier_reference_ground_y() -> float:
	var carrier: Node3D = get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		return NAN
	var local_pos: Vector3 = carrier.to_local(global_position)
	if absf(local_pos.x) > carrier_deck_extent_x_m:
		return NAN
	if absf(local_pos.z) > carrier_deck_extent_z_m:
		return NAN
	var fdm: Node = get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm == null or not fdm.has_method("get_deck_height"):
		return NAN
	var deck_y: float = float(fdm.get_deck_height())
	if absf(global_position.y - deck_y) > carrier_deck_altitude_zone_margin_y_m:
		return NAN
	return deck_y - carrier_deck_reference_altitude_m

func get_effective_altitude_agl_m() -> float:
	var physics_frame: int = Engine.get_physics_frames()
	if _effective_agl_cache_physics_frame == physics_frame:
		return _effective_agl_cache_value_m
	var ground_y: float = _get_ground_height_at_position(global_position)
	var carrier_ground_y: float = _get_carrier_reference_ground_y()
	var reference_ground_y: float = ground_y
	if not is_nan(carrier_ground_y):
		if is_nan(reference_ground_y):
			reference_ground_y = carrier_ground_y
		else:
			reference_ground_y = minf(reference_ground_y, carrier_ground_y)
	if is_nan(reference_ground_y):
		_effective_agl_cache_value_m = maxf(global_position.y - sea_level_from_origin, 0.0)
	else:
		_effective_agl_cache_value_m = maxf(global_position.y - reference_ground_y, 0.0)
	_effective_agl_cache_physics_frame = physics_frame
	return _effective_agl_cache_value_m

func get_effective_altitude_reference_y() -> float:
	var ground_y: float = _get_ground_height_at_position(global_position)
	var carrier_ground_y: float = _get_carrier_reference_ground_y()
	if not is_nan(carrier_ground_y):
		if is_nan(ground_y):
			return carrier_ground_y
		return minf(ground_y, carrier_ground_y)
	if not is_nan(ground_y):
		return ground_y
	return sea_level_from_origin

##############################################################################
#  ENERGY SYSTEM
# ----------------------------------------------------------------------------

func prepare_energy_system():
	# Calculate available energy from all containers
	var energy_levels = {}
	for energy_cont in energy_containers:
		if energy_cont.ContainerActive:
			if not energy_cont.EnergyType in energy_levels:
				energy_levels[energy_cont.EnergyType] = energy_cont.current_level
			else:
				energy_levels[energy_cont.EnergyType] += energy_cont.current_level
	available_energy = energy_levels
	
	# Reset energy budget for this frame
	for energy_type in available_energy:
		energy_budget_frame[energy_type] = 0.0

func request_energy(energy_type: String, amount: float) -> bool:
	if (not energy_type in energy_budget_frame) or (not energy_type in available_energy):
		return false
	
	var new_budget = energy_budget_frame[energy_type] + amount
	if (available_energy[energy_type] < new_budget):
		return false
	else:
		energy_budget_frame[energy_type] = new_budget
		return true

func consume_energy_budget():
	for energy_type in energy_budget_frame:
		var this_budget = energy_budget_frame[energy_type]
		if this_budget > 0:
			var energy_conts = energy_containers_by_type[energy_type]
			for this_container in energy_conts:
				if this_container.ContainerActive:
					var this_ratio = this_container.current_level / available_energy[energy_type]
					this_container.consume_energy(this_budget * this_ratio)

func load_energy(energy_type: String, value: float) -> bool:
	if not energy_type in energy_containers_by_type:
		return false
	
	var selected_energy_containers = energy_containers_by_type[energy_type]
	var number_of_containers = 0
	for this_container in selected_energy_containers:
		if this_container.ContainerActive:
			number_of_containers += 1
	
	if number_of_containers == 0:
		return true
	
	var amount_per_container = value / number_of_containers
	var is_at_least_one_container_not_full = false
	for this_container in selected_energy_containers:
		if this_container.ContainerActive:
			if not this_container.load_energy(amount_per_container):
				is_at_least_one_container_not_full = true
	return (not is_at_least_one_container_not_full)

##############################################################################
#  SHAKE SYSTEM
# ----------------------------------------------------------------------------

func add_shake(intensity: float, duration: float = 0.0):
	shake_intensity = max(shake_intensity, intensity) 
	if duration > 0:
		shake_time = duration

func apply_shake_forces(delta):
	if shake_intensity <= 0:
		return
	
	#print("Shake intensity: ", shake_intensity, " Decay rate: ", shake_decay_rate)
	# Decay shake over time
		
	# Always decay shake, regardless of shake_time
	shake_intensity -= shake_decay_rate * delta
	shake_intensity = max(shake_intensity, 0.0)
	
	# Generate random shake forces
	var shake_force = Vector3(
		sin(Time.get_ticks_msec() * 0.001 * shake_frequency + 0.0) * shake_intensity,
		sin(Time.get_ticks_msec() * 0.001 * shake_frequency + 1.5) * shake_intensity,
		sin(Time.get_ticks_msec() * 0.001 * shake_frequency + 3.0) * shake_intensity
	) * mass
	
	# Apply random torque for rotational shake
	var shake_torque = Vector3(
		sin(Time.get_ticks_msec() * 0.001 * shake_frequency + 4.5) * shake_intensity,
		sin(Time.get_ticks_msec() * 0.001 * shake_frequency + 6.0) * shake_intensity,
		sin(Time.get_ticks_msec() * 0.001 * shake_frequency + 7.5) * shake_intensity
	) * mass * 0.1
	
	apply_central_force(shake_force)
	apply_torque(shake_torque)

##############################################################################
#  FLIGHT DATA CALCULATIONS
# ----------------------------------------------------------------------------

func calculate_flight_data(delta):
	# Calculate speed
	air_velocity = linear_velocity.length()
	forward_air_speed = linear_velocity.dot(global_transform.basis.z)  # Speed in forward direction
	
	# Calculate altitude
	if altitude_enabled:
		local_altitude = get_effective_altitude_agl_m()
	else:
		local_altitude = 0.0
	
	# Calculate G-forces
	if last_linear_velocity != null:
		var up_vector = global_transform.basis.y
		var linear_acceleration = (linear_velocity - last_linear_velocity) / delta
		var vertical_acceleration_normalized = (up_vector.dot(linear_acceleration) / EARTH_GRAVITY) * g_force_factor
		
		local_load_factor = (1.0 + vertical_acceleration_normalized/gravity_factor) if gravity_factor > 0 else 0.0
		local_g_force = (gravity_factor + vertical_acceleration_normalized) if gravity_factor > 0 else 0.0

##############################################################################
#  MOVEMENT STATE TRACKING
# ----------------------------------------------------------------------------

func check_movement_state():
	var air_velocity = linear_velocity.length()
	var is_moving_now = (air_velocity > 0.005)
	
	# Check for state changes
	if (is_velocity_nonzero) and (not is_moving_now):
		# Just stopped
		emit_signal("parked")
	elif (not is_velocity_nonzero) and (is_moving_now):
		# Just started moving
		emit_signal("moved")
	
	is_velocity_nonzero = is_moving_now

##############################################################################
#  DAMAGE SYSTEM
# ----------------------------------------------------------------------------

func take_damage(damage_amount: float):
	if current_health <= 0 or _critical_damage_active or _has_exploded:
		return  # Already destroyed
	# Simple damage cooldown to prevent multiple applications from a single collision frame
	var now_ms: int = Time.get_ticks_msec()
	var time_since_last = now_ms - _last_damage_ms
	if time_since_last < int(damage_cooldown_s * 1000.0):
		if debug_damage:
			print("[Aircraft] Damage BLOCKED by cooldown - ", time_since_last, "ms since last (need ", int(damage_cooldown_s * 1000.0), "ms)")
		return
	_last_damage_ms = now_ms
	
	# Apply damage
	current_health -= damage_amount
	current_health = max(current_health, 0.0)
	if debug_damage:
		print("[Aircraft] take_damage=", damage_amount, " -> health=", current_health, "/", max_health)
	
	# emit_signal("damaged", damage_amount, current_health)  # Now handled by setter
	
	if current_health <= 0:
		_begin_critical_damage_sequence()

func explode():
	if _has_exploded:
		return
	_has_exploded = true
	_critical_damage_active = false
	emit_signal("destroyed")
	_spawn_destruction_explosion()
	_spawn_critical_damage_chunks()
	if legacy_exploded_model_breakup_enabled:
		_spawn_exploded_model()

	# Cleanly detach from deck systems
	if has_meta("arresting_cable"):
		var cable = get_meta("arresting_cable")
		if is_instance_valid(cable) and cable.has_method("manual_release"):
			cable.manual_release()

	queue_free()

func _spawn_destruction_explosion() -> void:
	var exp_scene: PackedScene = explosion_scene
	if exp_scene == null:
		exp_scene = load("res://Projectiles/Explosion/explosion.tscn")
	if exp_scene == null:
		return
	var scene_root: Node = get_tree().current_scene if get_tree() != null else null
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		return
	var exp := exp_scene.instantiate()
	scene_root.add_child(exp)
	if exp is Node3D:
		(exp as Node3D).global_position = global_position
	var blast_radius_value: Variant = exp.get("blast_radius")
	if blast_radius_value != null:
		exp.set("blast_radius", maxf(float(blast_radius_value), 30.0))
	var max_damage_value: Variant = exp.get("max_damage")
	if max_damage_value != null:
		exp.set("max_damage", maxf(float(max_damage_value), 140.0))
	var min_damage_value: Variant = exp.get("min_damage")
	if min_damage_value != null:
		exp.set("min_damage", maxf(float(min_damage_value), 20.0))
	var los_value: Variant = exp.get("use_line_of_sight")
	if los_value != null:
		exp.set("use_line_of_sight", false)

func _begin_critical_damage_sequence() -> void:
	if _critical_damage_active or _has_exploded:
		return
	_critical_damage_active = true
	_critical_damage_timer_s = 0.0
	_jam_roll_input = 1.0 if randf() >= 0.5 else -1.0
	_jam_pitch_input = 1.0 if randf() >= 0.5 else -1.0
	set_meta("player_control_locked", true)
	if has_meta("controls_disabled"):
		remove_meta("controls_disabled")
	_disable_ai_for_critical_damage()
	_disable_player_control_for_critical_damage()
	_disable_non_jam_control_modules()

func _disable_ai_for_critical_damage() -> void:
	var ai_toggle := get_node_or_null("AIToggle")
	if ai_toggle != null and "ai_active" in ai_toggle:
		ai_toggle.ai_active = false

	var ai_pilot := find_child("AIPilot", true, false)
	if ai_pilot == null:
		return
	if ai_pilot.has_method("deinitialize"):
		ai_pilot.deinitialize()
	ai_pilot.set_process(false)
	ai_pilot.set_physics_process(false)
	ai_pilot.set_process_input(false)

func _disable_player_control_for_critical_damage() -> void:
	if FlightDirector and FlightDirector.has_method("force_release_player_control_for"):
		FlightDirector.force_release_player_control_for(self)

func _update_critical_damage_state(delta: float) -> void:
	_apply_jammed_controls()
	_critical_damage_timer_s += delta
	if _critical_damage_timer_s >= 1.0:
		_critical_damage_timer_s -= 1.0
		current_health -= randf_range(bleed_damage_min_per_s, bleed_damage_max_per_s)
		if current_health <= explosion_health_threshold:
			explode()

func _apply_jammed_controls() -> void:
	_cache_control_jam_targets()
	if _jam_steering_module and _jam_steering_module.has_method("set_z"):
		_jam_steering_module.call("set_z", _jam_roll_input)
	if _jam_steering_module and _jam_steering_module.has_method("set_x"):
		_jam_steering_module.call("set_x", _jam_pitch_input)
	if _jam_steering_module and _jam_steering_module.has_method("set_y"):
		_jam_steering_module.call("set_y", 0.0)
	if _jam_simple_aero:
		_jam_simple_aero.roll_input = -_jam_roll_input
		_jam_simple_aero.pitch_input = _jam_pitch_input
		_jam_simple_aero.yaw_input = 0.0

func _cache_control_jam_targets() -> void:
	if _jam_steering_module == null:
		var steering_modules: Array = find_modules_by_type("steering")
		if not steering_modules.is_empty():
			_jam_steering_module = steering_modules[0] as Node
	if _jam_simple_aero == null:
		_jam_simple_aero = get_node_or_null("SimpleAero")
		if _jam_simple_aero == null:
			_jam_simple_aero = find_child("SimpleAero", true, false)

func _disable_non_jam_control_modules() -> void:
	var blocked_scripts: Array[String] = [
		"controlsteering.gd",
		"controlengine.gd",
		"controlenergycontainer.gd",
		"controllandinggear.gd",
		"controlflaps.gd",
		"controlweapons.gd",
		"controltargeting.gd",
		"controltargeting_aam.gd",
	]
	for script_name in blocked_scripts:
		var nodes: Array[Node] = _find_nodes_by_script_suffix(self, script_name)
		for node in nodes:
			node.set_process_input(false)
			node.set_process(false)
			node.set_physics_process(false)

func _find_nodes_by_script_suffix(root: Node, script_suffix: String) -> Array[Node]:
	var found_nodes: Array[Node] = []
	for child in root.get_children():
		var script_obj: Script = child.get_script()
		if script_obj != null and script_obj.resource_path.to_lower().ends_with(script_suffix):
			found_nodes.append(child)
		found_nodes.append_array(_find_nodes_by_script_suffix(child, script_suffix))
	return found_nodes

func _spawn_critical_damage_chunks() -> void:
	var parent_node: Node = get_parent()
	if not is_instance_valid(parent_node):
		return
	var min_count: int = maxi(1, critical_debris_chunk_min_count)
	var max_count: int = maxi(min_count, critical_debris_chunk_max_count)
	var chunk_count: int = randi_range(min_count, max_count)
	var min_size: float = maxf(critical_debris_chunk_min_size_m, 0.05)
	var max_size: float = maxf(min_size, critical_debris_chunk_max_size_m)
	var min_impulse: float = maxf(critical_debris_chunk_impulse_min_mps, 0.0)
	var max_impulse: float = maxf(min_impulse, critical_debris_chunk_impulse_max_mps)
	AIRCRAFT_DEBRIS_BURST_SCRIPT.call("spawn",
		parent_node,
		global_transform,
		linear_velocity,
		chunk_count,
		min_size,
		max_size,
		min_impulse,
		max_impulse,
		staged_critical_debris_enabled,
		critical_debris_spread_duration_s
	)

func activate_deathcam():
	# Prefer independent deathcam scene
	if deathcam_scene:
		var dc = deathcam_scene.instantiate()
		get_tree().current_scene.add_child(dc)
		if dc.has_method("set_target_position"):
			dc.set_target_position(global_position)
		return
	# Fallback to any camera controller
	var camera_controller = find_child("CameraController")
	if not camera_controller:
		camera_controller = get_tree().get_first_node_in_group("camera_controller")
	if camera_controller and camera_controller.has_method("activate_deathcam"):
		camera_controller.activate_deathcam(global_position)
	
	# Make aircraft non-interactive but don't remove it yet
	set_collision_layer(0)
	set_collision_mask(0)
	freeze = true

func _spawn_wreck_and_free():
	# Guard: need wreck scene assigned
	if not wreck_scene:
		queue_free()
		return

	var effective_agl_m: float = get_effective_altitude_agl_m()
	if wreck_spawn_max_agl_m >= 0.0 and effective_agl_m > wreck_spawn_max_agl_m:
		queue_free()
		return
	
	var parent := get_parent()
	if not is_instance_valid(parent):
		queue_free()
		return
	
	# Instance wreck and place where aircraft was
	var wreck_root: Node3D = wreck_scene.instantiate()
	parent.add_child(wreck_root)
	wreck_root.global_transform = global_transform

	# Cache aircraft velocities
	var aircraft_linear: Vector3 = linear_velocity
	var aircraft_angular: Vector3 = angular_velocity
	var explosion_center: Vector3 = global_transform.origin

	# Scatter settings
	var base_impulse: float = wreck_base_impulse
	var random_spread: float = wreck_random_spread
	var extra_spin: float = wreck_extra_spin

	# Copy velocities and apply impulses to rigid pieces
	for piece in wreck_root.get_children():
		if piece is RigidBody3D:
			var rb := piece as RigidBody3D
			rb.sleeping = false
			rb.linear_velocity = aircraft_linear
			rb.angular_velocity = aircraft_angular
			var to_piece: Vector3 = rb.global_transform.origin - explosion_center
			var dir: Vector3 = to_piece.normalized()
			if dir == Vector3.ZERO:
				dir = Vector3.FORWARD
			var rnd: float = 1.0 + randf_range(-random_spread, random_spread)
			rb.apply_central_impulse(dir * base_impulse * rnd)
			var torque_axis: Vector3 = Vector3(
				randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)
			).normalized()
			rb.apply_torque_impulse(torque_axis * extra_spin)

	# Cleanly detach from deck systems
	if has_meta("arresting_cable"):
		var cable = get_meta("arresting_cable")
		if is_instance_valid(cable) and cable.has_method("manual_release"):
			cable.manual_release()

	# Remove original aircraft
	queue_free()

func _spawn_exploded_model() -> void:
	if exploded_model_scene == null:
		return
	var parent: Node = get_parent()
	if not is_instance_valid(parent):
		return
	var root: Node3D = exploded_model_scene.instantiate() as Node3D
	if root == null:
		return
	# Add to scene so children have valid global transforms
	parent.add_child(root)
	root.global_transform = global_transform

	var aircraft_vel: Vector3 = linear_velocity
	var aircraft_ang: Vector3 = angular_velocity
	var aircraft_origin: Vector3 = global_position

	# Collect materials from the living aircraft before it's freed
	var mats: Array[Material] = _collect_mesh_materials()

	var parts: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D:
			parts.append(child as MeshInstance3D)

	var part_mass: float = maxf(mass / maxf(parts.size(), 1), 5.0)

	for mesh_inst in parts:
		var world_xform: Transform3D = mesh_inst.global_transform
		var aabb: AABB = mesh_inst.get_aabb()

		root.remove_child(mesh_inst)

		var rb := RigidBody3D.new()
		rb.mass = part_mass
		rb.collision_layer = 0
		rb.collision_mask = 513  # Layer 1 (default) + layer 10 (terrain)
		var phys_mat := PhysicsMaterial.new()
		phys_mat.bounce = 0.6
		phys_mat.friction = 0.3
		rb.physics_material_override = phys_mat

		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size.abs()
		col.shape = box
		rb.add_child(col)

		mesh_inst.transform = Transform3D.IDENTITY
		if not mats.is_empty():
			mesh_inst.material_override = mats[randi() % mats.size()]
		rb.add_child(mesh_inst)

		parent.add_child(rb)
		rb.global_transform = world_xform

		# Scatter outward from aircraft center
		var outward: Vector3 = (world_xform.origin - aircraft_origin).normalized()
		if outward.length_squared() < 0.001:
			outward = Vector3(randf_range(-1.0, 1.0), 1.0, randf_range(-1.0, 1.0)).normalized()
		outward.y += 0.3
		outward = outward.normalized()

		rb.linear_velocity = aircraft_vel + outward * randf_range(5.0, 25.0)
		rb.angular_velocity = aircraft_ang + Vector3(
			randf_range(-8.0, 8.0),
			randf_range(-8.0, 8.0),
			randf_range(-8.0, 8.0)
		)

		var fire_trail := FireTrail.new()
		fire_trail.duration = randf_range(5.0, 9.0)
		rb.add_child(fire_trail)

		var t := get_tree().create_timer(12.0)
		t.timeout.connect(func(): if is_instance_valid(rb): rb.queue_free())

	root.queue_free()


func _collect_mesh_materials() -> Array[Material]:
	var result: Array[Material] = []
	_collect_materials_from_node(self, result)
	return result


func _collect_materials_from_node(node: Node, result: Array[Material]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		# material_override is what Livery applies — prefer it
		if mi.material_override != null and not result.has(mi.material_override):
			result.append(mi.material_override)
		else:
			for i in range(mi.get_surface_override_material_count()):
				var mat := mi.get_surface_override_material(i)
				if mat != null and not result.has(mat):
					result.append(mat)
			if mi.mesh != null:
				for i in range(mi.mesh.get_surface_count()):
					var mat := mi.mesh.surface_get_material(i)
					if mat != null and not result.has(mat):
						result.append(mat)
	for child in node.get_children():
		_collect_materials_from_node(child, result)

##############################################################################
#  UTILITY FUNCTIONS
# ----------------------------------------------------------------------------

func find_modules_by_type(module_type: String) -> Array:
	var result = []
	for module in modules:
		if module.ModuleType == module_type:
			result.append(module)
	return result

func find_modules_by_tag(module_tag: String) -> Array:
	var result = []
	for module in modules:
		if module_tag in module.ModuleTags:
			result.append(module)
	return result

func get_team() -> int:
	return team

##############################################################################
#  CCIP (CONTINUOUSLY COMPUTED IMPACT POINT) SYSTEM
# ----------------------------------------------------------------------------

func calculate_ccip_impact_point() -> Dictionary:
	"""Calculate where a bomb would hit if dropped right now"""
	var result = {
		"has_impact": false,
		"impact_position": Vector3.ZERO,
		"time_to_impact": 0.0
	}
	
	# Get bomb hardpoints (first one with bombs)
	var bomb_hardpoint = null
	var bomb_projectile_scene = null
	var control_weapons = find_child("ControlWeapons")
	if control_weapons and control_weapons.hardpoints:
		for hardpoint in control_weapons.hardpoints:
			if not is_instance_valid(hardpoint):
				continue
			if (hardpoint.weapon_instance and 
				hardpoint.weapon_instance.weapon_name == "Bomb"):
				bomb_hardpoint = hardpoint
				if "bomb_projectile_scene" in hardpoint.weapon_instance:
					bomb_projectile_scene = hardpoint.weapon_instance.bomb_projectile_scene
				break
	
	if not bomb_hardpoint or not bomb_projectile_scene:
		return result
		
	# Get bomb drop parameters from the weapon
	var drop_force: float = 0.0
	if "drop_force" in bomb_hardpoint.weapon_instance:
		drop_force = float(bomb_hardpoint.weapon_instance.drop_force)

	# Match the real bomb weapon scripts: release inherits aircraft linear velocity
	# plus any explicit downward drop force, with no extra angular-velocity term.
	var release_transform: Transform3D = bomb_hardpoint.global_transform
	if bomb_hardpoint.weapon_instance.has_method("get_predicted_release_transform"):
		release_transform = bomb_hardpoint.weapon_instance.get_predicted_release_transform()
	var start_pos: Vector3 = release_transform.origin

	var initial_velocity: Vector3 = Vector3.DOWN * drop_force + linear_velocity
	if bomb_hardpoint.weapon_instance.has_method("get_predicted_initial_velocity"):
		initial_velocity = bomb_hardpoint.weapon_instance.get_predicted_initial_velocity(self)
	
	# Get bomb physics properties dynamically from the projectile scene
	var bomb_instance = bomb_projectile_scene.instantiate()
	var linear_damp := 0.0
	if "linear_damp" in bomb_instance:
		linear_damp = float(bomb_instance.linear_damp)
		# In Godot, -1 means inherit from project default; resolve it to the actual value
		if linear_damp < 0.0:
			linear_damp = float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.0))
	var gravity_scale := 1.0
	if "gravity_scale" in bomb_instance:
		gravity_scale = float(bomb_instance.gravity_scale)
	bomb_instance.queue_free() # Clean up the temporary instance
	
	# Get world gravity as a vector (direction * magnitude)
	var gravity_dir: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3(0, -1, 0))
	var gravity_mag: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var gravity_vec: Vector3 = gravity_dir * gravity_mag
	
	# Ballistic trajectory calculation with drag and proper terrain detection
	var time_step = 0.02  # Smaller timestep for better accuracy with fast motion/turning
	var max_time = 30.0  # Maximum 30 seconds trajectory
	var current_pos = start_pos
	var current_vel = initial_velocity
	
	# Raycast to terrain for each time step
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	
	for step in int(max_time / time_step):
		# Apply physics before moving
		# Apply gravity (vector-based) with gravity scale
		current_vel += gravity_vec * gravity_scale * time_step
		
		# Apply linear damping to match Godot: v /= (1 + damp * dt)
		if linear_damp > 0.0:
			current_vel /= (1.0 + linear_damp * time_step)
		
		# Calculate next position
		var next_pos = current_pos + current_vel * time_step
		
		# Check for terrain collision along the path
		var query = PhysicsRayQueryParameters3D.create(current_pos, next_pos)
		query.exclude = [self]  # Don't hit the aircraft
		
		# Use all physics layers so predicted impact works with any Terrain3D layer setup.
		query.collision_mask = 0xFFFFFFFF
		
		var hit_result = space_state.intersect_ray(query)
		if hit_result:
			# Found terrain collision
			result.has_impact = true
			result.impact_position = hit_result.position
			result.time_to_impact = step * time_step
			break
		
		# Also check if we've gone below a reasonable ground level (fallback)
		if next_pos.y < -1000:  # Assume no terrain goes below -1000m
			result.has_impact = false
			break
		
		current_pos = next_pos

	return result


func calculate_rocket_ccip_impact_point(target_pos: Vector3 = Vector3.INF, intended_target: Node = null) -> Dictionary:
	"""Calculate where a rocket would hit if fired right now"""
	var result = {
		"has_impact": false,
		"impact_position": Vector3.ZERO,
		"time_to_impact": 0.0,
		"hit_body": null,
		"hit_normal": Vector3.ZERO,
		"blocked": false,
		"blocked_reason": "",
		"target_miss_m": INF,
		"target_edge_miss_m": INF,
		"hit_intended_target": false,
		"effective_damage_radius_m": 0.0,
	}

	# Find the first active rocket hardpoint
	var rocket_hardpoint = null
	var rocket_scene = null
	var control_weapons = find_child("ControlWeapons")
	if control_weapons and control_weapons.hardpoints:
		for hardpoint in control_weapons.hardpoints:
			if not is_instance_valid(hardpoint):
				continue
			if hardpoint.weapon_instance and hardpoint.weapon_instance.weapon_name == "Rocket Pod":
				rocket_hardpoint = hardpoint
				if "rocket_scene" in hardpoint.weapon_instance:
					rocket_scene = hardpoint.weapon_instance.rocket_scene
				break

	if not rocket_hardpoint:
		return result

	if rocket_scene == null:
		rocket_scene = load("res://Projectiles/Rocket/rocket.tscn")
	if rocket_scene == null:
		return result

	var muzzle_velocity: float = 220.0
	if "muzzle_velocity" in rocket_hardpoint.weapon_instance:
		muzzle_velocity = float(rocket_hardpoint.weapon_instance.muzzle_velocity)

	var release_transform: Transform3D = rocket_hardpoint.global_transform
	if rocket_hardpoint.weapon_instance.has_method("get_predicted_release_transform"):
		release_transform = rocket_hardpoint.weapon_instance.get_predicted_release_transform()
	var start_pos: Vector3 = release_transform.origin

	var initial_velocity: Vector3 = release_transform.basis.z * muzzle_velocity
	if rocket_hardpoint.weapon_instance.has_method("get_predicted_initial_velocity"):
		initial_velocity = rocket_hardpoint.weapon_instance.get_predicted_initial_velocity(self)

	# Read physics from rocket scene
	var rocket_instance: Node = rocket_scene.instantiate()
	# Read the rocket's drag from its EXPORTED value, not the built-in linear_damp -- the latter is
	# only assigned in the rocket's _ready() (which hasn't run on this un-parented instance), so it
	# reads 0.0 here and the CCIP predicted a drag-free rocket that over-flew the target by ~400m.
	var linear_damp: float = 0.06
	if "rocket_linear_damp" in rocket_instance:
		var ld: float = float(rocket_instance.rocket_linear_damp)
		if ld >= 0.0:
			linear_damp = ld
	elif "linear_damp" in rocket_instance:
		var ld_builtin: float = float(rocket_instance.linear_damp)
		if ld_builtin > 0.0:
			linear_damp = ld_builtin
	var gravity_scale: float = 1.0
	if "gravity_scale" in rocket_instance:
		gravity_scale = float(rocket_instance.gravity_scale)
	var motor_acceleration_mps2: float = 0.0
	if "motor_acceleration_mps2" in rocket_instance:
		motor_acceleration_mps2 = float(rocket_instance.motor_acceleration_mps2)
	var motor_additional_speed_mps: float = 0.0
	if "motor_additional_speed_mps" in rocket_instance:
		motor_additional_speed_mps = float(rocket_instance.motor_additional_speed_mps)
	if "explosion_blast_radius" in rocket_instance:
		result.effective_damage_radius_m = maxf(float(rocket_instance.explosion_blast_radius), 0.0)
	var max_time: float = 15.0
	if "lifetime" in rocket_instance:
		max_time = maxf(float(rocket_instance.lifetime), 0.05)
	rocket_instance.queue_free()

	var gravity_dir: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3(0, -1, 0))
	var gravity_mag: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var gravity_vec: Vector3 = gravity_dir * gravity_mag

	var time_step: float = 0.02
	var current_pos: Vector3 = start_pos
	var current_vel: Vector3 = initial_velocity
	var launch_reference_speed_mps: float = initial_velocity.length()
	var space_state = get_world_3d().direct_space_state

	for step in int(max_time / time_step):
		var target_speed_mps: float = launch_reference_speed_mps + maxf(motor_additional_speed_mps, 0.0)
		var current_speed_mps: float = current_vel.length()
		if motor_acceleration_mps2 > 0.0 and current_speed_mps < target_speed_mps:
			var forward_dir: Vector3 = current_vel.normalized()
			if forward_dir.length_squared() < 0.001:
				forward_dir = release_transform.basis.z.normalized()
			if forward_dir.length_squared() < 0.001:
				forward_dir = Vector3.FORWARD
			current_vel += forward_dir * minf(motor_acceleration_mps2 * time_step, target_speed_mps - current_speed_mps)

		current_vel += gravity_vec * gravity_scale * time_step
		if linear_damp > 0.0:
			current_vel /= (1.0 + linear_damp * time_step)
		var next_pos: Vector3 = current_pos + current_vel * time_step

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(current_pos, next_pos)
		query.exclude = [self]
		query.collision_mask = 0xFFFFFFFF
		var hit_result: Dictionary = space_state.intersect_ray(query)
		if hit_result:
			result.has_impact = true
			result.impact_position = hit_result.position
			result.time_to_impact = step * time_step
			result.hit_body = hit_result.get("collider", null)
			result.hit_normal = hit_result.get("normal", Vector3.ZERO)
			_classify_rocket_ccip_impact(result, start_pos, target_pos, intended_target)
			break

		var terrain_h: float = _get_ground_height_at_position(next_pos)
		if not is_nan(terrain_h):
			var prev_h: float = _get_ground_height_at_position(current_pos)
			var prev_above: bool = is_nan(prev_h) or current_pos.y >= prev_h
			var curr_above: bool = next_pos.y >= terrain_h
			if prev_above and not curr_above:
				var denom: float = maxf((current_pos.y - prev_h) - (next_pos.y - terrain_h), 0.001) if not is_nan(prev_h) else 1.0
				var t: float = clampf((current_pos.y - prev_h) / denom, 0.0, 1.0) if not is_nan(prev_h) else 1.0
				var impact_pos: Vector3 = current_pos.lerp(next_pos, t)
				impact_pos.y = terrain_h
				result.has_impact = true
				result.impact_position = impact_pos
				result.time_to_impact = step * time_step
				result.hit_body = _get_cached_terrain_node()
				result.hit_normal = _sample_terrain_normal_for_ccip(impact_pos)
				_classify_rocket_ccip_impact(result, start_pos, target_pos, intended_target)
				break

		if next_pos.y < -1000:
			break

		current_pos = next_pos

	return result


func calculate_gun_ccip_impact_point(target_pos: Vector3 = Vector3.INF, intended_target: Node = null) -> Dictionary:
	"""Calculate where the selected gun stream would hit if fired right now."""
	var result := {
		"has_impact": false,
		"impact_position": Vector3.ZERO,
		"time_to_impact": 0.0,
		"hit_body": null,
		"hit_normal": Vector3.ZERO,
		"blocked": false,
		"blocked_reason": "",
		"target_miss_m": INF,
	}

	var gun_info: Dictionary = _get_selected_gun_ccip_source()
	if gun_info.is_empty():
		return result

	var source_node: Node3D = gun_info.get("source_node", null) as Node3D
	if source_node == null or not is_instance_valid(source_node):
		return result
	var weapon_node: Node = gun_info.get("weapon_node", null) as Node
	if weapon_node == null or not is_instance_valid(weapon_node):
		return result

	var muzzle_velocity: float = maxf(float(gun_info.get("muzzle_velocity", 500.0)), 50.0)
	var projectile_speed: float = _get_effective_ccip_projectile_speed(muzzle_velocity)
	var projectile_speed_cap_mps: float = _get_ccip_projectile_speed_cap_mps()
	var max_range_m: float = maxf(float(gun_info.get("max_range_m", 900.0)), 10.0)
	var max_time: float = maxf(max_range_m / maxf(projectile_speed, 1.0), 0.05)
	var projectile_scene: PackedScene = gun_info.get("projectile_scene", null) as PackedScene

	var gravity_scale: float = 1.0
	var linear_damp: float = 0.0
	if projectile_scene != null:
		var projectile_instance: Node = projectile_scene.instantiate()
		if "gravity_scale" in projectile_instance:
			gravity_scale = float(projectile_instance.gravity_scale)
		if "linear_damp" in projectile_instance:
			var projectile_linear_damp: float = float(projectile_instance.linear_damp)
			if projectile_linear_damp >= 0.0:
				linear_damp = projectile_linear_damp
		projectile_instance.queue_free()

	var release_transform: Transform3D = source_node.global_transform
	var spawn_point: Node3D = weapon_node.find_child("BulletSpawnPoint", true, false) as Node3D
	if spawn_point != null and is_instance_valid(spawn_point):
		release_transform = spawn_point.global_transform
	var start_pos: Vector3 = release_transform.origin
	var forward_dir: Vector3 = release_transform.basis.z.normalized()
	if forward_dir.length_squared() < 0.001:
		forward_dir = global_transform.basis.z.normalized()

	var initial_velocity: Vector3 = forward_dir * projectile_speed
	initial_velocity += linear_velocity
	var r_offset: Vector3 = start_pos - global_position
	initial_velocity += angular_velocity.cross(r_offset)
	# RigidBody3D clamps the completed velocity assignment, including inherited
	# platform motion. Mirror that second clamp or CCIP predicts rounds flying
	# substantially faster than the bullets during a high-speed attack run.
	if is_finite(projectile_speed_cap_mps) and initial_velocity.length() > projectile_speed_cap_mps:
		initial_velocity = initial_velocity.normalized() * projectile_speed_cap_mps

	var gravity_dir: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3(0.0, -1.0, 0.0))
	var gravity_mag: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var gravity_vec: Vector3 = gravity_dir.normalized() * gravity_mag
	var time_step: float = 0.02
	var current_pos: Vector3 = start_pos
	var current_vel: Vector3 = initial_velocity
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var steps: int = maxi(int(ceil(max_time / time_step)), 1)

	for step in range(steps):
		current_vel += gravity_vec * gravity_scale * time_step
		if linear_damp > 0.0:
			current_vel /= (1.0 + linear_damp * time_step)
		var next_pos: Vector3 = current_pos + current_vel * time_step

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(current_pos, next_pos)
		query.exclude = [self]
		query.collision_mask = 0xFFFFFFFF
		var hit_result: Dictionary = space_state.intersect_ray(query)
		if hit_result:
			result.has_impact = true
			result.impact_position = hit_result.position
			result.time_to_impact = float(step) * time_step
			result.hit_body = hit_result.get("collider", null)
			result.hit_normal = hit_result.get("normal", Vector3.ZERO)
			_classify_gun_ccip_impact(result, start_pos, target_pos, intended_target)
			break

		var terrain_h: float = _get_ground_height_at_position(next_pos)
		if not is_nan(terrain_h):
			var prev_h: float = _get_ground_height_at_position(current_pos)
			var prev_above: bool = is_nan(prev_h) or current_pos.y >= prev_h
			var curr_above: bool = next_pos.y >= terrain_h
			if prev_above and not curr_above:
				var denom: float = maxf((current_pos.y - prev_h) - (next_pos.y - terrain_h), 0.001) if not is_nan(prev_h) else 1.0
				var t: float = clampf((current_pos.y - prev_h) / denom, 0.0, 1.0) if not is_nan(prev_h) else 1.0
				var impact_pos: Vector3 = current_pos.lerp(next_pos, t)
				impact_pos.y = terrain_h
				result.has_impact = true
				result.impact_position = impact_pos
				result.time_to_impact = float(step) * time_step
				result.hit_body = _get_cached_terrain_node()
				result.hit_normal = _sample_terrain_normal_for_ccip(impact_pos)
				_classify_gun_ccip_impact(result, start_pos, target_pos, intended_target)
				break

		if next_pos.y < -1000.0:
			break

		current_pos = next_pos

	return result


func _get_selected_gun_ccip_source() -> Dictionary:
	var control_weapons: Node = find_child("ControlWeapons")
	if control_weapons == null:
		return {}
	var hardpoints_value: Variant = control_weapons.get("hardpoints")
	if not (hardpoints_value is Array):
		return {}
	var selected: String = str(control_weapons.get("selected_weapon_type"))
	if selected.is_empty():
		selected = "Autocannon"

	for hardpoint_variant in hardpoints_value:
		if not (hardpoint_variant is Node3D):
			continue
		var hardpoint: Node3D = hardpoint_variant as Node3D
		if not is_instance_valid(hardpoint):
			continue
		var weapon_variant: Variant = hardpoint.get("weapon_instance")
		if not (weapon_variant is Node):
			continue
		var weapon: Node = weapon_variant as Node
		if not is_instance_valid(weapon):
			continue
		var weapon_name: String = str(weapon.get("weapon_name"))
		var weapon_category: String = str(weapon.get("weapon_category"))
		if weapon_name != selected and weapon_category != selected:
			continue
		var muzzle_velocity: float = 500.0
		if "muzzle_velocity" in weapon:
			muzzle_velocity = float(weapon.get("muzzle_velocity"))
		elif "bullet_speed" in weapon:
			muzzle_velocity = float(weapon.get("bullet_speed"))
		var max_range_m: float = 900.0
		if "max_range_m" in weapon:
			max_range_m = float(weapon.get("max_range_m"))
		var projectile_scene: PackedScene = null
		if "bullet_projectile_scene" in weapon:
			projectile_scene = weapon.get("bullet_projectile_scene") as PackedScene
		elif "bullet_scene" in weapon:
			projectile_scene = weapon.get("bullet_scene") as PackedScene
		return {
			"source_node": hardpoint,
			"weapon_node": weapon,
			"muzzle_velocity": muzzle_velocity,
			"max_range_m": max_range_m,
			"projectile_scene": projectile_scene,
		}
	return {}


func _get_effective_ccip_projectile_speed(nominal_speed_mps: float) -> float:
	var speed_mps: float = maxf(nominal_speed_mps, 50.0)
	var speed_cap_mps: float = _get_ccip_projectile_speed_cap_mps()
	if is_finite(speed_cap_mps):
		speed_mps = minf(speed_mps, speed_cap_mps)
	return maxf(speed_mps, 50.0)


func _get_ccip_projectile_speed_cap_mps() -> float:
	for key in PROJECTILE_SPEED_CAP_SETTING_KEYS:
		if not ProjectSettings.has_setting(key):
			continue
		var cap_variant: Variant = ProjectSettings.get_setting(key)
		if typeof(cap_variant) in [TYPE_FLOAT, TYPE_INT]:
			var cap_mps: float = float(cap_variant)
			if cap_mps > 0.0:
				return cap_mps
	return INF


func _classify_gun_ccip_impact(result: Dictionary, start_pos: Vector3, target_pos: Vector3, intended_target: Node) -> void:
	var impact_variant: Variant = result.get("impact_position", Vector3.ZERO)
	var impact_pos: Vector3 = impact_variant if impact_variant is Vector3 else Vector3.ZERO
	if not _is_finite_vector3(target_pos) or impact_pos == Vector3.ZERO:
		return
	result.target_miss_m = Vector2(target_pos.x - impact_pos.x, target_pos.z - impact_pos.z).length()
	var hit_body: Node = result.get("hit_body", null) as Node
	if _rocket_ccip_hit_belongs_to_target(hit_body, intended_target):
		result.hit_intended_target = true
		return
	var shot_flat: Vector3 = Vector3(impact_pos.x - start_pos.x, 0.0, impact_pos.z - start_pos.z)
	var target_flat: Vector3 = Vector3(target_pos.x - start_pos.x, 0.0, target_pos.z - start_pos.z)
	if shot_flat.length_squared() < 1.0 or target_flat.length_squared() < 1.0:
		return
	var shot_dir: Vector3 = shot_flat.normalized()
	var impact_along_m: float = shot_flat.dot(shot_dir)
	var target_along_m: float = target_flat.dot(shot_dir)
	if impact_along_m < target_along_m - ROCKET_CCIP_TARGET_ALONG_MARGIN_M:
		result.blocked = true
		result.blocked_reason = "before_target"


func _classify_rocket_ccip_impact(result: Dictionary, start_pos: Vector3, target_pos: Vector3, intended_target: Node) -> void:
	var impact_variant: Variant = result.get("impact_position", Vector3.ZERO)
	var impact_pos: Vector3 = impact_variant if impact_variant is Vector3 else Vector3.ZERO
	if not _is_finite_vector3(target_pos) or impact_pos == Vector3.ZERO:
		return
	# Judge a moving target where it will be when the rocket arrives. The pilot's
	# terminal lead uses this same time of flight; comparing the impact with the
	# vehicle's current collider makes a correct lead look like a vehicle-speed * TOF
	# miss (roughly 45 m for a fast pickup).
	var target_translation := _get_ccip_target_linear_velocity(intended_target) \
		* maxf(float(result.get("time_to_impact", 0.0)), 0.0)
	var target_at_impact: Vector3 = target_pos + target_translation
	result.target_miss_m = Vector2(target_at_impact.x - impact_pos.x, target_at_impact.z - impact_pos.z).length()
	result.target_edge_miss_m = _horizontal_distance_to_target_collision_footprint(
		impact_pos,
		intended_target,
		target_at_impact,
		target_translation
	)
	var hit_body: Node = result.get("hit_body", null) as Node
	if _rocket_ccip_hit_belongs_to_target(hit_body, intended_target):
		return
	var shot_flat: Vector3 = Vector3(impact_pos.x - start_pos.x, 0.0, impact_pos.z - start_pos.z)
	var target_flat: Vector3 = Vector3(target_at_impact.x - start_pos.x, 0.0, target_at_impact.z - start_pos.z)
	if shot_flat.length_squared() < 1.0 or target_flat.length_squared() < 1.0:
		return
	var shot_dir: Vector3 = shot_flat.normalized()
	var impact_along_m: float = shot_flat.dot(shot_dir)
	var target_along_m: float = target_flat.dot(shot_dir)
	var normal_variant: Variant = result.get("hit_normal", Vector3.ZERO)
	var hit_normal: Vector3 = normal_variant if normal_variant is Vector3 else Vector3.ZERO
	var hit_is_steep: bool = hit_normal != Vector3.ZERO and hit_normal.y < ROCKET_CCIP_MIN_GROUND_NORMAL_Y
	# An impact short of the target is only blocked when the target is also outside
	# the rocket's real damage radius. This keeps terrain masking meaningful while
	# accepting a near-side ground impact that the configured explosion can damage.
	# The intended target's own collider was already accepted above.
	var effective_damage_radius_m: float = maxf(
		float(result.get("effective_damage_radius_m", 0.0)),
		0.0
	)
	var explosion_reaches_target: bool = float(result.get(
		"target_edge_miss_m",
		INF
	)) <= effective_damage_radius_m
	var hit_before_target: bool = not explosion_reaches_target \
		and impact_along_m + effective_damage_radius_m < target_along_m
	if hit_before_target or hit_is_steep:
		result.blocked = true
		result.blocked_reason = "before_target" if hit_before_target else "steep_terrain"


func _horizontal_distance_to_target_collision_footprint(
		point: Vector3,
		intended_target: Node,
		fallback_target_pos: Vector3,
		footprint_translation: Vector3 = Vector3.ZERO
) -> float:
	var fallback_distance_m: float = Vector2(
		point.x - fallback_target_pos.x,
		point.z - fallback_target_pos.z
	).length()
	if intended_target == null or not is_instance_valid(intended_target):
		return fallback_distance_m
	# Release against the physical damageable footprint, not every visual below the
	# target. Vehicle scenes contain turret barrels, tracers and other moving meshes;
	# folding all of those into one AABB can make a miss tens of metres away look valid.
	# Only shapes owned by the target CollisionObject3D are part of this footprint.
	if not (intended_target is CollisionObject3D):
		return fallback_distance_m
	var target_collision_object := intended_target as CollisionObject3D
	var target_shapes: Array[CollisionShape3D] = []
	for shape_value: Node in intended_target.find_children("*", "CollisionShape3D", true, false):
		if not (shape_value is CollisionShape3D):
			continue
		var collision_shape := shape_value as CollisionShape3D
		if collision_shape.disabled or collision_shape.shape == null:
			continue
		var owner: Node = collision_shape.get_parent()
		while owner != null and not (owner is CollisionObject3D):
			owner = owner.get_parent()
		if owner == target_collision_object:
			target_shapes.append(collision_shape)
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for collision_shape: CollisionShape3D in target_shapes:
		var local_bounds: AABB = _get_collision_shape_local_bounds(collision_shape.shape)
		if local_bounds.size == Vector3.ZERO:
			continue
		for x_index in range(2):
			for y_index in range(2):
				for z_index in range(2):
					var local_corner := local_bounds.position + Vector3(
						local_bounds.size.x * float(x_index),
						local_bounds.size.y * float(y_index),
						local_bounds.size.z * float(z_index)
					)
					var world_corner: Vector3 = collision_shape.global_transform * local_corner \
						+ footprint_translation
					min_x = minf(min_x, world_corner.x)
					max_x = maxf(max_x, world_corner.x)
					min_z = minf(min_z, world_corner.z)
					max_z = maxf(max_z, world_corner.z)
	if not is_finite(min_x) or not is_finite(max_x) \
			or not is_finite(min_z) or not is_finite(max_z):
		return fallback_distance_m
	var outside_x_m: float = maxf(maxf(min_x - point.x, point.x - max_x), 0.0)
	var outside_z_m: float = maxf(maxf(min_z - point.z, point.z - max_z), 0.0)
	return Vector2(outside_x_m, outside_z_m).length()


func _get_collision_shape_local_bounds(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var box_size: Vector3 = (shape as BoxShape3D).size
		return AABB(-box_size * 0.5, box_size)
	if shape is SphereShape3D:
		var sphere_radius: float = (shape as SphereShape3D).radius
		var sphere_size := Vector3.ONE * sphere_radius * 2.0
		return AABB(-sphere_size * 0.5, sphere_size)
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var capsule_size := Vector3(capsule.radius * 2.0, capsule.height, capsule.radius * 2.0)
		return AABB(-capsule_size * 0.5, capsule_size)
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		var cylinder_size := Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
		return AABB(-cylinder_size * 0.5, cylinder_size)
	var points: PackedVector3Array = PackedVector3Array()
	if shape is ConvexPolygonShape3D:
		points = (shape as ConvexPolygonShape3D).points
	elif shape is ConcavePolygonShape3D:
		points = (shape as ConcavePolygonShape3D).get_faces()
	if points.is_empty():
		return AABB()
	var bounds := AABB(points[0], Vector3.ZERO)
	for point_index in range(1, points.size()):
		bounds = bounds.expand(points[point_index])
	return bounds


func _get_ccip_target_linear_velocity(target: Node) -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	if target is RigidBody3D:
		return (target as RigidBody3D).linear_velocity
	if target is CharacterBody3D:
		return (target as CharacterBody3D).velocity
	if "linear_velocity" in target:
		var linear_velocity_value: Variant = target.get("linear_velocity")
		if linear_velocity_value is Vector3:
			return linear_velocity_value
	if "velocity" in target:
		var velocity_value: Variant = target.get("velocity")
		if velocity_value is Vector3:
			return velocity_value
	return Vector3.ZERO


func _rocket_ccip_hit_belongs_to_target(hit_body: Node, intended_target: Node) -> bool:
	if hit_body == null or intended_target == null or not is_instance_valid(intended_target):
		return false
	var node: Node = hit_body
	while node:
		if node == intended_target:
			return true
		node = node.get_parent()
	return false


func _sample_terrain_normal_for_ccip(world_pos: Vector3) -> Vector3:
	var sample_step_m: float = 5.0
	var hx0: float = _get_ground_height_at_position(world_pos + Vector3(-sample_step_m, 0.0, 0.0))
	var hx1: float = _get_ground_height_at_position(world_pos + Vector3(sample_step_m, 0.0, 0.0))
	var hz0: float = _get_ground_height_at_position(world_pos + Vector3(0.0, 0.0, -sample_step_m))
	var hz1: float = _get_ground_height_at_position(world_pos + Vector3(0.0, 0.0, sample_step_m))
	if is_nan(hx0) or is_nan(hx1) or is_nan(hz0) or is_nan(hz1):
		return Vector3.UP
	var dx: Vector3 = Vector3(sample_step_m * 2.0, hx1 - hx0, 0.0)
	var dz: Vector3 = Vector3(0.0, hz1 - hz0, sample_step_m * 2.0)
	var normal: Vector3 = dz.cross(dx).normalized()
	if normal.y < 0.0:
		normal = -normal
	return normal


func _is_finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
