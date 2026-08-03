extends RigidBody3D
class_name AircraftDebrisChunk

@export var smoke_interval_s: float = 0.18
@export var smoke_lifetime_s: float = 1.6
@export var max_lifetime_s: float = 20.0
@export var smoke_enabled: bool = true

var _smoke_timer_s: float = 0.0
var _life_timer_s: float = 0.0
var _ground_hit: bool = false

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = maxi(max_contacts_reported, 4)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if _ground_hit or not is_inside_tree() or is_queued_for_deletion():
		return
	_life_timer_s += delta
	if _life_timer_s >= max_lifetime_s:
		queue_free()
		return
	if not smoke_enabled:
		return
	_smoke_timer_s -= delta
	if _smoke_timer_s <= 0.0:
		_smoke_timer_s = maxf(smoke_interval_s, 0.05)
		_emit_smoke_puff()

func _on_body_entered(body: Node) -> void:
	if _ground_hit:
		return
	if _is_ground_or_terrain(body):
		_ground_hit = true
		queue_free()

func _is_ground_or_terrain(body: Node) -> bool:
	if body == null:
		return false
	if body.is_in_group("terrain") or body.is_in_group("ground") or body.is_in_group("runway_surface"):
		return true
	var body_name: String = body.name.to_lower()
	if "terrain" in body_name or "ground" in body_name:
		return true
	if body is StaticBody3D:
		return true
	return false

func _emit_smoke_puff() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not ParticleManager:
		return
	var smoke_position: Vector3 = global_position
	if get_tree().current_scene == null:
		return
	ParticleManager.spawn_managed_smoke(
		smoke_position,
		Vector3.ONE * randf_range(0.12, 0.26),
		Color(0.18, 0.18, 0.18, 0.55),
		smoke_lifetime_s,
		randf_range(0.4, 1.1),
		randf_range(-0.5, 0.5),
		true,
		"box",
		0.0,
		false
	)
