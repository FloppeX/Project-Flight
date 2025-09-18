extends Weapon
class_name AGMissileLauncher

@export var missile_scene: PackedScene
@export var fire_cooldown: float = 1.0
@export var max_ammo: int = 2
@export var hide_visual_on_fire: bool = true

var hardpoint: Hardpoint
var last_fire_time: float = 0.0
@onready var missile_visual: Node3D = get_node_or_null("MissileVisual")

func _ready():
	hardpoint = get_parent() as Hardpoint
	# Sanitize serialized values from scene instances
	if typeof(max_ammo) != TYPE_INT or max_ammo <= 0:
		max_ammo = 2
	if typeof(ammo_count) != TYPE_INT or ammo_count <= 0:
		ammo_count = max_ammo
	if typeof(fire_cooldown) != TYPE_FLOAT or fire_cooldown <= 0.0:
		fire_cooldown = 1.0
	weapon_name = "AGMissile"
	automatic_fire = false

func can_fire() -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	if ammo_count <= 0:
		return false
	if (current_time - last_fire_time) < fire_cooldown:
		return false
	return true

func fire() -> bool:
	if not can_fire():
		print("[AGMissileLauncher] Cannot fire: ammo=", ammo_count, " cooldown=", fire_cooldown)
		return false
	last_fire_time = Time.get_ticks_msec() / 1000.0
	if not missile_scene:
		if not _ensure_missile_scene():
			return false
	
	# Instantiate missile (avoid relying on global class)
	var missile = missile_scene.instantiate()
	get_tree().current_scene.add_child(missile)
	
	# Align missile with hardpoint orientation and position
	if hardpoint:
		var hp_tr: Transform3D = hardpoint.global_transform
		var hp_rot: Basis = hp_tr.basis.orthonormalized()
		var src_basis: Basis = missile.global_basis
		var src_rot: Basis = src_basis.orthonormalized()
		var src_scale: Vector3 = src_basis.get_scale()
		var final_basis: Basis = hp_rot * src_rot
		final_basis = final_basis.scaled(src_scale)
		missile.global_transform = Transform3D(final_basis, hp_tr.origin)
	else:
		missile.global_position = global_position
		missile.global_basis = Basis.IDENTITY
		missile.scale = Vector3.ONE

	# Get aircraft and target
	var aircraft_node: Node = get_parent()
	while aircraft_node and not (aircraft_node is RigidBody3D):
		aircraft_node = aircraft_node.get_parent()
	var aircraft: RigidBody3D = aircraft_node as RigidBody3D

	# Find targeting module for current target
	var targeting: Node = null
	if aircraft:
		targeting = aircraft.find_child("ControlTargeting", true, false)
	
	var target_node: Node3D = null
	if targeting and "current_target" in targeting:
		target_node = targeting.current_target

	# Initial velocity: inherit some aircraft velocity
	var initial_velocity: Vector3 = aircraft.linear_velocity if aircraft else Vector3.ZERO
	if missile and missile.has_method("fire_with_target"):
		missile.fire_with_target(initial_velocity, aircraft, target_node)
	elif missile and missile.has_method("fire"):
		missile.fire(initial_velocity, aircraft)
	else:
		print("[AGMissileLauncher] WARNING: Missile instance has no fire methods")
	
	ammo_count -= 1
	print("[AGMissileLauncher] Fired missile. Remaining ammo=", ammo_count)
	if hide_visual_on_fire and missile_visual and missile_visual.visible:
		missile_visual.visible = false
	if delete_when_empty and ammo_count <= 0:
		queue_free()
	return true

func _ensure_missile_scene() -> bool:
	var candidates: Array[String] = [
		"res://Projectiles/AG Missile/ag_missile.tscn",
		"res://Projectiles/AG Missile/ag_missile_projectile.tscn"
	]
	for p in candidates:
		if ResourceLoader.exists(p):
			var s = load(p) as PackedScene
			if s:
				missile_scene = s
				print("[AGMissileLauncher] Loaded missile scene: ", p)
				return true
	print("[AGMissileLauncher] ERROR: No valid missile scene found in candidates")
	return false
