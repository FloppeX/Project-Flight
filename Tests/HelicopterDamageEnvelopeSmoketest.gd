extends "res://Tests/HelicopterDamageSmoketest.gd"
## Uses authored aircraft and the normal AI physics loop, without player input.
## The moving deck is a collision/velocity fixture, not the full carrier scene.
const NUMBERS := [9,10,11,12,13,15]
const PROFILES := [
	{"name":"low_altitude","height":12.0},
	{"name":"forward_speed","velocity":Vector3(0,0,20)},
	{"name":"bank_and_drift","velocity":Vector3(6,0,0),"bank":12.0},
	{"name":"slope","slope":6.0},
	{"name":"gusts","wind":true},
	{"name":"moving_deck","deck":true,"velocity":Vector3(0,0,8)},
]
var results: Array[Dictionary] = []

class MovingDeck extends CharacterBody3D:
	func _physics_process(delta: float) -> void:
		move_and_collide(velocity * delta)

func _run() -> void:
	get_tree().create_timer(330.0).timeout.connect(func():
		push_error("HELICOPTER_ENVELOPE_TIMEOUT")
		get_tree().quit(1))
	for singleton in ["AirOpsManager","GroundOpsManager","OperationsCoordinator","FlightDirector","EnemyVisualBudget"]:
		get_node("/root/"+singleton).process_mode = Node.PROCESS_MODE_DISABLED
	host = Node3D.new()
	add_child(host)
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): only=arg.trim_prefix("--profile=")
	for profile in PROFILES:
		if only.is_empty() or only == profile.name: await run_profile(profile)
	check(results.size() == (NUMBERS.size() * PROFILES.size() if only.is_empty() else NUMBERS.size()),
		"unexpected case count or unknown profile: " + only)
	var report := {"cases":results,"failures":failures,"moving_deck_fixture":true}
	var output := FileAccess.open("res://logs/helicopter_damage_envelope.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	for failure in failures: push_error(failure)
	print("HELICOPTER_DAMAGE_ENVELOPE_","PASS" if failures.is_empty() else "FAIL"," cases=",results.size()," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func surface(origin: Vector3, profile: Dictionary) -> PhysicsBody3D:
	var body: PhysicsBody3D = MovingDeck.new() if profile.get("deck",false) else StaticBody3D.new()
	if body is MovingDeck:
		body.velocity = Vector3(0,0,8)
		body.name = "MovingCarrierDeck"
		body.collision_mask = 0
		body.add_to_group("carrier")
	else: body.add_to_group("terrain")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(90,2,280) if body is MovingDeck else Vector3(240,2,700)
	shape.shape = box
	shape.position.y = -1
	body.add_child(shape)
	host.add_child(body)
	body.position = origin
	body.rotation.z = deg_to_rad(float(profile.get("slope",0)))
	return body

func run_profile(profile: Dictionary) -> void:
	seed(7707)
	var records: Array[Dictionary] = []
	if profile.get("wind",false):
		var wind := preload("res://Weather/WindField.gd").new()
		wind.prevailing_velocity_mps = Vector3(10,0,0)
		wind.gust_amplitude_mps = Vector3(3,1,3)
		wind.turbulence_amplitude_mps = Vector3(1,.5,1)
		host.add_child(wind)
	for number in NUMBERS:
		var origin := Vector3(number*260,1400,0)
		var floor := surface(origin,profile)
		floor.set_physics_process(false)
		var craft := spawn(number)
		craft.position = origin+Vector3.UP*float(profile.get("height",60.0))
		while not craft.runtime_initialized: await get_tree().process_frame
		var pilot: HelicopterPilot = craft.get_node("HelicopterPilot")
		pilot.initialize(craft)
		prime(craft)
		craft.rotation.z = deg_to_rad(float(profile.get("bank",0)))
		craft.linear_velocity = profile.get("velocity",Vector3.ZERO)
		var record := {"aircraft":number,"profile":profile.name,"craft":craft,"floor":floor,
			"touchdown":{},"max_angular_speed":0.0,"minimum_airborne_rpm":1.0,"settled_time":-1.0,
			"pilot_alive":true,"exploded":false,"settled_frames":0,"trajectory":[]}
		craft.touchdown.connect(func(details: Dictionary):
			if record.touchdown.is_empty(): record.touchdown=details.duplicate())
		craft.destroyed.connect(func():
			record.exploded=true
			record.pilot_alive=not craft.get_meta("pilot_dead",false))
		records.append(record)
	# Release together after initialization so the entry conditions are exact.
	for record in records:
		record.floor.set_physics_process(true)
		var craft: Aircraft = record.craft
		craft.get_node("PartDamageModel").damage_zone(&"engine",1000)
		craft.get_node("HelicopterPilot").process_mode = Node.PROCESS_MODE_INHERIT
		craft.freeze = false
		craft.linear_velocity = profile.get("velocity",Vector3.ZERO)
		craft.rotation.z = deg_to_rad(float(profile.get("bank",0)))
	for frame in 2100:
		await get_tree().physics_frame
		var completed := 0
		for record in records:
			if not is_instance_valid(record.craft) or record.exploded:
				completed += 1
				continue
			var craft: Aircraft = record.craft
			var model = craft.get_node("PartDamageModel")
			var flight: HelicopterFlight = craft.get_node("SimpleAero")
			var relative := craft.linear_velocity - VelocityFrame.get_node_velocity(record.floor)
			if frame == 0:
				record.initial_speed = craft.linear_velocity.length()
				record.initial_bank = rad_to_deg(acos(clampf(craft.global_basis.y.y,-1,1)))
				var requested_velocity: Vector3 = profile.get("velocity",Vector3.ZERO)
				check((craft.linear_velocity-requested_velocity).length()<1.0,"entry velocity was not applied "+profile.name+str(record.aircraft))
			record.max_angular_speed = maxf(record.max_angular_speed,craft.angular_velocity.length())
			if record.touchdown.is_empty(): record.minimum_airborne_rpm = minf(record.minimum_airborne_rpm,flight.rotor_energy.rpm)
			if frame % 60 == 0:
				record.trajectory.append({"time":frame/60.0,"height":craft.position.y-1400,"rpm":flight.rotor_energy.rpm,
					"collective":flight.rotor_energy.collective,"vertical_speed":relative.y,"planar_speed":Vector2(relative.x,relative.z).length(),
					"angular_speed":craft.angular_velocity.length(),"supported":model.is_ground_supported(),
					"gear_contacts":craft.get_node("HelicopterPilot")._get_surface_contact_count()})
			var on_surface: bool = model.is_ground_supported()
			var pilot: HelicopterPilot = craft.get_node("HelicopterPilot")
			var stable := on_surface and relative.length()<.8 and pilot._surface_attitude_stable()
			record.settled_frames = record.settled_frames+1 if stable else 0
			if record.settled_frames >= 60 and record.settled_time<0: record.settled_time=frame/60.0
			if record.settled_time >= 0: completed+=1
		if completed == records.size(): break
	for record in records:
		var label := "%s Aircraft %d" % [profile.name,record.aircraft]
		if is_instance_valid(record.craft):
			var craft: Aircraft = record.craft
			record.pilot_alive = not bool(craft.get_meta("pilot_dead",false))
			record.damage = craft.get_node("PartDamageModel").get_damage_state()
			record.final_relative_speed = (craft.linear_velocity-VelocityFrame.get_node_velocity(record.floor)).length()
			record.final_bank = rad_to_deg(acos(clampf(craft.global_basis.y.y,-1,1)))
			record.final_angular_speed = craft.angular_velocity.length()
		check(not record.exploded and record.pilot_alive,label+" did not survive")
		check(record.settled_time>=0,label+" did not settle")
		check(not record.touchdown.is_empty(),label+" no touchdown")
		check(float(record.touchdown.get("descent_speed_mps",100))<6.0,label+" hard touchdown")
		record.erase("craft")
		record.erase("floor")
		record.erase("settled_frames")
		results.append(record)
		print("HELICOPTER_ENVELOPE_CASE ",label," sink=",record.touchdown.get("descent_speed_mps",-1)," settled=",record.settled_time," exploded=",record.exploded)
	await clear_case()
