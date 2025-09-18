extends StaticBody3D
class_name EnemyBox

signal destroyed(enemy)

@export var max_health: float = 50.0
@export var explosion_scene: PackedScene
@export var detection_range: float = 500.0
@export var team: int = 2
@export var turret_range: float = 400.0
@export var fire_rate: float = 2.0  # shots per second
@export var bullet_speed: float = 200.0  # m/s
@export var bullet_scene: PackedScene

var current_health: float
var detected_enemies: Array = []
#var original_material: StandardMaterial3D  # Disabled for performance
#var blink_timer: float = 0.0  # Disabled for performance
#var is_blinking: bool = false  # Disabled for performance
var turret_node: Node3D
var fire_timer: float = 0.0
var current_target: Node3D
var detection_timer: float = 0.0
var target_search_timer: float = 0.0
var shout_timer: float = 0.0
@export var freeze_when_offscreen: bool = false
@export var ground_clearance: float = 0.5
@export var ground_snap_probe_up: float = 50.0
@export var ground_snap_probe_down: float = 1500.0
@export var terrain_path: NodePath
@export var enable_ground_clamp: bool = true
var _notifier: VisibleOnScreenNotifier3D
var _last_ground_y: float = -INF
var _terrain: Node = null
var _last_integrator_log_ms: int = 0
var _disable_clamp_until_ms: int = 0
var _lock_xz: Vector2

func _ready():
	
	# Re-enabled enemy logic

	# Initialize health
	current_health = max_health
	# Ensure this body is not affected by parent transforms
	top_level = true
	# Capture initial XZ to lock position for static ground units
	_lock_xz = Vector2(global_position.x, global_position.z)
	
	# Add to enemy group for targeting
	add_to_group("enemies")
	add_to_group("team_" + str(team))
	var registry: Node = get_node_or_null("/root/EnemyRegistry")
	if registry and registry.has_method("register_enemy"):
		registry.register_enemy(self, team)
	# Detect immediate zeroing after spawn and correct once
	call_deferred("_post_spawn_verify_position")
	
	# Store original material for blinking (disabled for performance)
	#var mesh_instance = get_node("MeshInstance3D")
	#if mesh_instance and mesh_instance.material_override:
	#	original_material = mesh_instance.material_override.duplicate()
	
	# Create turret
	create_turret()
	
	# Load bullet scene if not set
	if not bullet_scene:
		bullet_scene = load("res://Projectiles/Bullet/bullet.tscn")
	
	# Ensure collision mask includes terrain layer (10) and default (1) if available
	var mask: int = get_collision_mask()
	mask |= (1 << 0) | (1 << 9)
	set_collision_mask(mask)

	# Cache terrain reference (deep search if not provided)
	if terrain_path != NodePath(""):
		_terrain = get_node_or_null(terrain_path)
	if _terrain == null:
		# Search breadth-first for any Terrain3D node
		var queue: Array = [get_tree().current_scene]
		while queue.size() > 0 and _terrain == null:
			var cur: Node = queue.pop_front()
			for child in cur.get_children():
				queue.append(child)
				if child.get_class() == "Terrain3D" or "terrain3d" in child.name.to_lower():
					_terrain = child
					break
	
	# Add a visibility notifier (optional hooks)
	if freeze_when_offscreen:
		_notifier = VisibleOnScreenNotifier3D.new()
		add_child(_notifier)
		_notifier.screen_entered.connect(_on_screen_entered)
		_notifier.screen_exited.connect(_on_screen_exited)
	

func _physics_process(delta):
	# Update timers
	detection_timer += delta
	target_search_timer += delta
	shout_timer += delta
	
	# Detection (once per second)
	if detection_timer >= 1.0:
		detect_enemies()
		detection_timer = 0.0
	
	# Update shout timer (no output)
	if shout_timer >= 5.0:
		shout_timer = 0.0
	
	#update_blinking(delta)  # Disabled for performance
	
	# Turret combat
	update_turret(delta)

func take_damage(damage_amount: float):
	if current_health <= 0:
		return  # Already destroyed
	
	print("Enemy box taking damage: ", damage_amount, " HP remaining: ", current_health - damage_amount)
	
	current_health -= damage_amount
	current_health = max(current_health, 0.0)
	
	if current_health <= 0:
		# Random delay before explosion (0-1 seconds)
		var explosion_delay: float = randf() * 1.0
		print("Enemy destroyed - will explode in ", explosion_delay, " seconds")
		get_tree().create_timer(explosion_delay).timeout.connect(explode)

func _on_screen_exited():
	if not freeze_when_offscreen:
		return
	# No-op for static bodies

func _on_screen_entered():
	if not freeze_when_offscreen:
		return
	# No-op for static bodies
	_snap_to_ground_if_needed()

