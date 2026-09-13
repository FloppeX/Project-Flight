extends Node3D

var checks := 0
var failures := 0

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("_run")

func _rack(craft: RigidBody3D) -> BombRack:
	var rack := BombRack.new()
	var slot := Node3D.new()
	slot.name = "BombSlot1"
	rack.add_child(slot)
	craft.add_child(rack)
	rack._last_fire_time = -10.0
	return rack

func _run() -> void:
	var craft := RigidBody3D.new()
	craft.freeze = true
	craft.position = Vector3(0, 500, 0)
	add_child(craft)
	var rack := _rack(craft)
	var second_rack := _rack(craft)
	_check(rack.can_fire(), "An empty release corridor remains usable")
	var preceding := RigidBody3D.new()
	preceding.freeze = true
	add_child(preceding)
	preceding.global_position = craft.global_position + Vector3(0, -0.3, 0)
	rack._register_released_bomb(preceding, craft)
	_check(not rack.can_fire(), "A following bomb cannot spawn inside its predecessor")
	_check(not second_rack.can_fire(), "Release clearance is shared across an aircraft's racks")
	preceding.global_position = craft.global_position + Vector3(0, -3, 0)
	_check(rack.can_fire(), "A separated predecessor must not stall the next release")
	preceding.global_position = craft.global_position + Vector3(0, -2, 0)
	preceding.linear_velocity = Vector3(0, 10, 0)
	_check(not rack.can_fire(), "A bomb closing into the release corridor is detected")
	var unrelated := RigidBody3D.new()
	unrelated.freeze = true
	add_child(unrelated)
	var unrelated_rack := _rack(unrelated)
	_check(unrelated_rack.can_fire(), "Another aircraft does not inherit the release lock")
	preceding.free()
	_check(rack.can_fire(), "Freed projectiles do not leave stale release blockers")
	craft.set_meta(BombRack.RELEASE_PENDING_META, true)
	_check(not second_rack.can_fire(), "Same-frame pending spawns are serialized across racks")
	craft.set_meta(BombRack.RELEASE_PENDING_META, false)
	_check(rack.can_fire(), "Clearing the pending spawn permits firing again")
	print("BOMB_RELEASE_SEPARATION_SMOKETEST checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
