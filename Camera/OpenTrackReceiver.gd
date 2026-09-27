extends Node
## OpenTrack UDP over network: six native little-endian doubles on Windows,
## X/Y/Z in centimetres, yaw/pitch/roll in degrees. Loopback only.
## Protocol: opentrack/proto-udp/ftnoir_protocol_ftn.cpp and api/plugin-api.hpp.

const PORT := 4242
const TIMEOUT_S := 0.5
const SMOOTHING_LABELS := ["OFF", "LIGHT", "MEDIUM", "STRONG"]
const SMOOTHING_SECONDS := [0.0, 0.035, 0.075, 0.15]

var enabled := false
var smoothing_index := 2
var head_position := Vector3.ZERO
var head_orientation := Quaternion.IDENTITY
var _udp := PacketPeerUDP.new()
var _target_position := Vector3.ZERO
var _target_orientation := Quaternion.IDENTITY
var _age := TIMEOUT_S
var _bind_error := OK


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -10
	set_process(false)


func configure(active: bool, smoothing: int) -> void:
	smoothing_index = clampi(smoothing, 0, SMOOTHING_SECONDS.size() - 1)
	if active == enabled:
		return
	enabled = active
	_udp.close()
	_age = TIMEOUT_S
	_target_position = Vector3.ZERO
	_target_orientation = Quaternion.IDENTITY
	head_position = Vector3.ZERO
	head_orientation = Quaternion.IDENTITY
	_bind_error = OK
	if enabled:
		_bind_error = _udp.bind(PORT, "127.0.0.1")
	set_process(enabled)


func _process(delta: float) -> void:
	_age += delta
	# Bound work and consume the queue, so old samples never add camera latency.
	for index in range(256):
		if _udp.get_available_packet_count() == 0:
			break
		accept_packet(_udp.get_packet())
	advance_pose(delta)


func accept_packet(packet: PackedByteArray) -> bool:
	if not enabled or packet.size() != 48:
		return false
	var values: Array[float] = []
	for index in range(6):
		var value := packet.decode_double(index * 8)
		if not is_finite(value) or absf(value) > 10000.0:
			return false
		values.append(value)
	# View-local axes: right +X, up +Y, backwards +Z. OpenTrack +yaw
	# turns right, +pitch looks up, +roll tilts right.
	# OpenTrack lateral translation has the opposite sign to view-local X.
	_target_position = Vector3(-values[0], values[1], values[2]) * 0.01
	_target_position = _target_position.clamp(Vector3(-0.25, -0.2, -0.3), Vector3(0.25, 0.2, 0.04))
	_target_orientation = Basis.from_euler(Vector3(
		deg_to_rad(clampf(values[4], -89.0, 89.0)),
		deg_to_rad(clampf(values[3], -180.0, 180.0)) * -1.0,
		deg_to_rad(clampf(values[5], -80.0, 80.0)) * -1.0
	)).get_rotation_quaternion()
	_age = 0.0
	return true


func advance_pose(delta: float) -> void:
	var connected := is_receiving()
	var target_position := _target_position if connected else Vector3.ZERO
	var target_orientation := _target_orientation if connected else Quaternion.IDENTITY
	var seconds: float = SMOOTHING_SECONDS[smoothing_index] if connected else 0.15
	var blend := 1.0 if seconds <= 0.0 else 1.0 - exp(-maxf(delta, 0.0) / seconds)
	head_position = head_position.lerp(target_position, blend)
	head_orientation = head_orientation.slerp(target_orientation, blend).normalized()


func is_receiving() -> bool:
	return enabled and _age < TIMEOUT_S


func status_text() -> String:
	if not enabled:
		return "OFF"
	if _bind_error != OK:
		return "PORT 4242 UNAVAILABLE — TOGGLE OFF/ON TO RETRY"
	return "RECEIVING" if is_receiving() else "WAITING FOR OPENTRACK"


func _exit_tree() -> void:
	_udp.close()
