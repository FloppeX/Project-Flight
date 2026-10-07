extends "res://Tests/RegionalAircraftDamageSmoketest.gd"

# Geometry-audited propeller mount positions in aircraft space. These catch a
# return to the generic nose colliders, including the mid-fuselage pushers.
const MOUNTS := {
	1: Vector3(0,0.3501,-0.4868), 2: Vector3(0,0.6840,-5.4553),
	3: Vector3(0,-0.0671,2.6138), 4: Vector3(0,0.2761,4.1515),
	5: Vector3(0.0015,0.4485,-1.6169), 6: Vector3(0,1.7655,1.2229),
	7: Vector3(0,-0.0571,-4.9737), 8: Vector3(0,0.2896,-3.9305),
	14: Vector3(0,0.3597,-2.3891), 16: Vector3(0,0,3.7795),
}
var camera: Camera3D
var render_smoke := false

func _run() -> void:
	get_tree().create_timer(100.0).timeout.connect(func():
		push_error("ENGINE_SMOKE_ORIGIN_TIMEOUT")
		get_tree().quit(1))
	for singleton in ["AirOpsManager", "GroundOpsManager", "OperationsCoordinator", "FlightDirector"]:
		var node := get_node_or_null("/root/" + singleton)
		if node != null: node.process_mode = Node.PROCESS_MODE_DISABLED
	host = Node3D.new()
	add_child(host)
	render_smoke = "--render-smoke" in OS.get_cmdline_user_args()
	if render_smoke: setup_render()
	for number in MOUNTS:
		var craft := spawn(number)
		while not craft.runtime_initialized: await get_tree().process_frame
		await get_tree().process_frame # DamageEffects caches modules deferred after Aircraft setup.
		var engine := craft.get_node("Engine") as AircraftModule_Engine
		var prop := engine.propeller as Node3D
		var model := craft.get_node("PartDamageModel") as AircraftPartDamageModel
		var pristine := model.get_damage_state()
		craft.position = Vector3(80,1500,-60)
		craft.rotation = Vector3(0.25,1.1,-0.2)
		model.damage_zone(&"engine", model.get_zone_max_health(&"engine") * 0.6)
		var smoke := craft.get_node_or_null("EngineDamageSmoke") as GPUParticles3D
		check(smoke != null and smoke.emitting, "%d engine damage did not produce smoke" % number)
		if smoke != null:
			check(craft.to_local(smoke.global_position).distance_to(MOUNTS[number]) < 0.01, "%d smoke missed authored propeller mount: %s" % [number,craft.to_local(smoke.global_position)])
			var origin := engine.get_damage_smoke_global_position()
			prop.rotate_object_local(engine.propeller_spin_axis_local.normalized(), 1.7)
			check(origin.distance_to(engine.get_damage_smoke_global_position()) < 0.001, "%d smoke orbited with blades" % number)
			craft.position += Vector3(100,5,-200)
			craft.rotation.y += 0.4
			check(smoke.global_position.distance_to(engine.get_damage_smoke_global_position()) < 0.001, "%d smoke lost its mount after aircraft moved" % number)
		# Exercise actual legacy smoke/fire puffs as well as the regional GPU source.
		var effects := craft.get_node_or_null("DamageEffects") as DamageEffects
		if effects != null:
			for fire in [false,true]:
				for sample in 4:
					if fire: effects._spawn_fire_puff(1.0)
					else: effects._spawn_damage_smoke(1.0)
					var puff := get_child(get_child_count()-1) as MeshInstance3D
					check(puff != null and puff.global_position.distance_to(craft.to_global(MOUNTS[number])) < 0.36, "%d legacy smoke/fire missed engine mount" % number)
					if puff != null: puff.queue_free()
			check(effects._engine_module == engine, "%d legacy smoke did not resolve its engine" % number)
		var restored := spawn(number)
		while not restored.runtime_initialized: await get_tree().process_frame
		restored.get_node("PartDamageModel").restore_damage_state(model.get_damage_state())
		var restored_smoke := restored.get_node_or_null("EngineDamageSmoke") as GPUParticles3D
		check(restored_smoke != null and restored.to_local(restored_smoke.global_position).distance_to(MOUNTS[number]) < 0.01, "%d saved damage restored smoke at wrong end" % number)
		restored.queue_free()
		if render_smoke and number in [2,5,6,16]: await capture(craft, number)
		if number == 2:
			model.damage_zone(&"tail", model.get_zone_max_health(&"tail"))
			check(not smoke.emitting, "detached rear engine still emitted on fuselage")
		else:
			model.restore_damage_state(pristine)
			check(not smoke.emitting, "%d repaired engine continued emitting" % number)
		print("ENGINE_SMOKE_ORIGIN_CASE aircraft=",number," mount=",MOUNTS[number])
		for child in host.get_children():
			if child is RigidBody3D: child.queue_free()
		await get_tree().process_frame
	for failure in failures: push_error(failure)
	print("ENGINE_SMOKE_ORIGIN_%s fleet=10 regional+fire+save+transform+propeller_rotation" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

func setup_render() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/engine_smoke"))
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("72828c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	host.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-30,0)
	host.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14
	host.add_child(camera)

func capture(craft: Aircraft, number: int) -> void:
	craft.position = Vector3.ZERO
	craft.rotation = Vector3.ZERO
	craft.get_node("Engine").engine_stop()
	camera.position = Vector3(13,5,-10)
	camera.look_at(Vector3(0,0.7,0))
	camera.make_current()
	var smoke := craft.get_node("EngineDamageSmoke") as GPUParticles3D
	smoke.restart()
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://captures/engine_smoke/%02d_engine.png" % number) == OK, "failed to save smoke render")
