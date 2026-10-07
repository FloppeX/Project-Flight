extends "res://Tests/RegionalAircraftDamageSmoketest.gd"

const CONTACT := preload("res://Aircraft/AircraftGroundContact.gd")
const RUNTIME := preload("res://Aircraft/AircraftRuntimeState.gd")
var camera: Camera3D

func _run() -> void:
	get_tree().create_timer(110.0).timeout.connect(func(): get_tree().quit(1))
	for singleton in ["AirOpsManager", "GroundOpsManager", "OperationsCoordinator", "FlightDirector"]:
		var node := get_node_or_null("/root/" + singleton)
		if node != null: node.process_mode = Node.PROCESS_MODE_DISABLED
	host = Node3D.new()
	add_child(host)
	for number in [1,2,3,4,5,6,7,8,14,16]:
		await check_gear(number)
	await check_contact_ownership()
	add_ground()
	await gear_landing()
	await strike(&"left_wing", "LeftWingDamageCollider")
	await strike(&"tail", "HorizontalStabilizerDamageCollider")
	for failure in failures: push_error(failure)
	print("ROUGH_LANDING_DAMAGE_%s gear_fleet=10 region_ownership=true physical_strikes=gear,wing,tail" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

func clear_aircraft() -> void:
	for child in host.get_children():
		if child is RigidBody3D: child.queue_free()
	await get_tree().process_frame

func check_gear(number: int) -> void:
	var craft := spawn(number)
	while not craft.runtime_initialized: await get_tree().process_frame
	var gear := craft.get_node("LandingGear") as AircraftModule_LandingGear
	var visible_count := 0
	for visual in gear.get_damage_visual_roots():
		if is_instance_valid(visual) and visual.is_visible_in_tree(): visible_count += 1
	check(visible_count == 3, "%d does not have three visible gear assemblies: %s" % [number, gear.get_damage_visual_roots()])
	gear.shear_from_damage()
	await get_tree().process_frame
	var debris_count := 0
	for child in host.get_children():
		if child.get_meta("damage_debris_zone", &"") == &"landing_gear":
			debris_count += 1
			check(child is RigidBody3D and child.get_child_count() >= 2, "%d gear lacks physical debris" % number)
	check(debris_count == visible_count, "%d gear debris %d does not match assemblies %d" % [number, debris_count, visible_count])
	for visual in gear.get_damage_visual_roots():
		if is_instance_valid(visual): check(not visual.is_visible_in_tree(), "%d original gear remains visible" % number)
	for collider in gear.gear_collision_shapes: check(collider.disabled, "%d lost wheel still supports plane" % number)
	var count := host.get_child_count()
	gear.shear_from_damage()
	check(count == host.get_child_count(), "%d repeated shear duplicated gear" % number)
	var saved := RUNTIME.capture(craft)
	check(RUNTIME.validate(saved), "%d sheared gear state invalid" % number)
	var restored := spawn(number)
	while not restored.runtime_initialized: await get_tree().process_frame
	count = host.get_child_count()
	RUNTIME.restore(restored, saved)
	check(count == host.get_child_count(), "%d restore replayed gear debris" % number)
	check(bool(restored.get_meta("gear_sheared", false)), "%d gear shear not saved" % number)
	await get_tree().physics_frame
	for visual in restored.get_node("LandingGear").get_damage_visual_roots():
		if is_instance_valid(visual): check(not visual.visible, "%d saved gear reappeared" % number)
	print("GEAR_SHEAR_CASE ", number, " debris=", debris_count)
	await clear_aircraft()

func contact(zone: StringName, impact: float = 8.0) -> Dictionary:
	return {"normal": Vector3.UP, "impact": impact, "gear": zone == &"gear", "shape": -1, "position": Vector3.ZERO}

func check_contact_ownership() -> void:
	var craft := spawn(5)
	while not craft.runtime_initialized: await get_tree().process_frame
	var model := craft.get_node("PartDamageModel") as AircraftPartDamageModel
	var handler := CONTACT.new()
	craft._regional_ground_contact = handler
	craft.linear_velocity = Vector3(0,0,45)
	handler._queue_contact(&"gear", contact(&"gear", 11.0))
	handler._queue_contact(&"left_wing", contact(&"left_wing", 8.0))
	handler._queue_contact(&"tail", contact(&"tail", 8.0))
	handler.update(craft, 1.0/60.0)
	check(model.get_zone_health(&"left_wing") < model.get_zone_max_health(&"left_wing"), "gear impact masked wing contact")
	check(model.get_zone_health(&"tail") < model.get_zone_max_health(&"tail"), "gear impact masked tail contact")
	check(model.get_zone_health(&"cockpit") == model.get_zone_max_health(&"cockpit"), "appendage hit damaged cockpit")
	var hp := model.get_zone_health(&"left_wing")
	for i in 5: handler._queue_contact(&"left_wing", contact(&"left_wing", 8.0))
	handler.update(craft, 1.0/60.0)
	check(is_equal_approx(model.get_zone_health(&"left_wing"), hp), "duplicate contact points multiplied impact damage")
	for frame in 180:
		handler._queue_contact(&"left_wing", contact(&"left_wing", 0.0))
		handler._queue_contact(&"tail", contact(&"tail", 0.0))
		handler.update(craft, 1.0/60.0)
	check(model.is_zone_destroyed(&"left_wing") and model.is_zone_destroyed(&"tail"), "sustained scrape did not tear weakened parts away")
	check(not craft._has_exploded and not bool(craft.get_meta("pilot_dead", false)), "appendage scrape killed the pilot or plane")
	craft.angular_velocity = Vector3.ZERO
	model._physics_process(1.0/60.0)
	check(craft.angular_velocity.is_zero_approx(), "grounded tail wreck received prescribed airborne spin")
	await clear_aircraft()

func add_ground() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "TerrainFixture"
	floor_body.add_to_group("terrain")
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000,1,1000)
	collider.shape = box
	collider.position.y = -.5
	floor_body.add_child(collider)
	host.add_child(floor_body)
	if DisplayServer.get_name() == "headless": return
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = box.size
	floor_mesh.position = collider.position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("716e56")
	floor_mesh.material_override = material
	floor_body.add_child(floor_mesh)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("253441")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .6
	host.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,25,0)
	host.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18
	host.add_child(camera)

