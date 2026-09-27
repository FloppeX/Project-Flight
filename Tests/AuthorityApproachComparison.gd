extends SceneTree
## Run with the ordinary landing matrix flags plus --authority-case=legacy_calm,
## reduced_calm or reduced_windy. Production scenes/settings are never saved.
const HARNESS = preload("res://Tests/Fixtures/AuthorityApproachHarness.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.get_node("SaveGameManager").autosave_enabled = false
	node_added.connect(configure_node)
	var scene = load("res://Main_Scene.tscn").instantiate()
	scene.randomize_play_area_each_run = false
	scene.get_node("LandCarrier").startup_placement_seed = 20260911
	root.add_child(scene)
	current_scene = scene
	create_timer(2400.0).timeout.connect(func():
		push_error("AUTHORITY_COMPARISON watchdog")
		quit(2))

func configure_node(node: Node) -> void:
	var script = node.get_script()
	if script != null and script.resource_path == "res://Scenario/LandingTestMode.gd":
		node.set_script(HARNESS)
