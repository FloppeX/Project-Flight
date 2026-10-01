extends Node3D
const GUNS := preload("res://Weapons/Turrets/TurretGunCatalog.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _ready() -> void: call_deferred("run")
func run() -> void:
	for child in get_tree().root.get_children():
		if child != self: child.process_mode = Node.PROCESS_MODE_DISABLED
	for caliber in [10, 15, 20, 25, 40]:
		var controller = load("res://LandCarrier/CarrierDefenseTurretAssembly.tscn").instantiate()
		controller.process_mode = Node.PROCESS_MODE_DISABLED
		controller.gun_profile_override = GUNS.get_profile(caliber)
		add_child(controller)
		controller.transform = Transform3D(Basis.from_euler(Vector3(0.3, 1.2, -0.2)).scaled(Vector3.ONE * 1.3), Vector3(10, 100, 20))
		verify_gun(controller.weapon_instance, controller.turret._get_current_muzzle_transform(), caliber)
		controller.free()
		var path := "res://Weapons/Guns/Hardpoint/%dmm_%s_hardpoint.tscn" % [caliber, "machine_gun" if caliber < 20 else "autocannon"]
		# This authored 40mm hardpoint is a rocket pod; test the actual gun instead.
		if caliber == 40: path = "res://Weapons/Turrets/40mm_autocannon_weapon.tscn"
		var gun = load(path).instantiate()
		gun.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(gun)
		gun.transform = Transform3D(Basis.from_euler(Vector3(-0.4, 1.0, 0.2)), Vector3(-10, 100, 20))
		var muzzle: Transform3D = gun._get_bullet_spawn_point().global_transform
		var barrel: MeshInstance3D = gun._barrel_recoil.targets[0].node
		var bounds: AABB = (muzzle.affine_inverse() * barrel.global_transform) * barrel.get_aabb()
		muzzle.origin = muzzle * Vector3(bounds.get_center().x, bounds.get_center().y, bounds.end.z)
		verify_gun(gun, muzzle, caliber)
		gun.free()
	if "--render" in OS.get_cmdline_user_args(): await render_probe()
	print("GUN_MUZZLE_FLASH_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func verify_gun(gun: Node3D, muzzle: Transform3D, caliber: int) -> void:
	check(gun.fire(), "Gun fires")
	var flash = gun.get_node_or_null("MuzzleFlash")
	check(flash != null and flash.visible, "Successful shot flashes")
	if flash == null: return
	check(flash.global_position.distance_to(muzzle.origin) < 0.0001, "Flash begins at firing muzzle")
	check(flash.global_basis.z.normalized().dot(muzzle.basis.z.normalized()) > 0.9999, "Flash follows barrel direction on tilted mounts")
	check(is_equal_approx(flash.global_basis.z.length(), float(caliber) / 20.0 * 1.2), "Caliber size is independent of mount scale")
	check(flash._mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Flash casts no shadows")
	var count: int = flash.pulses
	check(not gun.fire() and flash.pulses == count, "Cooldown does not flash")
	var anchor: Node3D = flash._anchor.get_ref()
	anchor.position.x += 1.0
	flash._process(0.25)
	check(flash.visible, "Flash survives its first update at low FPS")
	check(flash.global_position.distance_to((anchor.global_transform * flash._anchor_offset).origin) < 0.0001, "Flash follows muzzle movement and recoil")
	flash._process(0.1)
	check(not flash.visible and not flash.is_processing(), "Flash expires and stops processing")
	if gun is Autocannon: gun.fire_timer = 0.0
	else: gun.set_meta("next_fire_time_s", 0.0)
	gun.visible_round_multiplier = 2
	check(gun.fire() and gun.get_node("MuzzleFlash") == flash, "Subsequent shots reuse the effect")
	count = flash.pulses
	var virtual_count: int = gun.virtual_rounds_fired
	gun._process(1.0)
	check(gun.virtual_rounds_fired > virtual_count and flash.pulses > count, "Visual filler rounds also pulse the flash")
	gun.ammo_count = 0
	if gun is BulletWeapon: gun.infinite_ammo = false
	if gun is Autocannon: gun.fire_timer = 0.0
	else: gun.set_meta("next_fire_time_s", 0.0)
	count = flash.pulses
	check(not gun.fire() and flash.pulses == count, "Empty gun does not flash")

func render_probe() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("273747")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	environment.environment.glow_enabled = true
	environment.environment.glow_intensity = 0.45
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	add_child(light)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	var controller = load("res://LandCarrier/CarrierDefenseTurretAssembly.tscn").instantiate()
	controller.process_mode = Node.PROCESS_MODE_DISABLED
	controller.gun_profile_override = GUNS.get_profile(25)
	add_child(controller)
	var gun = load("res://Weapons/Guns/Hardpoint/20mm_autocannon_hardpoint.tscn").instantiate()
	gun.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(gun)
	for subject in ["turret", "hardpoint"]:
		controller.visible = subject == "turret"
		gun.visible = subject == "hardpoint"
		var weapon = controller.weapon_instance if subject == "turret" else gun
		camera.position = Vector3(5, 3.2, 4.5) if subject == "turret" else Vector3(1.7, 0.8, 2.1)
		camera.look_at(Vector3(0, 1.0, 0.8) if subject == "turret" else Vector3(0, 0, 0.7))
		weapon.fire()
		weapon.get_node("MuzzleFlash")._process(0.0)
		# Freeze one emitted flash for image inspection; normal lifetime is tested above.
		for lighting in ["day", "night"]:
			light.light_energy = 1.0 if lighting == "day" else 0.02
			environment.environment.ambient_light_energy = 0.65 if lighting == "day" else 0.08
			environment.environment.background_color = Color("273747") if lighting == "day" else Color("050912")
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://logs/muzzle_flash_%s_%s.png" % [subject, lighting])
