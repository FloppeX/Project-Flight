extends Node3D

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_1.tscn")

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	_expect(aircraft != null, "Aircraft 1 did not instantiate")
	if aircraft == null:
		_finish()
		return
	aircraft.freeze = true
	add_child(aircraft)
	await get_tree().process_frame

	var wing_fold := aircraft.get_node_or_null("WingFold") as WingFold1
	_expect(wing_fold != null, "Aircraft 1 has no WingFold controller")
	if wing_fold == null:
		aircraft.free()
		_finish()
		return
	wing_fold.set_process(false)

	var left_middle := aircraft.get_node_or_null("aircraft_1/wing middle left") as MeshInstance3D
	var right_middle := aircraft.get_node_or_null("aircraft_1/wing middle right") as MeshInstance3D
	var left_outer := aircraft.get_node_or_null("aircraft_1/wing outer left") as MeshInstance3D
	var right_outer := aircraft.get_node_or_null("aircraft_1/wing outer right") as MeshInstance3D
	_expect(
		left_middle != null and right_middle != null and left_outer != null and right_outer != null,
		"Aircraft 1 wing meshes were not found"
	)
	if left_middle == null or right_middle == null or left_outer == null or right_outer == null:
		aircraft.free()
		_finish()
		return
	var broad_wing_collider := aircraft.get_node_or_null("WingCollider") as CollisionShape3D
	var left_panel_collider := aircraft.get_node_or_null("LeftWingDamageCollider") as CollisionShape3D
	var right_panel_collider := aircraft.get_node_or_null("RightWingDamageCollider") as CollisionShape3D
	var has_localized_wing_colliders := left_panel_collider != null and right_panel_collider != null
	_expect(broad_wing_collider != null, "Aircraft 1 broad wing collider was not found")
	if broad_wing_collider != null:
		wing_fold.set_fold_fraction_immediate(0.0)
		_expect(
			broad_wing_collider.disabled if has_localized_wing_colliders else not broad_wing_collider.disabled,
			"broad wing collider state does not match the localized-collider setup while unfolded"
		)
		wing_fold.set_fold_fraction_immediate(0.25)
		_expect(broad_wing_collider.disabled, "wing collider remains active during a partial fold")
		wing_fold.set_fold_fraction_immediate(1.0)
		_expect(broad_wing_collider.disabled, "wing collider remains active while fully folded")
		wing_fold.set_fold_fraction_immediate(0.0)
		_expect(
			broad_wing_collider.disabled if has_localized_wing_colliders else not broad_wing_collider.disabled,
			"broad wing collider state does not match the localized-collider setup after unfolding"
		)

	var left_hinge: Vector3 = wing_fold.get("_left_inner_hinge")
	var right_hinge: Vector3 = wing_fold.get("_right_inner_hinge")
	var left_center: Vector3 = wing_fold._edge_center_in_model_space(left_middle, true)
	var right_center: Vector3 = wing_fold._edge_center_in_model_space(right_middle, false)
	var left_top: Vector3 = wing_fold._edge_center_in_model_space(left_middle, true, true)
	var right_top: Vector3 = wing_fold._edge_center_in_model_space(right_middle, false, true)

	_expect(left_hinge.is_equal_approx(left_top), "left root hinge is not on the upper root edge")
	_expect(right_hinge.is_equal_approx(right_top), "right root hinge is not on the upper root edge")
	_expect(left_hinge.y > left_center.y + 0.001, "left root hinge is still centered through the wing thickness")
	_expect(right_hinge.y > right_center.y + 0.001, "right root hinge is still centered through the wing thickness")

	var left_outer_hinge: Vector3 = wing_fold.get("_left_outer_hinge")
	var right_outer_hinge: Vector3 = wing_fold.get("_right_outer_hinge")
	var left_outer_center := (
		wing_fold._edge_center_in_model_space(left_middle, false)
		+ wing_fold._edge_center_in_model_space(left_outer, true)
	) * 0.5
	var right_outer_center := (
		wing_fold._edge_center_in_model_space(right_middle, true)
		+ wing_fold._edge_center_in_model_space(right_outer, false)
	) * 0.5
	var left_outer_bottom := (
		wing_fold._edge_center_in_model_space(left_middle, false, false, true)
		+ wing_fold._edge_center_in_model_space(left_outer, true, false, true)
	) * 0.5
	var right_outer_bottom := (
		wing_fold._edge_center_in_model_space(right_middle, true, false, true)
		+ wing_fold._edge_center_in_model_space(right_outer, false, false, true)
	) * 0.5
	_expect(left_outer_hinge.is_equal_approx(left_outer_bottom), "left outer hinge is not on the lower seam edge")
	_expect(right_outer_hinge.is_equal_approx(right_outer_bottom), "right outer hinge is not on the lower seam edge")
	_expect(left_outer_hinge.y < left_outer_center.y - 0.001, "left outer hinge is still centered through the wing thickness")
	_expect(right_outer_hinge.y < right_outer_center.y - 0.001, "right outer hinge is still centered through the wing thickness")

	var left_rest: Transform3D = wing_fold.get("_left_middle_rest")
	var right_rest: Transform3D = wing_fold.get("_right_middle_rest")
	var left_outer_rest: Transform3D = wing_fold.get("_left_outer_rest")
	var right_outer_rest: Transform3D = wing_fold.get("_right_outer_rest")
	var left_hinge_local := left_rest.affine_inverse() * left_hinge
	var right_hinge_local := right_rest.affine_inverse() * right_hinge
	var left_outer_hinge_local := left_outer_rest.affine_inverse() * left_outer_hinge
	var right_outer_hinge_local := right_outer_rest.affine_inverse() * right_outer_hinge
	wing_fold.set_fold_fraction_immediate(1.0)
	_expect((left_middle.transform * left_hinge_local).distance_to(left_hinge) < 0.001, "left root hinge moved during folding")
	_expect((right_middle.transform * right_hinge_local).distance_to(right_hinge) < 0.001, "right root hinge moved during folding")
	var left_middle_fold := left_middle.transform * left_rest.affine_inverse()
	var right_middle_fold := right_middle.transform * right_rest.affine_inverse()
	var left_outer_counter := left_middle_fold.affine_inverse() * left_outer.transform * left_outer_rest.affine_inverse()
	var right_outer_counter := right_middle_fold.affine_inverse() * right_outer.transform * right_outer_rest.affine_inverse()
	var left_middle_angle_deg := _short_rotation_angle_deg(left_middle_fold)
	var right_middle_angle_deg := _short_rotation_angle_deg(right_middle_fold)
	var left_outer_angle_deg := _short_rotation_angle_deg(left_outer_counter)
	var right_outer_angle_deg := _short_rotation_angle_deg(right_outer_counter)
	_expect(
		absf(left_middle_angle_deg - 130.0) < 0.05,
		"left middle panel did not fold 130 degrees (%.3f)" % left_middle_angle_deg
	)
	_expect(
		absf(right_middle_angle_deg - 130.0) < 0.05,
		"right middle panel did not fold 130 degrees (%.3f)" % right_middle_angle_deg
	)
	_expect(
		absf(left_outer_angle_deg - 180.0) < 0.05,
		"left outer panel did not counter-fold 180 degrees (%.3f)" % left_outer_angle_deg
	)
	_expect(
		absf(right_outer_angle_deg - 180.0) < 0.05,
		"right outer panel did not counter-fold 180 degrees (%.3f)" % right_outer_angle_deg
	)
	_expect(
		(left_outer.transform * left_outer_hinge_local).distance_to(left_middle_fold * left_outer_hinge) < 0.001,
		"left outer hinge separated from the folded middle panel"
	)
	_expect(
		(right_outer.transform * right_outer_hinge_local).distance_to(right_middle_fold * right_outer_hinge) < 0.001,
		"right outer hinge separated from the folded middle panel"
	)

	var livery := get_node_or_null("/root/Livery")
	_expect(livery != null, "Livery autoload is unavailable")
	if livery != null:
		livery.call("set_player_livery", Color("566b78"), Color("d19a3a"), 4)
		livery.call("apply", aircraft)
		var model_root := aircraft.get_node_or_null("aircraft_1") as Node3D
		if model_root != null:
			_expect_pattern_transform(left_middle, model_root.transform * left_rest, "left middle")
			_expect_pattern_transform(right_middle, model_root.transform * right_rest, "right middle")
			_expect_pattern_transform(left_outer, model_root.transform * left_outer_rest, "left outer")
			_expect_pattern_transform(right_outer, model_root.transform * right_outer_rest, "right outer")

	aircraft.free()
	_finish()


