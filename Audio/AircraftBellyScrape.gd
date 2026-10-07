extends AudioStreamPlayer3D
## Contact-driven airframe scrape. Wheel rolling and carrier travel are silent.
const SOUND := preload("res://Audio/impacts/belly_scrape.wav")
const START_SPEED := 0.8
const STOP_SPEED := 0.4
const FULL_SPEED := 35.0

var _craft: RigidBody3D
var _contact_frame := -1000
var _slide_speed := 0.0
var _audio_enabled := true

func _ready() -> void:
	_craft = get_parent() as RigidBody3D
	stream = preload("res://Audio/RuntimeAudio.gd").loop_stream(SOUND)
	unit_size = 12.0
	max_distance = 220.0
	volume_db = -80.0
	add_to_group("3d_audio")

func sample_contacts(state: PhysicsDirectBodyState3D) -> void:
	_slide_speed = 0.0
	_contact_frame = Engine.get_physics_frames()
	if _craft.freeze or _craft._has_exploded:
		return
	for index in state.get_contact_count():
		var other := state.get_contact_collider_object(index) as Node
		if other == null:
			continue
		var carrier: bool = _craft._is_carrier_body(other)
		if carrier and _craft._is_managed_by_carrier_deck_ops():
			continue
		if not carrier and not _craft._is_runway_surface(other) and not _craft._is_ground_or_terrain(other):
			continue
		var normal := state.get_contact_local_normal(index).normalized()
		if normal.dot(Vector3.UP) <= 0.55:
			continue
		var shape_index := state.get_contact_local_shape(index)
		var owner_id := _craft.shape_find_owner(shape_index)
		if owner_id < 0 or _craft.safe_colliders.has(_craft.shape_owner_get_owner(owner_id)):
			continue
		var surface_velocity := state.get_contact_collider_velocity_at_position(index)
		if carrier:
			# Carrier child colliders can have zero physics velocity despite travel.
			surface_velocity = _craft._get_carrier_contact_velocity(other)
		var relative := state.get_contact_local_velocity_at_position(index) - surface_velocity
		var speed := relative.slide(normal).length()
		if speed > _slide_speed:
			_slide_speed = speed
			position = state.transform.affine_inverse() * state.get_contact_local_position(index)

func _physics_process(delta: float) -> void:
	var fresh := Engine.get_physics_frames() - _contact_frame <= 2
	if not _audio_enabled or not is_instance_valid(_craft) or _craft.freeze or _craft.sleeping \
			or _craft._has_exploded or not fresh or _slide_speed < (STOP_SPEED if playing else START_SPEED):
		stop()
		volume_db = -80.0
		return
	var strength := clampf((_slide_speed - STOP_SPEED) / (FULL_SPEED - STOP_SPEED), 0.0, 1.0)
	var target_db := lerpf(-30.0, -6.0, sqrt(strength))
	volume_db = lerpf(volume_db, target_db, 1.0 - exp(-18.0 * delta)) if playing else target_db
	pitch_scale = lerpf(0.85, 1.05, strength)
	if not playing:
		play()

func set_aircraft_audio_budget_enabled(enabled: bool) -> void:
	_audio_enabled = enabled
	if not enabled:
		stop()
		volume_db = -80.0

func clear_contact() -> void:
	_contact_frame = -1000
	_slide_speed = 0.0
	stop()
