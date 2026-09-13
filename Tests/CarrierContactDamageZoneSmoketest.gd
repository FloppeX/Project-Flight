extends SceneTree

var failures: Array[String] = []
var contacts := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func shape_index(craft: RigidBody3D, collider: CollisionShape3D) -> int:
	for owner_id in craft.get_shape_owners():
		if craft.shape_owner_get_owner(owner_id) == collider:
			return craft.shape_owner_get_shape_index(owner_id, 0)
	return -1

func run() -> void:
	for number in [1, 2, 3, 4, 5, 6, 7, 8, 14]:
		var host := Node3D.new()
		root.add_child(host)
		current_scene = host
		var carrier := StaticBody3D.new()
		carrier.name = "LandCarrierContactFixture"
		host.add_child(carrier)
		var craft = load("res://Aircraft/Aircraft_%d.tscn" % number).instantiate()
		craft.freeze = true
		craft.position.y = 1000.0
		host.add_child(craft)
		await process_frame
		await process_frame
		var model = craft.get_node("PartDamageModel")
		# Resource replacement can reorder physics indices independently of owners.
		for collider in model._zone_colliders.values():
			if is_instance_valid(collider):
				collider.shape = collider.shape.duplicate()
		await process_frame
		craft.carrier_body_contact_min_damage = 5.0
		craft.carrier_body_contact_damage_per_mps = 3.0
		craft.damage_cooldown_s = 1.0
		craft.linear_velocity = Vector3(4, 0, 0)
		for zone in model._zone_colliders:
			var collider = model._zone_colliders[zone]
			check(is_instance_valid(collider), "Aircraft_%d missing collider %s" % [number, zone])
			if not is_instance_valid(collider):
				continue
			var index := shape_index(craft, collider)
			check(index >= 0, "Aircraft_%d missing index %s" % [number, zone])
			var before: Dictionary = model.get_damage_state()
			craft._last_damage_ms = -100000
			craft._on_Aircraft_body_shape_entered(carrier.get_rid(), carrier, 0, index)
			contacts += 1
			var after: Dictionary = model.get_damage_state()
			for other in before:
				var loss := float(before[other].health) - float(after[other].health)
				check(is_equal_approx(loss, 17.0 if other == zone else 0.0),
					"Aircraft_%d contact %s damaged %s by %.1f" % [number, zone, other, loss])
			craft._on_Aircraft_body_shape_entered(carrier.get_rid(), carrier, 0, index)
			check(model.get_damage_state() == after, "Aircraft_%d contact cooldown bypassed" % number)
		# Same-frame callbacks from an already destroyed shape must not fall
		# through to a different intact part while its collider is being disabled.
		var wing_index := shape_index(craft, model._zone_colliders[&"right_wing"])
		model.damage_zone(&"right_wing", model.get_zone_health(&"right_wing"))
		var destroyed_snapshot: Dictionary = model.get_damage_state()
		craft._last_damage_ms = -100000
		craft._on_Aircraft_body_shape_entered(carrier.get_rid(), carrier, 0, wing_index)
		check(model.get_damage_state() == destroyed_snapshot,
			"Aircraft_%d destroyed wing contact spilled damage into another part" % number)
		craft._last_damage_ms = -100000
		var hull_before: float = model.get_zone_health(&"fuselage")
		craft.take_damage(1.0)
		check(is_equal_approx(model.get_zone_health(&"fuselage"), hull_before - 1.0),
			"Aircraft_%d generic damage fallback changed" % number)
		host.free()
		await process_frame
	for failure in failures:
		push_error(failure)
	print("CARRIER_CONTACT_DAMAGE_ZONE_SMOKETEST %s models=9 contacts=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", contacts, failures.size()])
	quit(0 if failures.is_empty() else 1)
