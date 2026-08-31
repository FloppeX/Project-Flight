extends SceneTree


class TestEnemy:
	extends Node3D

	var team: int = 2

	func get_team() -> int:
		return team


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "DistantEnemyContrastSmoketest"
	root.add_child(scene)
	current_scene = scene

	var camera := Camera3D.new()
	camera.current = true
	scene.add_child(camera)

	var budget := root.get_node_or_null("EnemyVisualBudget")
	_expect(budget != null, "EnemyVisualBudget autoload was unavailable")
	if budget == null:
		await _finish(scene)
		return
	var budget_was_enabled: bool = bool(budget.get("enabled"))
	var original_start_distance := float(budget.get("enemy_contrast_start_distance_m"))
	var original_full_distance := float(budget.get("enemy_contrast_full_distance_m"))
	var original_max_strength := float(budget.get("enemy_max_contrast_strength"))
	budget.set("enabled", false)

	var targets: Array[Node3D] = []
	var aircraft := _make_target(scene, "EnemyAircraft", ["enemies", "aircraft"], Vector3(-300.0, 500.0, -4200.0))
	var vehicle := _make_target(scene, "EnemyGroundVehicle", ["enemies", "ground_vehicles"], Vector3(-100.0, -300.0, -4200.0))
	var structure := _make_target(scene, "EnemyStructure", ["enemies", "buildings"], Vector3(100.0, -300.0, -4200.0))
	var emplacement := _make_target(scene, "EnemyEmplacement", ["enemies", "buildings", "gun_emplacements"], Vector3(300.0, -300.0, -4200.0))
	targets.assign([aircraft, vehicle, structure, emplacement])

	var friendly := _make_target(scene, "FriendlyVehicle", ["friendlies", "ground_vehicles"], Vector3(0.0, -300.0, -4200.0))
	friendly.team = 1

	var candidates: Array = budget.call("_collect_contrast_candidates") as Array
	for target in targets:
		_expect(candidates.has(target), "%s was absent from the all-enemy contrast budget" % target.name)
	_expect(not candidates.has(friendly), "friendly vehicle entered the all-enemy contrast budget")

	budget.call("_update_enemy_contrast", targets, camera)
	for target in targets:
		var geometry := target.get_node("Geometry") as GeometryInstance3D
		_expect(_has_contrast_overlay(geometry), "%s did not receive distant contrast" % target.name)
		_expect(target.scale.is_equal_approx(Vector3.ONE), "%s geometry scale changed" % target.name)

	var aircraft_overlay := (aircraft.get_node("Geometry") as GeometryInstance3D).material_overlay as ShaderMaterial
	if aircraft_overlay != null:
		var shader_code := aircraft_overlay.shader.code if aircraft_overlay.shader != null else ""
		_expect(not shader_code.contains("depth_test_disabled"), "contrast pass bypassed normal occlusion")
		_expect(shader_code.contains("shadows_disabled"), "contrast pass added a redundant shadow pass")

	structure.position = Vector3(0.0, 0.0, -900.0)
	var near_target: Array[Node3D] = [structure]
	budget.call("_update_enemy_contrast", near_target, camera)
	_expect(not _has_contrast_overlay(structure.get_node("Geometry") as GeometryInstance3D), "near structure retained distant contrast")

	var short_range_target := _make_target(scene, "ShortRangeEnemy", ["enemies", "ground_vehicles"], Vector3(0.0, 0.0, -1200.0))
	var short_range_targets: Array[Node3D] = [short_range_target]
	budget.set("enemy_contrast_start_distance_m", 1800.0)
	budget.set("enemy_contrast_full_distance_m", 5200.0)
	budget.set("enemy_max_contrast_strength", 0.18)
	budget.call("_update_enemy_contrast", short_range_targets, camera)
	_expect(
		not _has_contrast_overlay(short_range_target.get_node("Geometry") as GeometryInstance3D),
		"standard visibility unexpectedly enhanced a 1.2 km target"
	)
	budget.set("enemy_contrast_start_distance_m", 900.0)
	budget.set("enemy_contrast_full_distance_m", 3500.0)
	budget.set("enemy_max_contrast_strength", 0.26)
	budget.call("_update_enemy_contrast", short_range_targets, camera)
	_expect(
		_has_contrast_overlay(short_range_target.get_node("Geometry") as GeometryInstance3D),
		"enhanced visibility did not reach a 1.2 km target"
	)

	budget.set("enemy_contrast_start_distance_m", original_start_distance)
	budget.set("enemy_contrast_full_distance_m", original_full_distance)
	budget.set("enemy_max_contrast_strength", original_max_strength)
	budget.set("enabled", budget_was_enabled)
	await _finish(scene)


func _make_target(scene: Node3D, node_name: String, groups: Array[String], target_position: Vector3) -> TestEnemy:
	var target := TestEnemy.new()
	target.name = node_name
	target.position = target_position
	scene.add_child(target)
	for group_name in groups:
		target.add_to_group(group_name)
	var geometry := MeshInstance3D.new()
	geometry.name = "Geometry"
	geometry.mesh = BoxMesh.new()
	target.add_child(geometry)
	return target


func _has_contrast_overlay(geometry: GeometryInstance3D) -> bool:
	if geometry == null or not (geometry.material_overlay is ShaderMaterial):
		return false
	return (geometry.material_overlay as ShaderMaterial).resource_name == "Distant Enemy Contrast"


func _finish(scene: Node3D) -> void:
	var passed := _failures.is_empty()
	current_scene = null
	root.remove_child(scene)
	scene.free()
	await process_frame
	if passed:
		print("[DistantEnemyContrastSmoketest] PASS categories=aircraft,ground_vehicle,structure,emplacement enhanced_range=1.2km geometry=unchanged")
		quit(0)
		return
	print("[DistantEnemyContrastSmoketest] %d failure(s)" % _failures.size())
	quit(1)


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("[DistantEnemyContrastSmoketest] FAIL: %s" % description)
