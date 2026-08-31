extends SceneTree

const CONTRAST_SCRIPT: Script = preload("res://Effects/DistantEnemyContrast.gd")
const HUD_SCENE: PackedScene = preload("res://HUD/HeadsUpDisplay.tscn")


class TestAircraft:
	extends RigidBody3D

	var team: int = 2

	func get_team() -> int:
		return team


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "DistantVisibilityHudSmoketest"
	root.add_child(scene)
	current_scene = scene

	var camera := Camera3D.new()
	camera.name = "TestCamera"
	camera.current = true
	scene.add_child(camera)

	_test_distant_contrast(scene, camera)
	await process_frame
	_test_budget_candidate_coverage(scene, camera)
	await _test_aircraft_integration(scene, camera)
	_test_target_direction_cue(scene, camera)
	await process_frame

	var passed := _failures.is_empty()
	current_scene = null
	root.remove_child(scene)
	scene.free()
	await process_frame
	if passed:
		print("[DistantVisibilityHudSmoketest] PASS contrast=all_enemy_distance_neutral arrow=edge_direction")
		quit(0)
		return
	print("[DistantVisibilityHudSmoketest] %d failure(s)" % _failures.size())
	quit(1)


func _test_distant_contrast(scene: Node3D, camera: Camera3D) -> void:
	var aircraft := TestAircraft.new()
	aircraft.name = "EnemyAircraft"
	aircraft.position = Vector3(0.0, 500.0, -4200.0)
	scene.add_child(aircraft)
	aircraft.add_to_group("enemies")

	var mesh := MeshInstance3D.new()
	mesh.name = "AirframeMesh"
	mesh.mesh = BoxMesh.new()
	aircraft.add_child(mesh)

	var contrast_session = CONTRAST_SCRIPT.new(aircraft)
	contrast_session.refresh_for_camera(camera)

	var overlay := mesh.material_overlay as ShaderMaterial
	_expect(overlay != null, "distant enemy mesh did not receive a contrast overlay")
	if overlay != null:
		var shader_code := overlay.shader.code if overlay.shader != null else ""
		_expect(not shader_code.contains("depth_test_disabled"), "contrast overlay bypassed normal depth occlusion")
		_expect(shader_code.contains("shadows_disabled"), "contrast-only pass still contributed a redundant shadow pass")
		var far_strength := float(overlay.get_shader_parameter("contrast_strength"))
		_expect(far_strength > 0.05 and far_strength <= 0.18, "distant contrast strength was outside the restrained range")
		var sky_color := overlay.get_shader_parameter("contrast_color") as Vector3

		aircraft.position = Vector3(0.0, -500.0, -4200.0)
		contrast_session.refresh_for_camera(camera)
		var terrain_color := overlay.get_shader_parameter("contrast_color") as Vector3
		_expect(
			terrain_color.length() > sky_color.length(),
			"terrain-backed enemy was not lifted relative to the sky-backed treatment"
		)

	aircraft.position = Vector3(0.0, 0.0, -900.0)
	contrast_session.refresh_for_camera(camera)
	_expect(mesh.material_overlay == null, "nearby enemy retained the distant contrast overlay")

	aircraft.position = Vector3(0.0, 0.0, -4200.0)
	aircraft.team = 1
	contrast_session.refresh_for_camera(camera)
	_expect(mesh.material_overlay == null, "friendly aircraft received the enemy contrast treatment")

	var budget_source := FileAccess.get_file_as_string("res://Effects/EnemyVisualBudget.gd")
	_expect(
		budget_source.contains("res://Effects/DistantEnemyContrast.gd")
			and budget_source.contains("func _collect_contrast_candidates()"),
		"global visual budget did not retain all-enemy contrast coverage"
	)
	contrast_session.dispose()


func _test_budget_candidate_coverage(scene: Node3D, camera: Camera3D) -> void:
	var budget := root.get_node_or_null("EnemyVisualBudget")
	_expect(budget != null, "EnemyVisualBudget autoload was unavailable")
	if budget == null:
		return

	var vehicle := TestAircraft.new()
	vehicle.name = "EnemyGroundVehicle"
	vehicle.position = Vector3(-100.0, -300.0, -4200.0)
	scene.add_child(vehicle)
	vehicle.add_to_group("enemies")
	vehicle.add_to_group("ground_vehicles")
	var vehicle_mesh := MeshInstance3D.new()
	vehicle_mesh.mesh = BoxMesh.new()
	vehicle.add_child(vehicle_mesh)

	var structure := TestAircraft.new()
	structure.name = "EnemyStructure"
	structure.position = Vector3(100.0, -300.0, -4200.0)
	scene.add_child(structure)
	structure.add_to_group("enemies")
	structure.add_to_group("buildings")
	var structure_mesh := MeshInstance3D.new()
	structure_mesh.mesh = BoxMesh.new()
	structure.add_child(structure_mesh)

	var friendly_vehicle := TestAircraft.new()
	friendly_vehicle.name = "FriendlyGroundVehicle"
	friendly_vehicle.team = 1
	scene.add_child(friendly_vehicle)
	friendly_vehicle.add_to_group("ground_vehicles")

	var candidates: Array = budget.call("_collect_contrast_candidates") as Array
	_expect(candidates.has(vehicle), "enemy ground vehicle was absent from the shared contrast budget")
	_expect(candidates.has(structure), "enemy building was absent from the shared contrast budget")
	_expect(not candidates.has(friendly_vehicle), "friendly ground vehicle entered the enemy contrast budget")

	var contrast_targets: Array[Node3D] = [vehicle, structure]
	budget.call("_update_enemy_contrast", contrast_targets, camera)
	_expect(_is_contrast_geometry(vehicle_mesh), "enemy ground vehicle did not receive distant contrast")
	_expect(_is_contrast_geometry(structure_mesh), "enemy structure did not receive distant contrast")

	vehicle.queue_free()
	structure.queue_free()
	friendly_vehicle.queue_free()


