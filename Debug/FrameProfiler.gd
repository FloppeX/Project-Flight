extends RefCounted
class_name FrameProfiler

static var enabled: bool = false
static var report_interval_s: float = 1.0
static var summary_interval_s: float = 10.0
static var spike_threshold_ms: float = 8.0
static var top_count: int = 8

static var _frame_index: int = -1
static var _frame_entries: Dictionary = {}
static var _interval_entries: Dictionary = {}
static var _summary_entries: Dictionary = {}
static var _interval_elapsed_s: float = 0.0
static var _summary_elapsed_s: float = 0.0


static func configure(interval_s: float, threshold_ms: float, count: int, summary_s: float = 10.0) -> void:
	report_interval_s = maxf(interval_s, 0.1)
	summary_interval_s = maxf(summary_s, 0.1)
	spike_threshold_ms = maxf(threshold_ms, 0.0)
	top_count = maxi(count, 1)


static func set_enabled(value: bool, reason: String = "") -> void:
	if enabled == value:
		return
	enabled = value
	_frame_index = -1
	_frame_entries.clear()
	_interval_entries.clear()
	_summary_entries.clear()
	_interval_elapsed_s = 0.0
	_summary_elapsed_s = 0.0
	var suffix := " (%s)" % reason if not reason.is_empty() else ""
	print("[FrameProfiler] %s%s" % ["enabled" if enabled else "disabled", suffix])


static func begin(_label: String) -> int:
	if not enabled:
		return 0
	return Time.get_ticks_usec()


static func end(label: String, start_usec: int) -> void:
	if not enabled or start_usec <= 0:
		return
	var elapsed_us: int = maxi(Time.get_ticks_usec() - start_usec, 0)
	_record(_frame_entries, label, elapsed_us)
	_record(_interval_entries, label, elapsed_us)
	_record(_summary_entries, label, elapsed_us)


static func tick(delta: float) -> void:
	if not enabled:
		return
	var frame := Engine.get_process_frames()
	if _frame_index < 0:
		_frame_index = frame
	elif frame != _frame_index:
		_flush_frame_if_spike()
		_frame_entries.clear()
		_frame_index = frame

	_interval_elapsed_s += maxf(delta, 0.0)
	_summary_elapsed_s += maxf(delta, 0.0)
	if _interval_elapsed_s >= maxf(report_interval_s, 0.1):
		_flush_interval()
		_interval_entries.clear()
		_interval_elapsed_s = 0.0
	if _summary_elapsed_s >= maxf(summary_interval_s, 0.1):
		_flush_summary()
		_summary_entries.clear()
		_summary_elapsed_s = 0.0


static func _record(entries: Dictionary, label: String, elapsed_us: int) -> void:
	var entry: Dictionary = entries.get(label, {"total_us": 0, "max_us": 0, "count": 0})
	entry["total_us"] = int(entry["total_us"]) + elapsed_us
	entry["max_us"] = maxi(int(entry["max_us"]), elapsed_us)
	entry["count"] = int(entry["count"]) + 1
	entries[label] = entry


static func _flush_frame_if_spike() -> void:
	var total_us := 0
	for entry in _frame_entries.values():
		total_us += int((entry as Dictionary).get("total_us", 0))
	if float(total_us) * 0.001 < spike_threshold_ms:
		return
	print("[FrameProfiler] frame_spike labeled=%.2fms top=%s" % [
		float(total_us) * 0.001,
		_format_top_entries(_frame_entries, false),
	])


static func _flush_interval() -> void:
	if _interval_entries.is_empty():
		return
	print("[FrameProfiler] %.1fs top=%s" % [
		_interval_elapsed_s,
		_format_top_entries(_interval_entries, true),
	])


static func _flush_summary() -> void:
	if _summary_entries.is_empty():
		return
	print("[FrameProfilerReport] %.1fs worst=%s" % [
		_summary_elapsed_s,
		_format_top_entries(_summary_entries, true),
	])


static func _format_top_entries(entries: Dictionary, include_avg: bool) -> String:
	var rows: Array[Dictionary] = []
	for label in entries.keys():
		var entry: Dictionary = entries[label]
		rows.append({
			"label": str(label),
			"total_us": int(entry.get("total_us", 0)),
			"max_us": int(entry.get("max_us", 0)),
			"count": int(entry.get("count", 0)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["total_us"]) > int(b["total_us"])
	)

	var parts: Array[String] = []
	var limit: int = mini(maxi(top_count, 1), rows.size())
	for i in range(limit):
		var row := rows[i]
		var count: int = maxi(int(row["count"]), 1)
		if include_avg:
			parts.append("%s total=%.2fms avg=%.3fms max=%.2fms n=%d" % [
				row["label"],
				float(row["total_us"]) * 0.001,
				float(row["total_us"]) * 0.001 / float(count),
				float(row["max_us"]) * 0.001,
				count,
			])
		else:
			parts.append("%s %.2fms" % [
				row["label"],
				float(row["total_us"]) * 0.001,
			])
	return "; ".join(parts)
