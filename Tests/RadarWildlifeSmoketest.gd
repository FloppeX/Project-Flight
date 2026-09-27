extends SceneTree

class RadarAircraft extends Node3D:
	func get_team() -> int:
		return 1

class RadarProvider extends Node:
	var aircraft: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var aircraft := RadarAircraft.new()
	scene.add_child(aircraft)
	var provider := RadarProvider.new()
	provider.aircraft = aircraft
	scene.add_child(provider)
	var radar_script := load("res://HUD/RadarCanvas.gd") as Script
	var radar := radar_script.new() as Control
	radar.size = Vector2(300.0, 300.0)
	radar.set("show_terrain_map", false)
	scene.add_child(radar)
	radar.call("set_provider", provider)

	var bird := Node3D.new()
	bird.name = "CanyonVultureRadarProbe"
	bird.position = Vector3(120.0, 80.0, 900.0)
	bird.add_to_group("wildlife")
	scene.add_child(bird)
	radar.call("_rebuild_contact_cache")
	var wildlife: Array = radar.get("_cached_wildlife_contacts")
	var air_contacts: Array = radar.get("_cached_air_contacts")
	var enemies: Array = radar.get("_cached_enemies")
	if wildlife.size() != 1 or wildlife[0] != bird:
		_fail("wildlife was not collected as a radar return")
		return
	if air_contacts.has(bird) or enemies.has(bird):
		_fail("wildlife leaked into combat radar contacts")
		return
	var radar_source := FileAccess.get_file_as_string("res://HUD/RadarCanvas.gd")
	if not radar_source.contains("WILDLIFE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)") \
			or not radar_source.contains("WILDLIFE_DOT_RADIUS_PX: float = 2.0"):
		_fail("wildlife radar return is not the requested little white dot")
		return

	print("RADAR_WILDLIFE_PASS contact=neutral color=white radius_px=2 targetable=false")
	quit(0)


func _fail(reason: String) -> void:
	push_error("RADAR_WILDLIFE_FAIL: %s" % reason)
	quit(1)
