extends Node

const TRACER_VISUAL_FACTORY := preload("res://Projectiles/Bullet/TracerVisualFactory.gd")
const VIRTUAL_TRACER_MANAGER_SCRIPT := preload("res://Projectiles/Bullet/MachineGunVirtualTracerManager.gd")
const PROFILE_10 := preload("res://Weapons/Guns/Profiles/10mm_machine_gun.tres")
const PROFILE_15 := preload("res://Weapons/Guns/Profiles/15mm_machine_gun.tres")
const PROFILE_20 := preload("res://Weapons/Guns/Profiles/20mm_autocannon.tres")
const PROFILE_25 := preload("res://Weapons/Guns/Profiles/25mm_autocannon.tres")
const PROFILE_40 := preload("res://Weapons/Guns/Profiles/40mm_autocannon.tres")
const EXPLOSIVE_ROUND := preload("res://Projectiles/SmallExplosiveRound/small_explosive_round.tscn")
const AIRCRAFT_1_GUN := preload("res://Weapons/Autocannon/Autocannon.tscn")
const HARDPOINT_20 := preload("res://Weapons/Guns/Hardpoint/20mm_autocannon_hardpoint.tscn")
const TURRET_20 := preload("res://Weapons/Guns/Turrets/20mm_autocannon_turret_weapon.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_profile(PROFILE_10, 0.18, 4.8, 2, 800.0 / 60.0 * 5.0, "10 mm")
	_check_profile(PROFILE_15, 0.18, 4.8, 2, 600.0 / 60.0 * 10.0, "15 mm")
	_check_profile(PROFILE_20, 0.22, 5.6, 1, 400.0 / 60.0 * 20.0, "20 mm")
	_check_profile(PROFILE_25, 0.26, 6.4, 1, 300.0 / 60.0 * 30.0, "25 mm")
	_check_profile(PROFILE_40, 0.34, 8.4, 1, 120.0 / 60.0 * 42.0, "40 mm")
	_check_tracer_geometry_and_material()
	_check_virtual_tracer_cardinal_alignment()

	var round := EXPLOSIVE_ROUND.instantiate() as Bullet
	_expect(round != null, "explosive autocannon round did not instantiate")
	if round != null:
		add_child(round)
		await get_tree().process_frame
		_expect(round.tracer_enabled, "explosive autocannon round disabled its tracer")
		_expect(round.tracer_mesh is ArrayMesh, "explosive autocannon round did not build tapered tracer geometry")
		_expect(round.tracer_width >= 0.22, "explosive autocannon fallback tracer became too narrow")
		_expect(round.tracer_visual_length >= round.tracer_width * 20.0, "explosive autocannon fallback tracer is not elongated")
		_check_physical_tracer_cardinal_alignment(round)

	var hardpoint_weapon := HARDPOINT_20.instantiate() as Autocannon
	add_child(hardpoint_weapon)
	await get_tree().process_frame
	var hardpoint_round := EXPLOSIVE_ROUND.instantiate() as Bullet
	hardpoint_weapon._configure_projectile_instance(hardpoint_round)
	_expect(is_equal_approx(hardpoint_round.tracer_width, PROFILE_20.physical_tracer_width_m), "aircraft hardpoint did not apply physical tracer width")
	_expect(is_equal_approx(hardpoint_round.tracer_visual_length, PROFILE_20.physical_tracer_length_m), "aircraft hardpoint did not apply physical tracer length")
	hardpoint_round.free()

	var aircraft_1_gun := AIRCRAFT_1_GUN.instantiate() as Autocannon
	add_child(aircraft_1_gun)
	await get_tree().process_frame
	_expect(is_equal_approx(aircraft_1_gun.physical_tracer_length_m, 4.8), "Aircraft 1 physical tracer did not use the doubled profile")
	_expect(is_equal_approx(aircraft_1_gun.virtual_tracer_length_m, 4.8), "Aircraft 1 virtual tracer did not use the doubled profile")

	var turret_weapon := TURRET_20.instantiate() as BulletWeapon
	add_child(turret_weapon)
	await get_tree().process_frame
	var turret_round := EXPLOSIVE_ROUND.instantiate() as Bullet
	turret_weapon._configure_projectile_instance(turret_round)
	_expect(is_equal_approx(turret_round.tracer_width, PROFILE_20.physical_tracer_width_m), "turret did not apply physical tracer width")
	_expect(is_equal_approx(turret_round.tracer_visual_length, PROFILE_20.physical_tracer_length_m), "turret did not apply physical tracer length")
	turret_round.free()

	_finish()


func _check_profile(
	profile: GunProfile,
	expected_width: float,
	expected_length: float,
	expected_visible_multiplier: int,
	expected_dps: float,
	label: String
) -> void:
	_expect(is_equal_approx(profile.physical_tracer_width_m, expected_width), "%s tracer width was not configured" % label)
	_expect(is_equal_approx(profile.physical_tracer_length_m, expected_length), "%s tracer length was not configured" % label)
	_expect(profile.visible_round_multiplier == expected_visible_multiplier, "%s visible-round cadence changed" % label)
	_expect(profile.physical_tracer_length_m >= profile.physical_tracer_width_m * 20.0, "%s tracer did not retain the doubled elongated silhouette" % label)
	_expect(is_equal_approx(profile.virtual_tracer_width_m, expected_width), "%s virtual tracer width diverged from the physical tracer" % label)
	_expect(is_equal_approx(profile.virtual_tracer_length_m, expected_length), "%s virtual tracer length diverged from the physical tracer" % label)
	var dps := profile.rounds_per_minute / 60.0 * profile.damage_per_shot
	_expect(is_equal_approx(dps, expected_dps), "%s DPS changed while tuning tracers" % label)


func _check_tracer_geometry_and_material() -> void:
	var mesh: ArrayMesh = TRACER_VISUAL_FACTORY.create_unit_tracer_mesh()
	_expect(mesh != null and mesh.get_surface_count() == 1, "shared tracer mesh was not created")
	if mesh != null and mesh.get_surface_count() == 1:
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		_expect(vertices.size() == 6, "shared tracer mesh lost its square base, tip, or cap center")
		_expect(indices.size() == 24, "shared tracer mesh is not a closed four-sided pyramid")
		var bounds := mesh.get_aabb()
		_expect(is_equal_approx(bounds.position.z, 0.0), "tracer base moved away from the bullet origin")
		_expect(is_equal_approx(bounds.end.z, 1.0), "tracer tip no longer extends behind the bullet")
	var material: StandardMaterial3D = TRACER_VISUAL_FACTORY.create_glow_material(Color.YELLOW, 5.0)
	_expect(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "tracer core still uses direction-dependent transparent face stacking")
	_expect(material.blend_mode == BaseMaterial3D.BLEND_MODE_MIX, "tracer core still uses additive face stacking")
	_expect(material.cull_mode == BaseMaterial3D.CULL_BACK, "tracer core still draws overlapping back faces")


func _check_virtual_tracer_cardinal_alignment() -> void:
	var manager := VIRTUAL_TRACER_MANAGER_SCRIPT.new() as MachineGunVirtualTracerManager
	var width_m := 0.18
	var length_m := 4.8
	for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var transform_value := manager._make_tracer_transform(
			Vector3(3.0, 4.0, 5.0),
			direction * 600.0,
			width_m,
			length_m
		)
		_expect(absf(transform_value.basis.x.length() - width_m) <= 0.0001, "virtual tracer width changed with cardinal heading %s" % direction)
		_expect(absf(transform_value.basis.y.length() - width_m) <= 0.0001, "virtual tracer height changed with cardinal heading %s" % direction)
		_expect(absf(transform_value.basis.z.length() - length_m) <= 0.0001, "virtual tracer length changed with cardinal heading %s" % direction)
		_expect(transform_value.basis.z.normalized().dot(-direction) >= 0.9999, "virtual tracer did not trail behind heading %s" % direction)
	manager.free()


func _check_physical_tracer_cardinal_alignment(round: Bullet) -> void:
	for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		round.linear_velocity = direction * 600.0
		round._align_visual_to_velocity()
		var visual_travel_axis := -round.global_transform.basis.z.normalized()
		_expect(visual_travel_axis.dot(direction) >= 0.9999, "physical tracer did not align to cardinal heading %s" % direction)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[AutocannonTracerSmoketest] PASS square_pyramid aspect_ratio>=20 cardinal_alignment=physical+virtual lengths=4.8/5.6/6.4/8.4 cadence=profile_preserved")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[AutocannonTracerSmoketest] FAIL %s" % failure)
	get_tree().quit(1)
