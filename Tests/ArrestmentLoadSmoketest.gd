extends SceneTree

const CABLE := preload("res://LandCarrier/arresting_cable.tscn")
var failures: Array[String] = []
var rows: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _disable(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_disable(child)

func _run() -> void:
	if OS.get_cmdline_user_args().has("--arrest-baseline"):
		push_error("Historical baseline requires the original source snapshot; force variants alone are not historical physics")
		quit(1)
		return
	await _roll_direction(-10.0)
	await _roll_direction(10.0)
	await _lateral_plane()
	await _pitch_damping(-0.8)
	await _pitch_damping(0.8)
	if not OS.get_cmdline_user_args().has("--arrest-unit-only"):
		for model in [1, 2, 5]:
			for bank in [-5.0, 5.0]:
				var variants := ["none"] if OS.get_cmdline_user_args().has("--arrest-no-hold-only") else ["both", "gear_only", "cable_only", "none"]
				for variant in variants:
					await _arrest(model, bank, variant)
			for bank in [-8.0, 8.0]:
				await _arrest(model, bank, "none", 65.0, 4.0, 1.2)
	var path := "user://arrestment_load_current_%d.json" % Time.get_unix_time_from_system()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"configuration": "current", "cases": rows, "failures": failures}, "\t"))
	file.close()
	for failure in failures:
		push_error(failure)
	print("ARRESTMENT_LOAD %s report=%s" % ["PASS" if failures.is_empty() else "FAIL", ProjectSettings.globalize_path(path)])
	quit(0 if failures.is_empty() else 1)

func _cable(host: Node3D) -> Node3D:
	var cable := CABLE.instantiate() as Node3D
	cable.set("visualize_cable", false)
	cable.set("swept_hook_capture_enabled", false)
	host.add_child(cable)
	cable.set_physics_process(false)
	return cable

func _roll_direction(bank: float) -> void:
	var host := Node3D.new()
	root.add_child(host)
	var craft := RigidBody3D.new()
	craft.mass = 1000
	craft.inertia = Vector3.ONE * 1000
	craft.gravity_scale = 0
	craft.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	craft.angular_damp = 0
	craft.rotation.z = deg_to_rad(bank)
	craft.linear_velocity = Vector3(0, 0, 30)
	craft.set_meta("arresting_hold_until_manual_release", true)
	host.add_child(craft)
	var cable := _cable(host)
	cable.set("_aircraft", craft)
	cable.set("_engaged", true)
	cable.set("max_tension", 0.0)
	cable.set("engaged_downforce_g", 0.0)
	for step in range(30):
		cable.call("_physics_process", 1.0 / 60.0)
		await physics_frame
		await process_frame
	var final_bank := rad_to_deg(craft.rotation.z)
	print("ARREST_ROLL start=%.2f final=%.2f" % [bank, final_bank])
	_check(absf(final_bank) < absf(bank) - 0.5, "Arrestment torque must reduce bank at both signs")
	host.queue_free()
	await process_frame

