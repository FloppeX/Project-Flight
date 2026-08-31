extends Node3D

const AIRCRAFT_SCENES: Array[String] = [
	"res://Aircraft/Aircraft_1.tscn",
	"res://Aircraft/Aircraft_2.tscn",
	"res://Aircraft/Aircraft_3.tscn",
	"res://Aircraft/Aircraft_4.tscn",
	"res://Aircraft/Aircraft_5.tscn",
	"res://Aircraft/Aircraft_6.tscn",
	"res://Aircraft/Aircraft_7.tscn",
	"res://Aircraft/Aircraft_8.tscn",
	"res://Aircraft/Aircraft_9.tscn",
	"res://Aircraft/Aircraft_10.tscn",
	"res://Aircraft/Aircraft_11.tscn",
	"res://Aircraft/Aircraft_12.tscn",
	"res://Aircraft/CompleteFighterJet.tscn",
	"res://Enemies/EnemyFighter.tscn",
]

var _outside_camera: Camera3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var visual_budget := get_node_or_null("/root/EnemyVisualBudget")
	if visual_budget != null and "enabled" in visual_budget:
		visual_budget.set("enabled", false)

	_outside_camera = Camera3D.new()
	_outside_camera.name = "CanopyGlassTestCamera"
	add_child(_outside_camera)
	_outside_camera.current = true
	await get_tree().process_frame

	var total_glass_surfaces := 0
	var max_rescan_usec := 0
	for scene_index in range(AIRCRAFT_SCENES.size()):
		var scene_path := AIRCRAFT_SCENES[scene_index]
		var packed := load(scene_path) as PackedScene
		_require(packed != null, "could not load %s" % scene_path)
		var aircraft := packed.instantiate() as Node3D
		_require(aircraft != null, "could not instantiate %s" % scene_path)
		aircraft.position = Vector3(float(scene_index) * 50.0, 10000.0, 0.0)
		if aircraft is RigidBody3D:
			(aircraft as RigidBody3D).freeze = true
		var ai_toggle := aircraft.get_node_or_null("AIToggle")
		if ai_toggle != null and "ai_enabled_at_start" in ai_toggle:
			ai_toggle.set("ai_enabled_at_start", false)
		add_child(aircraft)
		aircraft.process_mode = Node.PROCESS_MODE_DISABLED
		if aircraft is RigidBody3D:
			(aircraft as RigidBody3D).freeze = true
		await get_tree().process_frame
		await get_tree().process_frame
		_outside_camera.current = true
		await get_tree().process_frame

		var visibility := aircraft.get_node_or_null("CockpitCanopyVisibility") as CockpitCanopyVisibility
		_require(visibility != null, "%s has no cockpit glass controller" % scene_path)
		var glass_surfaces := _collect_glass_surfaces(aircraft, visibility)
		total_glass_surfaces += glass_surfaces.size()
		var cached_surfaces: Array = visibility.get("_canopy_surfaces") as Array
		for surface_data in glass_surfaces:
			_require(
				_has_cached_surface(cached_surfaces, surface_data),
				"%s did not cache Glass surface %s:%d" % [
					scene_path,
					(surface_data.get("mesh") as MeshInstance3D).get_path(),
					int(surface_data.get("surface", -1)),
				]
			)

		var rescan_started_usec := Time.get_ticks_usec()
		visibility.call("_cache_material_surfaces", aircraft)
		max_rescan_usec = maxi(max_rescan_usec, Time.get_ticks_usec() - rescan_started_usec)

		var cockpit_camera := aircraft.get_node_or_null("CameraCockpit/Camera3D") as Camera3D
		_require(cockpit_camera != null, "%s has no cockpit camera" % scene_path)
		cockpit_camera.current = true
		visibility.call("_update_canopy_visibility")
		for surface_data in glass_surfaces:
			var mesh := surface_data.get("mesh") as MeshInstance3D
			var surface_index := int(surface_data.get("surface", -1))
			var hidden_material := mesh.get_active_material(surface_index) as BaseMaterial3D
			_require(
				hidden_material != null and hidden_material.albedo_color.a <= 0.001,
				"%s left Glass surface visible at %s:%d" % [scene_path, mesh.get_path(), surface_index]
			)

		_outside_camera.current = true
		visibility.call("_update_canopy_visibility")
		print("[CockpitGlassMaterialVisibilitySmoketest] checked %s glass_surfaces=%d" % [scene_path, glass_surfaces.size()])

	print(
		"[CockpitGlassMaterialVisibilitySmoketest] PASS aircraft=%d glass_surfaces=%d max_rescan_usec=%d"
		% [AIRCRAFT_SCENES.size(), total_glass_surfaces, max_rescan_usec]
	)
	get_tree().quit(0)


func _collect_glass_surfaces(root: Node3D, visibility: CockpitCanopyVisibility) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_collect_glass_surfaces_recursive(root, visibility, result)
	return result


func _collect_glass_surfaces_recursive(
		node: Node3D,
		visibility: CockpitCanopyVisibility,
		result: Array[Dictionary]
	) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		for surface_index in range(mesh.mesh.get_surface_count()):
			var material := visibility.call("_get_surface_material", mesh, surface_index) as Material
			if bool(visibility.call("_material_name_matches", material)):
				result.append({"mesh": mesh, "surface": surface_index})
	for child_variant in node.get_children():
		var child := child_variant as Node3D
		if child != null:
			_collect_glass_surfaces_recursive(child, visibility, result)


func _has_cached_surface(cached_surfaces: Array, expected: Dictionary) -> bool:
	for cached in cached_surfaces:
		if cached.get("mesh") == expected.get("mesh") \
				and int(cached.get("surface", -1)) == int(expected.get("surface", -1)):
			return true
	return false


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("[CockpitGlassMaterialVisibilitySmoketest] FAIL %s" % message)
	get_tree().quit(1)
	assert(condition, message)
