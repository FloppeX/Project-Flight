extends Node

const AIRCRAFT_SCENES: Array[String] = [
	"res://Aircraft/Aircraft_1.tscn",
	"res://Aircraft/Aircraft_2.tscn",
	"res://Aircraft/Aircraft_3.tscn",
	"res://Aircraft/Aircraft_4.tscn",
	"res://Aircraft/Aircraft_5.tscn",
	"res://Aircraft/Aircraft_6.tscn",
	"res://Aircraft/Aircraft_7.tscn",
	"res://Aircraft/Aircraft_8.tscn",
	"res://Aircraft/Aircraft_9.tscn",
	"res://Aircraft/Aircraft_10.tscn",
	"res://Aircraft/Aircraft_11.tscn",
	"res://Aircraft/Aircraft_12.tscn",
	"res://Aircraft/Aircraft_14.tscn",
]

const EXPECTED_MARKER_COUNTS: Dictionary = {
	"res://Aircraft/Aircraft_1.tscn": 2,
	"res://Aircraft/Aircraft_2.tscn": 2,
	"res://Aircraft/Aircraft_3.tscn": 2,
	"res://Aircraft/Aircraft_4.tscn": 2,
	"res://Aircraft/Aircraft_5.tscn": 2,
	"res://Aircraft/Aircraft_6.tscn": 2,
	"res://Aircraft/Aircraft_7.tscn": 2,
	"res://Aircraft/Aircraft_8.tscn": 2,
	"res://Aircraft/Aircraft_9.tscn": 4,
	"res://Aircraft/Aircraft_10.tscn": 3,
	"res://Aircraft/Aircraft_11.tscn": 2,
	"res://Aircraft/Aircraft_12.tscn": 3,
	"res://Aircraft/Aircraft_14.tscn": 2,
}

const EXPECTED_WING_FOLLOW_TARGETS: Dictionary = {
	"res://Aircraft/Aircraft_1.tscn": NodePath("../aircraft_1/wing outer left"),
	"res://Aircraft/Aircraft_2.tscn": NodePath("../Aircraft 2 body/left outer wing"),
	"res://Aircraft/Aircraft_5.tscn": NodePath("../aircraft_5/outer wing left"),
	"res://Aircraft/Aircraft_14.tscn": NodePath("../aircraft_14/left wing"),
}

const WING_BASELINE := Basis(
	Vector3(-1.0, 0.0, 0.0),
	Vector3(0.0, 1.0, 0.0),
	Vector3(0.0, 0.0, -1.0)
)
const BODY_BASELINE := Basis(
	Vector3(0.0, 0.0, -1.0),
	Vector3(1.0, 0.0, 0.0),
	Vector3(0.0, -1.0, 0.0)
)

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var total_markers := 0
	for scene_path in AIRCRAFT_SCENES:
		var packed := load(scene_path) as PackedScene
		_expect(packed != null, "%s did not load" % scene_path)
		if packed == null:
			continue
		var aircraft := packed.instantiate()
		_expect(aircraft != null, "%s did not instantiate" % scene_path)
		if aircraft == null:
			continue
		var markers: Array[Node3D] = []
		_collect_insignia_nodes(aircraft, markers)
		var expected_count := int(EXPECTED_MARKER_COUNTS.get(scene_path, 0))
		_expect(markers.size() == expected_count, "%s has %d insignia objects; expected %d" % [scene_path, markers.size(), expected_count])
		for marker in markers:
			_expect(not (marker is Marker3D), "%s/%s is still a plain Marker3D" % [scene_path, marker.name])
			_expect(marker.has_method("get_decal_size"), "%s/%s is not an InsigniaMarker object" % [scene_path, marker.name])
			_verify_marker_orientation(scene_path, marker)
			if marker.has_method("get_decal_size"):
				var decal_size := marker.call("get_decal_size", 1.0) as Vector3
				_expect(decal_size.x > 0.0 and decal_size.y > 0.0 and decal_size.z > 0.0, "%s/%s has an invalid decal volume" % [scene_path, marker.name])
		total_markers += markers.size()
		aircraft.free()
	_expect(total_markers == 30, "converted insignia object total is %d; expected 30" % total_markers)
	await _verify_runtime_decals()
	await _verify_aircraft14_fold_follow()
	_finish()


