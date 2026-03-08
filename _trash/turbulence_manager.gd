extends Node3D
class_name TurbulenceManager

@export var turbulence_scene: PackedScene  # Drag TurbulenceVolume scene here
@export var spawn_interval_min: float = 5.0
@export var spawn_interval_max: float = 15.0
@export var spawn_area_size: Vector3 = Vector3(2000, 500, 2000)
@export var max_turbulence_count: int = 10
@export var intensity_range: Vector2 = Vector2(0.5, 2.0)

var spawn_timer: float = 0.0
var next_spawn_time: float = 5.0
var active_turbulence: Array = []

func _ready():
	# Set initial spawn time
	next_spawn_time = randf_range(spawn_interval_min, spawn_interval_max)

func _process(delta):
	spawn_timer += delta
	
	# Clean up destroyed turbulence from array
	active_turbulence = active_turbulence.filter(func(t): return is_instance_valid(t))
	
	# Spawn new turbulence if needed
	if spawn_timer >= next_spawn_time and active_turbulence.size() < max_turbulence_count:
		spawn_turbulence()
		spawn_timer = 0.0
		next_spawn_time = randf_range(spawn_interval_min, spawn_interval_max)

func spawn_turbulence():
	if not turbulence_scene:
		return
	
	var turbulence = turbulence_scene.instantiate() as TurbulenceVolume
	add_child(turbulence)
	
	# Random spawn position
	turbulence.global_position = global_position + Vector3(
		randf_range(-spawn_area_size.x/2, spawn_area_size.x/2),
		randf_range(50, spawn_area_size.y),  # Above ground
		randf_range(-spawn_area_size.z/2, spawn_area_size.z/2)
	)
	
	# Random properties
	turbulence.intensity = randf_range(intensity_range.x, intensity_range.y)
	turbulence.movement_speed = Vector3(
		randf_range(2, 8),
		randf_range(-1, 1),
		randf_range(2, 8)
	)
	
	active_turbulence.append(turbulence)
	
	print("Spawned turbulence at ", turbulence.global_position, " with intensity ", turbulence.intensity)
