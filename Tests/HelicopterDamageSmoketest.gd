extends "res://Tests/RegionalAircraftDamageSmoketest.gd"

func spawn(number: int) -> Aircraft:
	var craft := super.spawn(number)
	craft.get_node("HelicopterPilot").process_mode = Node.PROCESS_MODE_DISABLED
	craft.get_node("HeadsUpDisplay").process_mode = Node.PROCESS_MODE_DISABLED
	return craft

func prime(craft: Aircraft) -> void:
	craft.freeze = true
	var rotor := craft.get_node("RotorAssembly")
	rotor._fold_t = 0.0
	rotor._fold_target = 0.0
	rotor._power = 1.0
	rotor._apply_fold_pose()
	var flight: HelicopterFlight = craft.get_node("SimpleAero")
	flight._rotor_model_initialized = true
	flight.rotor_energy.rpm = 1.0
	var trim := flight.get_loaded_hover_collective()
	flight.rotor_energy.collective = trim
	var engine: AircraftModule_Engine = craft.get_node("Engine")
	engine.is_engine_working = true
	engine.current_power = trim
	engine.target_power = trim
	engine.throttle_input = trim

func _run() -> void:
	get_tree().create_timer(120.0).timeout.connect(func():
		push_error("HELICOPTER_DAMAGE_TIMEOUT")
		get_tree().quit(1))
	for singleton in ["AirOpsManager","GroundOpsManager","OperationsCoordinator","FlightDirector","EnemyVisualBudget"]:
		get_node("/root/"+singleton).process_mode = Node.PROCESS_MODE_DISABLED
	host = Node3D.new()
	add_child(host)
	for number in [9,10,11,12,13,15]:
		var craft := spawn(number)
		await get_tree().process_frame
		var model = craft.get_node("PartDamageModel")
		var flight: HelicopterFlight = craft.get_node("SimpleAero")
		var engine: AircraftModule_Engine = craft.get_node("Engine")
		prime(craft)
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(model.get_damage_state().size() == 6,"%d six regions" % number)
		check(model.rotor_areas.size() == 2,"%d two rotor discs" % number)
		for area in model.rotor_areas:
			print("ROTOR_AREA id=%d zone=%s radius=%.2f position=%s health=%.1f" % [number,area.zone,area.radius,str(area.position),model.get_zone_health(area.zone)])
			check(not model.is_zone_destroyed(area.zone),"%d rotor collided with itself" % number)
			check(area.radius > 0.2 and area.radius < 10.0,"%d rotor radius" % number)
		var rotor_area: Area3D = model.rotor_areas[0]
		var sparse_hits := 0
		for i in 100:
			if rotor_area.accepts_bullet(rotor_area.to_global(Vector3(rotor_area.radius*.7,0,0)),i/100.0): sparse_hits += 1
		check(sparse_hits > 0 and sparse_hits < 20,"%d sparse rotor disc" % number)
		check(rotor_area.accepts_bullet(rotor_area.global_position,.99),"%d solid hub" % number)
		for visual in model._tail_visuals:
			if str(visual.name).begins_with("TailBreakaway"):
				check(has_fracture_cap(visual) and has_fracture_cap(visual.get_parent()),"%d missing tail/stump cap" % number)
		model.damage_zone(&"main_rotor",model.get_zone_max_health(&"main_rotor")*.1)
		var mild_health: float = model.get_zone_health(&"main_rotor")
		model._physics_process(.3)
		check(is_equal_approx(model.get_zone_health(&"main_rotor"),mild_health),"%d mild rotor damage spread" % number)
		model.damage_zone(&"main_rotor",model.get_zone_max_health(&"main_rotor")*.55)
		check(flight.damage_vibration > .6 and flight.damage_cyclic < 1,"%d rotor vibration and controls" % number)
		check(flight.damage_engine_health == 1,"%d rotor hit also damaged engine" % number)
		var health: float = model.get_zone_health(&"main_rotor")
		model._physics_process(.3)
		check(model.get_zone_health(&"main_rotor") < health,"%d severe wear progresses" % number)
		model.damage_zone(&"engine",model.get_zone_max_health(&"engine")*.5)
		check(flight.damage_engine_health == .5,"%d partial engine" % number)
		model.damage_zone(&"cockpit",model.get_zone_max_health(&"cockpit")*.7)
		check(craft.get_meta("pilot_wounded",false) and not craft.get_meta("pilot_dead",false),"%d wounded but alive" % number)
		model.damage_zone(&"fuselage",model.get_zone_max_health(&"fuselage")*.6)
		check(model.systems.fuel_leak_rate > 0 and flight.damage_drag > 1,"%d fuselage penalties" % number)
		model.damage_zone(&"tail",model.get_zone_max_health(&"tail"))
		for visual in model._tail_visuals: check(not visual.visible,"%d attached tail %s" % [number,visual.name])
		check(not craft._critical_damage_active and not craft._has_exploded,"%d survivable tail loss" % number)
		check(flight.damage_yaw_authority > .5 if model.coaxial else flight.damage_yaw_authority == 0,"%d yaw type" % number)
		check(flight.damage_yaw_damping < .5,"%d reduced yaw stability" % number)
		model.damage_zone(&"engine",model.get_zone_max_health(&"engine"))
		engine.engine_set_power(.12)
		check(engine.damage_disabled and not engine.is_engine_working and engine.throttle_input == .12,"%d failed engine collective" % number)
		flight._update_rotor_energy(.1)
		check(flight.rotor_energy.rpm > .8 and flight.rotor_energy.autorotating,"%d freewheel" % number)
		var state := preload("res://Aircraft/AircraftRuntimeState.gd").capture(craft)
		var saved_rpm := flight.rotor_energy.rpm
		check(preload("res://Aircraft/AircraftRuntimeState.gd").validate(state),"%d valid save" % number)
		var other := spawn(number)
		other.position.x = 100
		while not other.runtime_initialized: await get_tree().process_frame
		var count := host.get_child_count()
		preload("res://Aircraft/AircraftRuntimeState.gd").restore(other,state)
		check(host.get_child_count() == count,"%d restore replayed debris" % number)
		check(other.get_node("PartDamageModel").is_zone_destroyed(&"tail"),"%d restored tail" % number)
		check(other.get_node("Engine").damage_disabled,"%d restored engine" % number)
		check(is_equal_approx(other.get_node("SimpleAero").rotor_energy.rpm,saved_rpm),"%d restored RPM" % number)
		other.free()
		craft.free()
		for node in host.get_children(): node.queue_free()
		await get_tree().physics_frame
	await projectile_case()
	for kind in ["terrain","carrier","aircraft"]: await rotor_contact_case(kind)
	await rotor_contact_case("tail_rotor")
	await rotor_contact_case("swept")
	for failure in failures: push_error(failure)
	print("HELICOPTER_DAMAGE_", "PASS" if failures.is_empty() else "FAIL", " ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func clear_case() -> void:
	for node in host.get_children(): node.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

func obstacle(at: Vector3, size: Vector3, group: String) -> StaticBody3D:
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

func rotor_contact_case(kind: String) -> void:
	var craft := spawn(10)
	while not craft.runtime_initialized: await get_tree().process_frame
	prime(craft)
	var model = craft.get_node("PartDamageModel")
	var area: Area3D = model.rotor_areas[1 if kind == "tail_rotor" else 0]
	await get_tree().physics_frame
	await get_tree().physics_frame
	var point: Vector3 = area.to_global(Vector3(area.radius*.7,0,0))
	if kind == "swept": point += Vector3(0,0,10)
	obstacle(point,Vector3(.1,.1,.1),kind)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if kind == "swept":
		craft.position.z += 20
		area.check_contact()
	else: area.check_contact()
	if not model.is_zone_destroyed(area.zone):
		print("ROTOR_CONTACT_MISS ",kind," active=",area.active," shape=",area._query.transform," point=",point," local=",area.to_local(point)," hits=",craft.get_world_3d().direct_space_state.intersect_shape(area._query,8))
	check(model.is_zone_destroyed(area.zone),kind+" rotor physical disc contact")
	check(not craft._has_exploded and not craft.get_meta("pilot_dead",false),kind+" rotor strike also killed pilot")
	if area.zone == &"main_rotor":
		check(craft.get_node("SimpleAero").damage_rotor_lift == 0,"lost rotor still lifts")
		for blade in craft.get_node("RotorAssembly/UpperRotor").get_children():
			if str(blade.name).begins_with("Blade"): check(not blade.visible,"lost rotor blade remains visible")
	else:
		craft.get_node("Engine")._apply_propeller_blur_t(1.0)
		for disc in craft.get_node("Engine")._prop_disc_mesh_nodes: check(not disc.visible,"lost tail rotor blur returned")
	await clear_case()

func projectile_case() -> void:
	var craft := spawn(10)
	while not craft.runtime_initialized: await get_tree().process_frame
	prime(craft)
	var model = craft.get_node("PartDamageModel")
	var area: Area3D = model.rotor_areas[0]
	var point: Vector3 = area.to_global(Vector3(area.radius*.7,0,0))
	var target := obstacle(point+Vector3.DOWN*3,Vector3(.4,.2,.4),"")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var bullet := preload("res://Projectiles/Bullet/bullet.tscn").instantiate() as Bullet
	host.add_child(bullet)
	bullet.set_physics_process(false)
	bullet.damage = .01
	bullet.damage_amount = .01
	bullet.ground_particle_count = 0
	bullet.hit_debris_count = 0
	bullet.virtual_impact_count = 0
	bullet.explosion_scene = null
	var rotor_hits := 0
	var through_hits := 0
	seed(47221)
	for i in 200:
		bullet._passed_rotor_discs.clear()
		var hit: Dictionary = bullet._query_rotor_hit(point+Vector3.UP*2,point+Vector3.DOWN*4,true)
		if not hit.is_empty(): rotor_hits += 1
		else:
			var body_hit := craft.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point+Vector3.DOWN*4))
			if body_hit.get("collider") == target: through_hits += 1
	check(rotor_hits > 0 and rotor_hits < 40 and through_hits > 160,"live sparse query did not pass most rounds through disc")
	var before: float = model.get_zone_health(&"main_rotor")
	bullet._passed_rotor_discs.clear()
	bullet._sweep_point_collision(area.global_position+Vector3.UP*2,area.global_position+Vector3.DOWN*2)
	check(model.get_zone_health(&"main_rotor") < before,"actual bullet impact did not damage rotor hub")
	check(model.get_zone_health(&"engine") == model.get_zone_max_health(&"engine"),"rotor hub hit leaked into engine health")
	print("HELICOPTER_BULLETS rotor_hits=",rotor_hits," passed=",through_hits)
	await clear_case()
