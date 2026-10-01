extends Node
## Isolated real rigid-body/aerodynamics/gear cycles, not a campaign simulation.
## Engine response is instantaneous; passengers are represented by an 80 kg load.

class TestBody:
	extends RigidBody3D
	func register_safe_collider(_shape: CollisionShape3D) -> void: pass

class TestEngine:
	extends Node
	var current_power := 0.56
	var is_engine_working := true
	func engine_set_power(value: float) -> void: current_power = value
	func engine_stop() -> void: current_power = 0.0

class Pilot:
	extends HelicopterPilot
	var ground_origin := Vector3.ZERO
	var slope := 0.0
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _process(_delta: float) -> void: pass
	func _get_ground_height_at_position(point: Vector3) -> float:
		return (point.x - ground_origin.x) * tan(slope)
	func _get_landing_surface_y() -> float:
		return _get_ground_height_at_position(aircraft.global_position)

var cases: Array[Dictionary] = []

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	for model in [9, 10, 11]:
		for variant in 4:
			var slope_deg := 0.0 if variant % 2 == 0 else 4.0
			var drift := 0.5 if variant < 2 else 2.0
			var origin := Vector3(cases.size() * 2000.0, 0, 0)
			var floor_body := StaticBody3D.new()
			floor_body.position = origin - Vector3(0, 0.5, 0)
			floor_body.rotation.z = deg_to_rad(slope_deg)
			var floor_shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(200, 1, 200)
			floor_shape.shape = box
			floor_body.add_child(floor_shape)
			add_child(floor_body)
			var body := (load("res://Aircraft/Aircraft_%d.tscn" % model) as PackedScene).instantiate() as RigidBody3D
			var authored_pilot := body.get_node("HelicopterPilot")
			var pilot := Pilot.new()
			for property in authored_pilot.get_property_list():
				if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_EDITOR:
					pilot.set(property.name, authored_pilot.get(property.name))
			var gear := body.get_node("LandingGear") as AircraftModule_LandingGear
			gear.gear_visuals.clear()
			body.set_script(TestBody)
			for child in body.get_children():
				if child is CollisionShape3D or child == gear or child.name == "SimpleAero": continue
				child.free()
			var engine := TestEngine.new()
			engine.name = "Engine"
			body.add_child(engine)
			body.position = origin + Vector3(0, 8, 0)
			body.linear_velocity = Vector3(drift, -0.4, drift)
			add_child(body)
			gear.InitialState = AircraftModule_LandingGear.LandingGearInitialStates.DEPLOYED
			gear.setup(body)
			body.add_child(pilot)
			pilot.aircraft = body
			pilot.engine = engine
			pilot.helicopter_flight = body.get_node("SimpleAero")
			pilot.ground_origin = origin
			pilot.slope = deg_to_rad(slope_deg)
			pilot.crash_log_enabled = false
			pilot.debug_enabled = false
			pilot.state = HelicopterPilot.State.LANDING
			pilot.mission_phase = HelicopterPilot.MissionPhase.RESCUE
			pilot.destination = origin
			pilot._has_destination = true
			pilot._physics_delta = 1.0 / 60.0
			pilot._collective_cmd = pilot._get_collective_trim()
			pilot.use_heightmap_pathfinding = false
			cases.append({"body":body, "gear":gear, "pilot":pilot, "model":model, "slope":slope_deg, "drift":drift,
				"landed":-1.0, "clear":-1.0, "peak_tilt":0.0, "contact_speed":0.0})
	for frame in 5400:
		for item in cases:
			if item.clear >= 0.0: continue
			var body: RigidBody3D = item.body
			var pilot: Pilot = item.pilot
			item.gear.process_physic_frame(1.0 / 60.0)
			if item.landed < 0.0:
				pilot._fly_toward(pilot.destination, pilot.hover_speed_mps, 1.0 / 60.0)
				pilot._try_finish_landing()
				if pilot._get_surface_contact_count() > 0:
					item.contact_speed = maxf(item.contact_speed, body.linear_velocity.length())
				if pilot.state == HelicopterPilot.State.IDLE:
					item.landed = frame / 60.0
					print("HELI_CYCLE landed model=%d slope=%.0f t=%.2f tilt=%.2f" % [item.model,item.slope,item.landed,item.peak_tilt])
			elif frame / 60.0 > item.landed + 1.0:
				if pilot.state == HelicopterPilot.State.IDLE:
					body.mass += 80.0
					item.pilot.engine.current_power = 1.0
					pilot.change_state(HelicopterPilot.State.TAKEOFF)
					pilot._desired_altitude_m = body.position.y + 25.0
				var target := pilot._takeoff_start_position + Vector3(100, 25, 100)
				pilot._fly_toward(target, pilot._get_takeoff_speed_limit(), 1.0 / 60.0)
				if not pilot._should_hold_vertical_takeoff():
					item.clear = frame / 60.0
			var tilt := rad_to_deg(acos(clampf(body.global_basis.y.normalized().dot(Vector3.UP), -1, 1)))
			item.peak_tilt = maxf(item.peak_tilt, tilt)
		await get_tree().physics_frame
		if frame % 600 == 0:
			for item in cases:
				if item.clear < 0:
					print("HELI_CYCLE t=%d model=%d slope=%.0f pos=%s %s" % [frame / 60,item.model,item.slope,item.body.position,item.pilot._surface_trace_snapshot()])
		var complete := true
		for item in cases:
			if item.clear < 0: complete = false
		if complete: break
	var failures := 0
	for item in cases:
		var passed: bool = item.landed >= 0 and item.clear >= 0 and item.peak_tilt < 20.0
		if not passed: failures += 1
		print("HELI_CYCLE %s model=%d slope=%.0f drift=%.1f landed=%.2f clear=%.2f peak_tilt=%.2f contact_speed=%.2f" % [
			"PASS" if passed else "FAIL",item.model,item.slope,item.drift,item.landed,item.clear,item.peak_tilt,item.contact_speed])
	print("HELICOPTER_SURFACE_CYCLES_%s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)
