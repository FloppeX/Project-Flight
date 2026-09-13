extends Node3D

class AircraftFixture:
	extends Aircraft
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _process(_delta: float) -> void: pass
	func _get_ground_height_at_position(_pos: Vector3) -> float: return 0.0

class WeaponFixture:
	extends Node3D
	var weapon_name := "Rocket Pod"
	var muzzle_velocity := 220.0
	var rocket_scene := preload("res://Projectiles/Rocket/rocket.tscn")

class HardpointFixture:
	extends Node3D
	var weapon_instance: Node3D

class WeaponsFixture:
	extends Node3D
	var hardpoints: Array = []

class RocketFixture:
	extends RocketProjectile
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass

var checks := 0
var failures := 0

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _shape(body: CollisionObject3D, size: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var craft := AircraftFixture.new()
	craft.freeze = true
	craft.position = Vector3(0, 300, 0)
	craft.rotation.x = 0.2
	add_child(craft)
	var controls := WeaponsFixture.new()
	controls.name = "ControlWeapons"
	craft.add_child(controls)
	controls.owner = craft
	var mount := HardpointFixture.new()
	controls.add_child(mount)
	mount.weapon_instance = WeaponFixture.new()
	mount.add_child(mount.weapon_instance)
	controls.hardpoints.append(mount)
	await get_tree().physics_frame
	var clear := craft.calculate_rocket_ccip_impact_point()
	_check(clear.has_impact and absf(clear.impact_position.y) < 0.01,
		"Clear rocket prediction reaches the ground")
	var preceding := RocketFixture.new()
	preceding.freeze = true
	preceding.position = Vector3(0, 279, 100)
	_shape(preceding, Vector3(5, 10, 5))
	add_child(preceding)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var cluttered := craft.calculate_rocket_ccip_impact_point()
	_check(cluttered.has_impact and cluttered.impact_position.is_equal_approx(clear.impact_position),
		"A preceding rocket cannot move the shared sight off its ground impact")
	craft.rocket_ccip_ignore_projectiles = false
	var legacy := craft.calculate_rocket_ccip_impact_point()
	_check(legacy.hit_body == preceding, "Comparison reproduces the old near-muzzle projectile obstruction")
	craft.rocket_ccip_ignore_projectiles = true
	var wall := StaticBody3D.new()
	wall.position = preceding.position
	_shape(wall, Vector3(5, 10, 1))
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var blocked := craft.calculate_rocket_ccip_impact_point()
	_check(blocked.hit_body == wall, "A real obstacle behind a skipped rocket still blocks the prediction")
	_check(preceding.collision_layer == 1 and preceding.collision_mask == 1,
		"Prediction filtering does not change physical projectile collision layers")
	wall.queue_free()
	preceding.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var removed := craft.calculate_rocket_ccip_impact_point()
	_check(removed.has_impact and removed.impact_position.is_equal_approx(clear.impact_position),
		"Freed projectiles and obstacles leave no stale prediction state")
	print("ROCKET_CCIP_SALVO_SMOKETEST checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
