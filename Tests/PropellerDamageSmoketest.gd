extends "res://Tests/RegionalAircraftDamageSmoketest.gd"

const STATE := preload("res://Aircraft/AircraftRuntimeState.gd")
const SHAPES := preload("res://Models/Aircraft_1/propeller_strike_geometry.gd")
var render_camera: Camera3D

func _run() -> void:
	get_tree().create_timer(140.0).timeout.connect(func():
		push_error("PROPELLER_DAMAGE_TIMEOUT")
		get_tree().quit(1))
	for singleton in ["AirOpsManager", "GroundOpsManager", "OperationsCoordinator", "FlightDirector"]:
		var node := get_node_or_null("/root/"+singleton)
		if node != null: node.process_mode = Node.PROCESS_MODE_DISABLED
	host = Node3D.new()
	add_child(host)
	if "--render-propeller" in OS.get_cmdline_user_args(): setup_render()
	for number in [1,2,3,4,5,6,7,8,14,16]: await fleet_case(number)
	for kind in ["terrain", "deck", "aircraft"]: await contact_case(kind)
	await disc_case(false)
	await disc_case(true)
	await swept_case()
	await origin_shift_case()
	await startup_case()
	var heli := spawn(13)
	while not heli.runtime_initialized: await get_tree().process_frame
	check(heli.get_node("Engine").propeller_damage == null, "helicopter gained fixed-wing blade damage")
	await clear_case()
	for failure in failures: push_error(failure)
	print("PROPELLER_DAMAGE_%s fleet=10 contacts=terrain,deck,aircraft stopped+spinning+swept+origin_shift+save+restart" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

func clear_case() -> void:
	for node in host.get_children():
		if node is PhysicsBody3D: node.queue_free()
	await get_tree().process_frame

func ready_craft(number: int) -> Aircraft:
	var craft := spawn(number)
	while not craft.runtime_initialized: await get_tree().process_frame
	await get_tree().physics_frame
	return craft

func fragment_count() -> int:
	var result := 0
	for node in host.get_children():
		if node.get_meta("damage_debris_zone", &"") == &"propeller": result += 1
	return result

func fleet_case(number: int) -> void:
	var craft := await ready_craft(number)
	var engine := craft.get_node("Engine") as AircraftModule_Engine
	var damage: Node = engine.propeller_damage
	check(damage != null, "%d missing propeller strike detector" % number)
	for frame in 3: await get_tree().physics_frame
	check(not engine.propeller_broken, "%d propeller struck its own airframe" % number)
	engine.current_power = 1.0
	engine.target_power = 1.0
	engine.is_engine_working = true
	damage.shatter()
	check(engine.propeller_broken and engine.get_effective_power_factor() == 0.0, "%d strike retained thrust" % number)
	check(engine.current_power == 0.0 and not engine.is_engine_working, "%d strike retained engine power" % number)
	check(fragment_count() == 10, "%d did not shatter into ten blade pieces" % number)
	damage.shatter()
	check(fragment_count() == 10, "%d repeated contact spawned duplicate debris" % number)
	for frame in 3:
		engine.engine_set_power(1.0)
		engine._apply_propeller_blur_t(1.0)
		await get_tree().physics_frame
	check(engine.current_power == 0.0 and engine.get_effective_power_factor() == 0.0, "%d broken propeller restarted" % number)
	var parts := craft.get_node("PartDamageModel") as AircraftPartDamageModel
	check(parts.get_zone_health(&"engine") == parts.get_zone_max_health(&"engine"), "%d propeller strike consumed structural engine health" % number)
	check(not craft.get_node("EngineDamageCollider").disabled, "%d propeller strike removed engine collision support" % number)
	for mesh in engine._prop_blade_mesh_nodes + engine._prop_disc_mesh_nodes:
		check(not mesh.is_visible_in_tree(), "%d intact blades or blur returned" % number)
	for mesh in engine._prop_hub_mesh_nodes: check(mesh.is_visible_in_tree(), "%d hub disappeared" % number)
	var stubs := engine.propeller.find_children("BrokenBladeStub*", "MeshInstance3D", true, false)
	check(stubs.size() == 5, "%d missing broken blade stubs" % number)
	for stub in stubs:
		var radius := 0.0
		var cap := false
		for surface in stub.mesh.get_surface_count():
			var material: Material = stub.mesh.surface_get_material(surface)
			cap = cap or (material != null and material.resource_name == "PropellerFractureInterior")
			for vertex: Vector3 in stub.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var local: Vector3 = engine.propeller.to_local(stub.to_global(vertex))
				radius = maxf(radius, Vector2(local.x,local.y).length())
		check(cap and radius > 0.3 and radius < 0.51, "%d stub missing jagged capped one-third fracture: %.3f" % [number,radius])
	var saved := STATE.capture(craft)
	check(STATE.validate(saved), "%d propeller save rejected" % number)
	var restored := spawn(number)
	restored.position.x = 100
	while not restored.runtime_initialized: await get_tree().process_frame
	var count := fragment_count()
	STATE.restore(restored, saved)
	check(restored.get_node("Engine").propeller_broken and restored.get_node("Engine").get_effective_power_factor() == 0.0, "%d saved propeller repaired itself" % number)
	check(fragment_count() == count, "%d restore replayed blade fragments" % number)
	if render_camera != null and number in [2,5,16]: await capture(craft, number)
	print("PROPELLER_FLEET_CASE ",number," fragments=",count," stubs=",stubs.size())
	await clear_case()

func obstacle(at: Vector3, size: Vector3, group: String = "") -> StaticBody3D:
	var body := StaticBody3D.new()
	if not group.is_empty(): body.add_to_group(group)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	host.add_child(body)
	body.global_position = at
	return body

func contact_case(kind: String) -> void:
	var craft := await ready_craft(16)
	var engine := craft.get_node("Engine") as AircraftModule_Engine
	var prop := engine.propeller as Node3D
	if kind == "aircraft":
		var other := spawn(5)
		# Put another real aircraft's fuselage into the propeller, away from its own propeller.
		other.position = prop.global_position - Vector3(0,0,2)
	else:
		var vertical_radius := SHAPES.RADIUS * Vector2(prop.global_basis.x.y, prop.global_basis.y.y).length()
		var lowest := prop.global_position.y - vertical_radius - absf(prop.global_basis.z.y) * SHAPES.HEIGHT * 0.5
		obstacle(Vector3(prop.global_position.x,lowest-0.48,prop.global_position.z), Vector3(20,1,20), "carrier" if kind == "deck" else "terrain")
	for frame in 6: await get_tree().physics_frame
	check(engine.propeller_broken, "%s contact did not shatter blades" % kind)
	check(not craft._has_exploded and not craft._critical_damage_active, "%s blade strike destroyed whole aircraft" % kind)
	check(not bool(craft.get_meta("pilot_dead", false)), "%s blade strike killed the pilot" % kind)
	print("PROPELLER_CONTACT_CASE ",kind," broken=",engine.propeller_broken)
	await clear_case()

func disc_case(spinning: bool) -> void:
	var craft := await ready_craft(16)
	var engine := craft.get_node("Engine") as AircraftModule_Engine
	var prop := engine.propeller as Node3D
	# The user requested a simple full disc, including gaps in stopped blades.
	engine.visual_budget_enabled = false
	prop.visible = false # Distance culling must not turn off the physical disc.
	engine.is_engine_working = spinning
	engine.current_power = 1.0 if spinning else 0.0
	engine.target_power = engine.current_power
	obstacle(prop.to_global(Vector3(0.85,0,0)),Vector3.ONE*0.025)
	for frame in 15: await get_tree().physics_frame
	check(engine.propeller_broken, "propeller disc missed contact (spinning=%s)" % spinning)
	await clear_case()

func swept_case() -> void:
	var craft := await ready_craft(16)
	var engine := craft.get_node("Engine") as AircraftModule_Engine
	var prop := engine.propeller as Node3D
	var axis := prop.global_basis.z.normalized()
	var wall := obstacle(prop.global_position + axis * 4.0, Vector3(4,4,0.02))
	wall.global_basis = prop.global_basis.orthonormalized()
	for frame in 3: await get_tree().physics_frame
	check(not engine.propeller_broken, "distant wall prematurely broke blades")
	craft.position += axis * 8.0
	for frame in 3: await get_tree().physics_frame
	check(engine.propeller_broken, "fast transit tunneled through a thin obstacle")
	await clear_case()

func origin_shift_case() -> void:
	var craft := await ready_craft(16)
	var engine := craft.get_node("Engine") as AircraftModule_Engine
	var prop := engine.propeller as Node3D
	var axis := prop.global_basis.z.normalized()
	var wall := obstacle(prop.global_position + axis * 4.0, Vector3(4,4,0.02))
	wall.global_basis = prop.global_basis.orthonormalized()
	for frame in 3: await get_tree().physics_frame
	# A rebase moves coordinates, rather than traversing the intervening space.
	craft.position += axis * 8.0
	craft.apply_origin_shift(-axis * 8.0)
	for frame in 3: await get_tree().physics_frame
	check(not engine.propeller_broken, "origin shift swept propeller across old world coordinates")
	await clear_case()

func startup_case() -> void:
	var craft := await ready_craft(16)
	var engine := craft.get_node("Engine") as AircraftModule_Engine
	engine.engine_start()
	engine.propeller_damage.shatter(false)
	for frame in 75: await get_tree().physics_frame
	check(not engine.is_engine_working and engine.get_effective_power_factor() == 0.0, "pending engine startup resurrected broken propeller")
	await clear_case()

func setup_render() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/propeller_damage"))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("72828c")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85,0.88,1.0)
	env.environment.ambient_light_energy = 0.8
	host.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-25,0)
	host.add_child(light)
	render_camera = Camera3D.new()
	render_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	host.add_child(render_camera)

func capture(craft: Aircraft, number: int) -> void:
	var engine := craft.get_node("Engine") as AircraftModule_Engine
	var prop := engine.propeller as Node3D
	var point := prop.global_position
	var axis := prop.global_basis.z.normalized()
	render_camera.size = 3.5
	render_camera.global_position = point - axis * 6.0 + Vector3(2,1,0)
	render_camera.look_at(point)
	render_camera.make_current()
	# Keep smoke out of the mesh close-up; other tests cover that effect.
	var smoke := craft.get_node_or_null("EngineDamageSmoke") as GPUParticles3D
	if smoke != null: smoke.visible = false
	await get_tree().create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://captures/propeller_damage/%02d_broken.png" % number) == OK, "could not save broken propeller preview")
