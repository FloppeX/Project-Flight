extends SceneTree

var failures: Array[String] = []
class RestartProbe extends Node:
	var calls := 0
	func restart() -> void: calls += 1

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var director: Node = load("res://Scenario/Trailer/TrailerScenario.gd").new()
	scene.add_child(director)
	root.get_node("PauseMenu").visible = false
	# Protect the scene from a real reload while checking the actual key path.
	var recorder := root.get_node("RecordingMode")
	recorder.recording = true
	var key := InputEventKey.new()
	key.pressed = true
	for physical in [true, false]:
		director.status = "unchanged"
		key.physical_keycode = KEY_F7 if physical else KEY_NONE
		key.keycode = KEY_NONE if physical else KEY_F7
		root.push_input(key)
		check(director.status.begins_with("Stop recording"), "F7 reaches protected reset path physical=%s" % physical)
	recorder.recording = false
	director.queue_free()
	await process_frame
	var probe := RestartProbe.new()
	scene.add_child(probe)
	probe.add_to_group("trailer_scenario")
	root.get_node("GameSession").is_trailer_scenario = true
	root.get_node("PauseMenu")._on_restart()
	check(probe.calls == 1, "pause menu delegates to trailer reset instead of plain scene reload")
	print("TRAILER_RESTART_INPUT_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
