extends RigidBody3D
class_name EnemyAircraft

@export var max_health: float = 50.0
@export var damage_per_shot: float = 10.0
@export var fire_rate: float = 1.0  # shots per second
@export var bullet_scene: PackedScene
@export var explosion_scene: PackedScene
@export var bullet_speed: float = 600.0  # m/s
@export var ballistics_drag: float = 0.1  # Air resistance factor
@export var aim_skill: float = 1.0  # 0.0 = terrible, 1.0 = perfect aim
@export var ground_clearance: float = 0.5
@export var ground_snap_probe_up: float = 50.0
@export var ground_snap_probe_down: float = 1500.0
@export var terrain_path: NodePath
@export var enable_ground_clamp: bool = false

var current_health: float
var fire_timer: float = 0.0
var target_aircraft: Node3D
var _last_ground_y: float = -INF
var _terrain: Node = null
var _last_integrator_log_ms: int = 0
var is_dying: bool = false # To prevent multiple explosion calls

signal destroyed(enemy)

func _ready():
	# Cache terrain
	if terrain_path != NodePath(""):
		_terrain = get_node_or_null(terrain_path)
	if _terrain == null:
		_terrain = get_tree().get_first_node_in_group("terrain_provider")
	if _terrain == null:
		# Search breadth-first for terrain providers.
		var queue: Array = [get_tree().current_scene]
		while queue.size() > 0 and _terrain == null:
			var cur: Node = queue.pop_front()
			for child in cur.get_children():
				queue.append(child)
				if child.get_class() == "Terrain3D" or "terrain3d" in child.name.to_lower() or (child is Node3D and child.has_method("get_height")):
					_terrain = child
					break
	current_health = max_health
	add_to_group("enemies")
	var registry: Node = get_node_or_null("/root/EnemyRegistry")
	if registry and registry.has_method("register_enemy"):
		registry.register_enemy(self, 2)
	
	# Find the player aircraft
	target_aircraft = get_tree().get_first_node_in_group("aircraft")
	if target_aircraft:
		print("[EnemyAircraft] Found target aircraft: ", target_aircraft.name)
	else:
		print("[EnemyAircraft] WARNING: No aircraft found in 'aircraft' group!")
	
	# Load bullet scene if not set
	if not bullet_scene:
		bullet_scene = load("res://Projectiles/Bullet/bullet.tscn")
	
	# Load explosion scene if not set
	if not explosion_scene:
		explosion_scene = load("res://Projectiles/Explosion/explosion.tscn")
	
	print("Enemy aircraft created with ", max_health, " HP")
	# Ensure body stays active
	can_sleep = false
	sleeping = false

func _process(delta):
	# If dying, do nothing else
	if is_dying:
		return

	if not target_aircraft or not is_instance_valid(target_aircraft):
		return
	
	# Update fire timer
	fire_timer += delta
	
	# Check if we should fire
	if fire_timer >= (1.0 / fire_rate):
		fire_at_target()
		fire_timer = 0.0

func fire_at_target():
	if not bullet_scene or not target_aircraft:
		return
	
	# Calculate proper lead position with ballistics
	var lead_pos = calculate_ballistic_lead_position(target_aircraft)
	var direction = (lead_pos - global_position).normalized()
	
	# Create bullet
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position + direction * 2.0  # Spawn slightly in front
	
	# Fire bullet towards predicted position
	var bullet_velocity = direction * bullet_speed
	bullet.fire(bullet_velocity, self)
	
	var distance = global_position.distance_to(target_aircraft.global_position)
	var lead_distance = global_position.distance_to(lead_pos)
	print("[EnemyAircraft] Fired at lead position! Distance: ", distance, "m, Lead: ", lead_distance, "m")

func calculate_ballistic_lead_position(target: Node3D) -> Vector3:
	# Enhanced ballistics calculation with drag and gravity compensation
	var target_pos = target.global_position
	var target_velocity = Vector3.ZERO
	
	# Get target velocity
	if target.has_method("get_linear_velocity"):
		target_velocity = target.get_linear_velocity()
	elif target.has_method("linear_velocity"):
		target_velocity = target.linear_velocity
	
	# Ballistic parameters
	var initial_bullet_speed = bullet_speed  # Use exported value
	var gravity = 9.8  # m/s²
	var drag_coefficient = ballistics_drag  # Use exported value
	
	# Iterative solution for intercept point
	var predicted_pos = target_pos
	var best_solution = target_pos
	var best_error = 999999.0
	
	# Try multiple iterations to converge on solution
	for iteration in range(5):
		var distance_to_predicted = global_position.distance_to(predicted_pos)
		
		# Calculate flight time with drag compensation
		var flight_time = calculate_flight_time_with_drag(distance_to_predicted, initial_bullet_speed, drag_coefficient)
		
		# Predict target position at flight time
		var target_predicted = target_pos + (target_velocity * flight_time)
		
		# Account for gravity drop
		var height_difference = target_predicted.y - global_position.y
		var horizontal_distance = Vector2(target_predicted.x - global_position.x, target_predicted.z - global_position.z).length()
		var gravity_drop = 0.5 * gravity * flight_time * flight_time
		
		# Adjust for gravity (aim higher)
		target_predicted.y += gravity_drop
		
		# Calculate error and update best solution
		var error = predicted_pos.distance_to(target_predicted)
		if error < best_error:
			best_error = error
			best_solution = target_predicted
		
		# Update for next iteration
		predicted_pos = target_predicted
		
		# Break if converged
		if error < 1.0:  # Within 1 meter is good enough
			break
	
	# Add some inaccuracy based on aim skill
	if aim_skill < 1.0:
		var inaccuracy_range = (1.0 - aim_skill) * 20.0  # Up to 20m spread for terrible aim
		var random_offset = Vector3(
			randf_range(-inaccuracy_range, inaccuracy_range),
			randf_range(-inaccuracy_range * 0.5, inaccuracy_range * 0.5),  # Less vertical spread
			randf_range(-inaccuracy_range, inaccuracy_range)
		)
		best_solution += random_offset
	
	return best_solution

