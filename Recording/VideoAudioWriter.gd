extends RefCounted
## Worker-owned float PCM spool. Never touches AudioServer or the scene tree.
const LIMIT := 0.891251 # -1 dBFS; leave headroom for AAC reconstruction peaks.
const FILTER := "alimiter=limit=0.891251:attack=5:release=50:level=false:latency=true"
var file: FileAccess
var frames := 0
var peak_before_gain := 0.0
var peak_after_gain := 0.0
var over_limit_frames := 0
var gain := -1.0
var mix_rate: int
var path: String

func _init(directory: String, rate: int) -> void:
	mix_rate = rate
	path = directory.path_join("audio.f32le")
	file = FileAccess.open(path, FileAccess.WRITE)

func append(samples: PackedVector2Array, target_gain: float) -> bool:
	if file == null: return false
	if gain < 0.0: gain = target_gain
	# Smooth volume/mute edits over at most 5 ms, rather than introducing clicks
	# at chunk boundaries. Below the ceiling, the later limiter adds no gain.
	var ramp := mini(samples.size(), maxi(1, int(mix_rate * 0.005)))
	for i in samples.size():
		var sample := samples[i]
		if not sample.is_finite(): return false
		peak_before_gain = maxf(peak_before_gain, maxf(absf(sample.x), absf(sample.y)))
		sample *= lerpf(gain, target_gain, minf(float(i + 1) / ramp, 1.0))
		var peak := maxf(absf(sample.x), absf(sample.y))
		peak_after_gain = maxf(peak_after_gain, peak)
		if peak > LIMIT: over_limit_frames += 1
		samples[i] = sample
	gain = target_gain
	file.store_buffer(samples.to_byte_array())
	frames += samples.size()
	return file.get_error() == OK

func finish(ffmpeg: String, wav_path: String) -> String:
	if file == null: return "Cannot write floating-point game audio"
	file.close()
	file = null
	if frames == 0: return "No game audio frames captured"
	var output: Array = []
	var code := OS.execute(ffmpeg, PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-n", "-f", "f32le",
		"-ar", str(mix_rate), "-ac", "2", "-i", path,
		"-af", FILTER, "-c:a", "pcm_s16le", wav_path]), output, true, false)
	if code != 0: return "Audio finishing failed (%d): %s" % [code, str(output)]
	return ""

func stats() -> Dictionary:
	return {"audio_frames": frames, "audio_mix_rate": mix_rate,
		"audio_seconds": float(frames) / mix_rate,
		"audio_peak_before_gain": peak_before_gain, "audio_peak_after_gain": peak_after_gain,
		"audio_over_limit_frames": over_limit_frames, "audio_limit_dbfs": -1.0}
