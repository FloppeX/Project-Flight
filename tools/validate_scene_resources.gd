extends SceneTree
## Load scene resources without instantiating them or running their _ready methods.
## Optional: -- --scene-root=res://Aircraft (repeatable).

const DEFAULT_ROOTS := ["Aircraft", "AI", "AirOps", "Audio", "Buildings", "Camera",
	"Effects", "Enemies", "Environment", "GroundOps", "GroundVehicle", "HUD",
	"LandCarrier", "Models", "Operations", "POI", "Projectiles", "Scenario",
	"UI", "Weapons", "Weather"]
var scenes: Array[String] = []
var failures: Array[String] = []

func collect(path: String) -> void:
	if FileAccess.file_exists(path.path_join(".gdignore")):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		failures.append("Cannot open scene directory: " + path)
		return
	for name in directory.get_files():
		if name.get_extension() in ["tscn", "scn"]:
			var scene_path := path.path_join(name)
			if scene_path not in scenes:
				scenes.append(scene_path)
	for name in directory.get_directories():
		if not name.begins_with("."):
			collect(path.path_join(name))

func _initialize() -> void:
	var roots: Array[String] = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene-root="):
			roots.append(argument.trim_prefix("--scene-root="))
	if roots.is_empty():
		for folder in DEFAULT_ROOTS:
			roots.append("res://" + folder)
		scenes.append("res://Main_Scene.tscn")
	for root_path in roots:
		collect(root_path)
	scenes.sort()
	for path in scenes:
		var resource := ResourceLoader.load(path, "PackedScene")
		if not resource is PackedScene or not resource.can_instantiate():
			failures.append("Cannot load scene: " + path)
	if scenes.is_empty():
		failures.append("No scenes found")
	for failure in failures:
		push_error(failure)
	print("SCENE_RESOURCE_CHECK %s scenes=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", scenes.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
