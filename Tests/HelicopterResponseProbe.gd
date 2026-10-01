extends Node

class TestEngine:
	extends Node
	var current_power := 0.6

class Pilot:
	extends HelicopterPilot
	var landing_surface_y := 0.0
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _process(_delta: float) -> void: pass
	func _get_ground_height_at_position(_point: Vector3) -> float: return 0.0
	func _get_landing_surface_y() -> float: return landing_surface_y
	func _apply_collective(value: float) -> void: engine.current_power = value

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var cases: Array[Dictionary] = []
	for model in [9, 10, 11, 12, 13, 15]:
		var authored := (load("res://Aircraft/Aircraft_%d.tscn" % model) as PackedScene).get_state()
		for revised in [false, true]:
			var body := RigidBody3D.new()
			body.name = "Aircraft_%d_%s" % [model, revised]
			body.mass = 2800.0
			for p in authored.get_node_property_count(0):
				if authored.get_node_property_name(0, p) == &"mass": body.mass = authored.get_node_property_value(0, p)
			body.inertia = Vector3(17000, 17000, 5000)
			body.collision_layer = 0
			body.collision_mask = 0
			body.position = Vector3(cases.size() * 1000, 1000, 0)
			var engine := TestEngine.new()
			engine.name = "Engine"
			body.add_child(engine)
			var aero = load("res://Aircraft/HelicopterFlight.gd").new()
			for i in authored.get_node_count():
				if str(authored.get_node_name(i)) == "SimpleAero":
					for p in authored.get_node_property_count(i):
						var key := authored.get_node_property_name(i, p)
						if key != &"script": aero.set(key, authored.get_node_property_value(i, p))
			aero.ground_effect_height_m = 0.0
			aero.wheel_brake_when_engine_stopped = false
			body.add_child(aero)
			add_child(body)
			var pilot := Pilot.new()
			for i in authored.get_node_count():
				if str(authored.get_node_name(i)) == "HelicopterPilot":
					for p in authored.get_node_property_count(i):
						var key := authored.get_node_property_name(i, p)
						if key != &"script": pilot.set(key, authored.get_node_property_value(i, p))
			body.add_child(pilot)
			pilot.aircraft = body
			pilot.helicopter_flight = aero
			pilot.engine = engine
			pilot._apply_baked_navigation_profile_for_aircraft()
			pilot.state = HelicopterPilot.State.HOVER
			pilot.navigation_response_scale = 1.3 if revised else 1.0
			cases.append({"body":body,"pilot":pilot,"model":model,"revised":revised,
				"target":body.position + Vector3(12, 0, 30),"capture":-1.0,"peak_bank":0.0,"late_error":0.0,"mean_error":0.0})
	for frame in 7200:
		for item in cases:
			item.pilot._fly_toward(item.target, 6.0, 1.0 / 60.0)
		await get_tree().physics_frame
		for item in cases:
			var offset: Vector3 = item.target - item.body.position
			var error := Vector2(offset.x, offset.z).length()
			item.mean_error += error / 7200.0
			if error < 2.5 and item.capture < 0.0: item.capture = frame / 60.0
			item.peak_bank = maxf(item.peak_bank, absf(item.body.rotation_degrees.z))
			if frame >= 6000: item.late_error += error / 1200.0
	var failures := 0
	for item in cases:
		print("HELI_RESPONSE model=%d revised=%s capture=%.2f mean_error=%.2f late_error=%.2f peak_bank=%.2f" % [item.model,item.revised,item.capture,item.mean_error,item.late_error,item.peak_bank])
		if item.revised:
			for baseline in cases:
				if baseline.model != item.model or baseline.revised: continue
				# Compare settling against the existing hover controller, which itself
				# circles outside a 2.5m radius in several models in this fixture.
				if item.mean_error >= baseline.mean_error or item.late_error > baseline.late_error + 0.25 or item.peak_bank > 20.0: failures += 1
	# At touchdown, both settings must produce identical commands even with
	# lateral drift and a heading error. Test terrain and carrier landing paths.
	for carrier in [false, true]:
		var reference := landing_commands(cases[0], 1.0, carrier)
		var revised := landing_commands(cases[0], 1.3, carrier)
		if reference != revised:
			failures += 1
			push_error("Final landing response changed, carrier=%s" % carrier)
	print("HELICOPTER_RESPONSE_%s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func landing_commands(item: Dictionary, scale: float, carrier: bool) -> Array[Vector3]:
	var pilot := Pilot.new()
	item.body.add_child(pilot)
	pilot.aircraft = item.body
	pilot.helicopter_flight = item.pilot.helicopter_flight
	pilot.engine = item.pilot.engine
	pilot.state = HelicopterPilot.State.LANDING
	pilot._landing_on_carrier = carrier
	pilot.landing_surface_y = item.body.position.y
	pilot.navigation_response_scale = scale
	var commands: Array[Vector3] = []
	for frame in 60:
		pilot._fly_toward(item.body.position + Vector3(4, 0, 6), 3.0, 1.0 / 60.0)
		commands.append(Vector3(pilot._pitch_cmd, pilot._roll_cmd, pilot._yaw_cmd))
	pilot.free()
	return commands
