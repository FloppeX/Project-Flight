extends RefCounted
## Shared playback setup without modifying imported stream resources.

static func loop_stream(source: AudioStream) -> AudioStream:
	var stream := source.duplicate() as AudioStream
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream

static func listener_near(node: Node3D, distance: float) -> bool:
	var camera := node.get_viewport().get_camera_3d()
	return camera != null and node.global_position.distance_squared_to(camera.global_position) < distance * distance
