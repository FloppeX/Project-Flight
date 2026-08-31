extends Node3D

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_14.tscn")

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	_expect(aircraft != null, "Aircraft 14 did not instantiate")
	if aircraft == null:
		_finish()
		return
	aircraft.freeze = true
	add_child(aircraft)
	await get_tree().process_frame

	var wing_fold := aircraft.get_node_or_null("WingFold")
	var left_wing := aircraft.get_node_or_null("aircraft_14/left wing") as MeshInstance3D
	var right_wing := aircraft.get_node_or_null("aircraft_14/right wing") as MeshInstance3D
	var broad_wing_collider := aircraft.get_node_or_null("WingCollider") as CollisionShape3D
	var left_wing_collider := aircraft.get_node_or_null("LeftWingDamageCollider") as CollisionShape3D
	var right_wing_collider := aircraft.get_node_or_null("RightWingDamageCollider") as CollisionShape3D
	_expect(wing_fold != null, "Aircraft 14 has no WingFold14 controller")
	_expect(left_wing != null and right_wing != null, "Aircraft 14 wing meshes were not found")
	_expect(broad_wing_collider != null, "Aircraft 14 broad wing collider was not found")
	_expect(left_wing_collider != null and right_wing_collider != null, "Aircraft 14 per-wing colliders were not found")
	if wing_fold == null or left_wing == null or right_wing == null or broad_wing_collider == null \
			or left_wing_collider == null or right_wing_collider == null:
		aircraft.free()
		_finish()
		return
	wing_fold.set_process(false)

	wing_fold.call("set_technical_index_preview_fraction", 0.0)
	var left_rest: Transform3D = wing_fold.get("_left_rest_transform")
	var right_rest: Transform3D = wing_fold.get("_right_rest_transform")
	var left_hinge: Vector3 = wing_fold.get("_left_hinge")
	var right_hinge: Vector3 = wing_fold.get("_right_hinge")
	var left_root_center: Vector3 = wing_fold.call("_edge_center_in_model_space", left_wing, true, false)
	var right_root_center: Vector3 = wing_fold.call("_edge_center_in_model_space", right_wing, false, false)
	var left_root_top: Vector3 = wing_fold.call("_edge_center_in_model_space", left_wing, true, true)
	var right_root_top: Vector3 = wing_fold.call("_edge_center_in_model_space", right_wing, false, true)
	var left_hinge_local := left_rest.affine_inverse() * left_hinge
	var right_hinge_local := right_rest.affine_inverse() * right_hinge
	var left_tip: Vector3 = wing_fold.call("_edge_center_in_model_space", left_wing, false)
	var right_tip: Vector3 = wing_fold.call("_edge_center_in_model_space", right_wing, true)
	var left_tip_local: Vector3 = left_rest.affine_inverse() * left_tip
	var right_tip_local: Vector3 = right_rest.affine_inverse() * right_tip
	var left_collider_rest := left_wing_collider.transform
	var right_collider_rest := right_wing_collider.transform

	_expect(broad_wing_collider.disabled, "obsolete full-span wing collider is active")
	_expect(not left_wing_collider.disabled and not right_wing_collider.disabled, "per-wing colliders are disabled while unfolded")
	_expect(wing_fold.call("get_technical_index_preview_kind") == &"wings", "Technical Index preview kind is not wings")
	_expect(absf(float(wing_fold.call("get_technical_index_preview_duration")) - 2.0) < 0.001, "fold duration no longer matches Aircraft 2")
	_expect(absf(float(wing_fold.get("fold_angle_deg")) - 110.0) < 0.001, "fold angle is not 110 degrees")
	_expect((wing_fold.get("fold_axis") as Vector3).distance_to(Vector3(0.0, 0.258819, 0.965926)) < 0.000001, "fold axis no longer matches Aircraft 2")
	_expect(left_hinge.is_equal_approx(left_root_top), "left hinge is not on the top of the wing-root seam")
	_expect(right_hinge.is_equal_approx(right_root_top), "right hinge is not on the top of the wing-root seam")
	_expect(left_hinge.y > left_root_center.y + 0.001, "left hinge is still centred through the wing-root seam")
	_expect(right_hinge.y > right_root_center.y + 0.001, "right hinge is still centred through the wing-root seam")

	wing_fold.call("set_technical_index_preview_fraction", 1.0)
	_expect(broad_wing_collider.disabled, "obsolete full-span wing collider became active while folded")
	_expect(not left_wing_collider.disabled and not right_wing_collider.disabled, "per-wing colliders disabled while folded")
	_expect(not _transform_matches(left_wing_collider.transform, left_collider_rest), "left wing collider did not follow the folded wing")
	_expect(not _transform_matches(right_wing_collider.transform, right_collider_rest), "right wing collider did not follow the folded wing")
	_expect((left_wing.transform * left_hinge_local).distance_to(left_hinge) < 0.001, "left hinge moved during folding")
	_expect((right_wing.transform * right_hinge_local).distance_to(right_hinge) < 0.001, "right hinge moved during folding")
	_expect((left_wing.transform * left_tip_local).y > left_tip.y + 0.5, "left wing tip did not fold upward")
	_expect((right_wing.transform * right_tip_local).y > right_tip.y + 0.5, "right wing tip did not fold upward")
	_expect(absf(_short_rotation_angle_deg(left_wing.transform * left_rest.affine_inverse()) - 110.0) < 0.05, "left wing did not fold 110 degrees")
	_expect(absf(_short_rotation_angle_deg(right_wing.transform * right_rest.affine_inverse()) - 110.0) < 0.05, "right wing did not fold 110 degrees")

	wing_fold.call("set_technical_index_preview_fraction", 0.0)
	_expect(broad_wing_collider.disabled, "obsolete full-span wing collider became active after unfolding")
	_expect(_transform_matches(left_wing_collider.transform, left_collider_rest), "left wing collider did not restore after unfolding")
	_expect(_transform_matches(right_wing_collider.transform, right_collider_rest), "right wing collider did not restore after unfolding")
	_expect(_transform_matches(left_wing.transform, left_rest), "left wing did not restore its authored transform")
	_expect(_transform_matches(right_wing.transform, right_rest), "right wing did not restore its authored transform")

	aircraft.set_meta("parking_brake", true)
	wing_fold.call("_process", 2.0)
	_expect(absf(float(wing_fold.call("get_technical_index_preview_fraction")) - 1.0) < 0.001, "parking brake did not fold the wings")
	aircraft.set_meta("parking_brake", false)
	wing_fold.call("_process", 2.0)
	_expect(absf(float(wing_fold.call("get_technical_index_preview_fraction"))) < 0.001, "releasing the parking brake did not unfold the wings")
	aircraft.set_meta("carrier_transport_mode", true)
	wing_fold.call("_process", 2.0)
	_expect(absf(float(wing_fold.call("get_technical_index_preview_fraction")) - 1.0) < 0.001, "carrier transport mode did not fold the wings")

	aircraft.free()
	_finish()


func _short_rotation_angle_deg(rotation_transform: Transform3D) -> float:
	var angle_deg := rad_to_deg(rotation_transform.basis.orthonormalized().get_rotation_quaternion().get_angle())
	return minf(angle_deg, 360.0 - angle_deg)


func _transform_matches(actual: Transform3D, expected: Transform3D) -> bool:
	return actual.origin.distance_to(expected.origin) <= 0.0001 \
			and actual.basis.x.distance_to(expected.basis.x) <= 0.0001 \
			and actual.basis.y.distance_to(expected.basis.y) <= 0.0001 \
			and actual.basis.z.distance_to(expected.basis.z) <= 0.0001


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("AIRCRAFT_14_WING_FOLD_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[Aircraft14WingFoldSmoketest] %s" % failure)
	get_tree().quit(1)
