extends SceneTree


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "BombBlastMarkerSmoketest"
	root.add_child(scene)
	current_scene = scene

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 10.0, 1600.0)
	scene.add_child(camera)
	camera.current = true

	var impact_budget: Node = root.get_node_or_null("BulletImpactBudget")
	_expect(impact_budget != null, "BulletImpactBudget autoload was unavailable")
	if impact_budget != null:
		_expect(
			not bool(impact_budget.call("should_spawn_visual", Vector3.ZERO)),
			"test impact was not outside the ordinary 1.2 km visual budget"
		)

	var ground := StaticBody3D.new()
	ground.name = "TerrainGround"
	ground.position = Vector3(0.0, -0.5, 0.0)
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(80.0, 1.0, 80.0)
	ground_shape.shape = ground_box
	ground.add_child(ground_shape)
	scene.add_child(ground)

	var turret_scene := load("res://Buildings/gun_emplacement.tscn") as PackedScene
	_expect(turret_scene != null, "enemy turret scene did not load")
	if turret_scene == null:
		_finish(scene)
		return
	var turret := turret_scene.instantiate() as StaticBody3D
	_expect(turret != null, "enemy turret scene did not instantiate")
	if turret == null:
		_finish(scene)
		return
	turret.name = "EnemyTurret"
	turret.set("inactive_when_no_targets", false)
	turret.set("is_dummy", true)
	turret.set_meta("suppress_enemy_ops_on_destroy", true)
	scene.add_child(turret)

	var bomb_scene := load("res://Projectiles/BombNew/bomb_new.tscn") as PackedScene
	_expect(bomb_scene != null, "bomb scene did not load")
	if bomb_scene == null:
		_finish(scene)
		return
	var bomb := bomb_scene.instantiate() as RigidBody3D
	_expect(bomb != null, "bomb scene did not instantiate")
	if bomb == null:
		_finish(scene)
		return
	bomb.freeze = true
	bomb.position = Vector3(0.0, 2.2, 0.0)
	scene.add_child(bomb)

	await physics_frame
	bomb.call("_trigger_explosion", turret)

	var marker := _find_blast_marker(scene)
	_expect(marker != null, "bomb impact did not create a persistent blast marker")
	if marker != null:
		_expect(marker.texture_albedo != null, "blast marker did not receive its scorch texture")
		_expect(
			absf(marker.global_position.y - 0.02) < 0.06,
			"direct-hit marker projected onto the turret instead of the surviving ground: y=%.3f" % marker.global_position.y
		)
		_expect(
			is_equal_approx(marker.size.x, 30.0) and is_equal_approx(marker.size.z, 30.0),
			"bomb marker did not use the configured 30 m blast footprint"
		)

	for _frame in range(4):
		await process_frame
	_expect(not is_instance_valid(turret), "destroyed turret fixture did not leave the scene")
	_expect(
		marker != null and is_instance_valid(marker) and marker.get_parent() == scene,
		"blast marker disappeared with the destroyed turret"
	)
	_finish(scene)


func _find_blast_marker(node: Node) -> Decal:
	if node is Decal:
		var decal := node as Decal
		if decal.texture_albedo != null:
			return decal
	for child in node.get_children():
		var marker := _find_blast_marker(child)
		if marker != null:
			return marker
	return null


func _finish(scene: Node) -> void:
	var passed := _failures.is_empty()
	current_scene = null
	if scene != null and is_instance_valid(scene):
		if scene.get_parent() != null:
			scene.get_parent().remove_child(scene)
		scene.free()
	if passed:
		print("[BombBlastMarkerSmoketest] PASS forced=persistent projection=ground footprint=30m")
		quit(0)
		return
	print("[BombBlastMarkerSmoketest] %d failure(s)" % _failures.size())
	quit(1)


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("[BombBlastMarkerSmoketest] FAIL: %s" % description)
