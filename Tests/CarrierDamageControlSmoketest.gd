extends SceneTree

var failures: Array[String] = []
class Stores:
	extends Node
	var plasteel_units := 1000.0
	var corium_units := 1000.0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func run() -> void:
	var carrier := (load("res://Tests/Fixtures/ModularTurretCarrierFixture.gd") as Script).new() as Node3D
	carrier.process_mode = Node.PROCESS_MODE_DISABLED
	(carrier as CollisionObject3D).disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	var stores := Stores.new()
	stores.name = "CarrierManager"
	carrier.add_child(stores)
	var control := (load("res://LandCarrier/CarrierDamageControl.gd") as Script).new() as Node
	control.name = "CarrierDamageControl"
	carrier.add_child(control)
	var mesh := MeshInstance3D.new()
	mesh.name = "catapult 1"
	mesh.mesh = BoxMesh.new()
	mesh.position = Vector3(20, 0, 0)
	carrier.add_child(mesh)
	root.add_child(carrier)
	control.call("refresh_regions")
	check(control.call("region_at", mesh.global_position) == "catapults", "authored impact region was not found")
	for amount in [5.0, 10.0, 20.0]:
		carrier.call("take_damage_at", amount, mesh.global_position, -1)
	check(control.get("structure") == 2000.0, "armor failed to block small hits")
	carrier.call("take_damage_at", 30.0, mesh.global_position, -1)
	check(control.get("structure") == 1990.0, "armor deduction was wrong")
	check((control.get("systems") as Dictionary).catapults.condition == 97.0, "localized wear was wrong")
	carrier.call("take_damage_event", 70.0, mesh.global_position, "round1")
	carrier.call("take_damage_event", 45.0, mesh.global_position, "round1")
	control.call("flush_hits", true)
	check(control.get("structure") == 1940.0, "impact/blast was double counted")
	carrier.call("take_damage_event", 70.0, mesh.global_position, "round1")
	control.call("flush_hits", true)
	check(control.get("structure") == 1940.0, "duplicate event was applied twice")
	var pristine: Dictionary = control.call("capture_save_state")
	control.call("damage_system", "drive", 50.0)
	check(carrier.call("get_system_capability", "drive") == 0.5, "degraded drive did not lose capability")
	control.call("set_isolated", "drive", true)
	check(carrier.call("get_system_capability", "drive") == 0.0, "isolated drive stayed operational")
	control.call("set_isolated", "drive", false)
	var systems: Dictionary = control.get("systems")
	systems.catapults.fire = 35.0
	systems.hangar.fire = 35.0
	control.call("set_urgent", "drive")
	control.call("advance", 0.25)
	var jobs: Array = control.get("teams")
	check(jobs[0].task == "Fire suppression" and jobs[1].task == "Fire suppression", "urgent repair preempted firefighting")
	control.call("set_isolated", "catapults", true)
	check(not control.call("set_isolated", "catapults", false), "burning compartment could be reconnected")
	control.set("repairs_enabled", false)
	stores.plasteel_units = 0.0
	for i in range(120):
		control.call("advance", 0.25)
	check(systems.catapults.fire == 0.0 and systems.hangar.fire == 0.0, "firefighting required material or enabled repairs")
	check(control.call("status", "catapults") == "ISOLATED", "fire containment silently reconnected system")
	control.call("set_isolated", "catapults", false)
	control.set("repairs_enabled", true)
	stores.plasteel_units = 101.0
	control.set("repair_reserve", 100.0)
	for i in range(240):
		control.call("advance", 0.25)
	check(stores.plasteel_units >= 100.0 and stores.plasteel_units < 101.0, "repairs ignored material cost/reserve")
	var saved: Dictionary = carrier.call("capture_save_state")
	check(saved.has("damage_control"), "carrier save omitted damage control")
	check(carrier.call("restore_save_state", saved), "carrier damage save restore failed")
	check((control.call("capture_save_state") as Dictionary).systems == saved.damage_control.systems, "restoration lost condition/fire/isolation")
	check(not control.call("restore_save_state", {"structure": 100.0, "systems": {}}), "invalid save was accepted")
	check(control.get("structure") == saved.damage_control.structure, "invalid restore mutated structure")
	# Use the carrier's actual speed telemetry (it moves by position, not velocity).
	carrier.set("_last_planar_speed_mps", 5.0)
	stores.plasteel_units = 1000.0
	check(not control.call("_can_repair", "hull"), "structural repairs were allowed while moving")
	carrier.set("_last_planar_speed_mps", 0.0)
	control.set("_quiet_time", 60.0)
	check(control.call("_can_repair", "hull"), "stopped carrier could not repair structure")
	var deck := (load("res://Tests/Fixtures/DamageControlDeckFixture.gd") as Script).new() as Node
	carrier.add_child(deck)
	control.call("set_isolated", "catapults", true)
	check(not deck.call("_damage_control_allows", ["flight", "catapults"]), "damaged catapult did not hold launch path")
	check(deck.call("_damage_control_allows", ["flight"]), "catapult isolation incorrectly blocked recovery")
	control.call("set_isolated", "catapults", false)
	var scene := load("res://LandCarrier/CarrierDefenseTurretPosition.tscn") as PackedScene
	var site := scene.instantiate() as Node3D
	site.name = "DamageTestMount"
	site.position = Vector3(20, 10, 20)
	carrier.add_child(site)
	site.call("build_turret", 10)
	control.call("refresh_regions")
	var gun: Node = site.get("built_turret")
	var mount_id := "mount:" + str(carrier.get_path_to(site))
	check((control.get("systems") as Dictionary).has(mount_id), "built mount was not tracked individually")
	control.call("damage_system", mount_id, 100.0)
	check(carrier.call("get_system_capability", "defenses", gun) == 0.0, "destroyed local mount retained firing capability")
	check(carrier.call("get_system_capability", "defenses") == 1.0, "one mount failure disabled all defenses")
	check((gun.call("get_defense_candidates") as Array).is_empty(), "offline turret remained available to DefenseOps")
	await physics_frame
	await physics_frame
	var body_mesh := gun.find_child("turret body", true, false) as MeshInstance3D
	var aim_point := body_mesh.global_transform * body_mesh.mesh.get_aabb().get_center()
	var query := PhysicsRayQueryParameters3D.create(aim_point + Vector3(10, 0, 0), aim_point, 1 << 19)
	var hit := carrier.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty(), "exposed turret could not be struck by projectile ray")
	check(control.call("region_at", aim_point) == mount_id, "turret impact did not map to local mount")
	site.call("clear_turret")
	control.call("refresh_regions")
	check(not (control.get("systems") as Dictionary).has(mount_id), "removed mount left a phantom repair job")
	# Real physics query: a blast near a long hull must not use origin distance,
	# and multiple collision shapes on one body must not multiply damage.
	var collision := CollisionShape3D.new()
	var hull_box := BoxShape3D.new()
	hull_box.size = Vector3(4, 4, 100)
	collision.shape = hull_box
	carrier.add_child(collision)
	var second_collision := CollisionShape3D.new()
	second_collision.shape = hull_box
	carrier.add_child(second_collision)
	await physics_frame
	await physics_frame
	var blast := (load("res://Projectiles/Explosion/explosion.gd") as Script).new() as Node3D
	blast.set("_triggered", true)
	blast.set("visual_effects_enabled", false)
	blast.set("play_explosion_audio", false)
	blast.set("blast_radius", 10.0)
	blast.set("max_damage", 100.0)
	blast.set("min_damage", 0.0)
	blast.position = Vector3(0, 0, 51)
	root.add_child(blast)
	var hull_before: float = control.get("structure")
	blast.call("deal_explosion_damage")
	control.call("flush_hits", true)
	check(is_equal_approx(hull_before - float(control.get("structure")), 70.0), "blast falloff or compound-shape deduplication was wrong: damage=%.2f" % (hull_before - float(control.get("structure"))))
	blast.free()
	# Deferred pending-load startup restores damage before normal simulation.
	var session := root.get_node("GameSession")
	var previous_pending: Dictionary = session.get("_pending_save_state")
	session.set("_pending_save_state", {"campaign": {"carrier": saved}})
	control.call("_restore_pending_state")
	session.set("_pending_save_state", previous_pending)
	check(control.get("structure") == saved.damage_control.structure, "pending-load state did not restore integrity")
	# Actual UI callbacks must mutate the live simulation, not private preview data.
	var page := (load("res://UI/CarrierPage.gd") as Script).new() as Control
	root.add_child(page)
	page.call("bind_damage_control", control)
	page.call("_select_system", "drive")
	page.call("_request_urgent")
	check(control.get("urgent") == "", "UI urgent toggle did not change authoritative priority")
	page.call("_toggle_isolation")
	check(control.call("status", "drive") == "ISOLATED", "UI isolation did not reach simulation")
	page.call("_cycle_repair_priority")
	check(control.get("doctrine") == "FLIGHT OPS", "UI doctrine remained cosmetic")
	page.call("_toggle_repairs")
	check(not control.get("repairs_enabled"), "UI repair switch remained cosmetic")
	var snapshot: Dictionary = page.call("get_debug_snapshot")
	check(snapshot.telemetry_connected and not snapshot.mock_data, "UI did not bind live telemetry")
	control.call("restore_save_state", pristine)
	carrier.call("take_damage", 10000.0)
	check(control.get("lost") and carrier.call("get_system_capability", "drive") == 0.0, "zero integrity did not disable carrier")
	var before: float = control.get("structure")
	control.call("advance", 100.0)
	check(control.get("structure") == before, "lost carrier repaired itself")
	page.free()
	carrier.free()
	await process_frame
	if failures.is_empty():
		print("CARRIER_DAMAGE_CONTROL_SMOKETEST_OK armor localization dedup crews fires repairs reserve save UI loss")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)
