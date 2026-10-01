extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	var carrier := Node3D.new()
	root.add_child(carrier)
	current_scene = carrier
	var bots: Array[SimpleTractorBot] = []
	for i in 4:
		var bot := SimpleTractorBot.new()
		carrier.add_child(bot)
		bots.append(bot)
	# Captured hangar positions: three selected bots and an unused fourth bot
	# left beside the middle bot after storage. Repeat under carrier rotation.
	for yaw in [0.0, 0.7]:
		carrier.rotation.y = yaw
		var starts := [Vector3(4.5, -9.5, -15.5), Vector3(9.89447, -9.35, -7.69934), Vector3(4.5, -9.5, -8), Vector3(9.14996, -9.35, -6.89954)]
		var goals := [Vector3(4.5, -9.5, -15.5), Vector3(4.5, -9.5, -12), Vector3(4.5, -9.5, -8)]
		for i in 4:
			bots[i].position = starts[i]
			bots[i].rotation.y = 0.0
			bots[i]._route.clear()
			bots[i]._route_goal = Vector3.INF
		var away := (bots[1].global_position - bots[3].global_position).normalized()
		check(bots[1]._peer_separation_is_outward(bots[3], bots[1].global_position + away * 0.05), "outward separation rejected")
		check(not bots[1]._peer_separation_is_outward(bots[3], bots[1].global_position - away * 0.05), "inward movement allowed")
		check(not bots[1]._peer_separation_is_outward(bots[3], bots[3].global_position - away * 4.0), "movement through peer allowed")
		paused = true
		bots[1].move_deck_transit(goals[1], 12.0, 1.0 / 60.0)
		check(bots[1].position.is_equal_approx(starts[1]), "separation moved while paused")
		paused = false
		var finished := false
		var separated := false
		for tick in 1200:
			var done := true
			for i in 3:
				var before := bots[i].global_position
				done = bots[i].move_deck_transit(goals[i], 12.0, 1.0 / 60.0) and done
				check(before.distance_to(bots[i].global_position) <= 0.201, "robot teleported during separation")
			var overlaps := bots[1]._peer_sweep_blocked(bots[3], bots[1].global_position)
			if separated: check(not overlaps, "robot re-entered idle bot after separating")
			separated = separated or not overlaps
			for i in 3:
				for j in range(i + 1, 4):
					if i == 1 and j == 3: continue
					check(not bots[i]._peer_sweep_blocked(bots[j], bots[i].global_position), "created another robot overlap")
			if done:
				finished = true
				break
		check(finished, "hangar boarding deadlocked yaw=%s positions=%s" % [yaw, bots.map(func(b): return b.position)])
		check(bots[3].position.is_equal_approx(starts[3]), "unused robot moved")
	for failure in failures: push_error(failure)
	print("TRACTOR_OVERLAP_RECOVERY_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	carrier.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message): failures.append(message)
