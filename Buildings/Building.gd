extends StaticBody3D
class_name Building

signal destroyed(building)
signal damaged(amount, current_health)

@export var max_health: float = 150.0
@export var destroyed_scene_path: String = ""
@export var team: int = 2

var _explosion_scene: PackedScene = null
var current_health: float
var is_destroyed: bool = false

func _ready() -> void:
	current_health = max_health
	_explosion_scene = load("res://Projectiles/Explosion/explosion.tscn")
	add_to_group("enemies")
	add_to_group("buildings")
	add_to_group("team_" + str(team))

func get_team() -> int:
	return team

func take_damage(damage_amount: float) -> void:
	if is_destroyed:
		return
	current_health -= damage_amount
	current_health = maxf(current_health, 0.0)
	damaged.emit(damage_amount, current_health)
	if current_health <= 0.0:
		_destroy()

func _destroy() -> void:
	is_destroyed = true
	destroyed.emit(self)

	# Spawn destroyed version
	if destroyed_scene_path != "":
		var destroyed_scene: PackedScene = load(destroyed_scene_path)
		if destroyed_scene:
			var wreck := destroyed_scene.instantiate()
			get_tree().current_scene.add_child(wreck)
			wreck.global_transform = global_transform

			# Add smoking ruins effect
			_add_ruin_smoke(wreck)

	# Spawn explosion
	if _explosion_scene:
		var exp: Node3D = _explosion_scene.instantiate()
		get_tree().current_scene.add_child(exp)
		exp.global_position = global_position + Vector3(0, 2.0, 0)

	queue_free()

func _add_ruin_smoke(wreck: Node3D) -> void:
	# Spawn a few black smoke columns that rise from the ruins
	var smoke_timer := Timer.new()
	wreck.add_child(smoke_timer)
	smoke_timer.wait_time = 1.5
	smoke_timer.autostart = true

	var smoke_count: int = 0
	var max_smoke: int = 40
	var wreck_pos := wreck.global_position

	smoke_timer.timeout.connect(func():
		if not is_instance_valid(wreck):
			smoke_timer.queue_free()
			return
		smoke_count += 1
		if smoke_count > max_smoke:
			smoke_timer.queue_free()
			return

		var puff := MeshInstance3D.new()
		get_tree().current_scene.add_child(puff)
		puff.global_position = wreck.global_position + Vector3(
			randf_range(-2.0, 2.0),
			randf_range(1.0, 3.0),
			randf_range(-2.0, 2.0)
		)

		var sphere := SphereMesh.new()
		sphere.radial_segments = 4
		sphere.rings = 2
		sphere.radius = 1.0
		sphere.height = 2.0
		puff.mesh = sphere

		var s: float = randf_range(0.8, 1.5)
		puff.scale = Vector3(s, s, s)

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var grey: float = randf_range(0.05, 0.15)
		mat.albedo_color = Color(grey, grey, grey, 0.4)
		puff.material_override = mat

		var particle_manager := get_node_or_null("/root/ParticleManager")
		if particle_manager and particle_manager.has_method("add_rising_smoke"):
			particle_manager.call(
				"add_rising_smoke",
				puff,
				randf_range(4.0, 6.0),
				puff.scale,
				randf_range(3.0, 5.0),
				randf_range(-0.3, 0.3)
			)
	)
