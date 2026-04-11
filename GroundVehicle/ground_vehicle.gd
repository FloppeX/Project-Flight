extends VehicleBody3D
class_name GroundVehicle

signal destroyed(vehicle)

@export var max_engine_force: float = 800.0
@export var max_brake_force: float = 40.0
@export var max_steering_angle: float = 0.5  # radians (~28 degrees)
@export var steering_speed: float = 3.0

# Combat
@export var max_health: float = 80.0
@export var team: int = 2
@export var turret_range: float = 400.0
@export var burst_length: float = 1.5
@export var delay_length: float = 3.0
@export var turret_weapon: PackedScene
@export var aim_skill: float = 0.75
@export var explosion_scene: PackedScene

var turret_controller: TurretController
var current_health: float
var is_dying: bool = false

# --- Movement ---
var _target_throttle: float = 0.0
var _target_steering: float = 0.0
var _braking: bool = false

func _ready() -> void:
	current_health = max_health
	add_to_group("enemies") # Default
	add_to_group("team_" + str(team))
	var livery_node: Node = get_node_or_null("/root/Livery")
	if livery_node != null and livery_node.has_method("apply"):
		livery_node.call("apply", self)
	
	# Look for a turret controller child
	for child in get_children():
		if child is TurretController:
			turret_controller = child
			break
			
	if not turret_controller:
		push_warning("GroundVehicle: No TurretController found as child!")

func _physics_process(delta: float) -> void:
	if is_dying:
		return

	engine_force = _target_throttle * max_engine_force
	brake = max_brake_force if _braking else 0.0
	steering = move_toward(steering, _target_steering * max_steering_angle, steering_speed * delta)
	
	# Turret logic is now handled autonomously by the TurretController component

# --- AI interface ---

func set_throttle(value: float) -> void:
	_target_throttle = clamp(value, -1.0, 1.0)

func set_ai_steering(value: float) -> void:
	_target_steering = clamp(value, -1.0, 1.0)

func set_ai_brake(value: bool) -> void:
	_braking = value

func stop() -> void:
	_target_throttle = 0.0
	_braking = true

func get_speed() -> float:
	return linear_velocity.length()

func get_team() -> int:
	return team

# --- Combat ---

func take_damage(damage_amount: float) -> void:
	if is_dying or current_health <= 0:
		return
	current_health -= damage_amount
	current_health = max(current_health, 0.0)
	if current_health <= 0:
		is_dying = true
		var death_timer = Timer.new()
		death_timer.wait_time = randf_range(0.0, 0.8)
		death_timer.one_shot = true
		death_timer.timeout.connect(explode)
		death_timer.timeout.connect(death_timer.queue_free)
		add_child(death_timer)
		death_timer.start()

func explode() -> void:
	emit_signal("destroyed", self)
	var explosion_res = load("res://Projectiles/Explosion/explosion.tscn")
	if explosion_res:
		var exp = explosion_res.instantiate()
		get_parent().add_child(exp)
		exp.global_position = global_position
	queue_free()
