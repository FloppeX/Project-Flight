extends Node

const SCREENSHOT_DIR := "res://screenshots"
const VIDEO_DIR := "res://captures"
const CLIP_DURATION_SECONDS := 3.0
const CLIP_FRAMERATE := 60
const FFMPEG_PACKAGE_DIR := "Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe"

var _clip_recording_active: bool = false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_get_screenshot_dir_absolute())
	DirAccess.make_dir_recursive_absolute(_get_video_dir_absolute())
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_INSERT:
			_take_screenshot()
		elif event.keycode == KEY_DELETE:
			if event.shift_pressed:
				DustEffect.dust_enabled = not DustEffect.dust_enabled
				print("[ScreenshotCapture] Dust effects %s" % ("enabled" if DustEffect.dust_enabled else "disabled"))
			else:
				_record_clip()

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

func _record_clip() -> void:
	if _clip_recording_active:
		print("[ScreenshotCapture] Clip capture already in progress")
		return

	var ffmpeg_path := _find_ffmpeg_executable()
	if ffmpeg_path.is_empty():
		push_error("[ScreenshotCapture] ffmpeg.exe not found; clip capture unavailable")
		return

	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var file_name := "clip_%s.mp4" % timestamp
	var absolute_dir := _get_video_dir_absolute()
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var absolute_path := absolute_dir.path_join(file_name)
	var args: Array[String] = [
		"-y",
		"-hide_banner",
		"-loglevel", "error",
		"-f", "gdigrab",
		"-framerate", str(CLIP_FRAMERATE),
		"-draw_mouse", "0",
		"-t", str(CLIP_DURATION_SECONDS),
		"-i", "desktop",
		"-c:v", "libx264",
		"-preset", "ultrafast",
		"-crf", "18",
		"-pix_fmt", "yuv420p",
		absolute_path
	]
	var pid := OS.create_process(ffmpeg_path, args, false)
	if pid <= 0:
		push_error("[ScreenshotCapture] Failed to start ffmpeg clip capture")
		return

	_clip_recording_active = true
	print("[ScreenshotCapture] Recording 3-second clip to %s" % absolute_path)
	_clear_recording_flag_later()

func _clear_recording_flag_later() -> void:
	var reset_delay := CLIP_DURATION_SECONDS + 0.75
	await get_tree().create_timer(reset_delay, true, false, true).timeout
	_clip_recording_active = false

func _find_ffmpeg_executable() -> String:
	var explicit_candidates: Array[String] = [
		OS.get_environment("LOCALAPPDATA").path_join(FFMPEG_PACKAGE_DIR).path_join("ffmpeg-8.1-full_build/bin/ffmpeg.exe"),
		OS.get_environment("LOCALAPPDATA").path_join(FFMPEG_PACKAGE_DIR).path_join("ffmpeg/bin/ffmpeg.exe")
	]
	for candidate in explicit_candidates:
		if candidate != "" and FileAccess.file_exists(candidate):
			return candidate

	var package_root := OS.get_environment("LOCALAPPDATA").path_join(FFMPEG_PACKAGE_DIR)
	if DirAccess.dir_exists_absolute(package_root):
		var build_dirs := DirAccess.get_directories_at(package_root)
		for build_index in range(build_dirs.size() - 1, -1, -1):
			var exe_path := package_root.path_join(build_dirs[build_index]).path_join("bin/ffmpeg.exe")
			if FileAccess.file_exists(exe_path):
				return exe_path
	return ""

func _get_screenshot_dir_absolute() -> String:
	return ProjectSettings.globalize_path(SCREENSHOT_DIR)

func _get_video_dir_absolute() -> String:
	return ProjectSettings.globalize_path(VIDEO_DIR)
