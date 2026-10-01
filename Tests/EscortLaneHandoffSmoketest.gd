extends SceneTree

class EscortVehicle extends Node3D:
	var waypoint_reach_distance := 25.0

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	await process_frame
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	var carrier := Node3D.new()
	world.add_child(carrier)
	var platoon: Node3D = load("res://GroundVehicle/ground_vehicle_platoon.gd").new()
	world.add_child(platoon)
	platoon.set_physics_process(false)
	platoon.set_escort_carrier(carrier, 100.0)
	var vehicle := EscortVehicle.new()
	world.add_child(vehicle)
	# Check both flanks and both longitudinal staging directions, including
	# the 10-25 m gap where the driver formerly stopped before handoff.
	for yaw in [0.0, 0.6]:
		carrier.rotation.y = yaw
		for side in [-1.0, 1.0]:
			for end in [-1.0, 1.0]:
				var slot := carrier.to_global(Vector3(side * 82.0, 0, end * 148.0))
				for reach in [6.0, 25.0]:
					vehicle.waypoint_reach_distance = reach
					var gap: float = reach - 1.0
					vehicle.position = carrier.to_global(Vector3(side * (79.0 - gap), 0, -end * 87.0))
					var next: Vector3 = carrier.to_local(platoon._get_escort_navigation_position(vehicle, slot))
					if absf(next.z - end * 87.0) > 0.01:
						failures.append("side staging did not advance at driver arrival")
					vehicle.position = carrier.to_global(Vector3(side * 79.0, 0, end * (87.0 - gap)))
					next = carrier.to_local(platoon._get_escort_navigation_position(vehicle, slot))
					if absf(next.z - end * 148.0) > 0.01:
						failures.append("longitudinal staging did not advance to final slot")
				vehicle.position = carrier.to_global(Vector3(0, 0, -end * 100))
				var first: Vector3 = carrier.to_local(platoon._get_escort_navigation_position(vehicle, slot))
				if absf(first.x - side * 79.0) > 0.01 or signf(first.z) != -end:
					failures.append("vehicle skipped the flank staging leg")
	world.free()
	print("ESCORT_LANE_HANDOFF_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)