func gear_landing() -> void:
	var craft := spawn(5)
	while not craft.runtime_initialized: await get_tree().process_frame
	craft.position = Vector3(0,3.5,0)
	craft.get_node("SimpleAero").set_physics_process(false)
	craft.get_node("Engine").engine_stop()
	craft.freeze = false
	craft.linear_velocity = Vector3(0,-11,40)
	var sheared := false
	var belly := false
	var final_speed := 40.0
	for frame in 360:
		await get_tree().physics_frame
		if not is_instance_valid(craft) or craft._has_exploded: break
		sheared = sheared or bool(craft.get_meta("gear_sheared", false))
		belly = belly or craft.get_meta("ground_landing_mode", "") == "belly"
		final_speed = craft.linear_velocity.length()
		if camera != null:
			camera.position = craft.position + Vector3(12,9,-14)
			camera.look_at(craft.position)
			camera.make_current()
	var survived := is_instance_valid(craft) and not craft._has_exploded and not craft._critical_damage_active and not bool(craft.get_meta("pilot_dead", false))
	check(sheared, "rough wheel arrival did not shear gear")
	check(belly and final_speed < 30.0, "sheared gear did not transition to slowing belly slide")
	check(survived, "rough gear arrival did not leave surviving pilot and airframe")
	if survived:
		for visual in craft.get_node("LandingGear").get_damage_visual_roots():
			check(not visual.is_visible_in_tree(), "sheared gear reappeared during slide")
		if camera != null:
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/rough_landing"))
			get_viewport().get_texture().get_image().save_png("res://captures/rough_landing/gear.png")
	print("ROUGH_GEAR_LANDING sheared=", sheared, " belly=", belly, " survived=", survived, " speed=", final_speed)
	await clear_aircraft()


func strike(zone: StringName, collider_name: String) -> void:
	var craft := spawn(5)
	while not craft.runtime_initialized: await get_tree().process_frame
	craft.position = Vector3(0,2.5,0)
	craft.get_node("SimpleAero").set_physics_process(false)
	craft.get_node("Engine").engine_stop()
	craft.get_node("LandingGear").shear_from_damage(false)
	var part := craft.get_node(collider_name) as CollisionShape3D
	var obstacle := StaticBody3D.new()
	obstacle.name = "TerrainRidge"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, .4, 2.0)
	shape.shape = box
	obstacle.add_child(shape)
	host.add_child(obstacle)
	obstacle.global_position = part.global_position + Vector3(0,-.8,1.0)
	craft.freeze = false
	craft.linear_velocity = Vector3(0,-13.5,18)
	var torn := false
	var hull := 1.0
	for frame in 360:
		await get_tree().physics_frame
		if not is_instance_valid(craft) or craft._has_exploded: break
		var model := craft.get_node("PartDamageModel") as AircraftPartDamageModel
		torn = torn or model.is_zone_destroyed(zone)
		hull = model.systems.fraction(&"fuselage")
		if camera != null:
			camera.position = craft.position + Vector3(12,9,-14)
			camera.look_at(craft.position)
			camera.make_current()
	check(torn, "%s ridge contact did not detach part" % zone)
	var survived := is_instance_valid(craft) and not craft._has_exploded and not craft._critical_damage_active and not bool(craft.get_meta("pilot_dead", false))
	check(survived, "%s ridge contact did not leave surviving pilot and airframe" % zone)
	print("ROUGH_STRIKE ", zone, " detached=",torn," survived=",survived," hull=",hull," state=",craft.global_position if is_instance_valid(craft) else Vector3.INF)
	if survived:
		check(craft.angular_velocity.length() < .5, "%s wreck did not settle" % zone)
		if camera != null:
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/rough_landing"))
			get_viewport().get_texture().get_image().save_png("res://captures/rough_landing/%s.png" % zone)
	obstacle.queue_free()
	await clear_aircraft()
