extends ProjectileNew
class_name BombProjectile

# =============================================================================
# BOMB PROJECTILE - Specialized bomb with arming delay
# =============================================================================

@export var arming_delay: float = 1.0  # Seconds before bomb can explode
@export var armed: bool = false
@export var explosion_blast_radius: float = 50.0

var arming_timer: float = 0.0

func _ready():
	super._ready()
	# Override the base class collision detection
	body_entered.disconnect(_on_body_entered)
	body_entered.connect(_on_bomb_body_entered)

func _physics_process(delta):
	# Update arming timer
	if not armed:
		arming_timer += delta
		if arming_timer >= arming_delay:
			arm_bomb()
	
	# Call parent physics process for tunneling detection
	super._physics_process(delta)

func arm_bomb():
	"""Arm the bomb after the delay"""
	armed = true

func _on_bomb_body_entered(body):
	"""Handle bomb collision with arming check"""
	if body == shooter:
		return  # Don't hit the aircraft that dropped us
	
	# Only explode if armed
	if not armed:
		# Still apply some damage even if not armed (dud bomb)
		if body.has_method("take_damage"):
			body.take_damage(damage * 0.1)  # Reduced damage for unarmed bomb
		queue_free()
		return
	
	# Determine if we hit the ground/terrain for scorch mark
	var hit_ground = is_ground_or_terrain(body)
	
	# Create explosion effect
	if creates_explosion and explosion_scene:
		var explosion = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = global_position
		# Apply configured blast radius if compatible
		if explosion is Explosion:
			(explosion as Explosion).blast_radius = explosion_blast_radius
		
		# Create scorch mark if we hit the ground
		if hit_ground:
			explosion.create_scorch_mark()
	
	# Fallback to old impact effect if no explosion
	elif impact_effect:
		var effect = impact_effect.instantiate()
		get_tree().current_scene.add_child(effect)
		effect.global_position = global_position
	
	# Apply full damage if target has health
	if body.has_method("take_damage"):
		body.take_damage(damage)
	
	queue_free()

func get_arming_status() -> Dictionary:
	"""Get bomb arming status for UI display"""
	return {
		"armed": armed,
		"arming_progress": arming_timer / arming_delay if arming_delay > 0 else 1.0,
		"time_remaining": max(0.0, arming_delay - arming_timer)
	}