func _short_rotation_angle_deg(rotation_transform: Transform3D) -> float:
	var angle_deg := rad_to_deg(rotation_transform.basis.orthonormalized().get_rotation_quaternion().get_angle())
	return minf(angle_deg, 360.0 - angle_deg)


func _expect_pattern_transform(mesh_instance: MeshInstance3D, expected: Transform3D, label: String) -> void:
	var material := mesh_instance.get_surface_override_material(0)
	_expect(material is ShaderMaterial, "%s wing surface has no pattern material" % label)
	if not material is ShaderMaterial:
		return
	var shader_material := material as ShaderMaterial
	_expect(bool(shader_material.get_shader_parameter("use_shared_pattern_space")), "%s wing does not use shared pattern space" % label)
	var actual_variant: Variant = shader_material.get_shader_parameter("pattern_local_to_root")
	_expect(actual_variant is Transform3D, "%s wing has no shared pattern transform" % label)
	if not actual_variant is Transform3D:
		return
	var actual := actual_variant as Transform3D
	var matches := actual.origin.distance_to(expected.origin) <= 0.0001 \
			and actual.basis.x.distance_to(expected.basis.x) <= 0.0001 \
			and actual.basis.y.distance_to(expected.basis.y) <= 0.0001 \
			and actual.basis.z.distance_to(expected.basis.z) <= 0.0001
	_expect(matches, "%s wing pattern was projected from its folded transform instead of its shared rest-space transform" % label)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("AIRCRAFT_1_WING_FOLD_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[Aircraft1WingFoldSmoketest] %s" % failure)
	get_tree().quit(1)