func calculate_flight_time_with_drag(distance: float, initial_speed: float, drag: float) -> float:
	# Approximate flight time accounting for drag deceleration
	# Using simplified drag model: v(t) = v0 * e^(-drag * t)
	# Distance with drag: d = (v0 / drag) * (1 - e^(-drag * t))
	
	if drag <= 0.0:
		return distance / initial_speed
	
	# Solve for time using Newton's method approximation
	var time_estimate = distance / initial_speed  # Start with no-drag estimate
	
	for i in range(3):  # Few iterations for approximation
		var predicted_distance = (initial_speed / drag) * (1.0 - exp(-drag * time_estimate))
		var error = predicted_distance - distance
		
		if abs(error) < 0.1:  # Close enough
			break
			
		# Newton's method derivative
		var derivative = initial_speed * exp(-drag * time_estimate)
		if derivative > 0.01:  # Avoid division by zero
			time_estimate -= error / derivative
		
		# Clamp to reasonable values
		time_estimate = clamp(time_estimate, 0.01, 10.0)
	
	return time_estimate

func _physics_process(delta: float) -> void:
	# If dying, do nothing else
	if is_dying:
		# Keep gravity enabled so it falls out of the sky
		return
	# Ground clamp to avoid falling through streamed-out terrain
	if not enable_ground_clamp:
		return
	var ground_y: float = _get_ground_height(global_position)
	if not is_nan(ground_y):
		_last_ground_y = float(ground_y)
		var min_y: float = _last_ground_y + ground_clearance
		if global_position.y < min_y:
			var pos := global_position
			pos.y = min_y
			global_position = pos
			if linear_velocity.y < 0.0:
				linear_velocity.y = 0.0
	elif _last_ground_y != -INF and global_position.y < _last_ground_y + ground_clearance - 0.5:
		var pos2 := global_position
		pos2.y = _last_ground_y + ground_clearance
		global_position = pos2
		if linear_velocity.y < 0.0:
			linear_velocity.y = 0.0

func _get_ground_height(world_pos: Vector3) -> float:
	if _terrain:
		if _terrain.has_method("get_height"):
			return float(_terrain.get_height(world_pos))
		elif "data" in _terrain and _terrain.data and _terrain.data.has_method("get_height"):
			return float(_terrain.data.get_height(world_pos))
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = world_pos + Vector3.UP * ground_snap_probe_up
	var to: Vector3 = world_pos - Vector3.UP * ground_snap_probe_down
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self]
	var hit: Dictionary = space_state.intersect_ray(params)
	if hit and hit.has("position"):
		return float(hit.position.y)
	return NAN

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not enable_ground_clamp:
		return
	# Ground clamp at physics integration time
	var gy: float = _get_ground_height(state.transform.origin)
	if is_nan(gy):
		return
	var min_y: float = gy + ground_clearance
	if state.transform.origin.y < min_y:
		var t := state.transform
		t.origin.y = min_y
		state.transform = t
		var lv := state.linear_velocity
		if lv.y < 0.0:
			lv.y = 0.0
			state.linear_velocity = lv
		# Nuclear clamp via PhysicsServer3D to avoid solver races
		var rid: RID = get_rid()
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, state.transform)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, state.linear_velocity)
		# Rate-limited log
		var now_ms: int = Time.get_ticks_msec()
		if now_ms - _last_integrator_log_ms > 1000:
			print("[EnemyAircraft] Integrator clamp y=", state.transform.origin.y, " gy=", gy)
			_last_integrator_log_ms = now_ms

func take_damage(damage_amount: float):
	if is_dying or current_health <= 0:
		return  # Already destroyed or in the process of exploding
	
	current_health -= damage_amount
	current_health = max(current_health, 0.0)
	
	print("Enemy aircraft taking damage: ", damage_amount, " HP remaining: ", current_health)
	
	if current_health <= 0:
		is_dying = true
		# Create a timer for a random delay before exploding
		var death_timer = Timer.new()
		death_timer.wait_time = randf_range(0.0, 1.0)
		death_timer.one_shot = true
		death_timer.timeout.connect(explode)
		add_child(death_timer)
		death_timer.start()
		# Make sure the timer is removed after it's done
		death_timer.timeout.connect(death_timer.queue_free)

func explode():
	print("Enemy aircraft exploding!")
	emit_signal("destroyed", self)
	
	# Spawn explosion effect
	if explosion_scene:
		var explosion_instance = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion_instance)
		explosion_instance.global_position = global_position
		print("Enemy explosion spawned at: ", global_position)
	
	# Remove the enemy
	queue_free()
