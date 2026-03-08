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

var current_health: float
var turret_node: Node3D
var weapon_instance: Weapon
var current_target: Node3D
var is_dying: bool = false

# --- Movement ---
var _target_throttle: float = 0.0
var _target_steering: float = 0.0
var _braking: bool = false

# --- Burst firing ---
enum FireState { IDLE, BURSTING, DELAYING }
var fire_state: FireState = FireState.IDLE
var burst_timer: float = 0.0
var delay_timer: float = 0.0
var is_firing: bool = false

var target_search_timer: float = 0.0

func _ready() -> void:
	current_health = max_health
	add_to_group("enemies")
	add_to_group("team_" + str(team))
	create_turret()
	if turret_weapon and turret_node:
		mount_weapon_on_turret(turret_weapon)

func _physics_process(delta: float) -> void:
	if is_dying:
		return

	engine_force = _target_throttle * max_engine_force
	brake = max_brake_force if _braking else 0.0
	steering = move_toward(steering, _target_steering * max_steering_angle, steering_speed * delta)

	target_search_timer += delta
	update_turret(delta)

# --- AI interface ---

func set_throttle(value: float) -> void:
	_target_throttle = clamp(value, -1.0, 1.0)

func set_steering(value: float) -> void:
	_target_steering = clamp(value, -1.0, 1.0)

func set_brake(value: bool) -> void:
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

# --- Turret ---

func create_turret() -> void:
	turret_node = Node3D.new()
	turret_node.name = "Turret"
	add_child(turret_node)
	# Box half-height is 0.5, center offset is 0.5 → top at y=1.0
	turret_node.position = Vector3(0, 1.1, 0)

	var barrel_mesh = CylinderMesh.new()
	barrel_mesh.height = 2.0
	barrel_mesh.top_radius = 0.1
	barrel_mesh.bottom_radius = 0.1

	var barrel_instance = MeshInstance3D.new()
	barrel_instance.name = "Barrel"
	barrel_instance.mesh = barrel_mesh
	turret_node.add_child(barrel_instance)

	var turret_material = StandardMaterial3D.new()
	turret_material.albedo_color = Color(0.25, 0.25, 0.25, 1)
	barrel_instance.material_override = turret_material

	barrel_instance.position = Vector3(0, 0, 1.0)
	barrel_instance.rotation_degrees = Vector3(90, 0, 0)

func mount_weapon_on_turret(weapon_scene: PackedScene) -> void:
	if weapon_instance:
		weapon_instance.queue_free()

	var turret_mount = TurretMount.new()
	turret_mount.ground_vehicle = self
	turret_node.add_child(turret_mount)

	weapon_instance = weapon_scene.instantiate()
	turret_mount.add_child(weapon_instance)
	turret_mount.weapon_instance = weapon_instance
	turret_mount.position = Vector3(0, 0, 1.0)

func update_turret(delta: float) -> void:
	if not turret_node:
		return

	if target_search_timer >= 1.0:
		current_target = find_best_target()
		target_search_timer = 0.0

	if current_target and is_instance_valid(current_target):
		track_target(current_target)
		update_burst_firing(delta)
	else:
		stop_firing()
		fire_state = FireState.IDLE

func update_burst_firing(delta: float) -> void:
	match fire_state:
		FireState.IDLE:
			start_burst()
		FireState.BURSTING:
			burst_timer += delta
			if burst_timer >= burst_length:
				stop_firing()
				fire_state = FireState.DELAYING
				delay_timer = 0.0
			else:
				fire_at_target(current_target)
		FireState.DELAYING:
			delay_timer += delta
			if delay_timer >= delay_length:
				fire_state = FireState.IDLE

func start_burst() -> void:
	fire_state = FireState.BURSTING
	burst_timer = 0.0
	is_firing = true

func stop_firing() -> void:
	is_firing = false
	if weapon_instance and weapon_instance.has_method("stop_firing"):
		weapon_instance.stop_firing()

func find_best_target() -> Node3D:
	var best_target: Node3D = null
	var best_distance = turret_range
	for enemy in _get_hostile_targets_in_range(turret_range):
		var distance = global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best_target = enemy
			best_distance = distance
	return best_target

func _get_hostile_targets_in_range(max_range: float) -> Array:
	var results: Array = []
	var seen: Dictionary = {}
	for group_name in ["aircraft", "enemies", "friendlies", "ai_aircraft"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is Node3D) or node == self or not is_instance_valid(node):
				continue
			if not node.has_method("get_team"):
				continue
			if int(node.get_team()) == team:
				continue
			var id: int = node.get_instance_id()
			if seen.has(id):
				continue
			if global_position.distance_to((node as Node3D).global_position) <= max_range:
				seen[id] = true
				results.append(node)
	return results

func track_target(target: Node3D) -> void:
	if not target or not turret_node:
		return
	var target_pos = calculate_lead_position(target)
	var direction = (target_pos - turret_node.global_position).normalized()
	if direction.length() > 0:
		turret_node.look_at(turret_node.global_position + direction, Vector3.UP)

func calculate_lead_position(target: Node3D) -> Vector3:
	var target_pos = target.global_position
	var target_velocity = Vector3.ZERO
	if target.has_method("get_linear_velocity"):
		target_velocity = target.get_linear_velocity()
	elif "linear_velocity" in target:
		target_velocity = target.linear_velocity

	var distance = global_position.distance_to(target_pos)
	var flight_time = distance / 600.0
	var lead_position = target_pos + (target_velocity * flight_time)

	if aim_skill < 1.0:
		var spread = (1.0 - aim_skill) * 15.0
		lead_position += Vector3(
			randf_range(-spread, spread),
			randf_range(-spread * 0.3, spread * 0.3),
			randf_range(-spread, spread)
		)
	return lead_position

func fire_at_target(target: Node3D) -> void:
	if not weapon_instance or not turret_node:
		return

	var target_pos = calculate_lead_position(target)
	var fire_direction = (target_pos - turret_node.global_position).normalized()
	if fire_direction.length() > 0:
		var up = Vector3.UP
		var right = fire_direction.cross(up).normalized()
		up = right.cross(fire_direction).normalized()
		turret_node.global_transform.basis = Basis(right, up, fire_direction)

	if weapon_instance.can_fire():
		weapon_instance.fire()

# --- Inner class: turret weapon mount ---

class TurretMount extends Hardpoint:
	var ground_vehicle: GroundVehicle

	func _ready() -> void:
		call_deferred("_set_aircraft_reference")

	func get_aircraft() -> Node3D:
		return ground_vehicle

	func get_aircraft_velocity() -> Vector3:
		if ground_vehicle:
			return ground_vehicle.linear_velocity
		return Vector3.ZERO

	func apply_recoil_force(_force_magnitude: float) -> void:
		pass

	func _set_aircraft_reference() -> void:
		if ground_vehicle:
			set("aircraft", ground_vehicle)

	func _get(property: StringName):
		if property == "aircraft":
			return ground_vehicle
		return null

	func _set(property: StringName, _value) -> bool:
		if property == "aircraft":
			return true
		return false
