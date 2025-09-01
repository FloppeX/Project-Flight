extends RigidBody3D
class_name Projectile

@export var damage: float = 10.0
@export var lifetime: float = 5.0
@export var impact_effect: PackedScene  # Explosion/impact visual

var shooter: Node3D  # Reference to whoever fired this

func _ready():
	# Auto-destroy after lifetime
	get_tree().create_timer(lifetime).timeout.connect(_on_timeout)
	
	# Connect collision detection
	body_entered.connect(_on_body_entered)

func fire(initial_velocity: Vector3, firing_aircraft: Node3D):
	shooter = firing_aircraft
	linear_velocity = initial_velocity
	# Inherit some of the aircraft's velocity for realistic ballistics
	linear_velocity += firing_aircraft.linear_velocity * 0.5

func _on_body_entered(body):
	if body == shooter:
		return  # Don't hit the aircraft that fired us
	
	# Create impact effect
	if impact_effect:
		var effect = impact_effect.instantiate()
		get_tree().current_scene.add_child(effect)
		effect.global_position = global_position
	
	# Apply damage if target has health
	if body.has_method("take_damage"):
		body.take_damage(damage)
	
	queue_free()

func _on_timeout():
	queue_free()
