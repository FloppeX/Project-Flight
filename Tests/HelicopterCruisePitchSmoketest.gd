extends SceneTree

class TestEngine extends Node:
	var current_power := 0.86

var pairs: Array = []
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	# Load authored tuning without starting weapons, AI, audio or player controls.
	for id in [9, 10, 11, 12, 13, 15]:
		var state := (load("res://Aircraft/Aircraft_%d.tscn" % id) as PackedScene).get_state()
		var pair: Array = []
		for limited in [false, true]:
			var body := RigidBody3D.new()
			body.mass = 2800.0
			for p in state.get_node_property_count(0):
				if state.get_node_property_name(0, p) == &"mass":
					body.mass = state.get_node_property_value(0, p)
			body.inertia = Vector3(17000, 17000, 5000)
			body.collision_layer = 0
			body.collision_mask = 0
			body.position = Vector3(id * 100, 5000, 0)
			var engine := TestEngine.new()
			engine.name = "Engine"
			body.add_child(engine)
			var aero = load("res://Aircraft/HelicopterFlight.gd").new()
			for i in state.get_node_count():
				if str(state.get_node_name(i)) == "SimpleAero":
					for p in state.get_node_property_count(i):
						var key := state.get_node_property_name(i, p)
						if key != &"script":
							aero.set(key, state.get_node_property_value(i, p))
			aero.cruise_body_pitch_deg = 15.0 if limited else 0.0
			aero.pitch_input = -1.0
			aero.ground_effect_height_m = 0.0
			aero.wheel_brake_when_engine_stopped = false
			body.add_child(aero)
			root.add_child(body)
			pair.append({"body":body,"aero":aero,"max_pitch":0.0})
		pairs.append({"id":id,"craft":pair})
	for frame in 3600:
		await physics_frame
		for pair in pairs:
			for craft in pair.craft:
				craft.max_pitch = maxf(craft.max_pitch, absf(craft.aero._signed_pitch_deg()))
	for pair in pairs:
		var old = pair.craft[0]
		var tuned = pair.craft[1]
		var old_speed := Vector2(old.body.linear_velocity.x, old.body.linear_velocity.z).length()
		var new_speed := Vector2(tuned.body.linear_velocity.x, tuned.body.linear_velocity.z).length()
		print("PITCH_SAMPLE id=%d old_pitch=%.2f new_pitch=%.2f peak=%.2f old_kmh=%.2f new_kmh=%.2f" % [pair.id, -old.aero._signed_pitch_deg(), -tuned.aero._signed_pitch_deg(), tuned.max_pitch, old_speed * 3.6, new_speed * 3.6])
		if absf(tuned.aero._signed_pitch_deg()) > 16.0 or absf(tuned.aero._signed_pitch_deg()) < 13.5:
			failures.append("settled cruise pitch Aircraft_%d" % pair.id)
		if absf(new_speed - old_speed) / maxf(old_speed, 1.0) > 0.05:
			failures.append("cruise speed changed over 5%% Aircraft_%d" % pair.id)
		for craft in pair.craft:
			craft.aero.pitch_input = 1.0
		pair["braking_pitch"] = 0.0
	for frame in 480:
		await physics_frame
		for pair in pairs:
			pair.braking_pitch = maxf(pair.braking_pitch, pair.craft[1].aero._signed_pitch_deg())
	for pair in pairs:
		print("MANOEUVRE_SAMPLE id=%d braking_pitch=%.2f" % [pair.id, pair.braking_pitch])
		if pair.braking_pitch < 17.0:
			failures.append("cyclic braking cannot exceed cruise trim Aircraft_%d" % pair.id)
		for craft in pair.craft:
			craft.aero.pitch_input = 0.0
	for frame in 1200:
		await physics_frame
	for pair in pairs:
		if absf(pair.craft[1].aero._signed_pitch_deg()) > 1.0:
			failures.append("neutral recovery Aircraft_%d" % pair.id)
	for pair in pairs:
		for craft in pair.craft:
			craft.body.queue_free()
	await process_frame
	print("HELICOPTER_CRUISE_PITCH_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)