func _arrest(model: int, bank: float, variant: String, speed: float = 55.0, sink: float = 2.0, mass_scale: float = 1.0) -> void:
	var host := Node3D.new()
	root.add_child(host)
	var deck := StaticBody3D.new()
	deck.name = "ArrestmentFixtureDeck"
	deck.add_to_group("carrier")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 2, 600)
	shape.shape = box
	shape.position.y = -1
	deck.add_child(shape)
	host.add_child(deck)
	var craft := (load("res://Aircraft/Aircraft_%d.tscn" % model) as PackedScene).instantiate() as RigidBody3D
	craft.freeze = true
	craft.position.y = 1000
	craft.rotation.z = deg_to_rad(bank)
	host.add_child(craft)
	await process_frame
	await physics_frame
	_disable(craft)
	craft.mass *= mass_scale
	var gear := craft.get_node("LandingGear")
	gear.call("deploy")
	gear.set("airborne_suspension_budget_enabled", false)
	gear.set("deck_hold_force", 15000.0 if variant in ["both", "gear_only"] else 0.0)
	var bottom := INF
	var wheels: Array = gear.get("gear_collision_shapes")
	for i in wheels.size():
		var wheel := wheels[i] as CollisionShape3D
		bottom = minf(bottom, wheel.global_position.y - float(gear.call("get_wheel_rest_height", i)))
	craft.freeze = false
	await physics_frame
	await process_frame
	craft.global_position.y += 0.05 - bottom
	craft.linear_velocity = Vector3(0, -sink, speed)
	craft.angular_velocity = Vector3.ZERO
	craft.sleeping = false
	craft.set_meta("arresting_engaged", true)
	craft.set_meta("arresting_hold_until_manual_release", true)
	var hook := craft.get_node("TailHook/HookArea") as Node3D
	var cable := _cable(host)
	cable.global_position = Vector3(0, 0, hook.global_position.z)
	cable.set("_aircraft", craft)
	cable.set("_hook_node", hook)
	cable.set("_gear_module", gear)
	cable.set("_engaged", true)
	cable.set("engaged_downforce_g", 2.0 if variant in ["both", "cable_only"] else 0.0)
	var samples: Array[Dictionary] = []
	var body_bounds: Array[Dictionary] = []
	for owner_id in craft.get_shape_owners():
		var collider: Object = craft.shape_owner_get_owner(owner_id)
		if collider is CollisionShape3D and collider not in craft.get("safe_colliders") and not collider.disabled and collider.shape != null:
			body_bounds.append({"node": collider, "bounds": collider.shape.get_debug_mesh().get_aabb()})
	var contacts: Array[Dictionary] = []
	craft.connect("crashed", func(speed: float): contacts.append({"speed": speed, "shape": craft.get_meta("last_collision_local_shape", "unknown"), "gear": craft.get_meta("last_collision_safe_gear", false)}))
	var peak_bank := absf(bank)
	var peak_pitch := 0.0
	var bottomed := false
	var stopped := false
	var stable := 0.0
	var damaged := false
	var max_compression := 0.0
	for step in range(600):
		if not is_instance_valid(craft) or craft.is_queued_for_deletion():
			damaged = true
			break
		gear.call("process_physic_frame", 1.0 / 60.0)
		cable.call("_physics_process", 1.0 / 60.0)
		for compression in gear.get("gear_compressions"):
			max_compression = maxf(max_compression, compression)
			bottomed = bottomed or compression >= float(gear.get("max_compression")) * 0.98
		await physics_frame
		await process_frame
		if not is_instance_valid(craft):
			damaged = true
			break
		peak_bank = maxf(peak_bank, absf(rad_to_deg(craft.rotation.z)))
		peak_pitch = maxf(peak_pitch, absf(rad_to_deg(craft.rotation.x)))
		stable = stable + 1.0 / 60.0 if craft.linear_velocity.length() < 2.0 else 0.0
		stopped = stopped or stable >= 2.0
		if step % 15 == 0:
			var body_lowest := INF
			for body_shape in body_bounds:
				if not is_instance_valid(body_shape.node):
					continue
				var bounds: AABB = body_shape.bounds
				for corner in range(8):
					body_lowest = minf(body_lowest, (body_shape.node.global_transform * bounds.get_endpoint(corner)).y)
			samples.append({"t": step / 60.0, "y": craft.position.y, "speed": craft.linear_velocity.length(),
				"bank": rad_to_deg(craft.rotation.z), "pitch": rad_to_deg(craft.rotation.x),
				"compression": gear.get("gear_compressions").duplicate(), "spring_forces": gear.get("gear_normal_forces_n").duplicate(),
				"body_aabb_clearance_m": body_lowest, "braking_force": cable.get("last_braking_force_n"),
				"lateral_force": cable.get("last_lateral_force_n"), "attitude_torque": cable.get("last_attitude_torque_nm"),
				"gear_hold_per_wheel_n": gear.get("deck_hold_force"), "cable_downforce_n": craft.mass * 9.8 * float(cable.get("engaged_downforce_g"))})
		damaged = bool(craft.get("_has_exploded")) or bool(craft.get("_critical_damage_active"))
		if damaged:
			break
	var row := {"model": model, "bank": bank, "variant": variant, "stopped": stopped,
		"initial_speed": speed, "initial_sink": sink, "mass_scale": mass_scale, "mass_kg": craft.mass if is_instance_valid(craft) else -1.0,
		"critical_damage": damaged, "contacts": contacts, "bottomed": bottomed,
		"peak_bank": peak_bank, "peak_pitch": peak_pitch, "max_compression": max_compression, "samples": samples,
		"hard_stop_corrections": cable.get("hard_stop_corrections")}
	rows.append(row)
	print("ARREST_CASE model=%d bank=%.0f variant=%s stopped=%s critical=%s bottomed=%s roll=%.1f pitch=%.1f" % [model, bank, variant, stopped, damaged, bottomed, peak_bank, peak_pitch])
	if variant == "none" and mass_scale == 1.0:
		_check(not damaged and stopped, "Aircraft %d bank %.0f must survive and stop without hold forces" % [model, bank])
		_check(not bottomed, "Gentle arrestment must retain suspension travel")
	host.queue_free()
	await process_frame

func _lateral_plane() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var craft := RigidBody3D.new()
	craft.freeze = true
	host.add_child(craft)
	var cable := _cable(host)
	cable.rotation = Vector3(0.15, 0.6, -0.1)
	var up := cable.global_basis.y.normalized()
	var side := cable.global_basis.x.normalized()
	craft.linear_velocity = side * 4.0 - up * 6.0
	craft.set_meta("arresting_hold_until_manual_release", true)
	cable.set("_aircraft", craft)
	cable.set("_engaged", true)
	cable.set("_engage_point", up * 10.0 + side * 3.0)
	cable.call("_physics_process", 1.0 / 60.0)
	var force: Vector3 = cable.get("last_lateral_force_n")
	_check(absf(force.dot(up)) < 0.01, "Lateral centering must not apply vertical force on a tilted deck")
	_check(force.dot(side) < 0.0, "Lateral centering must oppose cross-deck displacement and velocity")
	host.queue_free()
	await process_frame

func _pitch_damping(rate: float) -> void:
	var host := Node3D.new()
	root.add_child(host)
	var craft := RigidBody3D.new()
	craft.mass = 1000
	craft.inertia = Vector3(3000, 2000, 1000)
	craft.gravity_scale = 0
	craft.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	craft.angular_damp = 0
	craft.rotation.y = 0.8
	host.add_child(craft)
	await physics_frame
	await process_frame
	craft.angular_velocity = craft.global_basis.x * rate
	var cable := _cable(host)
	cable.set("_aircraft", craft)
	for step in range(30):
		var torque: Vector3 = cable.call("_pitch_damping_torque", 1.0 / 60.0)
		_check(torque.dot(craft.angular_velocity) <= 0.001, "Pitch damping must never add rotational energy")
		craft.apply_torque(torque)
		await physics_frame
		await process_frame
	_check(craft.angular_velocity.length() < absf(rate) * 0.2, "Pitch rate must decay using actual inertia")
	craft.angular_velocity = Vector3.ZERO
	var resting_torque: Vector3 = cable.call("_pitch_damping_torque", 1.0 / 60.0)
	_check(resting_torque.is_zero_approx(), "Pitch damper must not force a resting aircraft level")
	host.queue_free()
	await process_frame
