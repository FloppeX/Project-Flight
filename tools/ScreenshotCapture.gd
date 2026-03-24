extends Node

const SCREENSHOT_DIR := "user://screenshots"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)
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
	var path := SCREENSHOT_DIR.path_join("screenshot_%s.jpg" % timestamp)
	image.save_jpg(path, 0.9)