func _snap_to_ground_if_needed():
	if not enable_ground_clamp:
		return
	# Always use locked XZ for static units
	var sample_pos := Vector3(_lock_xz.x, global_position.y, _lock_xz.y)
	var ground_y: float = _get_ground_height(sample_pos)
	if is_nan(ground_y):
		return
	var target_y: float = ground_y + ground_clearance
	_last_ground_y = ground_y
	var desired := Vector3(_lock_xz.x, target_y, _lock_xz.y)
	if not global_position.is_equal_approx(desired):
		global_position = desired

func _get_ground_height(world_pos: Vector3) -> float:
	# Prefer Terrain3D data height if available
	if _terrain:
		if _terrain.has_method("get_height"):
			var h = _terrain.get_height(world_pos)
			return float(h)
		elif "data" in _terrain and _terrain.data and _terrain.data.has_method("get_height"):
			var h2 = _terrain.data.get_height(world_pos)
			return float(h2)
	# Fallback to raycast
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = world_pos + Vector3.UP * ground_snap_probe_up
	var to: Vector3 = world_pos - Vector3.UP * ground_snap_probe_down
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self]
	var hit: Dictionary = space_state.intersect_ray(params)
	if hit and hit.has("position"):
		return float(hit.position.y)
	return NAN

## Removed physics integrator; StaticBody3D isn't integrated like RigidBody3D

func disable_ground_clamp_for_ms(ms: int) -> void:
	_disable_clamp_until_ms = Time.get_ticks_msec() + ms

func explode():
	print("Enemy box exploding!")
	emit_signal("destroyed", self)
	
	# Clear this enemy from any targeting systems to prevent crashes
	var aircraft = get_tree().get_first_node_in_group("aircraft")
	if aircraft:
		var targeting_module = aircraft.find_child("ControlTargeting", true, false)
		if targeting_module and "current_target" in targeting_module:
			if targeting_module.current_target == self:
				targeting_module.current_target = null
				print("Cleared destroyed enemy from targeting system")
	
	# Spawn explosion effect
	var explosion_scene_resource = load("res://Projectiles/Explosion/explosion.tscn")
	if explosion_scene_resource:
		var explosion_instance = explosion_scene_resource.instantiate()
		get_parent().add_child(explosion_instance)
		explosion_instance.global_position = global_position
		print("Enemy explosion spawned at: ", global_position)
	
	# Remove the enemy
	queue_free()

func detect_enemies():
	# Find all enemies from other teams within detection range
	var enemies_in_range = []
	
	# Check aircraft group (player)
	var aircraft = get_tree().get_first_node_in_group("aircraft")
	if aircraft and aircraft.has_method("get_team") and aircraft.get_team() != team:
		var distance = global_position.distance_to(aircraft.global_position)
		if distance <= detection_range:
			enemies_in_range.append(aircraft)
	
	# Check other enemies group
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in all_enemies:
		if enemy == self:
			continue
		
		# Check if enemy is from different team
		if enemy.has_method("get_team") and enemy.get_team() != team:
			var distance = global_position.distance_to(enemy.global_position)
			if distance <= detection_range:
				enemies_in_range.append(enemy)
	
	# Update detection state (blinking and debug prints disabled for performance)
	#if enemies_in_range.size() > 0:
	#	print("Enemy detected! Distance: ", global_position.distance_to(enemies_in_range[0].global_position))
	#else:
	#	print("No enemies in range")
	
	detected_enemies = enemies_in_range

func update_blinking(delta):
	# Blinking disabled for performance
	pass

func get_team() -> int:
	return team

func create_turret():
	# Create turret node
	turret_node = Node3D.new()
	turret_node.name = "Turret"
	add_child(turret_node)
	
	# Position turret on top of the box
	turret_node.position = Vector3(0, 1.5, 0)  # 1.5m above center (box is 2m tall)
	
	# Create turret barrel (simple cylinder)
	var barrel_mesh = CylinderMesh.new()
	barrel_mesh.height = 2.0
	barrel_mesh.top_radius = 0.1
	barrel_mesh.bottom_radius = 0.1
	
	var barrel_instance = MeshInstance3D.new()
	barrel_instance.name = "Barrel"
	barrel_instance.mesh = barrel_mesh
	turret_node.add_child(barrel_instance)
	
	# Create turret material (dark gray)
	var turret_material = StandardMaterial3D.new()
	turret_material.albedo_color = Color(0.3, 0.3, 0.3, 1)
	barrel_instance.material_override = turret_material
	
	# Position barrel pointing forward
	barrel_instance.position = Vector3(0, 0, 1.0)  # 1m forward from turret center
	barrel_instance.rotation_degrees = Vector3(90, 0, 0)  # Rotate to point forward

