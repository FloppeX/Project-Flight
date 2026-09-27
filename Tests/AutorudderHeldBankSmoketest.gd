extends Node3D
const AIRCRAFT = preload("res://Aircraft/Aircraft_5.tscn")
# Holds pitch/bank only; yaw and translation use the real aircraft physics.
# Paired runs differ only in accumulated autorudder correction.
class FlatTerrain extends Node3D:
	func get_height(_p: Vector3) -> float: return 0.0
var cases: Array[Dictionary] = []
var elapsed := 0.0
var failures: Array[String] = []
func _ready() -> void:
	set_physics_process(false)
	call_deferred("run")
func run() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(2))
	await get_tree().process_frame
	for child in get_tree().root.get_children():
		if child != self: child.process_mode = Node.PROCESS_MODE_DISABLED
	var terrain := FlatTerrain.new()
	add_child(terrain)
	terrain.add_to_group("terrain_provider")
	get_node("/root/TerrainReference").terrain_node = terrain
	get_node("/root/PauseMenu").set("_rudder_assist_level", 2)
	for bank in [-35.0, -20.0, 20.0, 35.0]:
		for integral in [false, true]:
			var craft := AIRCRAFT.instantiate() as RigidBody3D
			craft.freeze = true
			craft.position = Vector3(cases.size()*10000.0, 2500.0, 0.0)
			var aero = craft.get_node("SimpleAero")
			aero.aero_report_enabled = false
			aero.airflow_feedback_enabled = false
			aero.set_flight_model_override_for_testing(1)
			add_child(craft)
			await get_tree().process_frame
			craft.get_node("AIToggle").disable_ai()
			var pilot = craft.find_child("AIPilot", true, false)
			pilot.set_process(false)
			pilot.set_physics_process(false)
			var controls = craft.get_node("ControlSteering")
			controls.setup(craft)
			controls.set_physics_process(false)
			craft.get_node("ControlEngine").set_physics_process(false)
			var engine = craft.get_node("Engine")
			engine.set_physics_process(false)
			controls._reset_rudder_assist_state()
			if not integral: controls.rudder_assist_integral_gain = 0.0
			craft.global_position = Vector3(cases.size()*10000.0, 2500.0, 0.0)
			craft.linear_velocity = Vector3(0,0,100)
			craft.angular_velocity = Vector3.ZERO
			cases.append({"craft":craft,"aero":aero,"controls":controls,"bank":bank,"integral":integral,"sum":0.0,"count":0,"rollout":0.0,"reverse_sum":0.0,"reverse_count":0,"min_g":INF,"max_g":-INF})
	for c in cases: c.craft.freeze = false
	set_physics_process(true)
func _physics_process(delta: float) -> void:
	elapsed += delta
	for c in cases:
		var craft: RigidBody3D = c.craft
		var basis := craft.global_basis.orthonormalized()
		var heading := atan2(basis.z.x, basis.z.z)
		var bank := float(c.bank)
		if elapsed > 20.0: bank *= clampf(1.0-(elapsed-20.0)/3.0,-1,1)
		if elapsed > 40.0: bank *= clampf(1.0-(elapsed-40.0)/3.0,0,1)
		var yaw_rate := craft.angular_velocity.dot(basis.y)
		craft.global_basis = Basis(Vector3.UP, heading) * Basis(Vector3.BACK, deg_to_rad(bank))
		craft.angular_velocity = craft.global_basis.y * yaw_rate
		# Cruise-speed harness acts only along the fuselage; no lateral force or yaw moment.
		var forward := craft.global_basis.z
		craft.apply_central_force(forward * craft.mass * (100.0 - craft.linear_velocity.dot(forward)) * 2.0)
		c.aero.pitch_input = 0.0
		c.aero.roll_input = 0.0
		c.aero.yaw_input = c.controls._apply_rudder_assist(0.0,delta)
		if elapsed > 15.0 and elapsed < 20.0:
			if c.count == 0:
				print("[Condition] bank=%.0f integral=%s speed=%.1f stiffness=%.2f airborne=%s stored=%.3f g=%.3f" % [bank,c.integral,craft.linear_velocity.length(),c.aero.current_high_speed_stiffening,c.aero._is_airborne_for_stall_effects(),c.controls._rudder_integral,c.controls._filtered_lateral_g])
			c.sum += absf(c.controls._filtered_lateral_g)
			c.count += 1
			c.min_g = minf(c.min_g,c.controls._filtered_lateral_g)
			c.max_g = maxf(c.max_g,c.controls._filtered_lateral_g)
		if elapsed > 35.0 and elapsed < 40.0:
			c.reverse_sum += absf(c.controls._filtered_lateral_g)
			c.reverse_count += 1
		if elapsed > 47.0: c.rollout = maxf(c.rollout, absf(c.controls._filtered_lateral_g))
	if elapsed < 50.0: return
	set_physics_process(false)
	for i in range(0,cases.size(),2):
		var old = cases[i]
		var revised = cases[i+1]
		var before: float = old.sum / old.count
		var after: float = revised.sum / revised.count
		var reversed_error: float = revised.reverse_sum/revised.reverse_count
		print("[HeldBank] bank=%.0f before=%.4fg after=%.4fg reverse=%.4fg ripple=%.4fg rollout=%.4fg trim=%.3f" % [old.bank,before,after,reversed_error,revised.max_g-revised.min_g,revised.rollout,revised.controls._rudder_integral])
		if after > before * 0.5 or after > 0.04: failures.append("held bank %.0f insufficient improvement" % old.bank)
		if reversed_error > 0.04: failures.append("reversal %.0f did not settle" % old.bank)
		if revised.max_g-revised.min_g > 0.04: failures.append("held bank %.0f is hunting" % old.bank)
		if revised.rollout > 0.04: failures.append("rollout %.0f did not settle" % old.bank)
	for failure in failures: push_error(failure)
	print("[HeldBank] PASS" if failures.is_empty() else "[HeldBank] FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)

