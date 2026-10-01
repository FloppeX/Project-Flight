extends Node

class CheckpointProbe:
	extends "res://SaveGameManager.gd"
	var writes := 0
	var fail_write := false
	var blocked := false
	func _is_campaign_scene_ready() -> bool:
		return true
	func _collect_raw_blockers(_prune: bool = true) -> Array[Dictionary]:
		if blocked:
			return [{"code": "world_starting", "message": "World starting"}]
		return []
	func _save_campaign(_automatic: bool) -> Dictionary:
		writes += 1
		return {"ok": not fail_write}

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var root := get_tree().root
	var session := root.get_node("GameSession")
	var grid := root.get_node("TerrainNavGrid")
	var graph := root.get_node("NavGraph")
	var probe := CheckpointProbe.new()
	root.add_child(probe)
	probe.set_process(false)
	probe.autosave_enabled = true
	session.configure_new_game("Checkpoint test", Color.WHITE, Color.BLACK, 0)
	probe._process(0.016)
	_expect(probe.writes == 0, "saved before navigation was ready")
	grid.set("_is_baked", true)
	graph.set("_is_ready", true)
	probe.blocked = true
	probe._process(0.016)
	_expect(probe.writes == 0, "saved while startup was blocked")
	probe.blocked = false
	probe.fail_write = true
	probe._process(0.016)
	_expect(probe.writes == 1 and not probe._initial_checkpoint_saved, "failed write marked complete")
	probe._process(0.016)
	_expect(probe.writes == 1, "failed save retried every frame")
	probe.fail_write = false
	probe._process(5.0)
	_expect(probe.writes == 2 and probe._initial_checkpoint_saved, "initial save did not retry successfully")
	probe._process(0.016)
	_expect(probe.writes == 2, "initial save repeated")
	probe._last_saved_fingerprint = 123
	probe.clear_cached_runtime_state()
	_expect(probe._last_saved_fingerprint == 0, "previous campaign fingerprint survived reset")
	probe._process(0.016)
	_expect(probe.writes == 3, "next campaign waited for the calm window")
	probe.clear_cached_runtime_state()
	probe.autosave_enabled = false
	probe._process(0.016)
	_expect(probe.writes == 3, "disabled autosave still wrote initial checkpoint")
	probe.autosave_enabled = true
	session.is_new_game = false
	probe._process(0.016)
	_expect(probe.writes == 3, "Continue treated as a new game")
	session.is_new_game = true
	session.is_trailer_scenario = true
	probe._process(0.016)
	_expect(probe.writes == 3, "trailer triggered initial checkpoint")
	grid.set("_is_baked", false)
	graph.set("_is_ready", false)
	probe.queue_free()
	if failures.is_empty():
		print("[NewCampaignCheckpointSmoketest] PASS")
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
