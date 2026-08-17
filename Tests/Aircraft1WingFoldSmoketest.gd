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
	_expect(
		(left_outer.transform * left_outer_hinge_local).distance_to(left_middle_fold * left_outer_hinge) < 0.001,
		"left outer hinge separated from the folded middle panel"
	)
	_expect(
		(right_outer.transform * right_outer_hinge_local).distance_to(right_middle_fold * right_outer_hinge) < 0.001,
		"right outer hinge separated from the folded middle panel"
	)

	aircraft.free()
	_finish()


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
