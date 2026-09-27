extends SceneTree

## Aircraft_13's cockpit camera may be current in the editor scene tree. That
## must not hide the imported pilot body while the seat is being positioned.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not Engine.is_editor_hint():
		_fail("test must run with --editor")
		return
	var aircraft: Node3D = load("res://Aircraft/Aircraft_13.tscn").instantiate()
	root.add_child(aircraft)
	await process_frame
	var mount := aircraft.get_node_or_null("CockpitPilot") as CockpitPilotMount
	var pilot := mount.get_pilot_visual() if mount != null else null
	if pilot == null:
		_fail("aircraft has no editor-preview pilot")
		return
	if pilot.get_viewport().get_camera_3d() != pilot.get("_cockpit_camera"):
		_fail("test did not reproduce the cockpit-camera visibility condition")
		return
	var imported := pilot.get_node_or_null("Pilot") as Node3D
	if imported == null or not mount.visible or not imported.visible:
		_fail("seated pilot mesh is hidden in the editor")
		return
	var animation_player := pilot.get_node_or_null("Pilot/AnimationPlayer") as AnimationPlayer
	if animation_player == null or animation_player.assigned_animation != "rigAction" \
			or animation_player.is_playing():
		_fail("editor pilot is not frozen in the imported seated pose")
		return
	print("AIRCRAFT13_PILOT_EDITOR_PREVIEW_PASS visible=true seated=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("AIRCRAFT13_PILOT_EDITOR_PREVIEW_FAIL %s" % reason)
	quit(1)
