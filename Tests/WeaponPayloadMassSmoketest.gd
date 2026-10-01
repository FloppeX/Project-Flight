extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var count := 0
	for id in range(1, 16):
		var path := "res://Aircraft/Aircraft_%d.tscn" % id
		if not ResourceLoader.exists(path):
			continue
		var craft = load(path).instantiate()
		var authored_mass: float = craft.mass
		craft.freeze = true
		craft.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		craft.process_mode = Node.PROCESS_MODE_DISABLED
		world.add_child(craft)
		await process_frame
		check(is_equal_approx(craft.get_unloaded_mass_kg(), authored_mass), "base mass changed %d" % id)
		var baseline: float = craft.mass
		check(baseline > authored_mass, "authored weapons have no mass %d" % id)
		var station = load("res://Weapons/hardpoint.gd").new()
		craft.add_child(station)
		for spec in [
			["res://Weapons/Guns/Hardpoint/10mm_machine_gun_hardpoint.tscn", 43.0, 0.04, 35.0, 200],
			["res://Weapons/Guns/Hardpoint/15mm_machine_gun_hardpoint.tscn", 75.0, 0.1, 55.0, 200],
			["res://Weapons/Guns/Hardpoint/20mm_autocannon_hardpoint.tscn", 122.5, 0.25, 85.0, 150],
			["res://Weapons/Guns/Hardpoint/25mm_autocannon_hardpoint.tscn", 155.0, 0.45, 110.0, 100],
			["res://Weapons/Turrets/40mm_autocannon_weapon.tscn", 275.0, 0.95, 180.0, 100],
			["res://Weapons/RocketPod/rocket_pod.tscn", 200.0, 5.0, 80.0, 24],
		]:
			check(station.mount_weapon_from_scene(load(spec[0])), "mount %d %s" % [id, spec[0]])
			await process_frame
			var weapon = station.weapon_instance
			check(weapon.ammo_count == spec[4], "full ammunition load %d %s" % [id, spec[0]])
			if spec[0] == "res://Weapons/Turrets/40mm_autocannon_weapon.tscn":
				weapon.infinite_ammo = false
			check(absf(craft.mass - baseline - spec[1]) < 0.02, "loaded weight %d %s" % [id, spec[0]])
			check(weapon.fire(), "weapon firing %d %s" % [id, spec[0]])
			check(weapon.ammo_count == spec[4] - 1, "one round consumed %d %s" % [id, spec[0]])
			check(absf(craft.mass - baseline - spec[1] + spec[2]) < 0.02, "firing sheds round weight %d" % id)
			if weapon.has_method("cancel_burst"):
				weapon.cancel_burst()
			weapon.ammo_count += 1
			weapon.ammo_count -= 1
			check(absf(craft.mass - baseline - spec[1] + spec[2]) < 0.02, "ammo consumption %d" % id)
			weapon.ammo_count += 1
			check(absf(craft.mass - baseline - spec[1]) < 0.02, "rearm %d" % id)
			weapon.ammo_count = 0
			check(absf(craft.mass - baseline - spec[3]) < 0.02, "empty hardware %d" % id)
			weapon.free()
			station.weapon_instance = null
			check(absf(craft.mass - baseline) < 0.02, "unmount %d" % id)
		check(station.mount_weapon_from_scene(load("res://Weapons/Bomb/bomb_rack.tscn")), "bomb rack mount")
		await process_frame
		var rack = station.weapon_instance
		var bomb_count: int = rack.ammo_count
		check(bomb_count > 0 and absf(craft.mass - baseline - bomb_count * 50.0) < 0.02, "bomb rack weight %d" % id)
		check(rack.fire(), "bomb release %d" % id)
		check(absf(craft.mass - baseline - (bomb_count - 1) * 50.0) < 0.02, "released bomb weight %d" % id)
		await physics_frame
		await process_frame
		check(station.mount_weapon_from_scene(load("res://Weapons/RocketPod/rocket_pod.tscn")), "replace loaded rack")
		await process_frame
		check(absf(craft.mass - baseline - 200.0) < 0.02, "replacement double counted %d" % id)
		var aero = craft.get_node("SimpleAero")
		if aero.has_method("_get_lift_reference_mass_kg"):
			check(is_equal_approx(aero._get_lift_reference_mass_kg(), authored_mass), "rotor power increased with load %d" % id)
		else:
			check(is_equal_approx(aero.get_lift_reference_mass_kg(), authored_mass), "wing lift increased with load %d" % id)
		station.free()
		check(absf(craft.mass - baseline) < 0.02, "station removal weight %d" % id)
		var pilot = craft.get_node_or_null("HelicopterPilot")
		if pilot != null:
			var rescued := Node3D.new()
			world.add_child(rescued)
			if pilot.can_accept_passenger():
				check(pilot.add_passenger(rescued), "passenger boarding %d" % id)
				check(absf(craft.mass - baseline - 80.0) < 0.02, "passenger 80kg %d" % id)
				check(aero.get_max_static_rotor_thrust_n() > craft.mass * 9.8, "loaded rescue cannot hover %d" % id)
				var boarded := 1
				while pilot.can_accept_passenger():
					var extra := Node3D.new()
					world.add_child(extra)
					check(pilot.add_passenger(extra), "additional passenger %d" % id)
					boarded += 1
					extra.queue_free()
				check(absf(craft.mass - baseline - boarded * 80.0) < 0.02, "full cabin weight %d" % id)
				check(aero.get_max_static_rotor_thrust_n() > craft.mass * 9.8, "full cabin cannot hover %d" % id)
				pilot.disembark_passengers()
				check(absf(craft.mass - baseline) < 0.02, "passenger disembark weight %d" % id)
			if is_instance_valid(rescued):
				rescued.queue_free()
		print("PAYLOAD_AIRCRAFT id=%d unloaded=%.1f authored_loaded=%.1f" % [id, authored_mass, baseline])
		craft.queue_free()
		await process_frame
		count += 1
	world.queue_free()
	await process_frame
	print("WEAPON_PAYLOAD_MASS_", "PASS" if failures.is_empty() else "FAIL", " aircraft=", count, " ", failures)
	quit(0 if failures.is_empty() else 1)
