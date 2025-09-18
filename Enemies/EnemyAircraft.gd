extends RigidBody3D
class_name EnemyAircraft

@export var max_health: float = 50.0
@export var damage_per_shot: float = 10.0
@export var fire_rate: float = 1.0  # shots per second
@export var bullet_scene: PackedScene
@export var explosion_scene: PackedScene
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
		# Search breadth-first for any Terrain3D node
		var queue: Array = [get_tree().current_scene]
		while queue.size() > 0 and _terrain == null:
			var cur: Node = queue.pop_front()
			for child in cur.get_children():
				queue.append(child)
				if child.get_class() == "Terrain3D" or "terrain3d" in child.name.to_lower():
					_terrain = child
					break
	current_health = max_health
	add_to_group("enemies")
	var registry: Node = get_node_or_null("/root/EnemyRegistry")
	if registry and registry.has_method("register_enemy"):
		registry.register_enemy(self, 2)
	
	# Find the player aircraft
	target_aircraft = get_tree().get_first_node_in_group("aircraft")
	
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
	
	# Calculate direction to target
	var direction = (target_aircraft.global_position - global_position).normalized()
	
	# Create bullet
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position + direction * 2.0  # Spawn slightly in front
	
	# Fire bullet towards target
	var bullet_velocity = direction * 100.0  # Adjust speed as needed
	bullet.fire(bullet_velocity, self)
	
	print("Enemy fired at aircraft!")

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