func _verify_marker_orientation(scene_path: String, marker: Node3D) -> void:
	var expected := Basis.IDENTITY
	if String(marker.name).begins_with("InsigniaWing"):
		expected = WING_BASELINE
		if marker.name == &"InsigniaWing" and EXPECTED_WING_FOLLOW_TARGETS.has(scene_path):
			var actual_follow_path := marker.get("follow_target_path") as NodePath
			var expected_follow_path := EXPECTED_WING_FOLLOW_TARGETS[scene_path] as NodePath
			_expect(actual_follow_path == expected_follow_path, "%s/%s follow target is %s; expected %s" % [scene_path, marker.name, actual_follow_path, expected_follow_path])
			_expect(marker.get_node_or_null(actual_follow_path) is Node3D, "%s/%s follow target does not resolve to a Node3D" % [scene_path, marker.name])
	elif String(marker.name).begins_with("InsigniaTail") or String(marker.name).begins_with("InsigniaSide"):
		expected = BODY_BASELINE
	else:
		return
	var actual := marker.transform.basis.orthonormalized()
	_expect(actual.is_equal_approx(expected), "%s/%s does not match the Aircraft 14 orientation baseline" % [scene_path, marker.name])


func _collect_insignia_nodes(node: Node, out: Array[Node3D]) -> void:
	for child_variant in node.get_children():
		var child := child_variant as Node
		if child is Node3D and String(child.name).begins_with("Insignia") \
				and (child is Marker3D or child.has_method("get_decal_size")):
			out.append(child as Node3D)
		_collect_insignia_nodes(child, out)


func _verify_runtime_decals() -> void:
	var packed := load("res://Aircraft/Aircraft_1.tscn") as PackedScene
	if packed == null:
		_expect(false, "runtime decal aircraft did not load")
		return
	var aircraft := packed.instantiate()
	add_child(aircraft)
	await get_tree().process_frame
	var markers: Array[Node3D] = []
	_collect_insignia_nodes(aircraft, markers)
	for marker in markers:
		_expect(not marker.visible, "runtime insignia gizmo %s is visible" % marker.name)
	var decals: Array[Decal] = []
	_collect_runtime_decals(aircraft, decals)
	_expect(decals.size() == 2, "Aircraft 1 created %d runtime insignia decals; expected 2" % decals.size())
	for decal in decals:
		_expect(decal.size.x > 0.0 and decal.size.y > 0.0 and decal.size.z > 0.0, "%s has an invalid runtime decal volume" % decal.name)
	var wing_marker := _find_named_node(markers, &"InsigniaWing") as Node3D
	var wing_decal := _find_named_node(decals, &"InsigniaDecal_InsigniaWing") as Decal
	var outer_wing := aircraft.get_node_or_null("aircraft_1/wing outer left") as Node3D
	_expect(wing_marker != null, "Aircraft 1 runtime wing marker is missing")
	_expect(wing_decal != null, "Aircraft 1 runtime wing decal is missing")
	_expect(outer_wing != null, "Aircraft 1 outer-left wing is missing")
	if wing_marker != null and wing_decal != null and outer_wing != null:
		_expect(wing_decal.get_parent() == aircraft, "Aircraft 1 followed decal is not kept in aircraft-root space")
		_expect(wing_decal.has_method("get_follow_target") and wing_decal.call("get_follow_target") == outer_wing, "Aircraft 1 wing decal is not following its outer wing")
		_expect(wing_decal.global_transform.is_equal_approx(wing_marker.global_transform), "Aircraft 1 wing decal does not begin at its authored marker pose")
		_expect(is_equal_approx(wing_decal.size.x, float(wing_marker.get("diameter"))), "Aircraft 1 wing decal width differs from its marker")
		_expect(is_equal_approx(wing_decal.size.y, float(wing_marker.get("depth"))), "Aircraft 1 wing decal depth differs from its marker")
		var decal_before := wing_decal.global_transform
		var decal_size_before := wing_decal.size
		var decal_scale_before := wing_decal.transform.basis.get_scale()
		var wing_fold := aircraft.get_node_or_null("WingFold")
		_expect(wing_fold != null and wing_fold.has_method("set_fold_fraction_immediate"), "Aircraft 1 wing-fold test API is missing")
		if wing_fold != null and wing_fold.has_method("set_fold_fraction_immediate"):
			wing_fold.call("set_fold_fraction_immediate", 1.0)
			wing_fold.set_process(false)
			await get_tree().process_frame
			_expect(not wing_decal.global_transform.is_equal_approx(decal_before), "Aircraft 1 wing decal did not move with the folded outer wing")
			_expect(wing_decal.size.is_equal_approx(decal_size_before), "Aircraft 1 wing decal size changed during folding")
			_expect(wing_decal.transform.basis.get_scale().is_equal_approx(decal_scale_before), "Aircraft 1 wing decal scale changed during folding")
	aircraft.queue_free()
	await get_tree().process_frame


