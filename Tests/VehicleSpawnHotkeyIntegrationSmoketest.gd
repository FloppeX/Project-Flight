extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Load after the project autoloads have entered the tree. A compile-time preload
	# resolves Main_Scene's global singleton types before they are registered.
	var packed := load("res://Main_Scene.tscn") as PackedScene
	var world := packed.instantiate() as Node3D if packed != null else null
	if world == null:
		_fail("main scene could not be instantiated")
		return
	root.add_child(world)
	current_scene = world
	await process_frame
	await process_frame

	var menu := world.get_node_or_null("VehicleSpawnMenu") as CanvasLayer
	if menu == null:
		_fail("ScenarioManager did not install the vehicle spawn menu")
		return

	var spawn_key := InputEventKey.new()
	spawn_key.pressed = true
	spawn_key.physical_keycode = KEY_S
	world.call("_input", spawn_key)
	if not bool(menu.call("is_open")) or not paused:
		_fail("S did not open the picker and pause the main scene")
		return

	var escape_key := InputEventKey.new()
	escape_key.pressed = true
	escape_key.keycode = KEY_ESCAPE
	escape_key.physical_keycode = KEY_ESCAPE
	menu.call("_input", escape_key)
	if bool(menu.call("is_open")) or paused:
		_fail("Escape did not close the picker and restore the main scene")
		return

	print("[VehicleSpawnHotkeyIntegrationSmoketest] PASS main_scene=true s_opens=true escape_closes=true pause_restore=true")
	world.free()
	quit(0)


func _fail(reason: String) -> void:
	push_error("[VehicleSpawnHotkeyIntegrationSmoketest] FAIL %s" % reason)
	paused = false
	quit(1)
