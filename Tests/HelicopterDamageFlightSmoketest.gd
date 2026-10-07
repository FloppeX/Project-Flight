extends "res://Tests/HelicopterDamageSmoketest.gd"

func _run() -> void:
	get_tree().create_timer(110.0).timeout.connect(func():
		push_error("HELICOPTER_DAMAGE_FLIGHT_TIMEOUT")
		get_tree().quit(1))
	for singleton in ["AirOpsManager","GroundOpsManager","OperationsCoordinator","FlightDirector","EnemyVisualBudget"]:
		get_node("/root/"+singleton).process_mode = Node.PROCESS_MODE_DISABLED
	host = Node3D.new()
	add_child(host)
	var fleet: Array[Aircraft] = []
	for number in [9,10,11,12,13,15]:
		var craft := spawn(number)
		craft.position.x = number*100
		fleet.append(craft)
		while not craft.runtime_initialized: await get_tree().process_frame
		prime(craft)
		craft.freeze = false
	for frame in 180: await get_tree().physics_frame
	for craft in fleet:
		check(absf(craft.linear_velocity.y) < .8,"healthy hover changed: "+str(craft.name)+str(craft.linear_velocity))
		craft.get_node("PartDamageModel").damage_zone(&"tail",1000)
	for frame in 300: await get_tree().physics_frame
	for craft in fleet:
		var model = craft.get_node("PartDamageModel")
		var yaw_rate := rad_to_deg(craft.angular_velocity.dot(craft.global_basis.y))
		print("HELICOPTER_YAW id=",model.aircraft_number," coaxial=",model.coaxial," deg_s=",yaw_rate)
		check(absf(yaw_rate)<1.0 if model.coaxial else absf(yaw_rate)>5.0,"tail-loss yaw "+str(model.aircraft_number))
	await clear_case()
	fleet.clear()
	obstacle(Vector3(1200,1399,0),Vector3(1200,2,200),"terrain")
	var contacts := {}
	for number in [9,10,11,12,13,15]:
		var craft := spawn(number)
		craft.position = Vector3(number*100,1460,0)
		fleet.append(craft)
		while not craft.runtime_initialized: await get_tree().process_frame
		craft.get_node("HelicopterPilot").initialize(craft)
		prime(craft)
		craft.get_node("PartDamageModel").damage_zone(&"engine",1000)
		craft.freeze = false
		craft.touchdown.connect(func(details: Dictionary):
			if not contacts.has(number): contacts[number]=details.duplicate())
	for frame in 1800:
		await get_tree().physics_frame
		for craft in fleet:
			if is_instance_valid(craft): craft.get_node("HelicopterPilot")._try_engine_out_landing()
		if contacts.size() == 6 and frame > 900: break
	for craft in fleet:
		if not is_instance_valid(craft):
			check(false,"autorotation aircraft exploded")
			continue
		var number: int = craft.get_node("PartDamageModel").aircraft_number
		print("HELICOPTER_AUTOROTATION id=",number," y=",craft.position.y," velocity=",craft.linear_velocity," rpm=",craft.get_node("SimpleAero").rotor_energy.rpm," contact=",contacts.get(number,{}))
		check(contacts.has(number),"autorotation did not land "+str(number))
		check(float(contacts.get(number,{}).get("descent_speed_mps",100)) < 6.0,"autorotation exceeded safe gear impact "+str(number))
		check(not craft._has_exploded and not craft.get_meta("pilot_dead",false),"autorotation killed pilot "+str(number))
		check(craft.position.y < 1404 and craft.linear_velocity.length() < 2,"autorotation failed to settle "+str(number))
	await clear_case()
	# Full collective without unloading must spend the stored energy.
	var energy := preload("res://Aircraft/HelicopterRotorEnergy.gd").new()
	energy.rpm = 1.0
	energy.collective = 1.0
	for i in 600: energy.step(1.0/60,1,false,0,1,12,false,true)
	check(energy.rpm == 0.0,"held collective retained energy")
	for i in 600: energy.step(1.0/60,0,false,0,1,12,false,true)
	check(energy.rpm == 0.0,"stalled rotor gained another free autorotation")
	for failure in failures: push_error(failure)
	print("HELICOPTER_DAMAGE_FLIGHT_", "PASS" if failures.is_empty() else "FAIL", " ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
