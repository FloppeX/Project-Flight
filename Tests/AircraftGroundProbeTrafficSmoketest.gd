extends Node3D

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var surface := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 10, 200)
	shape.shape = box
	surface.add_child(shape)
	surface.position.y = -5
	add_child(surface)
	var lower := (load("res://Aircraft/Aircraft_5.tscn") as PackedScene).instantiate() as Aircraft
	var upper := (load("res://Aircraft/Aircraft_3.tscn") as PackedScene).instantiate() as Aircraft
	for entry in [[lower, 1000.0], [upper, 1020.0]]:
		var craft: Aircraft = entry[0]
		craft.position = Vector3(0, entry[1], 0)
		craft.freeze = true
		# Keep safety callable explicitly; this isolates ground sensing from AI/flight.
		craft.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		craft.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(craft)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var from := lower.global_position + Vector3.UP * lower.ground_probe_up
	var to := lower.global_position - Vector3.UP * lower.ground_probe_down
	var raw := PhysicsRayQueryParameters3D.create(from, to)
	raw.exclude = [lower.get_rid()]
	raw.collision_mask = 0xFFFFFFFF
	var old_hit := get_world_3d().direct_space_state.intersect_ray(raw)
	check(not old_hit.is_empty() and old_hit.get("collider") == upper,
		"Fixture must reproduce the old ground ray hitting overhead traffic")
	check(not old_hit.is_empty() and old_hit.position.y > lower.position.y,
		"Old probe must put a healthy airborne aircraft below fabricated ground")
	check(is_zero_approx(lower._get_ground_height_at_position(lower.position)),
		"Ground height must ignore overhead traffic and find real ground")
	check(not lower._is_below_terrain(), "Airborne traffic must not cause below-terrain status")
	lower._enforce_above_terrain()
	check(not lower._has_exploded and lower.current_health == lower.max_health,
		"Terrain enforcement must preserve the lower aircraft")
	check(lower._evaluate_terrain_impact_normal().dot(Vector3.UP) > 0.999,
		"Terrain normal must use the ground surface, not the aircraft")
	# Raised static decks remain valid ground. No aircraft collision layers change.
	surface.position.y = 95
	surface.add_to_group("runway_surface")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(is_equal_approx(lower._get_ground_height_at_position(lower.position), 100.0),
		"Raised runway/deck surface must remain detectable")
	lower.position.y = 99
	check(lower._is_below_terrain(), "Real ground penetration must still be detected")
	lower.position.y = 1000
	# With no surface, return unknown instead of the aircraft overhead.
	surface.position.x = 500
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(is_nan(lower._get_ground_height_at_position(lower.position)),
		"Traffic alone must not fabricate ground in an empty scene")
	lower._enforce_above_terrain()
	check(not lower._has_exploded, "Unknown ground must not destroy the aircraft")
	print("AIRCRAFT_GROUND_PROBE_TRAFFIC_SMOKETEST %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
