extends Node3D

const TURRET_WEAPON_SCENE := preload(
	"res://Weapons/Guns/Turrets/10mm_machine_gun_turret_weapon.tscn"
)
const HARDPOINT_WEAPON_SCENE := preload(
	"res://Weapons/Guns/Hardpoint/10mm_machine_gun_hardpoint.tscn"
)
const BULLET_SCENE := preload("res://Projectiles/Bullet/bullet.tscn")
const TEN_MM_PROFILE := preload("res://Weapons/Guns/Profiles/10mm_machine_gun.tres")
const FIFTEEN_MM_PROFILE := preload("res://Weapons/Guns/Profiles/15mm_machine_gun.tres")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_ensure_service("BulletPool", "res://Projectiles/Bullet/BulletPool.gd")
	var pool := get_tree().root.get_node_or_null("BulletPool")
	_expect(pool != null, "BulletPool service was unavailable")
	if pool == null:
		_finish()
		return

	_expect(TEN_MM_PROFILE.visible_round_multiplier == 2, "10 mm profile did not request 2x visible cadence")
	_expect(FIFTEEN_MM_PROFILE.visible_round_multiplier == 2, "15 mm profile did not request 2x visible cadence")
	_expect(TEN_MM_PROFILE.physical_tracer_length_m <= TEN_MM_PROFILE.physical_tracer_width_m * 4.0, "10 mm tracer remained line-like")
	_expect(FIFTEEN_MM_PROFILE.physical_tracer_length_m <= FIFTEEN_MM_PROFILE.physical_tracer_width_m * 4.0, "15 mm tracer remained line-like")
	_expect(
		is_equal_approx(TEN_MM_PROFILE.rounds_per_minute / 60.0 * TEN_MM_PROFILE.damage_per_shot, 66.6666667),
		"10 mm physical DPS changed from its 800 RPM x 5 damage baseline"
	)
	_expect(
		is_equal_approx(FIFTEEN_MM_PROFILE.rounds_per_minute / 60.0 * FIFTEEN_MM_PROFILE.damage_per_shot, 100.0),
		"15 mm physical DPS changed from its 600 RPM x 10 damage baseline"
	)

	var sample_bullet := BULLET_SCENE.instantiate() as Bullet
	_expect(sample_bullet != null, "machine-gun bullet scene did not instantiate")
	if sample_bullet != null:
		_expect(sample_bullet.tracer_width >= 0.2, "physical tracer width was not increased")
		_expect(sample_bullet.tracer_visual_length <= sample_bullet.tracer_width * 4.0, "physical tracer remained line-like")
		_expect(sample_bullet.tracer_hidden_physics_frames <= 1, "physical tracer still appeared too late")
		add_child(sample_bullet)
		await get_tree().process_frame
		_expect(sample_bullet.tracer_mesh is ArrayMesh, "physical tracer was not changed to a tapered mesh")
		if sample_bullet.tracer_mesh != null:
			var tracer_aabb := sample_bullet.tracer_mesh.get_aabb()
			_expect(is_zero_approx(tracer_aabb.position.z), "physical tracer base was not located at the bullet")
			_expect(tracer_aabb.end.z > 0.9, "physical tracer did not taper behind the bullet")
			var tracer_arrays := sample_bullet.tracer_mesh.surface_get_arrays(0)
			var tracer_vertices: PackedVector3Array = tracer_arrays[Mesh.ARRAY_VERTEX]
			_expect(tracer_vertices.size() >= 14, "physical tracer still used the four-sided flat pyramid")
		var tracer_material := sample_bullet.trail_mesh.material_override as StandardMaterial3D
		_expect(
			tracer_material != null
					and tracer_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
					and tracer_material.blend_mode == BaseMaterial3D.BLEND_MODE_MIX
					and tracer_material.cull_mode == BaseMaterial3D.CULL_BACK,
			"physical tracer did not use a solid emissive core"
		)
		sample_bullet.queue_free()
		await get_tree().process_frame

	var acquired_before := int((pool.call("get_stats") as Dictionary).get("acquired", 0))
	var turret_weapon := TURRET_WEAPON_SCENE.instantiate() as BulletWeapon
	add_child(turret_weapon)
	await get_tree().process_frame
	_expect(turret_weapon.visible_round_multiplier == 2, "turret weapon did not apply the profile multiplier")
	var turret_ammo_before := turret_weapon.ammo_count
	var turret_sound_before := turret_weapon.shot_sound_events
	turret_weapon.set_meta("next_fire_time_s", 0.0)
	_expect(turret_weapon.fire(), "turret machine gun did not fire")
	_expect(turret_weapon.physical_rounds_fired == 1, "turret shot did not create exactly one physical projectile")
	_expect(
		turret_weapon.last_fired_projectile != null
				and int(turret_weapon.last_fired_projectile.get("virtual_impact_count")) == 1,
		"turret physical bullet did not carry one cosmetic virtual impact"
	)
	_expect(turret_weapon.virtual_rounds_fired == 0, "turret virtual round was not delayed between physical shots")
	_expect(turret_weapon.shot_sound_events - turret_sound_before == 1, "turret virtual sound played at the same time as the physical shot")
	_expect(turret_weapon.ammo_count == turret_ammo_before, "virtual tracer changed infinite turret ammunition accounting")
	await get_tree().create_timer(0.06).timeout
	_expect(turret_weapon.virtual_rounds_fired == 1, "turret shot did not create one delayed virtual filler tracer")
	_expect(turret_weapon.shot_sound_events - turret_sound_before == 2, "turret virtual round did not play its own shot sound")

	var manager := get_node_or_null("MachineGunVirtualTracers")
	_expect(manager != null, "shared virtual-tracer manager was not created")
	if manager != null:
		var manager_stats := manager.call("get_stats") as Dictionary
		_expect(int(manager_stats.get("active", 0)) == 1, "turret shot did not add one active virtual tracer")
		_expect(int(manager_stats.get("draw_batches", 0)) == 1, "virtual tracers were not held in one render batch")
		_expect(int(manager_stats.get("physics_projectiles", -1)) == 0, "virtual tracer reported a physics projectile")
		var batch := manager.get_node_or_null("VirtualTracerBatch") as MultiMeshInstance3D
		_expect(batch != null and batch.multimesh != null, "virtual tracer batch was unavailable")
		if batch != null and batch.multimesh != null and batch.multimesh.mesh != null:
			var virtual_aabb := batch.multimesh.mesh.get_aabb()
			_expect(is_zero_approx(virtual_aabb.position.z), "virtual tracer base was not located at the virtual bullet")
			_expect(virtual_aabb.end.z > 0.9, "virtual tracer did not taper behind the virtual bullet")
			var virtual_arrays := batch.multimesh.mesh.surface_get_arrays(0)
			var virtual_vertices: PackedVector3Array = virtual_arrays[Mesh.ARRAY_VERTEX]
			_expect(virtual_vertices.size() >= 14, "virtual tracer still used the four-sided flat pyramid")
			var virtual_material := batch.multimesh.mesh.surface_get_material(0) as StandardMaterial3D
			_expect(
				virtual_material != null
						and virtual_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
						and virtual_material.blend_mode == BaseMaterial3D.BLEND_MODE_MIX
						and virtual_material.cull_mode == BaseMaterial3D.CULL_BACK,
				"virtual tracer did not use a solid emissive core"
			)

	var acquired_after_turret := int((pool.call("get_stats") as Dictionary).get("acquired", 0))
	_expect(acquired_after_turret - acquired_before == 1, "turret virtual tracer acquired an extra physical bullet")

	var hardpoint_weapon := HARDPOINT_WEAPON_SCENE.instantiate() as Autocannon
	add_child(hardpoint_weapon)
	await get_tree().process_frame
	_expect(hardpoint_weapon.visible_round_multiplier == 2, "aircraft machine gun did not apply the profile multiplier")
	var hardpoint_impact_sample := BULLET_SCENE.instantiate() as Bullet
	_expect(hardpoint_impact_sample != null, "aircraft impact-configuration sample did not instantiate")
	if hardpoint_impact_sample != null:
		hardpoint_weapon._configure_projectile_instance(hardpoint_impact_sample)
		_expect(hardpoint_impact_sample.virtual_impact_count == 1, "aircraft physical bullet did not carry one cosmetic virtual impact")
		hardpoint_impact_sample.free()
	var hardpoint_ammo_before := hardpoint_weapon.ammo_count
	var hardpoint_sound_before := hardpoint_weapon.shot_sound_events
	hardpoint_weapon.fire_timer = 0.0
	_expect(hardpoint_weapon.fire(), "aircraft machine gun did not fire")
	_expect(hardpoint_weapon.physical_rounds_fired == 1, "aircraft shot did not create exactly one physical projectile")
	_expect(hardpoint_weapon.virtual_rounds_fired == 0, "aircraft virtual round was not delayed between physical shots")
	_expect(hardpoint_weapon.shot_sound_events - hardpoint_sound_before == 1, "aircraft virtual sound played at the same time as the physical shot")
	_expect(hardpoint_weapon.ammo_count == hardpoint_ammo_before - 1, "aircraft virtual tracer consumed ammunition")
	await get_tree().create_timer(0.06).timeout
	_expect(hardpoint_weapon.virtual_rounds_fired == 1, "aircraft shot did not create one delayed virtual filler tracer")
	_expect(hardpoint_weapon.shot_sound_events - hardpoint_sound_before == 2, "aircraft virtual round did not play its own shot sound")

	var acquired_after_hardpoint := int((pool.call("get_stats") as Dictionary).get("acquired", 0))
	_expect(acquired_after_hardpoint - acquired_after_turret == 1, "aircraft virtual tracer acquired an extra physical bullet")
	if manager != null:
		var final_manager_stats := manager.call("get_stats") as Dictionary
		_expect(int(final_manager_stats.get("active", 0)) == 2, "both machine guns did not share the batched tracer stream")

	await get_tree().physics_frame
	_finish()


func _ensure_service(service_name: String, script_path: String) -> void:
	if get_tree().root.get_node_or_null(service_name) != null:
		return
	var service := Node.new()
	service.name = service_name
	service.set_script(load(script_path))
	get_tree().root.add_child(service)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		var manager := get_node_or_null("MachineGunVirtualTracers")
		var stats: Dictionary = manager.call("get_stats") as Dictionary if manager != null else {}
		print("[MachineGunVirtualRoundsSmoketest] PASS stats=%s" % [stats])
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[MachineGunVirtualRoundsSmoketest] %s" % failure)
	get_tree().quit(1)
