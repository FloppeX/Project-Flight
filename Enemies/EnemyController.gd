extends Node3D
class_name EnemyController

@export var land_carrier_path: NodePath
@export var enemy_scene: PackedScene
@export var terrain_path: NodePath
@export var enemy_count: int = 10

var _terrain: Node
var _carrier: Node3D

func _ready():
	# Find carrier
	_carrier = get_node_or_null(land_carrier_path) as Node3D
	if _carrier == null:
		_carrier = get_tree().get_first_node_in_group("carrier") as Node3D
	
	# Find terrain
	if terrain_path != NodePath(""):
		_terrain = get_node_or_null(terrain_path)
	if _terrain == null:
		var queue: Array = [get_tree().current_scene]
		while queue.size() > 0 and _terrain == null:
			var cur: Node = queue.pop_front()
			for child in cur.get_children():
				queue.append(child)
				if child.get_class() == "Terrain3D":
					_terrain = child
					break
	
	# Load enemy scene if not set
	if enemy_scene == null:
		enemy_scene = load("res://Enemies/EnemyBox.tscn") as PackedScene
	
	# Spawn enemies
	_spawn_enemies()

func _spawn_enemies():
	if _carrier == null or enemy_scene == null:
		return
	
	var carrier_pos: Vector3 = _carrier.global_position
	
	for i in range(enemy_count):
		# Random position 800-1600m from carrier
		var angle = randf() * TAU  # Random angle in radians
		var distance = randf_range(1600.0, 4800.0)
		var spawn_pos = Vector3(
			carrier_pos.x + cos(angle) * distance,
			0.0,  # Will be set to ground height
			carrier_pos.z + sin(angle) * distance
		)
		
		# Get ground height and place on surface with small clearance
		var ground_height = _get_ground_height(spawn_pos)
		if not is_nan(ground_height):
			spawn_pos.y = ground_height + 0.5  # Add 0.5m clearance above ground
			print("Ground height at ", spawn_pos.x, ",", spawn_pos.z, " = ", ground_height)
		else:
			spawn_pos.y = 0.5  # Fallback to ground level + clearance
			print("WARNING: No ground height found, using ground level: 0.5")
		
		# Create enemy
		var enemy = enemy_scene.instantiate() as Node3D
		
		# Add directly to this node (EnemyController) which is already in the scene tree
		add_child(enemy)
		
		print("Spawned enemy at: ", spawn_pos, " - Enemy name: ", enemy.name, " - Script: ", enemy.get_script())
		
		# Set position after enemy is in tree
		call_deferred("_set_enemy_position", enemy, spawn_pos)

func _get_ground_height(world_pos: Vector3) -> float:
	# Try Terrain3D height lookup first
	if _terrain and _terrain.has_method("get_height"):
		var h = _terrain.get_height(world_pos)
		if not is_nan(h):
			return float(h)
	
	# Try Terrain3D data method
	if _terrain and "data" in _terrain and _terrain.data and _terrain.data.has_method("get_height"):
		var h2 = _terrain.data.get_height(world_pos)
		if not is_nan(h2):
			return float(h2)
	
	# Fallback to raycast with terrain collision layer
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = world_pos + Vector3.UP * 200.0
	var to: Vector3 = world_pos - Vector3.UP * 2000.0
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	# Set collision mask to include terrain layers (1 and 10)
	params.collision_mask = (1 << 0) | (1 << 9)  # Layers 1 and 10
	var hit: Dictionary = space_state.intersect_ray(params)
	if hit and hit.has("position"):
		return float(hit.position.y)
	
	return NAN

func _set_enemy_position(enemy: Node3D, pos: Vector3):
	if enemy and is_instance_valid(enemy):
		enemy.global_position = pos
		print("Set enemy position to: ", pos, " - Actual position: ", enemy.global_position, " - In tree: ", enemy.is_inside_tree())
