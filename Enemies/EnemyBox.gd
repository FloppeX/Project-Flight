extends StaticBody3D
class_name EnemyBox

signal destroyed(enemy)

@export var max_health: float = 50.0
@export var explosion_scene: PackedScene
@export var detection_range: float = 500.0
@export var team: int = 2
@export var turret_range: float = 400.0
@export var burst_length: float = 2.0  # How long to hold trigger (seconds)
@export var delay_length: float = 4.0  # How long to wait between bursts (seconds)
@export var turret_weapon: PackedScene  # Drag weapon scene here (e.g., Autocannon.tscn)
@export var aim_skill: float = 0.8  # Ground turrets are pretty good but not perfect
@export var debug_enabled: bool = false

var current_health: float
var detected_enemies: Array = []
#var original_material: StandardMaterial3D  # Disabled for performance
#var blink_timer: float = 0.0  # Disabled for performance
#var is_blinking: bool = false  # Disabled for performance
var turret_node: Node3D
var weapon_instance: Weapon
var current_target: Node3D
var detection_timer: float = 0.0
var target_search_timer: float = 0.0
var is_dying: bool = false # To prevent multiple explosion calls

# Burst firing system
enum FireState { IDLE, BURSTING, DELAYING }
var fire_state: FireState = FireState.IDLE
var burst_timer: float = 0.0
var delay_timer: float = 0.0
var is_firing: bool = false

func _ready():
	# Initialize health
	current_health = max_health
	
	# Add to enemy group for targeting
	add_to_group("enemies")
	add_to_group("team_" + str(team))
	
	# Store original material for blinking (disabled for performance)
	#var mesh_instance = get_node("MeshInstance3D")
	#if mesh_instance and mesh_instance.material_override:
	#	original_material = mesh_instance.material_override.duplicate()
	
	# Create turret with weapon
	create_turret()
	
	# Mount weapon on turret if provided
	if turret_weapon and turret_node:
		mount_weapon_on_turret(turret_weapon)
	
	if debug_enabled:
		print("Enemy box created with ", max_health, " HP at position: ", global_position, " (Team ", team, ")")

func mount_weapon_on_turret(weapon_scene: PackedScene):
	if weapon_instance:
		weapon_instance.queue_free()
	
	# Create a simple turret mount that acts like a hardpoint
	var turret_mount = TurretMount.new()
	turret_mount.enemy_box = self
	turret_node.add_child(turret_mount)
	
	# Don't set aircraft directly due to type conflicts - TurretMount will handle this
	
	# Mount weapon on the turret mount
	weapon_instance = weapon_scene.instantiate()
	turret_mount.add_child(weapon_instance)
	
	# Store weapon reference in both places for easy access
	turret_mount.weapon_instance = weapon_instance
	
	# Position mount at turret tip
	turret_mount.position = Vector3(0, 0, 1.0)  # 1 meter forward on turret
	
	# Ensure weapon is oriented correctly (may need rotation adjustment)
	# The weapon should fire in the +Z direction of the turret mount
	if debug_enabled:
		print("[EnemyBox] Weapon mounted at position: ", turret_mount.position)
		print("[EnemyBox] Turret Z-axis: ", turret_node.transform.basis.z)
		print("[EnemyBox] Mounted weapon: ", weapon_instance.weapon_name if weapon_instance else "Unknown")

func _physics_process(delta):
	# If dying, do nothing else
	if is_dying:
		return

	# Update timers
	detection_timer += delta
	target_search_timer += delta
	
	# Detection (once per second)
	if detection_timer >= 1.0:
		detect_enemies()
		detection_timer = 0.0
	#update_blinking(delta)  # Disabled for performance
	
	# Turret combat
	update_turret(delta)

func take_damage(damage_amount: float):
	if is_dying or current_health <= 0:
		return  # Already destroyed or in the process of exploding
	
	if debug_enabled:
		print("Enemy box taking damage: ", damage_amount, " HP remaining: ", current_health - damage_amount)
	
	current_health -= damage_amount
	current_health = max(current_health, 0.0)
	
	if current_health <= 0:
		is_dying = true
		# Create a timer for a random delay before exploding
		var death_timer = Timer.new()
		death_timer.wait_time = randf_range(0.0, 1.0)
		death_timer.one_shot = true
		death_timer.timeout.connect(explode)
		add_child(death_timer)
		death_timer.start()
		# Make sure the timer is removed after it's done
		death_timer.timeout.connect(death_timer.queue_free)

