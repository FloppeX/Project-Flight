extends Weapon
class_name AAMissileLauncher

@export var missile_scene: PackedScene
@export var fire_cooldown: float = 1.0
@export var max_ammo: int = 2
@export var hide_visual_on_fire: bool = true

var hardpoint: Hardpoint
var last_fire_time: float = 0.0
var last_fired_missile: Node3D = null
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
	weapon_name = "AAMissile"
	automatic_fire = false

func can_fire() -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	if ammo_count <= 0:
		return false
	if (current_time - last_fire_time) < fire_cooldown:
		return false
		
	# Verify AAM locking via targeting module
	var aircraft_node: Node = get_parent()
	while aircraft_node and not (aircraft_node is RigidBody3D):
		aircraft_node = aircraft_node.get_parent()
		
	if aircraft_node:
		var targeting = aircraft_node.find_child("ControlTargeting_AAM", true, false)
		if targeting and targeting.has_method("get_target_lock_time"):
			var required_lock_time: float = 3.0
			if "required_lock_time" in targeting:
				required_lock_time = maxf(float(targeting.required_lock_time), 0.0)
			if targeting.get_target_lock_time() < required_lock_time:
				return false
			# Also need a target
			var raw_target = targeting.get("current_target")
			if not is_instance_valid(raw_target):
				return false
		else:
			# No AAM targeting module — can't fire
			return false
	return true

func fire() -> bool:
	if not can_fire():
		print("[AAMissileLauncher] Cannot fire: ammo=", ammo_count, " cooldown=", fire_cooldown)
		return false
	last_fire_time = Time.get_ticks_msec() / 1000.0
	if not missile_scene:
		if not _ensure_missile_scene():
			return false
	
	# Instantiate missile (avoid relying on global class)
	var missile = missile_scene.instantiate()
	get_tree().current_scene.add_child(missile)
	last_fired_missile = missile as Node3D
	
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

	# Get aircraft and target (mostly already checked in can_fire, but repeated for setup)
	var aircraft_node: Node = get_parent()
	while aircraft_node and not (aircraft_node is RigidBody3D):
		aircraft_node = aircraft_node.get_parent()
	var aircraft: RigidBody3D = aircraft_node as RigidBody3D

	# Find AAM targeting module for current target
	var targeting: Node = null
	if aircraft:
		targeting = aircraft.find_child("ControlTargeting_AAM", true, false)
	
	var target_node: Node3D = null
	if targeting:
		var raw = targeting.get("current_target")
		if is_instance_valid(raw):
			target_node = raw as Node3D

	# Initial velocity: inherit some aircraft velocity
	var initial_velocity: Vector3 = aircraft.linear_velocity if aircraft else Vector3.ZERO
	if missile and missile.has_method("fire_with_target"):
		missile.fire_with_target(initial_velocity, aircraft, target_node)
	elif missile and missile.has_method("fire"):
		missile.fire(initial_velocity, aircraft)
	else:
		print("[AAMissileLauncher] WARNING: Missile instance has no fire methods")
	
	# Trigger missile camera tracking on instrument panel
	_start_missile_camera_tracking(missile, aircraft)
	
	ammo_count -= 1
	print("[AAMissileLauncher] Fired missile. Remaining ammo=", ammo_count)
	if hide_visual_on_fire and missile_visual and missile_visual.visible:
		missile_visual.visible = false
	if delete_when_empty and ammo_count <= 0:
		queue_free()
	return true

func _start_missile_camera_tracking(missile: Node3D, aircraft: Node3D) -> void:
	"""Find instrument panel and start missile camera tracking"""
	if not missile or not aircraft:
		return
	
	# Look for instrument panel in the aircraft
	var instrument_panel = aircraft.find_child("InstrumentPanel", true, false)
	if not instrument_panel:
		# Try to find it in the scene tree
		instrument_panel = get_tree().get_first_node_in_group("instrument_panel")
	
	if instrument_panel and instrument_panel.has_method("start_missile_camera_tracking"):
		print("[AAMissileLauncher] Starting missile camera tracking")
		instrument_panel.start_missile_camera_tracking(missile)
	else:
		print("[AAMissileLauncher] Could not find instrument panel for missile camera")

func _ensure_missile_scene() -> bool:
	var candidates: Array[String] = [
		"res://Projectiles/AA Missile/aa_missile.tscn",
		"res://Projectiles/AA Missile/AA_Missile_projectile.tscn"
	]
	for p in candidates:
		if ResourceLoader.exists(p):
			var s = load(p) as PackedScene
			if s:
				missile_scene = s
				return true
	return false