func update_turret(delta):
	if not turret_node:
		return
	
	# Update fire timer
	fire_timer += delta
	
	# Find best target within turret range (once per second)
	if target_search_timer >= 1.0:
		var best_target = find_best_target()
		current_target = best_target
		target_search_timer = 0.0
	
	if current_target and is_instance_valid(current_target):
		# Track target
		track_target(current_target)
		
		# Fire if ready and in range
		if fire_timer >= (1.0 / fire_rate):
			fire_at_target(current_target)
			fire_timer = 0.0

func find_best_target() -> Node3D:
	var best_target: Node3D = null
	var best_distance = turret_range
	
	# Check aircraft
	var aircraft = get_tree().get_first_node_in_group("aircraft")
	if aircraft and aircraft.has_method("get_team") and aircraft.get_team() != team:
		var distance = global_position.distance_to(aircraft.global_position)
		if distance <= turret_range and distance < best_distance:
			best_target = aircraft
			best_distance = distance
	
	# Check other enemies
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in all_enemies:
		if enemy == self:
			continue
		
		if enemy.has_method("get_team") and enemy.get_team() != team:
			var distance = global_position.distance_to(enemy.global_position)
			if distance <= turret_range and distance < best_distance:
				best_target = enemy
				best_distance = distance
	
	return best_target

func track_target(target: Node3D):
	if not target or not turret_node:
		return
	
	# Calculate target position with lead
	var target_pos = calculate_lead_position(target)
	
	# Point turret at target
	var direction = (target_pos - turret_node.global_position).normalized()
	if direction.length() > 0:
		# Calculate rotation to look at target
		var look_at_pos = turret_node.global_position + direction
		turret_node.look_at(look_at_pos, Vector3.UP)

func calculate_lead_position(target: Node3D) -> Vector3:
	if not target:
		return Vector3.ZERO

	# Get target position and velocity
	var target_pos = target.global_position
	var target_velocity = Vector3.ZERO
	
	# Try to get target velocity
	if target.has_method("get_linear_velocity"):
		target_velocity = target.get_linear_velocity()
	elif "linear_velocity" in target:
		target_velocity = target.linear_velocity
	
	# Get our position (turret barrel tip is more accurate)
	var barrel_tip = turret_node.global_position + turret_node.global_transform.basis.z * 1.0
	
	# Get gravity from project settings
	var gravity = ProjectSettings.get_setting("physics/3d/default_gravity_vector") * ProjectSettings.get_setting("physics/3d/default_gravity")

	# Iteratively calculate the lead position (3 iterations is a good balance)
	var time_to_target = 0.0
	var predicted_pos = target_pos
	
	for i in range(3):
		var distance = barrel_tip.distance_to(predicted_pos)
		time_to_target = distance / bullet_speed if bullet_speed > 0 else 0
		predicted_pos = target_pos + (target_velocity * time_to_target)

	# Compensate for bullet drop. The formula for drop is 0.5 * g * t^2.
	# We must aim *higher* to counteract the drop, so we subtract the gravity vector's effect.
	var bullet_drop_offset = 0.5 * gravity * time_to_target * time_to_target
	var final_aim_position = predicted_pos - bullet_drop_offset
	
	return final_aim_position

func fire_at_target(target: Node3D):
	if not bullet_scene or not turret_node:
		return
	
	# Create bullet
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	
	# Position bullet at turret barrel tip
	var barrel_tip = turret_node.global_position + turret_node.global_transform.basis.z * 1.0
	bullet.global_position = barrel_tip
	
	# Calculate firing direction with lead
	var target_pos = calculate_lead_position(target)
	var fire_direction = (target_pos - barrel_tip).normalized()
	var bullet_velocity = fire_direction * bullet_speed
	
	# Fire bullet
	bullet.fire(bullet_velocity, self)
	
	#print("Turret fired at target! Distance: ", global_position.distance_to(target.global_position))

func _post_spawn_verify_position():
	if global_position.is_equal_approx(Vector3.ZERO):
		# If we somehow got zeroed, try to place on terrain under our current XZ
		var gy := _get_ground_height(Vector3(_lock_xz.x, 0.0, _lock_xz.y))
		if not is_nan(gy):
			global_position = Vector3(_lock_xz.x, gy + ground_clearance, _lock_xz.y)
			#print("[EnemyBox] Post-spawn corrected from origin to ", global_position)
	else:
		# Ensure initial placement is at terrain height once
		var gy2 := _get_ground_height(Vector3(_lock_xz.x, 0.0, _lock_xz.y))
		if not is_nan(gy2):
			global_position = Vector3(_lock_xz.x, gy2 + ground_clearance, _lock_xz.y)