func explode():
	if debug_enabled:
		print("Enemy box exploding!")
	emit_signal("destroyed", self)
	
	# Spawn explosion effect
	var explosion_scene_resource = load("res://Projectiles/Explosion/explosion.tscn")
	if explosion_scene_resource:
		var explosion_instance = explosion_scene_resource.instantiate()
		get_parent().add_child(explosion_instance)
		explosion_instance.global_position = global_position
		if debug_enabled:
			print("Enemy explosion spawned at: ", global_position)
	
	# Remove the enemy
	queue_free()

func detect_enemies():
	# Find all hostiles from other teams within detection range.
	detected_enemies = _get_hostile_targets_in_range(detection_range)

func update_blinking(delta):
	# Blinking disabled for performance
	pass

func get_team() -> int:
	return team

func create_turret():
	# Create turret node
	turret_node = Node3D.new()
	turret_node.name = "Turret"
	add_child(turret_node)
	
	# Position turret on top of the box
	turret_node.position = Vector3(0, 1.5, 0)  # 1.5m above center (box is 2m tall)
	
	# Create turret barrel (simple cylinder)
	var barrel_mesh = CylinderMesh.new()
	barrel_mesh.height = 2.0
	barrel_mesh.top_radius = 0.1
	barrel_mesh.bottom_radius = 0.1
	
	var barrel_instance = MeshInstance3D.new()
	barrel_instance.name = "Barrel"
	barrel_instance.mesh = barrel_mesh
	turret_node.add_child(barrel_instance)
	
	# Create turret material (dark gray)
	var turret_material = StandardMaterial3D.new()
	turret_material.albedo_color = Color(0.3, 0.3, 0.3, 1)
	barrel_instance.material_override = turret_material
	
	# Position barrel pointing forward
	barrel_instance.position = Vector3(0, 0, 1.0)  # 1m forward from turret center
	barrel_instance.rotation_degrees = Vector3(90, 0, 0)  # Rotate to point forward

func update_turret(delta):
	if not turret_node:
		return
	
	# Find best target within turret range (once per second)
	if target_search_timer >= 1.0:
		var best_target = find_best_target()
		current_target = best_target
		target_search_timer = 0.0
	
	if current_target and is_instance_valid(current_target):
		# Track target
		track_target(current_target)
		
		# Update burst firing state machine
		update_burst_firing(delta)
	else:
		# No target - stop firing and reset to idle
		stop_firing()
		fire_state = FireState.IDLE

func update_burst_firing(delta):
	match fire_state:
		FireState.IDLE:
			# Start a new burst
			start_burst()
			
		FireState.BURSTING:
			# Continue firing for burst_length seconds
			burst_timer += delta
			if burst_timer >= burst_length:
				# Burst complete - enter delay phase
				stop_firing()
				fire_state = FireState.DELAYING
				delay_timer = 0.0
				if debug_enabled:
					print("[EnemyBox] Burst complete, entering delay phase")
			else:
				# Keep firing during burst
				fire_at_target(current_target)
				
		FireState.DELAYING:
			# Wait for delay_length seconds before next burst
			delay_timer += delta
			if delay_timer >= delay_length:
				# Delay complete - ready for next burst
				fire_state = FireState.IDLE
				if debug_enabled:
					print("[EnemyBox] Delay complete, ready for next burst")

func start_burst():
	fire_state = FireState.BURSTING
	burst_timer = 0.0
	is_firing = true
	if debug_enabled:
		print("[EnemyBox] Starting burst - will fire for ", burst_length, " seconds")

func stop_firing():
	is_firing = false
	# Tell weapon to stop firing if it supports it
	if weapon_instance and weapon_instance.has_method("stop_firing"):
		weapon_instance.stop_firing()

func find_best_target() -> Node3D:
	var best_target: Node3D = null
	var best_distance = turret_range
	var hostiles: Array = _get_hostile_targets_in_range(turret_range)
	for enemy in hostiles:
		var distance = global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best_target = enemy
			best_distance = distance
	
	return best_target

func _get_hostile_targets_in_range(max_range: float) -> Array:
	"""Collect unique hostile Node3D targets across relevant aircraft groups."""
	var results: Array = []
	var seen: Dictionary = {}
	var groups_to_scan: Array[String] = ["aircraft", "enemies", "friendlies", "ai_aircraft"]
	for group_name in groups_to_scan:
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
			var distance = global_position.distance_to((node as Node3D).global_position)
			if distance <= max_range:
				seen[id] = true
				results.append(node)
	return results

