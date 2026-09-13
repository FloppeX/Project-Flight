extends SceneTree

const STATION_SCENE := preload("res://LandCarrier/ComputerStation.tscn")
const COMMANDER_SCENE := preload("res://LandCarrier/Commander.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	world.name = "ComputerStationTestWorld"
	root.add_child(world)

	var station := STATION_SCENE.instantiate() as Node3D
	station.position = Vector3(0.0, 0.0, 2.2)
	station.rotation.y = PI
	world.add_child(station)

	var second_station := STATION_SCENE.instantiate() as Node3D
	second_station.position = Vector3(20.0, 0.0, 20.0)
	world.add_child(second_station)

	var commander := COMMANDER_SCENE.instantiate() as CharacterBody3D
	commander.set("computer_camera_transition_s", 0.04)
	commander.set("computer_screen_focus_s", 0.04)
	world.add_child(commander)
	await process_frame
	await process_frame

	var snapshot: Dictionary = station.call("get_debug_snapshot")
	_expect(bool(snapshot.get("has_model", false)), "station does not instance computer station.glb")
	_expect(bool(snapshot.get("has_interaction_target", false)), "station interaction target is missing")
	_expect(bool(snapshot.get("has_camera_anchor", false)), "station seated camera anchor is missing")
	_expect(bool(snapshot.get("screen_mesh_found", false)), "computer console screen mesh was not found")
	_expect(str(snapshot.get("screen_anchor_source", "")) == "computer console screen", "screen prompt retained its authored fallback transform")
	_expect(bool(snapshot.get("has_tactical_screen_display", false)), "shared tactical screen display was not created")
	_expect(bool(snapshot.get("has_tactical_screen_material", false)), "screen did not receive the tactical viewport material")
	var tactical_display := root.get_node_or_null("TacticalScreenDisplay")
	_expect(tactical_display != null, "shared tactical display is missing from the scene root")
	if tactical_display != null:
		var display_snapshot: Dictionary = tactical_display.call("get_debug_snapshot")
		_expect(display_snapshot.get("viewport_size", Vector2i.ZERO) == Vector2i(1024, 576), "tactical monitor viewport has the wrong resolution")
		_expect(is_equal_approx(float(display_snapshot.get("refresh_interval_s", 0.0)), 0.1), "tactical monitor viewport is not throttled to 10 Hz")
	var first_screen := station.find_child("computer console screen", true, false) as MeshInstance3D
	var second_screen := second_station.find_child("computer console screen", true, false) as MeshInstance3D
	_expect(first_screen != null and second_screen != null, "multi-station screen meshes are unavailable")
	if first_screen != null and second_screen != null:
		_expect(first_screen.material_override == second_screen.material_override, "stations do not share one tactical viewport material")
	var world_map := root.get_node_or_null("WorldMapOverlay")
	var world_map_root := world_map.get("_root") as Control if world_map != null else null
	_expect(world_map_root != null, "WorldMapOverlay control root is unavailable")
	if world_map_root != null:
		_expect(
			world_map_root.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_DISABLED,
			"monitor preview can intercept unrelated main-window mouse input"
		)

	var camera := commander.get_node_or_null("Camera3D") as Camera3D
	_expect(camera != null, "commander camera is missing")
	if camera != null:
		# The test aims the camera directly; pause the normal look controller so it
		# does not overwrite that synthetic orientation between assertions.
		commander.set_physics_process(false)
		var screen_target := station.get_node("InteractionTarget") as Marker3D
		camera.look_at(screen_target.global_position + Vector3.UP * 0.75, Vector3.UP)
		var missed_score := float(station.call("get_interaction_score", camera))
		_expect(missed_score == -INF, "station remained usable while looking above its screen")
		camera.look_at(screen_target.global_position, Vector3.UP)
		var score := float(station.call("get_interaction_score", camera))
		_expect(score > -INF, "station is not usable while its screen is directly looked at")
		var standing_transform := camera.transform
		var entered := bool(commander.call("enter_computer_station", station))
		_expect(entered, "commander could not enter the computer station")
		_expect(bool(commander.call("is_using_computer_station")), "commander did not retain station-use state")
		_expect(bool(station.call("is_in_use")), "station did not retain in-use state")
		await create_timer(0.12).timeout

		var expected_focus_global: Transform3D = station.call(
			"get_screen_focus_camera_transform"
		) as Transform3D
		var expected_focus := commander.global_transform.affine_inverse() * expected_focus_global
		_expect(camera.transform.is_equal_approx(expected_focus), "camera did not rotate down toward the station screen")
		var viewport_size := camera.get_viewport().get_visible_rect().size
		var viewport_aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
		var expected_focus_fov := float(station.call("get_screen_focus_fov", viewport_aspect))
		_expect(is_equal_approx(camera.fov, expected_focus_fov), "camera did not zoom to the screen-fitted FOV")
		_expect(camera.fov < float(station.call("get_seated_camera_fov")), "screen focus did not zoom in from the seated view")

		var console := root.get_node_or_null("CarrierConsole")
		_expect(console != null, "CarrierConsole autoload is missing")
		if console != null:
			_expect(str(console.call("get_current_page")) == "tactical", "station did not select the tactical page")
			_expect(bool(console.call("is_open")), "station did not open the carrier console")
			if world_map_root != null:
				_expect(
					world_map_root.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_INHERITED,
					"fullscreen tactical console did not restore mouse input"
				)
			if tactical_display != null:
				var active_snapshot: Dictionary = tactical_display.call("get_debug_snapshot")
				_expect(not bool(active_snapshot.get("preview_enabled", true)), "monitor viewport kept rendering beneath the fullscreen console")
			console.call("set_open", false)
			await create_timer(0.08).timeout
			if tactical_display != null:
				var resumed_snapshot: Dictionary = tactical_display.call("get_debug_snapshot")
				_expect(bool(resumed_snapshot.get("preview_enabled", false)), "monitor viewport did not resume after closing the console")
			if world_map_root != null:
				_expect(
					world_map_root.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_DISABLED,
					"closed tactical console resumed intercepting main-window mouse input"
				)

		_expect(not bool(commander.call("is_using_computer_station")), "closing the console did not release the station")
		_expect(not bool(station.call("is_in_use")), "station stayed reserved after exit")
		_expect(camera.transform.is_equal_approx(standing_transform), "camera did not return to its standing transform")

	world.queue_free()
	await process_frame
	if _failures.is_empty():
		print("[ComputerStationSmoketest] PASS reusable_scene=true shared_live_preview=true preview_hz=10 look_gate=true seated_camera=true screen_focus=true tactical_page=true preview_pauses_fullscreen=true close_returns_to_standing=true")
		quit(0)
		return
	for failure in _failures:
		push_error("[ComputerStationSmoketest] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
