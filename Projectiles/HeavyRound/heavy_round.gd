extends Bullet
class_name HeavyRound

@export var explosion_blast_radius: float = 8.0
@export var explosion_max_damage: float = 45.0
@export var explosion_min_damage: float = 14.0
@export var explosion_flash_duration: float = 0.35
@export var explosion_effect_duration: float = 3.0
@export var explosion_debris_count: int = 10
@export var explosion_knockback_impulse_at_center: float = 900.0
@export var explosion_knockback_impulse_at_edge: float = 120.0

func _ready() -> void:
	super._ready()
	damage = damage_amount
	creates_explosion = false
	if explosion_scene == null:
		explosion_scene = load("res://Projectiles/Explosion/explosion.tscn")

func _on_body_entered(body: Node) -> void:
	if has_impacted:
		return
	if body == shooter:
		return

	var damage_target: Node = find_damage_target(body)
	var hit_ground: bool = is_ground_or_terrain(body)
	has_impacted = true

	_spawn_custom_explosion(hit_ground)
	play_impact_sound(body)

	if damage_target and _supports_target_hit_mark(damage_target):
		create_bullet_scorch_mark(damage_target)
	if damage_target and damage_target.has_method("take_damage"):
		damage_target.take_damage(damage)
	queue_free()

func _spawn_custom_explosion(hit_ground: bool) -> void:
	if explosion_scene == null:
		return
	var explosion := explosion_scene.instantiate()
	if not (explosion is Explosion):
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = global_position
		return

	var explosion_node := explosion as Explosion
	get_tree().current_scene.add_child(explosion_node)
	explosion_node.global_position = global_position
	explosion_node.blast_radius = explosion_blast_radius
	explosion_node.max_damage = explosion_max_damage
	explosion_node.min_damage = explosion_min_damage
	explosion_node.flash_duration = explosion_flash_duration
	explosion_node.effect_duration = explosion_effect_duration
	explosion_node.debris_count = explosion_debris_count
	explosion_node.knockback_impulse_at_center = explosion_knockback_impulse_at_center
	explosion_node.knockback_impulse_at_edge = explosion_knockback_impulse_at_edge
	explosion_node.use_line_of_sight = false
	if hit_ground:
		explosion_node.create_scorch_mark()
