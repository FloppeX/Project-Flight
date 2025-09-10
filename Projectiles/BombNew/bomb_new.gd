extends ProjectileNew
class_name BombProjectile

# =============================================================================
# BOMB PROJECTILE - Specialized bomb with arming delay
# =============================================================================

@export var arming_delay: float = 1.0  # Seconds before bomb can explode
@export var armed: bool = false

var arming_timer: float = 0.0
var status_label: Label3D

func _ready():
	super._ready()
	# Override the base class collision detection
	body_entered.disconnect(_on_body_entered)
	body_entered.connect(_on_bomb_body_entered)
	
	# Create status label for visual feedback
	create_status_label()

func create_status_label():
	"""Create a 3D label to show bomb status"""
	status_label = Label3D.new()
	status_label.text = "ARMING..."
	status_label.font_size = 24
	status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status_label.modulate = Color.RED
	status_label.position = Vector3(0, 1, 0)  # Above the bomb
	add_child(status_label)

func _physics_process(delta):
	# Update arming timer
	if not armed:
		arming_timer += delta
		if arming_timer >= arming_delay:
			arm_bomb()
		else:
			# Update status label with countdown
			if status_label:
				var time_remaining = arming_delay - arming_timer
				status_label.text = "ARMING... " + str(int(time_remaining * 10) / 10.0)
	
	# Call parent physics process for tunneling detection
	super._physics_process(delta)

func arm_bomb():
	"""Arm the bomb after the delay"""
	armed = true
	if status_label:
		status_label.text = "ARMED"
		status_label.modulate = Color.GREEN

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
