extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node.new()
	scene.name = "LoadingScreenNonsenseSmoketest"
	root.add_child(scene)
	current_scene = scene
	var loading_screen: Node = root.get_node("LoadingScreen")
	loading_screen.call("begin_scenario_load")
	var status_label := loading_screen.get("_label") as Label
	var detail_label := loading_screen.get("_detail_label") as Label
	if status_label == null or detail_label == null:
		_fail("loading labels were unavailable")
		return
	var first_message := status_label.text
	if not first_message.ends_with("0%") or first_message.contains("INITIALIZING SCENARIO"):
		_fail("initial status was not aircraft nonsense with genuine progress")
		return
	if detail_label.text != "GROUND CREW REPORTS EVERYTHING IS WITHIN IMAGINARY TOLERANCES":
		_fail("detail text remained literal loading information")
		return

	loading_screen.call("_update_nonsense_message", 2.0)
	loading_screen.call("_update_progress_display")
	if status_label.text == first_message:
		_fail("aircraft nonsense did not rotate")
		return
	var second_message := status_label.text
	for literal_stage in ["LOCATING TERRAIN", "SAMPLING TERRAIN", "STREAMING LOCAL TERRAIN"]:
		if status_label.text.contains(literal_stage):
			_fail("real loading stage leaked into status text")
			return

	loading_screen.set("_bound_scene_id", scene.get_instance_id())
	loading_screen.set("_navgrid_done", true)
	loading_screen.set("_terrain_done", true)
	loading_screen.call("_update_progress_display")
	if status_label.text != "DECLARING THE SKY AIRWORTHY  100%":
		_fail("completion message was not themed")
		return

	loading_screen.call("_hide_immediately")
	print("[LoadingScreenNonsenseSmoketest] PASS first='%s' second='%s'" % [
		first_message,
		second_message,
	])
	quit(0)


func _fail(reason: String) -> void:
	push_error("[LoadingScreenNonsenseSmoketest] FAIL %s" % reason)
	quit(1)
