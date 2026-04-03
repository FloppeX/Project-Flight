class_name Aircraft
extends RigidBody3D

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
@export var prevent_below_terrain: bool = true 
@export var ground_clearance: float = 0.25
@export var ground_probe_up: float = 50.0
@export var ground_probe_down: float = 2000.0
@export var belly_land_max_vertical_speed: float = 6.0
@export var belly_land_max_total_speed: float = 80.0
@export var belly_align_tolerance_deg: float = 25.0
@export var hard_crash_vertical_speed: float = 10.0
@export var steep_slope_min_up_dot: float = 0.7

var _last_damage_ms: int = 0
var _current_health: float
var current_health: float:
	get:
		return _current_health
	set(value):
		if _current_health != value:
			_current_health = value


@export var MaxLandingForce: float = 3.0
@export var Gravity: float = 1.0 # Normalized to Earth average at sea level
@export var SeaLevelFromOrigin: float = 0.0
@export var AltitudeEnabled: bool = true
@export var carrier_deck_reference_altitude_m: float = 40.0
@export var carrier_deck_extent_x_m: float = 90.0
@export var carrier_deck_extent_z_m: float = 140.0
@export var carrier_deck_altitude_zone_margin_y_m: float = 120.0
@export var GForceFactor: float = 1.0
@export var WorldOrientationReference: NodePath
@onready var world_ref : Node3D = get_node_or_null(WorldOrientationReference)
var internal_world_reference : Node3D

const EARTH_GRAVITY = 9.8 # for g-force calculation

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
var shake_frequency: float = 30.0
var shake_time: float = 0.0

var last_linear_velocity = null
var last_angular_velocity = null
var is_velocity_nonzero = false
var _terrain_node: Node = null
const AAM_TARGETING_SCRIPT := preload("res://Weapons/AA_Missile/ControlTargeting_AAM.gd")

# Flight data
var air_velocity = 0.0
var forward_air_speed = 0.0
var local_altitude = 0.0
var local_g_force = 1.0
var local_load_factor = 1.0

func _ready():
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
	
	setup()

	# Apply player livery colors to friendly aircraft
	if team == 1 and Livery:
		Livery.apply(self)

	physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_ON

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

func _unhandled_input(event):
	for module in modules:
		if module.ReceiveInput:
			module.receive_input(event)

func _physics_process(delta):
	prepare_energy_system()
	apply_shake_forces(delta)
	calculate_flight_data(delta)
	
	# Let modules do their physics
	for module in modules:
		if module.ProcessPhysics:
			module.process_physic_frame(delta)
	
	# Safety: never allow aircraft below terrain height (fallback against streaming holes)
	if prevent_below_terrain:
		_enforce_above_terrain()
	
	# Clean up energy budget and check movement state
	consume_energy_budget()
	check_movement_state()
	
	last_linear_velocity = linear_velocity
	last_angular_velocity = angular_velocity

func _process(delta):
	for module in modules:
		if module.ProcessRender:
			module.process_render_frame(delta)

##############################################################################
#  COLLISION HANDLING
# ----------------------------------------------------------------------------

func _on_Aircraft_body_shape_entered(body_rid, body, body_shape_index, local_shape_index):
	# If the colliding body is a projectile, let the projectile's script handle the damage.
	if body is ProjectileNew:
		return
	var collider_shape = shape_owner_get_owner(local_shape_index)
	var impact_force = linear_velocity.length()
	if _is_runway_surface(body):
		if collider_shape in safe_colliders:
			var landing_force = linear_velocity.dot(global_transform.basis.y)
			land(landing_force, impact_force)
		else:
			_evaluate_terrain_impact()
		return
	# Terrain-specific handling
	if _is_ground_or_terrain(body):
		_evaluate_terrain_impact()
		return
	
	if collider_shape in safe_colliders:
		var landing_force = linear_velocity.dot(global_transform.basis.y)
		land(landing_force, impact_force)
	else:
		crash(impact_force)

func _on_Aircraft_body_shape_exited(body_rid, body, body_shape_index, local_shape_index):
	pass

func register_safe_collider(collider: CollisionShape3D):
	if not collider in safe_colliders:
		safe_colliders.append(collider)

func unregister_safe_collider(collider: CollisionShape3D):
	if collider in safe_colliders:
		safe_colliders.erase(collider)

