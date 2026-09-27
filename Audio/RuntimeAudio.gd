extends RefCounted
## Shared playback setup without modifying imported stream resources.

static func loop_stream(source: AudioStream) -> AudioStream:
	var stream := source.duplicate() as AudioStream
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamWAV:
		# Imported non-looping WAVs can retain a zero-length loop range.
		# Give runtime-enabled loops the full recording before enabling playback.
		if stream.loop_end <= stream.loop_begin:
			stream.loop_end = maxi(1, roundi(stream.get_length() * stream.mix_rate) - 1)
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream

static func listener_near(node: Node3D, distance: float) -> bool:
	var camera := node.get_viewport().get_camera_3d()
	return camera != null and node.global_position.distance_squared_to(camera.global_position) < distance * distance
