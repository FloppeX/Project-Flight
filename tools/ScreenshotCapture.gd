extends Node

const SCREENSHOT_DIR := "res://screenshots"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_get_screenshot_dir_absolute())
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_INSERT:
			_take_screenshot()
		elif event.keycode == KEY_DELETE:
			DustEffect.dust_enabled = not DustEffect.dust_enabled
		elif event.keycode == KEY_P:
			get_tree().paused = not get_tree().paused

func _take_screenshot() -> void:
	var image := get_viewport().get_texture().get_image()
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var file_name := "screenshot_%s.jpg" % timestamp
	var absolute_dir := _get_screenshot_dir_absolute()
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var absolute_path := absolute_dir.path_join(file_name)
	var err := image.save_jpg(absolute_path, 0.9)
	if err == OK:
		print("[ScreenshotCapture] Saved screenshot to %s" % absolute_path)
	else:
		push_error("[ScreenshotCapture] Failed to save screenshot to %s (err=%d)" % [absolute_path, err])

func _get_screenshot_dir_absolute() -> String:
	return ProjectSettings.globalize_path(SCREENSHOT_DIR)