func land(landing_velocity: float, impact_velocity: float):
	if landing_velocity > MaxLandingForce:
		crash(landing_velocity)

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
	return global_position.y < ground_y - 0.01

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
	# Belly alignment: aircraft belly faces -up (down vector)
	var belly_normal: Vector3 = -global_transform.basis.y
	var align_dot: float = clamp(belly_normal.normalized().dot(ground_normal), -1.0, 1.0)
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
		# Aircraft penetrated terrain - crash (no more rescuing by snapping back up)
		explode()

func _get_cached_terrain_node() -> Node:
	if _terrain_node and is_instance_valid(_terrain_node):
		return _terrain_node
	var tagged: Node = get_tree().get_first_node_in_group("terrain_provider")
	if tagged and is_instance_valid(tagged):
		_terrain_node = tagged
		return _terrain_node
	var root: Node = get_tree().current_scene
	if not root:
		return null
	var queue: Array = [root]
	while queue.size() > 0:
		var cur: Node = queue.pop_front()
		if cur.get_class() == "Terrain3D":
			_terrain_node = cur
			return _terrain_node
		if cur is Node3D and cur.has_method("get_height"):
			_terrain_node = cur
			return _terrain_node
		for child in cur.get_children():
			queue.append(child)
	return null

func _get_ground_height_at_position(world_pos: Vector3) -> float:
	# Prefer Terrain3D height API (works even when physics collider misses),
	# then fallback to a raycast.
	var terrain: Node = _get_cached_terrain_node()
	if terrain:
		if terrain.has_method("get_height"):
			var h = terrain.get_height(world_pos)
			if typeof(h) == TYPE_FLOAT and not is_nan(float(h)):
				return float(h)
		if "data" in terrain and terrain.data and terrain.data.has_method("get_height"):
			var h2 = terrain.data.get_height(world_pos)
			if typeof(h2) == TYPE_FLOAT and not is_nan(float(h2)):
				return float(h2)

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
	var ground_y: float = _get_ground_height_at_position(global_position)
	var carrier_ground_y: float = _get_carrier_reference_ground_y()
	var reference_ground_y: float = ground_y
	if not is_nan(carrier_ground_y):
		if is_nan(reference_ground_y):
			reference_ground_y = carrier_ground_y
		else:
			reference_ground_y = minf(reference_ground_y, carrier_ground_y)
	if is_nan(reference_ground_y):
		return maxf(global_position.y - SeaLevelFromOrigin, 0.0)
	return maxf(global_position.y - reference_ground_y, 0.0)

func get_effective_altitude_reference_y() -> float:
	var ground_y: float = _get_ground_height_at_position(global_position)
	var carrier_ground_y: float = _get_carrier_reference_ground_y()
	if not is_nan(carrier_ground_y):
		if is_nan(ground_y):
			return carrier_ground_y
		return minf(ground_y, carrier_ground_y)
	if not is_nan(ground_y):
		return ground_y
	return SeaLevelFromOrigin

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
	if AltitudeEnabled:
		local_altitude = get_effective_altitude_agl_m()
	else:
		local_altitude = 0.0
	
	# Calculate G-forces
	if last_linear_velocity != null:
		var up_vector = global_transform.basis.y
		var linear_acceleration = (linear_velocity - last_linear_velocity) / delta
		var vertical_acceleration_normalized = (up_vector.dot(linear_acceleration) / EARTH_GRAVITY) * GForceFactor
		
		local_load_factor = (1.0 + vertical_acceleration_normalized/Gravity) if Gravity > 0 else 0.0
		local_g_force = (Gravity + vertical_acceleration_normalized) if Gravity > 0 else 0.0

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
	if current_health <= 0:
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
	
	emit_signal("damaged", damage_amount, current_health)
	
	if current_health <= 0:
		explode()

func explode():
	emit_signal("destroyed")
	
	# Only player aircraft should trigger deathcam cut.
	# AI aircraft are removed from "aircraft" group by the spawner.
	if is_in_group("aircraft"):
		activate_deathcam()
	
	# Spawn explosion effect if available
	if explosion_scene:
		var explosion_instance = explosion_scene.instantiate()
		get_parent().add_child(explosion_instance)
		explosion_instance.global_position = global_position

	# Swap to wreck and free the aircraft body
	_spawn_wreck_and_free()

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

	# Start from bomb hardpoint position
	var start_pos = bomb_hardpoint.global_position
	var aircraft_velocity = linear_velocity
	# Include angular velocity contribution: v = ω × r
	var r_offset: Vector3 = start_pos - global_position
	var angular_vel_component: Vector3 = angular_velocity.cross(r_offset)
	var initial_velocity = Vector3.DOWN * drop_force + aircraft_velocity + angular_vel_component
	
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
	var space_state = get_world_3d().direct_space_state
	
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
