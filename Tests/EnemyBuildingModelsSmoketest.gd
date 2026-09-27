extends Node3D

const GUN_SCENE := preload("res://Buildings/gun_emplacement.tscn")
const OUTPOST_SCENE := preload("res://Buildings/building_enemy_outpost.tscn")
const CATALOG := preload("res://Weapons/Turrets/TurretGunCatalog.gd")
var failures: Array[String] = []
var aim_cases := 0
var max_aim_error := 0.0

class Target extends StaticBody3D:
	var health := 1000.0
	func get_team() -> int: return 1
	func take_damage(amount: float) -> void: health -= amount

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _make_gun() -> GunEmplacement:
	var gun := GUN_SCENE.instantiate() as GunEmplacement
	gun.inactive_when_no_targets = false
	gun.set_meta("suppress_enemy_ops_on_destroy", true)
	add_child(gun)
	gun._turret_controller.set_physics_process(false)
	gun._explosion_scene = null
	return gun

func _run() -> void:
	EnemyBaseManager.disable_for_heli_test()
	EnemyOpsManager.set_physics_process(false)
	FloatingOrigin.enabled = false
	var gun := _make_gun()
	var controller := gun._turret_controller
	var rig = controller.turret
	check(gun.get_node("Model").scene_file_path == "res://Models/building - enemy gun emplacement.glb", "production scene uses new GLB")
	check(gun._authored_collisions.size() == 3, "base, turret and holder have collision")
	check(rig.barrel_attachment.get_parent() == rig.yaw_mount, "authored holder hierarchy preserved")
	var base_mesh := gun.get_node("Model/base") as Node3D
	for caliber in [10, 15, 20]:
		controller.gun_profile_override = CATALOG.get_profile(caliber)
		controller.mount_weapon(load("res://Weapons/Turrets/bullet_weapon.tscn"))
		check(rig.mounted_caliber_mm == caliber, "caliber %d mounts authored barrel" % caliber)
		for tilted in [false, true]:
			gun.transform = Transform3D(Basis.from_euler(Vector3(0.15, 1.1, -0.08)), Vector3(10, 15, 5)) if tilted else Transform3D.IDENTITY
			var fixed_base := base_mesh.global_transform
			for azimuth in [-150, -90, 0, 70, 170]:
				for elevation in [-8, 25, 70]:
					var angle := deg_to_rad(float(azimuth))
					var target := gun.to_global(Vector3(sin(angle) * 250, tan(deg_to_rad(float(elevation))) * 250, cos(angle) * 250))
					rig.aim_at_point(target)
					for tick in range(240):
						rig.tick(1.0 / 60.0, target)
					var error: float = rig.get_aim_angle_to_target()
					max_aim_error = maxf(max_aim_error, error)
					aim_cases += 1
					check(error < 0.35, "muzzle tracks target: %d/%d/%d" % [caliber, azimuth, elevation])
					check(base_mesh.global_transform.is_equal_approx(fixed_base), "base remains fixed while turret aims")
					check(rig.barrel_attachment.transform.is_equal_approx(rig.barrel_mount.transform * rig._holder_from_pitch), "holder follows pitch without scale loss")
		var holder_rest: Transform3D = rig.barrel_attachment.transform
		var mount_rest: Transform3D = rig.barrel_mount.transform
		var barrel_rest: Vector3 = rig.mounted_barrel.global_position
		var muzzle_before: Transform3D = rig.get_current_muzzle_transform()
		check(controller.weapon_instance.fire(), "real weapon fires from new rig")
		check(rig.mounted_barrel.global_position.distance_to(barrel_rest - muzzle_before.basis.z.normalized() * caliber * 0.01) < 0.001, "caliber-scaled barrel recoil")
		check(rig.barrel_mount.transform.is_equal_approx(mount_rest) and rig.barrel_attachment.transform.is_equal_approx(holder_rest), "recoil leaves holder and aim pivot fixed")
		var projectile: Node3D = controller.weapon_instance.last_fired_projectile
		# Shared bullet spawning keeps a 2.5 m forward clearance from the muzzle.
		var expected_spawn := muzzle_before.origin + muzzle_before.basis.z.normalized() * 2.5
		check(is_instance_valid(projectile) and projectile.global_position.distance_to(expected_spawn) < 0.01, "round uses actual barrel tip plus shared clearance")
		rig.reset_barrel_recoil()
	gun.transform = Transform3D.IDENTITY
	var target := Target.new()
	target.position = Vector3(0, 2.35, 100)
	var box := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8, 8, 8)
	box.shape = shape
	target.add_child(box)
	add_child(target)
	target.add_to_group("friendlies")
	controller.aim_skill = 1.0
	controller.performance_lod_enabled = false
	controller.multi_rate_tracking_enabled = false
	controller.set_physics_process(true)
	await get_tree().create_timer(3.0).timeout
	controller.set_physics_process(false)
	check(target.health < 1000.0, "AI acquires and damages a real hostile target")
	target.free()
	gun._set_turret_active(false)
	gun._set_full_presence_active(false)
	check(not gun.visible and gun._authored_collisions.all(func(entry): return entry.shape.disabled), "distant emplacement hides and disables collision")
	gun._set_full_presence_active(true)
	check(gun.visible and gun._authored_collisions.all(func(entry): return not entry.shape.disabled), "activation restores authored collision")
	gun.set_meta("managed_enemy_emplacement", true)
	gun.set_meta("enemy_faction_id", 0)
	EnemyBaseManager.emplacements.append(gun)
	gun.take_damage(10000)
	await get_tree().process_frame
	await get_tree().physics_frame
	check(not is_instance_valid(gun), "destroyed live gun leaves scene")
	var wreck: Node3D = get_tree().get_first_node_in_group("building_wrecks")
	check(wreck != null and wreck.get_node("Model").scene_file_path == "res://Models/building - enemy gun emplacement destroyed.glb", "authored emplacement wreck replaces gun")
	check(wreck.find_children("*", "CollisionShape3D", true, false).size() == 1, "emplacement rubble has physical collision")
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 2.8, 10), Vector3(0, 2.8, -10)))
	check(hit.is_empty(), "removed turret leaves no invisible collision")
	var saved: Dictionary = SaveGameManager._decode_json_value(JSON.parse_string(JSON.stringify(SaveGameManager._encode_json_value(EnemyBaseManager.capture_save_state()))))
	check(saved.emplacements.size() == 1 and saved.emplacements[0].is_destroyed, "checkpoint stores wreck without resurrecting live gun")
	wreck.free()
	EnemyBaseManager._spawn_bases_from_save(saved)
	wreck = get_tree().get_first_node_in_group("building_wrecks")
	check(wreck != null and EnemyBaseManager.emplacements.all(func(value): return not is_instance_valid(value)), "checkpoint restores inert wreck")
	check(wreck.get_meta("emplacement_main_color") == saved.emplacements[0].main_color, "wreck paint persists through checkpoint")
	wreck.position = Vector3(10, 0, 0)
	var outpost := OUTPOST_SCENE.instantiate() as EnemyOutpost
	outpost.position = Vector3(25, 0, 0)
	add_child(outpost)
	outpost.set_physics_process(false)
	outpost._explosion_scene = null
	outpost.take_damage(10000)
	await get_tree().process_frame
	await get_tree().physics_frame
	check(outpost._destroyed_model.get_node("Model").scene_file_path == "res://Models/building - enemy outpost destroyed.glb", "authored outpost wreck replaces placeholder")
	check(outpost._destroyed_model.find_children("*", "CollisionShape3D", true, false).size() == 1, "outpost rubble has physical collision")
	check(outpost._intact_collision_shapes.all(func(value): return value.disabled), "intact outpost collision disabled")
	check(not outpost.can_observe(Vector3(25, 0, 100)), "destroyed outpost remains offline")
	hit = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(25, 12, 20), Vector3(25, 12, -20)))
	check(hit.is_empty(), "destroyed upper floors leave no invisible collision")
	var restored := OUTPOST_SCENE.instantiate() as EnemyOutpost
	add_child(restored)
	restored.restore_save_state(outpost.capture_save_state())
	await get_tree().process_frame
	check(restored._destroyed_model != null and restored._destroyed_model.is_inside_tree(), "loading destroyed outpost installs authored ruin")
	restored.free()
	var dummy := load("res://Buildings/dummy_gun_emplacement.tscn").instantiate() as GunEmplacement
	dummy.inactive_when_no_targets = false
	add_child(dummy)
	check(dummy._turret_controller.weapon_instance == null and dummy._turret_controller.turret.mounted_barrel != null, "dummy keeps new visual rig without a live weapon")
	dummy.free()
	if "--render" in OS.get_cmdline_user_args():
		await _render(wreck, outpost)
	print("ENEMY_BUILDING_MODELS_", "OK" if failures.is_empty() else "FAILED", " aim_cases=", aim_cases, " max_error_deg=", max_aim_error, " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _render(wreck: Node3D, outpost: EnemyOutpost) -> void:
	var live := _make_gun()
	live.position = Vector3(-10, 0.46, 0)
	live._turret_controller.gun_profile_override = CATALOG.get_profile(20)
	live._turret_controller.mount_weapon(load("res://Weapons/Turrets/bullet_weapon.tscn"))
	var rig = live._turret_controller.turret
	var aim := live.global_position + Vector3(160, 65, -160)
	rig.aim_at_point(aim)
	for tick in range(120): rig.tick(1.0 / 60.0, aim)
	wreck.position = Vector3(4, 0.46, 0)
	outpost.position = Vector3(20, 0, 0)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("96866d")
	floor_mesh.material_override = material
	add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("91a8b1")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	add_child(environment)
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = 42
	camera.position = Vector3(29, 25, 52)
	camera.look_at(Vector3(5, 3, 0))
	camera.current = true
	await get_tree().create_timer(1.0).timeout
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://captures/enemy_building_models.png")
	camera.position = live.global_position + Vector3(10, 8, 13)
	camera.look_at(live.global_position + Vector3.UP * 1.5)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://captures/enemy_emplacement_rig.png")
