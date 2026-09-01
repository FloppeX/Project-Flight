extends Node

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")
const HITCH_LOG_PATH := "user://perf_logs/hitch_events.csv"
const BLOCKING_SCOPE := "PerformanceHitchTraceSmoketest.blocker"


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# Let startup/import stalls form a separate hitch episode before injecting the
	# deterministic block that this test needs to correlate.
	await get_tree().create_timer(0.4).timeout
	var blocker_start_usec: int = FrameProfiler.begin(BLOCKING_SCOPE)
	OS.delay_msec(55)
	FrameProfiler.end(BLOCKING_SCOPE, blocker_start_usec)
	await get_tree().process_frame
	await get_tree().process_frame

	var hitch_file_variant: Variant = FPSCounter.get("_hitch_file")
	if hitch_file_variant is FileAccess:
		(hitch_file_variant as FileAccess).flush()
	var log_text := FileAccess.get_file_as_string(HITCH_LOG_PATH)
	var found_hitch := false
	var found_scope := false
	for line in log_text.split("\n", false):
		if ",hitch," in line or ",severe_hitch," in line:
			found_hitch = true
			if BLOCKING_SCOPE in line:
				found_scope = true
	if not found_hitch:
		_fail("55 ms main-thread block was not recorded as a hitch")
	if not found_scope:
		_fail("hitch row did not contain its blocking profiler scope")
	if found_hitch and found_scope:
		print("[PerformanceHitchTraceSmoketest] PASS threshold_capture=true scope_correlation=true")
		get_tree().quit(0)


func _fail(message: String) -> void:
	push_error("[PerformanceHitchTraceSmoketest] FAIL %s" % message)
	get_tree().quit(1)
