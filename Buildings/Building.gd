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
	if is_destroyed:
		return
	is_destroyed = true
	_register_plasteel_salvage("Building ruin salvage", 180.0)
	if team != 1 and not bool(get_meta("suppress_enemy_ops_on_destroy", false)):
		EnemyOpsManager.report_asset_loss(global_position, "building")
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

func _register_plasteel_salvage(label: String, amount: float) -> void:
	register_plasteel_salvage(self, label, amount, team == 1)

static func register_plasteel_salvage(unit: Node3D, label: String, amount: float, known := false) -> void:
	# Restore paths install their saved ruins directly and do not create new material.
	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.has_meta("plasteel_salvage_registered") or unit.is_in_group("runway_surface"):
		return
	var scene := unit.get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://Main_Scene.tscn" or GameSession.has_pending_save_state() or bool(unit.get_meta("suppress_enemy_ops_on_destroy", false)):
		return
	var field := POIManager.get_resource_field()
	var site_key := "building_wreck_%d_%d_%d" % [unit.get_instance_id(), Time.get_ticks_usec(), int(Time.get_unix_time_from_system())]
	if "outpost_id" in unit:
		site_key = "outpost_ruin_%s" % str(unit.get("outpost_id"))
	elif unit.get_parent() != null and "outpost_id" in unit.get_parent():
		site_key = "outpost_ruin_%s_%s" % [str(unit.get_parent().get("outpost_id")), str(unit.name)]
	var source_id: int = field.add_salvage_source(label, _salvage_exterior_position(unit), amount, site_key, known)
	if source_id > 0:
		field.get_source(source_id)["wreck_position"] = unit.global_position
		unit.set_meta("plasteel_salvage_registered", true)

static func _salvage_exterior_position(unit: Node3D) -> Vector3:
	# Put the collection marker beyond the authored footprint, where the arm can
	# reach the loose metal without driving into the ruin's surviving collision.
	var bounds := AABB()
	var have_bounds := false
	for mesh: MeshInstance3D in unit.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var local_bounds: AABB = (unit.global_transform.affine_inverse() * mesh.global_transform) * mesh.mesh.get_aabb()
		bounds = bounds.merge(local_bounds) if have_bounds else local_bounds
		have_bounds = true
	if not have_bounds:
		return unit.global_position + unit.global_basis.z.normalized() * 8.0
	var center := bounds.get_center()
	var candidates: Array[Vector3] = [
		Vector3(bounds.position.x - 6.0, 0.0, center.z),
		Vector3(bounds.end.x + 6.0, 0.0, center.z),
		Vector3(center.x, 0.0, bounds.position.z - 6.0),
		Vector3(center.x, 0.0, bounds.end.z + 6.0),
	]
	var selected := unit.to_global(candidates[0])
	var closest := INF
	for candidate in candidates:
		var at := unit.to_global(candidate)
		if TerrainNavGrid.is_ready() and not TerrainNavGrid.is_low_clear_position(at.x, at.z, 5.0):
			continue
		var distance := at.distance_squared_to(unit.global_position)
		if distance < closest:
			closest = distance
			selected = at
	return selected

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