func _test_aircraft_integration(scene: Node3D, camera: Camera3D) -> void:
	# Runtime loading happens after project singletons and global classes are ready,
	# matching ordinary scenario spawning more closely than a top-level preload.
	var packed_scene := load("res://Aircraft/Aircraft_5.tscn") as PackedScene
	_expect(packed_scene != null, "reference aircraft scene did not load")
	if packed_scene == null:
		return
	var aircraft := packed_scene.instantiate() as RigidBody3D
	_expect(aircraft != null, "reference aircraft scene did not instantiate")
	if aircraft == null:
		return
	aircraft.set("spawn_cockpit_pilot", false)
	aircraft.freeze = true
	scene.add_child(aircraft)
	# Several live spawners assign the enemy team immediately after add_child().
	# The controller must therefore resolve team dynamically rather than only in _ready().
	aircraft.set("team", 2)
	aircraft.add_to_group("enemies")
	aircraft.position = Vector3(0.0, 0.0, -4200.0)
	await process_frame
	await process_frame
	var budget := root.get_node_or_null("EnemyVisualBudget")
	_expect(budget != null, "EnemyVisualBudget was unavailable for real-aircraft integration")
	if budget != null:
		var contrast_targets: Array[Node3D] = [aircraft]
		budget.call("_update_enemy_contrast", contrast_targets, camera)
		_expect(
			_count_contrast_geometry(aircraft) > 0,
			"real enemy aircraft meshes did not receive the shared distant contrast pass"
		)
		var hud_glass := aircraft.find_child("HUDglass", true, false) as MeshInstance3D
		_expect(
			hud_glass == null or hud_glass.material_overlay == null,
			"contrast pass leaked into the aircraft presentation HUD"
		)
	aircraft.queue_free()
	await process_frame


func _count_contrast_geometry(node: Node) -> int:
	var count := 0
	if node is GeometryInstance3D and _is_contrast_geometry(node as GeometryInstance3D):
		count += 1
	for child in node.get_children():
		count += _count_contrast_geometry(child)
	return count


func _is_contrast_geometry(geometry: GeometryInstance3D) -> bool:
	if geometry == null or not (geometry.material_overlay is ShaderMaterial):
		return false
	var overlay := geometry.material_overlay as ShaderMaterial
	return overlay.resource_name == "Distant Enemy Contrast"


func _test_target_direction_cue(scene: Node3D, camera: Camera3D) -> void:
	var aircraft := TestAircraft.new()
	aircraft.name = "HudAircraft"
	aircraft.team = 1
	scene.add_child(aircraft)

	var hud := HUD_SCENE.instantiate() as Node3D
	hud.name = "TestHUD"
	hud.position = Vector3(0.0, 0.0, -1.0)
	scene.add_child(hud)
	hud.set("cam", camera)
	hud.set("aircraft", aircraft)

	var target := Node3D.new()
	target.name = "SelectedTarget"
	scene.add_child(target)
	var arrow := hud.get("target_direction_arrow") as Control
	var box := hud.get("target_overlay") as Control
	_expect(arrow != null, "selected-target direction arrow was not created")
	_expect(box != null, "existing selected-target box was unavailable")
	if arrow == null or box == null:
		return

	target.position = Vector3(100.0, 0.0, -100.0)
	hud.call("_update_target_cues_for_target", target)
	var right_center := arrow.position + arrow.pivot_offset
	var arrow_margin := float(hud.get("target_arrow_edge_margin_px"))
	var hud_viewport := hud.get("viewport") as SubViewport
	var hud_size := Vector2(hud_viewport.size) if hud_viewport != null else Vector2(512.0, 512.0)
	_expect(arrow.visible and not box.visible, "off-glass target did not switch from box to arrow")
	_expect(
		absf(right_center.x - (hud_size.x - arrow_margin)) < 2.0
			and absf(right_center.y - hud_size.y * 0.5) < 2.0,
		"right-side target arrow did not use the inset HUD boundary"
	)
	_expect(absf(arrow.rotation) < 0.01, "right-side target arrow did not point right")

	target.position = Vector3(0.0, 0.0, -100.0)
	hud.call("_update_target_cues_for_target", target)
	_expect(box.visible and not arrow.visible, "on-glass target did not switch back to the target box")

	target.position = Vector3(0.0, 0.0, 100.0)
	hud.call("_update_target_cues_for_target", target)
	var aft_center := arrow.position + arrow.pivot_offset
	_expect(arrow.visible and not box.visible, "aft target lost its direction cue")
	_expect(absf(aft_center.y - (hud_size.y - arrow_margin)) < 2.0, "directly aft target did not use the inset lower boundary")
	_expect(absf(arrow.rotation - PI * 0.5) < 0.01, "directly aft target arrow did not point down")


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("[DistantVisibilityHudSmoketest] FAIL: %s" % description)
