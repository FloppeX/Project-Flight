extends Node3D
var trial_model := 14
var samples: FileAccess
var sample_tick := 0
# Holds pitch/bank only; yaw and translation use the real aircraft physics.
# Paired runs differ only in the adaptive autorudder setting; zero-bank cases fly freely.
class FlatTerrain extends Node3D:
	func get_height(_p: Vector3) -> float: return 0.0
var cases: Array[Dictionary] = []
var trial_speed := 100.0
var elapsed := 0.0
var failures: Array[String] = []
func _ready() -> void:
	set_physics_process(false)
	call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speed="): trial_speed = float(arg.get_slice("=", 1))
		if arg.begins_with("--model="): trial_model = int(arg.get_slice("=", 1))
	samples = FileAccess.open("res://captures/autorudder_adaptive_%d_%d.jsonl" % [trial_model, roundi(trial_speed)], FileAccess.WRITE)
	var aircraft_scene: PackedScene = load("res://Aircraft/Aircraft_%d.tscn" % trial_model)
	Engine.max_fps = 0
	get_tree().create_timer(180.0).timeout.connect(func(): get_tree().quit(2))
	await get_tree().process_frame
	for child in get_tree().root.get_children():
		if child != self: child.process_mode = Node.PROCESS_MODE_DISABLED
	var terrain := FlatTerrain.new()
	add_child(terrain)
	terrain.add_to_group("terrain_provider")
	get_node("/root/TerrainReference").terrain_node = terrain
	get_node("/root/PauseMenu").set("_rudder_assist_level", 2)
	for bank in [0.0, -20.0, 20.0]:
		for adaptive in [false, true]:
			var craft := aircraft_scene.instantiate() as RigidBody3D
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
			controls.rudder_assist_adaptive_response_enabled = adaptive
			craft.global_position = Vector3(cases.size()*10000.0, 2500.0, 0.0)
			craft.linear_velocity = Vector3(6,0,trial_speed)
			craft.angular_velocity = Vector3.ZERO
			cases.append({"craft":craft,"aero":aero,"controls":controls,"bank":bank,"adaptive":adaptive,"sum":0.0,"count":0,"rollout":0.0,"reverse_sum":0.0,"reverse_count":0,"min_g":INF,"max_g":-INF})
	for c in cases: c.craft.freeze = false
	set_physics_process(true)
func _physics_process(delta: float) -> void:
	elapsed += delta
	sample_tick += 1
	for c in cases:
		var craft: RigidBody3D = c.craft
		var basis := craft.global_basis.orthonormalized()
		var heading := atan2(basis.z.x, basis.z.z)
		var bank := float(c.bank)
		if elapsed > 20.0: bank *= clampf(1.0-(elapsed-20.0)/3.0,-1,1)
		if elapsed > 40.0: bank *= clampf(1.0-(elapsed-40.0)/3.0,0,1)
		var yaw_rate := craft.angular_velocity.dot(basis.y)
		if float(c.bank) != 0.0:
			craft.global_basis = Basis(Vector3.UP, heading) * Basis(Vector3.BACK, deg_to_rad(bank))
			craft.angular_velocity = craft.global_basis.y * yaw_rate
		# Cruise-speed harness acts only along the fuselage; no lateral force or yaw moment.
		var forward := craft.global_basis.z
		craft.apply_central_force(forward * craft.mass * (trial_speed - craft.linear_velocity.dot(forward)) * 2.0)
		c.aero.pitch_input = 0.0
		c.aero.roll_input = 0.0
		c.aero.yaw_input = c.controls._apply_rudder_assist(0.0,delta)
		if sample_tick % 6 == 0:
			samples.store_line(JSON.stringify({"time":elapsed,"bank":c.bank,"adaptive":c.adaptive,"ball_g":c.controls._filtered_lateral_g,"rudder":c.aero.yaw_input,"yaw_rate":yaw_rate,"roll":atan2(basis.x.y,basis.y.y),"integral":c.controls._rudder_integral}))
		if elapsed > 15.0 and elapsed < 20.0:
			if c.count == 0:
				print("[Condition] bank=%.0f adaptive=%s speed=%.1f stiffness=%.2f airborne=%s stored=%.3f g=%.3f" % [bank,c.adaptive,craft.linear_velocity.length(),c.aero.current_high_speed_stiffening,c.aero._is_airborne_for_stall_effects(),c.controls._rudder_integral,c.controls._filtered_lateral_g])
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
		var old_reverse: float = old.reverse_sum/old.reverse_count
		var old_ripple: float = old.max_g-old.min_g
		print("[AdaptiveResponse] model=%d speed=%.0f bank=%.0f ripple_before=%.4f ripple_after=%.4f reverse_before=%.4f reverse_after=%.4f" % [trial_model,trial_speed,old.bank,old_ripple,revised.max_g-revised.min_g,old_reverse,reversed_error])
		print("[AdaptiveResponse] bank=%.0f before=%.4fg after=%.4fg reverse=%.4fg ripple=%.4fg rollout=%.4fg trim=%.3f" % [old.bank,before,after,reversed_error,revised.max_g-revised.min_g,revised.rollout,revised.controls._rudder_integral])
		if after > before + 0.02: failures.append("bank %.0f mean slip regressed" % old.bank)
		if reversed_error > maxf(0.04, old_reverse + 0.02): failures.append("reversal %.0f did not settle" % old.bank)
		if revised.max_g-revised.min_g > maxf(0.04, old_ripple * 0.75): failures.append("held bank %.0f is hunting" % old.bank)
		if revised.rollout > maxf(0.04, old.rollout + 0.01): failures.append("rollout %.0f did not settle" % old.bank)
	samples.close()
	for failure in failures: push_error(failure)
	print("[AdaptiveResponse] PASS" if failures.is_empty() else "[AdaptiveResponse] FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)

