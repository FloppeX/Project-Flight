extends Node

var failures: Array[String] = []
var host: Node3D

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	get_tree().create_timer(100.0).timeout.connect(func():
		push_error("REGIONAL_GROUND_TIMEOUT")
		get_tree().quit(1))
	for singleton in ["AirOpsManager", "GroundOpsManager", "OperationsCoordinator", "FlightDirector"]:
		var node := get_node_or_null("/root/" + singleton)
		if node != null: node.process_mode = Node.PROCESS_MODE_DISABLED
	host = Node3D.new()
	add_child(host)
	var ground := StaticBody3D.new()
	ground.name = "TerrainFixture"
	ground.add_to_group("terrain")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000,1,2000)
	shape.shape = box
	shape.position.y = -.5
	ground.add_child(shape)
	host.add_child(ground)
	for number in [1,2,3,4,5,6,7,8,14,16]:
		await landing(number, true, Vector3(0,-2,65), 4.0)
		await landing(number, false, Vector3(0,-2,60), 5.0)
	await landing(5, true, Vector3(0,-11,35), 2.0)
	await landing(5, false, Vector3(0,-35,20), 2.0)
	for failure in failures: push_error(failure)
	print("REGIONAL_GROUND_LANDING_%s cases=22" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

func landing(number: int, wheels: bool, velocity: Vector3, duration: float) -> void:
	var craft := load("res://Aircraft/Aircraft_%d.tscn" % number).instantiate() as Aircraft
	craft.freeze = true
	craft.prevent_below_terrain = false
	craft.position = Vector3(0,3.5 if wheels else 1.8,-200)
	host.add_child(craft)
	for node in craft.get_children():
		if node.name in ["AIPilot","AIToggle","ControlEngine","ControlSteering","SimpleAero","EjectionSequence"]:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var gear := craft.get_node("LandingGear") as AircraftModule_LandingGear
	await get_tree().process_frame
	await get_tree().process_frame
	var control := craft.get_node("ControlLandingGear")
	if wheels: control.deploy_gear()
	elif gear.lock_deployed: gear.collapse_from_damage()
	else: control.stow_gear()
	if not wheels and gear.is_deployed and not gear.damage_collapsed: failures.append("%d belly fixture failed to retract gear" % number)
	craft.freeze = false
	craft.linear_velocity = velocity
	var destroyed := false
	var saw_contact := false
	var collapsed := false
	var minimum_hull := 1.0
	var final_speed := velocity.length()
	for frame in int(duration * 60.0):
		await get_tree().physics_frame
		if not is_instance_valid(craft) or craft._has_exploded:
			destroyed = true
			break
		saw_contact = saw_contact or craft.has_meta("ground_landing_mode")
		collapsed = collapsed or bool(craft.get_meta("gear_collapsed",false))
		var model := craft.get_node("PartDamageModel") as AircraftPartDamageModel
		minimum_hull = minf(minimum_hull, model.get_zone_health(&"fuselage")/model.get_zone_max_health(&"fuselage"))
		final_speed = craft.linear_velocity.length()
	var label := "%d %s sink=%.1f" % [number,"gear" if wheels else "belly",-velocity.y]
	if velocity.y > -10.0:
		if destroyed: failures.append(label+" gentle landing destroyed aircraft")
		if not saw_contact and not wheels: failures.append(label+" no contact classification")
		if minimum_hull < .5: failures.append(label+" excessive gentle contact damage")
		if not wheels and final_speed >= velocity.length() - 1: failures.append(label+" no sliding deceleration")
	elif velocity.y > -20.0:
		if not collapsed: failures.append(label+" hard arrival did not collapse gear")
	else:
		if not destroyed: failures.append(label+" severe impact was not destructive")
	print("GROUND_CASE ",label," destroyed=",destroyed," hull=",minimum_hull," speed=",final_speed," collapsed=",collapsed," contact=",saw_contact)
	if is_instance_valid(craft): craft.free()
	for child in host.get_children():
		if child is RigidBody3D: child.queue_free()
	await get_tree().process_frame