func _find_named_node(nodes: Array, wanted_name: StringName) -> Node:
	for node_variant in nodes:
		var node := node_variant as Node
		if node != null and node.name == wanted_name:
			return node
	return null


func _verify_aircraft14_fold_follow() -> void:
	var packed := load("res://Aircraft/Aircraft_14.tscn") as PackedScene
	if packed == null:
		_expect(false, "Aircraft 14 fold-follow scene did not load")
		return
	var aircraft := packed.instantiate()
	add_child(aircraft)
	await get_tree().process_frame
	var markers: Array[Node3D] = []
	_collect_insignia_nodes(aircraft, markers)
	var decals: Array[Decal] = []
	_collect_runtime_decals(aircraft, decals)
	var wing_marker := _find_named_node(markers, &"InsigniaWing") as Node3D
	var wing_decal := _find_named_node(decals, &"InsigniaDecal_InsigniaWing") as Decal
	var outer_wing := aircraft.get_node_or_null("aircraft_14/left wing") as Node3D
	var wing_fold := aircraft.get_node_or_null("WingFold")
	_expect(wing_marker != null, "Aircraft 14 runtime wing marker is missing")
	_expect(wing_decal != null, "Aircraft 14 runtime wing decal is missing")
	_expect(outer_wing != null, "Aircraft 14 left wing is missing")
	_expect(wing_fold != null and wing_fold.has_method("set_technical_index_preview_fraction"), "Aircraft 14 wing-fold test API is missing")
	if wing_marker != null and wing_decal != null and outer_wing != null and wing_fold != null:
		_expect(wing_decal.get_parent() == aircraft, "Aircraft 14 followed decal is not kept in aircraft-root space")
		_expect(wing_decal.has_method("get_follow_target") and wing_decal.call("get_follow_target") == outer_wing, "Aircraft 14 wing decal is not following its left wing")
		_expect(wing_decal.global_transform.is_equal_approx(wing_marker.global_transform), "Aircraft 14 wing decal does not begin at its authored marker pose")
		var decal_before := wing_decal.global_transform
		var decal_size_before := wing_decal.size
		var decal_scale_before := wing_decal.transform.basis.get_scale()
		wing_fold.call("set_technical_index_preview_fraction", 1.0)
		wing_fold.set_process(false)
		await get_tree().process_frame
		_expect(not wing_decal.global_transform.is_equal_approx(decal_before), "Aircraft 14 wing decal did not move with the folded wing")
		_expect(wing_decal.size.is_equal_approx(decal_size_before), "Aircraft 14 wing decal size changed during folding")
		_expect(wing_decal.transform.basis.get_scale().is_equal_approx(decal_scale_before), "Aircraft 14 wing decal scale changed during folding")
		var folded_local := wing_decal.transform
		var livery := get_node_or_null("/root/Livery")
		_expect(livery != null and livery.has_method("apply"), "Livery autoload is unavailable for folded reapply test")
		if livery != null and livery.has_method("apply"):
			livery.call("apply", aircraft)
			await get_tree().process_frame
			decals.clear()
			_collect_runtime_decals(aircraft, decals)
			wing_decal = _find_decal_following_target(decals, outer_wing) as Decal
			_expect(wing_decal != null, "Aircraft 14 wing decal disappeared after folded livery reapply")
			if wing_decal != null:
				_expect(wing_decal.get_parent() == aircraft, "Reapplied Aircraft 14 decal left aircraft-root space")
				_expect(wing_decal.has_method("get_follow_target") and wing_decal.call("get_follow_target") == outer_wing, "Reapplied Aircraft 14 decal lost its wing target")
				_expect(wing_decal.size.is_equal_approx(decal_size_before), "Reapplied Aircraft 14 decal changed size")
				_expect(wing_decal.transform.is_equal_approx(folded_local), "Reapplied Aircraft 14 decal changed position on the folded wing")
	aircraft.queue_free()
	await get_tree().process_frame


func _find_decal_following_target(nodes: Array, wanted_target: Node3D) -> Node:
	for node_variant in nodes:
		var node := node_variant as Node
		if node != null and node.has_method("get_follow_target") \
				and node.call("get_follow_target") == wanted_target:
			return node
	return null


func _collect_runtime_decals(node: Node, out: Array[Decal]) -> void:
	for child_variant in node.get_children():
		var child := child_variant as Node
		if child is Decal and child.is_in_group("livery_insignia"):
			out.append(child as Decal)
		_collect_runtime_decals(child, out)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("AIRCRAFT_INSIGNIA_MARKER_SMOKETEST_OK aircraft=13 markers=30")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[AircraftInsigniaMarkerSmoketest] %s" % failure)
	get_tree().quit(1)
