extends SceneTree

const SOUND := preload("res://Audio/landing_gear/stow.wav")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var budget := load("res://Effects/EnemyVisualBudget.gd").new() as Node
	budget.enabled = false
	root.add_child(budget)
	budget._reset_stats()
	var players: Array = [AudioStreamPlayer.new(), AudioStreamPlayer3D.new()]
	var finishes := [0, 0]
	for i in range(players.size()):
		var player: Node = players[i]
		player.stream = SOUND
		root.add_child(player)
		player.finished.connect(func(): finishes[i] += 1)
		player.play()
	await process_frame
	await process_frame

	for cycle in range(2):
		if cycle > 0:
			for player in players:
				player.play()
			await process_frame
			await process_frame
		budget._apply_aircraft_audio_budget(players, false)
		budget._apply_aircraft_audio_budget(players, false)
		for player in players:
			_check(not player.playing, "budget must stop suppressed audio")
		# A detached player must retain its pending restore until reattached.
		root.remove_child(players[1])
		budget._apply_aircraft_audio_budget([players[1]], true)
		_check(players[1].has_meta("visual_budget_audio_was_playing"), "detached restore lost its snapshot")
		root.add_child(players[1])
		budget._apply_aircraft_audio_budget(players, true)
		await process_frame
		await process_frame
		for player in players:
			_check(player.playing, "interrupted audio must resume once")
		# Continue the real periodic budget pass beyond the clip's duration.
		var deadline := Time.get_ticks_msec() + int((SOUND.get_length() + 0.7) * 1000.0)
		while Time.get_ticks_msec() < deadline:
			budget._apply_aircraft_audio_budget(players, true)
			await create_timer(0.04).timeout
		for i in range(players.size()):
			_check(not players[i].playing, "finished one-shot was restarted")
			_check(finishes[i] == cycle + 1, "one-shot must finish exactly once per restore")
		budget._apply_aircraft_audio_budget(players, false)
		budget._apply_aircraft_audio_budget(players, true)
		await process_frame
		for player in players:
			_check(not player.playing, "silent player resumed from an old snapshot")

	for player in players:
		player.queue_free()
	budget.queue_free()
	await process_frame
	if failures.is_empty():
		print("AIRCRAFT_AUDIO_BUDGET_PASS one_shots=2D+3D cycles=2 detached_restore=true")
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("AIRCRAFT_AUDIO_BUDGET_FAIL " + message)
