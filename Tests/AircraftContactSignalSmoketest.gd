extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Load after project autoloads and global classes have initialized. Preloading
	# Aircraft_5 from a standalone --script parse occurs too early for dependencies
	# such as VelocityFrame.
	var aircraft_scene := load("res://Aircraft/Aircraft_5.tscn") as PackedScene
	var aircraft := aircraft_scene.instantiate() as RigidBody3D if aircraft_scene != null else null
	if aircraft == null:
		print("AIRCRAFT_CONTACT_SIGNAL_SMOKETEST FAIL aircraft_scene_load")
		quit(1)
		return
	aircraft.name = "ContactSignalAircraft"
	aircraft.freeze = true
	aircraft.position = Vector3(0.0, 1000.0, 0.0)
	aircraft.set("touchdown_signal_cooldown_s", 0.0)
	root.add_child(aircraft)
	await process_frame
	await process_frame

	var touchdowns: Array[Dictionary] = []
	var hard_landings: Array[Dictionary] = []
	var crashes: Array[float] = []
	aircraft.connect("touchdown", func(details: Dictionary): touchdowns.append(details.duplicate(true)))
	aircraft.connect("hard_landing", func(details: Dictionary): hard_landings.append(details.duplicate(true)))
	aircraft.connect("crashed", func(speed): crashes.append(float(speed)))

	aircraft.call("land", 2.0, 60.0, "carrier")
	aircraft.call("land", 6.0, 60.0, "carrier")
	aircraft.call("crash", 5.0)
	aircraft.call("land", 12.0, 60.0, "carrier")
	var touchdown_meta_valid := aircraft.has_meta("last_touchdown_details")

	var passed := touchdowns.size() == 3 \
		and hard_landings.size() == 2 \
		and crashes.size() == 1 \
		and is_equal_approx(crashes[0], 12.0) \
		and not bool(touchdowns[0].get("hard", true)) \
		and bool(touchdowns[1].get("hard", false)) \
		and not bool(touchdowns[1].get("damaging", true)) \
		and bool(touchdowns[2].get("damaging", false)) \
		and str(touchdowns[2].get("surface", "")) == "carrier" \
		and is_equal_approx(float(touchdowns[2].get("descent_speed_mps", 0.0)), 12.0) \
		and touchdown_meta_valid
	print("AIRCRAFT_CONTACT_SIGNAL_SMOKETEST %s touchdowns=%d hard=%d crashes=%d classes=NORMAL,HARD,DAMAGING" % [
		"PASS" if passed else "FAIL",
		touchdowns.size(),
		hard_landings.size(),
		crashes.size(),
	])
	if is_instance_valid(aircraft) and not aircraft.is_queued_for_deletion():
		aircraft.queue_free()
	await process_frame
	quit(0 if passed else 1)
