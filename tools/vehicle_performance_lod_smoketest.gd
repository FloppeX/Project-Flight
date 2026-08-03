extends SceneTree

## Focused regression test for camera-driven ground-vehicle performance LOD.

const VEHICLE_SCENES: Array[String] = [
	"res://GroundVehicle/GroundVehicle.tscn",
	"res://GroundVehicle/vehicle_enemy_buggy.tscn",
	"res://GroundVehicle/vehicle_enemy_pickup.tscn",
	"res://GroundVehicle/vehicle_enemy_battle_bus.tscn",
	"res://GroundVehicle/vehicle_friendly_light.tscn",
]

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.global_position = Vector3(0.0, 4.0, 0.0)
	camera.look_at(Vector3(0.0, 1.0, -20.0), Vector3.UP)
	camera.current = true
	await process_frame

	for scene_path in VEHICLE_SCENES:
		await _check_vehicle_scene(world, scene_path)

	world.queue_free()
	await process_frame
	if _failures == 0:
		print("[VehiclePerformanceLOD] PASS")
		quit(0)
	else:
		push_error("[VehiclePerformanceLOD] FAIL (%d checks)" % _failures)
		quit(1)

func _check_vehicle_scene(world: Node3D, scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	_check(packed != null, "%s loads" % scene_path)
	if packed == null:
		return
	var vehicle = packed.instantiate()
	world.add_child(vehicle)
	vehicle.global_position = Vector3(0.0, 1.0, 30.0)
	await process_frame
	await process_frame
	vehicle.set_physics_process(false)

	if vehicle.has_method("_consume_drive_command_delta"):
		var saved_multi_rate: bool = bool(vehicle.get("multi_rate_drive_commands_enabled"))
		vehicle.set("multi_rate_drive_commands_enabled", true)
		vehicle.set("_drive_command_interval_scale", 1.0)
		vehicle.set("_drive_command_timer_s", 0.05)
		vehicle.set("_drive_command_elapsed_s", 0.0)
		_check(
			is_zero_approx(float(vehicle.call("_consume_drive_command_delta", 0.01))),
			"%s holds its cached drive command between decision ticks" % scene_path
		)
		_check(
			float(vehicle.call("_consume_drive_command_delta", 0.05)) >= 0.06,
			"%s returns accumulated command time on refresh" % scene_path
		)
		vehicle.set("multi_rate_drive_commands_enabled", false)
		_check(
			is_equal_approx(float(vehicle.call("_consume_drive_command_delta", 0.016)), 0.016),
			"%s drive-command rollback restores full rate" % scene_path
		)
		vehicle.set("multi_rate_drive_commands_enabled", saved_multi_rate)
		if vehicle.has_method("_apply_cached_drive_motion"):
			vehicle.set("_drive_command_has_destination", true)
			if "_drive_command_formation_hold" in vehicle:
				vehicle.set("_drive_command_formation_hold", false)
			vehicle.set("_drive_command_steer", 0.0)
			vehicle.set("_drive_command_throttle", 1.0)
			vehicle.set("_drive_command_combat", false)
			vehicle.velocity = Vector3.ZERO
			var motion_start: Vector3 = vehicle.global_position
			for _step in range(8):
				vehicle.call("_apply_cached_drive_motion", 0.016)
			_check(
				vehicle.global_position.distance_to(motion_start) > 0.001,
				"%s applies cached movement on every physics step" % scene_path
			)
			vehicle.velocity = Vector3.ZERO
			var coarse_motion_start: Vector3 = vehicle.global_position
			vehicle.call("_apply_cached_drive_motion", 0.10, true)
			_check(
				vehicle.global_position.distance_to(coarse_motion_start) > 0.001,
				"%s preserves motion distance on a coarse simulation tick" % scene_path
			)

	if vehicle.has_method("_consume_vehicle_simulation_delta"):
		var saved_multi_rate_simulation: bool = bool(vehicle.get("multi_rate_vehicle_simulation_enabled"))
		var saved_full_rate_distance: float = float(vehicle.get("full_rate_simulation_distance_m"))
		vehicle.set("multi_rate_vehicle_simulation_enabled", true)
		vehicle.set("full_rate_simulation_distance_m", 100.0)
		vehicle.global_position = Vector3(0.0, 1.0, 1000.0)
		vehicle.set("_simulation_lod_phase", 1.0)
		vehicle.set("_camera_visibility_timer_s", 0.0)
		vehicle.call("reset_simulation_lod_schedule")
		_check(
			is_zero_approx(float(vehicle.call("_consume_vehicle_simulation_delta", 0.01))),
			"%s holds an off-screen vehicle between coarse simulation ticks" % scene_path
		)
		_check(
			float(vehicle.call("_consume_vehicle_simulation_delta", 0.10)) >= 0.11,
			"%s returns accumulated vehicle time on a coarse simulation tick" % scene_path
		)
		_check(
			vehicle.call("get_vehicle_simulation_lod_band") == &"offscreen",
			"%s enters the off-screen simulation band" % scene_path
		)
		vehicle.call("wake_vehicle_simulation_lod", 0.5)
		_check(
			is_equal_approx(float(vehicle.call("_consume_vehicle_simulation_delta", 0.016)), 0.016),
			"%s wakes to full-rate simulation immediately" % scene_path
		)
		vehicle.set("multi_rate_vehicle_simulation_enabled", false)
		_check(
			is_equal_approx(float(vehicle.call("_consume_vehicle_simulation_delta", 0.016)), 0.016),
			"%s vehicle-simulation rollback restores full rate" % scene_path
		)
		vehicle.set("multi_rate_vehicle_simulation_enabled", saved_multi_rate_simulation)
		vehicle.set("full_rate_simulation_distance_m", saved_full_rate_distance)
		vehicle.call("reset_simulation_lod_schedule")

	vehicle._camera_visibility_timer_s = 0.0
	var offscreen_visible: bool = vehicle._is_camera_visible(1.0)
	_check(not offscreen_visible, "%s is classified off-screen behind the camera" % scene_path)
	var probe_counter_before: int = vehicle._suspension_probe_counter
	vehicle._update_wheel_visuals()
	_check(
		vehicle._suspension_probe_counter == probe_counter_before,
		"%s skips suspension probes off-screen" % scene_path
	)

	var dust = vehicle.get_node_or_null("DustEffect")
	_check(dust != null, "%s has a dust component" % scene_path)
	if dust != null:
		_check(dust._puff_pool.is_empty(), "%s lazily allocates no off-screen dust pool" % scene_path)
		_check(not dust._compute_should_emit_for_camera(0.0), "%s suppresses off-screen dust" % scene_path)
		var detached_camera := Camera3D.new()
		dust.set("_cached_camera", detached_camera)
		dust.set("_camera_cache_timer_s", 1.0)
		_check(not bool(dust.call("_is_camera_usable", detached_camera)), "%s rejects a detached cached camera" % scene_path)
		_check(dust.call("_get_active_camera", 0.0) != detached_camera, "%s replaces a detached cached camera" % scene_path)
		detached_camera.free()

	var turret = vehicle.turret_controller
	var offscreen_search_interval: float = 0.0
	if turret != null:
		turret._refresh_targeting_detail_cache(0.0)
		offscreen_search_interval = turret._get_effective_target_search_interval(0.0)
		if turret.has_method("_consume_tracking_lod_delta"):
			var saved_multi_rate_tracking: bool = bool(turret.get("multi_rate_tracking_enabled"))
			turret.set("multi_rate_tracking_enabled", true)
			turret.set("_tracking_lod_phase", 1.0)
			vehicle.set_meta("ground_simulation_lod_band", &"offscreen")
			turret.call("reset_tracking_lod_schedule")
			_check(
				is_zero_approx(float(turret.call("_consume_tracking_lod_delta", 0.01))),
				"%s holds off-screen turret tracking between ticks" % scene_path
			)
			_check(
				float(turret.call("_consume_tracking_lod_delta", 0.10)) >= 0.11,
				"%s returns accumulated turret time on a tracking tick" % scene_path
			)
			vehicle.set_meta("ground_simulation_lod_band", &"near")
			_check(
				is_equal_approx(float(turret.call("_consume_tracking_lod_delta", 0.016)), 0.016),
				"%s restores full-rate turret tracking near the camera" % scene_path
			)
			turret.set("multi_rate_tracking_enabled", false)
			_check(
				is_equal_approx(float(turret.call("_consume_tracking_lod_delta", 0.016)), 0.016),
				"%s turret-tracking rollback restores full rate" % scene_path
			)
			turret.set("multi_rate_tracking_enabled", saved_multi_rate_tracking)
			turret.call("reset_tracking_lod_schedule")

	var mesh_lod = vehicle._mesh_lod_controller
	_check(mesh_lod != null, "%s has a mesh LOD controller" % scene_path)
	if mesh_lod != null:
		_check(mesh_lod.get_mesh_count() > 0, "%s discovers render meshes" % scene_path)
		_check(mesh_lod.get_wheel_mesh_count() > 0, "%s identifies wheel detail meshes" % scene_path)
		vehicle.global_position = Vector3(0.0, 1.0, -1000.0)
		mesh_lod.force_refresh()
		vehicle._update_mesh_lod(1.0)
		_check(mesh_lod.get_current_lod_bias_multiplier() < 0.3, "%s selects aggressive far mesh LOD" % scene_path)
		vehicle.mesh_lod_enabled = false
		mesh_lod.force_refresh()
		vehicle._update_mesh_lod(1.0)
		_check(is_equal_approx(mesh_lod.get_current_lod_bias_multiplier(), 1.0), "%s restores original mesh detail when disabled" % scene_path)
		vehicle.mesh_lod_enabled = true

	vehicle.global_position = Vector3(0.0, 1.0, -30.0)
	vehicle._camera_visibility_timer_s = 0.0
	if mesh_lod != null:
		mesh_lod.force_refresh()
		vehicle._update_mesh_lod(1.0)
		_check(is_equal_approx(mesh_lod.get_current_lod_bias_multiplier(), 1.0), "%s retains full mesh detail nearby" % scene_path)
	var onscreen_visible: bool = vehicle._is_camera_visible(1.0)
	_check(onscreen_visible, "%s re-enters visible detail" % scene_path)
	_check(not vehicle._suspension_probe_ready, "%s invalidates stale probes on re-entry" % scene_path)
	if dust != null:
		_check(dust._compute_should_emit_for_camera(0.0), "%s permits dust while visible" % scene_path)
	if turret != null:
		turret._refresh_targeting_detail_cache(0.0)
		var onscreen_search_interval: float = turret._get_effective_target_search_interval(0.0)
		_check(
			offscreen_search_interval > onscreen_search_interval,
			"%s slows turret scans while off-screen" % scene_path
		)

	world.remove_child(vehicle)
	if dust != null:
		_check(not dust._compute_should_emit_for_camera(0.0), "%s skips dust work while detached" % scene_path)
	vehicle.free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	if condition:
		print("[VehiclePerformanceLOD] ok: %s" % message)
		return
	_failures += 1
	push_error("[VehiclePerformanceLOD] %s" % message)