func track_target(target: Node3D):
	if not target or not turret_node:
		return
	
	# Calculate target position with lead
	var target_pos = calculate_lead_position(target)
	
	# Point turret at target
	var direction = (target_pos - turret_node.global_position).normalized()
	if direction.length() > 0:
		# Calculate rotation to look at target
		var look_at_pos = turret_node.global_position + direction
		turret_node.look_at(look_at_pos, Vector3.UP)

func calculate_lead_position(target: Node3D) -> Vector3:
	var target_pos = target.global_position
	var target_velocity = Vector3.ZERO

	if target.has_method("get_linear_velocity"):
		target_velocity = target.get_linear_velocity()
	elif target.has_method("linear_velocity"):
		target_velocity = target.linear_velocity

	var distance = global_position.distance_to(target_pos)
	var bullet_speed = 600.0
	if weapon_instance:
		var spd = weapon_instance.get("bullet_speed")
		if typeof(spd) in [TYPE_FLOAT, TYPE_INT]:
			bullet_speed = maxf(float(spd), 50.0)
	var flight_time = distance / bullet_speed

	# Predict target position with lead
	var lead_position = target_pos + (target_velocity * flight_time)

	# Gravity compensation: bullet drops 0.5*g*t^2 during flight
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	lead_position.y += 0.5 * gravity * flight_time * flight_time

	if aim_skill < 1.0:
		var inaccuracy_range = (1.0 - aim_skill) * 15.0
		lead_position += Vector3(
			randf_range(-inaccuracy_range, inaccuracy_range),
			randf_range(-inaccuracy_range * 0.3, inaccuracy_range * 0.3),
			randf_range(-inaccuracy_range, inaccuracy_range)
		)

	return lead_position

# Simple turret mount that extends Hardpoint for weapons
class TurretMount extends Hardpoint:
	var enemy_box: EnemyBox
	
	func _init():
		# Initialize aircraft reference immediately
		pass
	
	func _ready():
		# Don't call super._ready() to avoid mounted_weapon logic
		# Use a workaround for the aircraft property type conflict
		call_deferred("_set_aircraft_reference")
	
	func get_aircraft() -> Node3D:
		return enemy_box
	
	# Override methods for turret-specific behavior
	func get_aircraft_velocity() -> Vector3:
		return Vector3.ZERO  # Turrets are stationary
	
	func apply_recoil_force(force_magnitude: float):
		# Turrets don't have recoil effects like aircraft
		pass
	
	func _set_aircraft_reference():
		# Workaround for type conflict - use reflection to set the property
		if enemy_box:
			# Try to set the aircraft property using reflection
			var success = false
			if has_method("set"):
				set("aircraft", enemy_box)
				success = true
			
			if success and aircraft == enemy_box:
				if enemy_box.debug_enabled:
					print("[TurretMount] Successfully set aircraft reference to: ", enemy_box.name)
			else:
				if enemy_box.debug_enabled:
					print("[TurretMount] Failed to set aircraft reference - type conflict remains")
	
	# Override property access to return enemy_box when aircraft is accessed
	func _get(property):
		if property == "aircraft":
			return enemy_box
		return null
	
	func _set(property, value):
		if property == "aircraft":
			# Accept the assignment but store in enemy_box reference
			return true
		return false

func fire_at_target(target: Node3D):
	if not weapon_instance or not turret_node:
		if debug_enabled:
			print("[EnemyBox] Cannot fire - no weapon mounted or turret missing")
		return
	
	# Calculate lead position for aiming
	var target_pos = calculate_lead_position(target)
	
	# Aim turret at target position
	var fire_direction = (target_pos - turret_node.global_position).normalized()
	if fire_direction.length() > 0:
		# Create a transform that makes +Z point toward target
		var up = Vector3.UP
		var right = fire_direction.cross(up).normalized()
		up = right.cross(fire_direction).normalized()
		
		# Build basis with +Z pointing toward target
		var new_basis = Basis(right, up, fire_direction)
		turret_node.global_transform.basis = new_basis
	
	# Fire the weapon (let weapon handle its own fire rate)
	if weapon_instance.can_fire() and weapon_instance.fire():
		if debug_enabled:
			var distance = global_position.distance_to(target.global_position)
			var lead_distance = global_position.distance_to(target_pos)
			print("[EnemyBox] Turret fired! Distance: ", distance, "m, Lead: ", lead_distance, "m")
			print("[EnemyBox] Target pos: ", target.global_position)
			print("[EnemyBox] Lead pos: ", target_pos)
			print("[EnemyBox] Turret pos: ", turret_node.global_position)
			print("[EnemyBox] Fire direction: ", fire_direction)
