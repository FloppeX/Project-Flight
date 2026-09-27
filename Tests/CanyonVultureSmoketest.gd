extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene

	var manager := load("res://Wildlife/WildlifeManager.gd").new() as Node3D
	scene.add_child(manager)
	manager.set_process(false)
	var bird: Node = manager.call("spawn_vulture", Vector3(100.0, 400.0, 200.0), 180.0, 0.0, 1.0)
	if bird == null or not bird.is_in_group("wildlife"):
		_fail("vulture scene did not spawn as wildlife")
		return
	var left_wing := bird.find_child("wing left", true, false) as Node3D
	var right_wing := bird.find_child("wing right", true, false) as Node3D
	if left_wing == null or right_wing == null:
		_fail("separate GLB wing meshes were not found")
		return
	var resting_left := left_wing.rotation_degrees.z
	var resting_right := right_wing.rotation_degrees.z
	bird.call("_start_flap_burst", 2)
	bird.call("_update_wings", 0.18)
	if absf(left_wing.rotation_degrees.z - resting_left) < 10.0 \
			or absf(right_wing.rotation_degrees.z - resting_right) < 10.0:
		_fail("procedural flap did not move both authored wing meshes")
		return
	if not is_equal_approx(left_wing.rotation_degrees.z, -right_wing.rotation_degrees.z):
		_fail("wing flap was not mirrored")
		return

	var session := root.get_node("GameSession")
	var original_approval := int(session.get("public_approval"))
	var original_incidents := int(session.get("wildlife_incidents"))
	session.set("public_approval", 100)
	session.set("wildlife_incidents", 0)
	var attacker := Node3D.new()
	attacker.add_to_group("aircraft")
	scene.add_child(attacker)
	var projectile: Node = load("res://Projectiles/ProjectileNew/projectile_new.gd").new()
	scene.add_child(projectile)
	projectile.set("shooter", attacker)
	projectile.call("_apply_impact_damage", bird, 20.0)
	if int(session.get("public_approval")) != 85 or int(session.get("wildlife_incidents")) != 1:
		_restore_reputation(session, original_approval, original_incidents)
		_fail("player wildlife kill did not apply the persistent approval consequence")
		return
	var saved: Dictionary = session.call("capture_save_state")
	if int(saved.get("public_approval", -1)) != 85 or int(saved.get("wildlife_incidents", -1)) != 1:
		_restore_reputation(session, original_approval, original_incidents)
		_fail("wildlife consequence was absent from campaign save state")
		return

	_restore_reputation(session, original_approval, original_incidents)
	print("CANYON_VULTURE_PASS wings=procedural_glide_flap spawn=rare_canyon kill=approval_minus_15")
	quit(0)


func _restore_reputation(session: Node, approval: int, incidents: int) -> void:
	session.set("public_approval", approval)
	session.set("wildlife_incidents", incidents)


func _fail(reason: String) -> void:
	push_error("CANYON_VULTURE_FAIL: %s" % reason)
	quit(1)
