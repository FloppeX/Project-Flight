extends ProjectileNew
class_name BombProjectile

signal tuning_impact(position: Vector3)
signal tuning_impact_detail(position: Vector3, body: Node)

# =============================================================================
# BOMB PROJECTILE - Specialized bomb with arming delay
# =============================================================================

@export var arming_delay: float = 1.0  # Seconds before bomb can explode
@export var armed: bool = false
@export var explosion_radius: float = 30.0
@export var explosion_damage_multiplier: float = 2.0  # Multiplier for max damage

var arming_timer: float = 0.0
var _debug_elapsed: float = 0.0
var _tuning_impact_emitted: bool = false

func _init():
	# Bombs should keep their release velocity and only curve due to gravity.
	# Set damping at construction time so AI prediction sees the same values.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0

func _ready():
	super._ready()
	mass = 50.0
	damage = 200.0
	if explosion_scene == null:
		explosion_scene = load("res://Projectiles/Explosion/explosion.tscn")
	body_entered.disconnect(_on_body_entered)
	body_entered.connect(_on_body_entered)

func _exit_tree() -> void:
	_emit_tuning_impact(global_position)

func _emit_tuning_impact(position: Vector3, body: Node = null) -> void:
	if _tuning_impact_emitted:
		return
	_tuning_impact_emitted = true
	tuning_impact.emit(position)
	tuning_impact_detail.emit(position, body)

func _physics_process(delta):
	# Update arming timer
	if not armed:
		arming_timer += delta
		if arming_timer >= arming_delay:
			arm_bomb()

	# Debug tracking — prints every 0.5s while the bomb is falling
	if has_meta("_debug_track"):
		_debug_elapsed += delta
		if fmod(_debug_elapsed, 0.5) < delta:
			var speed := linear_velocity.length()
			var dir := linear_velocity.normalized() if speed > 0.01 else Vector3.ZERO
			print("  [bomb t=%.2f]  pos=%s  vel=%.1f m/s  dir=%s" % [
				_debug_elapsed,
				snapped(global_position, Vector3.ONE * 0.1),
				speed,
				snapped(dir, Vector3.ONE * 0.01)
			])

	# Call parent physics process for tunneling detection
	super._physics_process(delta)

func arm_bomb():
	"""Arm the bomb after the delay"""
	armed = true

func _on_body_entered(body):
	if body == shooter:
		return
	if not armed:
		_emit_tuning_impact(global_position, body)
		has_impacted = true
		queue_free()
		return
	_trigger_explosion(body)

func _trigger_explosion(hit_body: Node = null):
	# Debug: report actual vs intended impact
	var impact_pos: Vector3 = global_position
	_emit_tuning_impact(impact_pos, hit_body)
	if has_meta("debug_aim_target"):
		var aim: Vector3 = get_meta("debug_aim_target")
		var predicted: Vector3 = get_meta("debug_predicted_impact", Vector3.ZERO)
		var miss: float = Vector2(impact_pos.x - aim.x, impact_pos.z - aim.z).length()
		print("━━━━ BOMB IMPACT ━━━━")
		print("  actual    pos=", snapped(impact_pos, Vector3.ONE * 0.1))
		print("  target    pos=", snapped(aim, Vector3.ONE * 0.1), "  miss=", snapped(miss, 0.1), "m")
		if predicted != Vector3.ZERO:
			var pred_miss: float = Vector2(impact_pos.x - predicted.x, impact_pos.z - predicted.z).length()
			print("  predicted pos=", snapped(predicted, Vector3.ONE * 0.1), "  predict_err=", snapped(pred_miss, 0.1), "m")

	# Create custom explosion with missile's damage values
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion)

		# Position explosion 1m above ground to avoid line-of-sight issues
		explosion.global_position = impact_pos + Vector3.UP * 1.0

		# Set explosion damage to match missile damage
		explosion.max_damage = damage * explosion_damage_multiplier
		explosion.min_damage = damage * 0.5
		explosion.blast_radius = explosion_radius
		explosion.use_line_of_sight = false
		if explosion is Explosion:
			(explosion as Explosion).visual_preset = Explosion.VisualPreset.HEAVY
		if "source_attacker" in explosion and is_instance_valid(shooter):
			explosion.source_attacker = shooter

		# Always create scorch mark for missile explosions since they detonate near ground
		explosion.create_scorch_mark()

	# Mark as impacted and cleanup
	has_impacted = true
	queue_free()

func get_arming_status() -> Dictionary:
	"""Get bomb arming status for UI display"""
	return {
		"armed": armed,
		"arming_progress": arming_timer / arming_delay if arming_delay > 0 else 1.0,
		"time_remaining": max(0.0, arming_delay - arming_timer)
	}
