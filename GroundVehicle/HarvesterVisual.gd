extends Node3D
## Uses the live authored hull/head. Geometry exists before _ready for fabrication.
const SHOULDER := Vector3(0, 2.40, -1.9)
const UPPER_LENGTH := 3.25
const LOWER_LENGTH := 2.85
const HEAD_LENGTH := 1.7527194
const MIN_EXTENSION := 0.65
const MAX_EXTENSION := 2.30
const FOLD_UPPER := 0.10
const FOLD_LOWER := PI - 0.16

var arm_target := Vector3.ZERO
var arm_extended := false
var suction := false
var cargo_fraction := 0.0
var _tip := Vector3.ZERO
var _deployment := 0.0
var _yaw := 0.0
var _upper_pitch := FOLD_UPPER
var _lower_pitch := FOLD_LOWER
var _extension := MIN_EXTENSION
var _head_pitch := 0.0
var _work_yaw := 0.0
var _work_upper := 0.65
var _work_lower := -0.6
var _work_extension := MIN_EXTENSION
var _upper: Node3D
var _lower: Node3D
var _slider: Node3D
var _hose: MeshInstance3D
var _head: Node3D
var _joint: MeshInstance3D
var _wrist: MeshInstance3D
var _fill: Array[MeshInstance3D] = []
var _particles: GPUParticles3D
var _yellow: StandardMaterial3D
var _dark: StandardMaterial3D

func _init() -> void:
	_yellow = _material(Color("d7a535"))
	_dark = _material(Color("293334"))
	var ivory := _material(Color("c9c7b9"))
	var metal := _material(Color("75817f"))
	var hull := preload("res://Models/Vehicles/Harvester/harvester_hull.glb").instantiate()
	hull.name = "AuthoredHull"
	add_child(hull)
	_cylinder("SlewPedestal", 0.55, 0.76, Vector3(0, 1.81, SHOULDER.z), _dark)
	_cylinder("SlewTurntable", 0.62, 0.2, Vector3(0, 2.24, SHOULDER.z), _yellow)
	var shoulder_pin := _cylinder("ShoulderPin", 0.30, 0.72, SHOULDER, _dark)
	shoulder_pin.rotation.z = PI / 2
	_upper = _link("UpperBoom", 0.48, UPPER_LENGTH, _yellow, ivory)
	_lower = _link("OuterForearm", 0.38, LOWER_LENGTH, _yellow, ivory)
	_slider = _link("TelescopicSection", 0.24, MAX_EXTENSION, metal, _dark)
	_hose = _cylinder("SuctionHose", 0.13, 1, Vector3.ZERO, _dark)
	_joint = _cylinder("ElbowPin", 0.30, 0.72, Vector3.ZERO, _dark)
	_wrist = _cylinder("WristPin", 0.22, 0.58, Vector3.ZERO, _dark)
	_head = Node3D.new()
	_head.name = "ExtractorHeadMount"
	add_child(_head)
	var head := preload("res://Models/Vehicles/Harvester/extractor_head.glb").instantiate()
	head.name = "AuthoredExtractorHead"
	_head.add_child(head)
	# Small gauges attach to the authored rear storage hull.
	for side in [-1.0, 1.0]:
		_box("LevelWindow", Vector3(0.08, 0.75, 0.28), Vector3(side * 2.21, 0.6, -2.5), _dark)
		_fill.append(_box("CargoLevel", Vector3(0.10, 0.71, 0.20), Vector3(side * 2.26, 0.6, -2.5), _yellow))
	var warning := _material(Color("e3ad39"))
	warning.emission_enabled = true
	warning.emission = Color("ffc24a")
	warning.emission_energy_multiplier = 3.0
	_cylinder("Beacon", 0.14, 0.20, Vector3(0.82, 1.95, -3.65), warning)
	_apply_pose()

func _link(label: String, width: float, length: float, mat: Material, trim: Material) -> Node3D:
	var link := Node3D.new()
	link.name = label
	add_child(link)
	var housing := _box("BoomHousing", Vector3(width, length - 0.12, width), Vector3.ZERO, mat)
	remove_child(housing)
	link.add_child(housing)
	for end in [-1.0, 1.0]:
		var collar := _box("EndCollar", Vector3(width * 1.15, 0.16, width * 1.15), Vector3(0, end * (length * 0.5 - 0.18), 0), trim)
		remove_child(collar)
		link.add_child(collar)
	var rail := _box("HydraulicRail", Vector3(0.09, length * 0.72, 0.09), Vector3(width * 0.60, 0, 0), _dark)
	remove_child(rail)
	link.add_child(rail)
	return link

func _material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.76
	return result

func _box(label: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(label, mesh, at, mat)

func _cylinder(label: String, radius: float, height: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	return _mesh(label, mesh, at, mat)

func _mesh(label: String, shape: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = shape
	result.material_override = mat
	result.position = at
	add_child(result)
	return result

func _ready() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "IntakeDust"
	_particles.amount = 30
	_particles.lifetime = 0.5
	_particles.emitting = false
	_particles.visibility_aabb = AABB(Vector3(-12, -5, -12), Vector3(24, 14, 24))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = 1.3
	process.initial_velocity_max = 2.4
	process.gravity = Vector3(0, 2, 0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.4
	process.scale_min = 0.035
	process.scale_max = 0.11
	process.color = Color("d7b47e")
	_particles.process_material = process
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.08
	dust_mesh.height = 0.16
	dust_mesh.material = _material(Color("d7b47e"))
	_particles.draw_pass_1 = dust_mesh
	add_child(_particles)

func _process(delta: float) -> void:
	_pose_arm(delta)
	for fill in _fill:
		fill.scale.y = maxf(0.015, cargo_fraction)
		fill.position.y = 0.245 + 0.355 * cargo_fraction
	if is_instance_valid(_particles):
		_particles.position = _tip + Vector3(0, -0.5, 0)
		_particles.emitting = suction and arm_ready()

func arm_ready() -> bool:
	return arm_extended and intake_target_clear() and _deployment > 0.99 and _tip.distance_to(arm_target) < 0.25

func intake_target_clear() -> bool:
	# A downward head cannot safely work inside the authored chassis footprint.
	# Include the head's width, not just its centerline.
	return absf(arm_target.x) > 2.9 or arm_target.z < -4.9 or arm_target.z > 5.5

func is_folded() -> bool:
	return _deployment < 0.001 and absf(_yaw) < 0.015 and absf(_upper_pitch - FOLD_UPPER) < 0.015 and absf(_lower_pitch - FOLD_LOWER) < 0.015 and absf(_extension - MIN_EXTENSION) < 0.01 and _head_pitch < 0.015

func _solve_target() -> void:
	# The authored head points +Z from its mounting end. Hold the intake down,
	# solving the boom to its wrist rather than treating the whole head as a point.
	var wrist := arm_target + Vector3.UP * HEAD_LENGTH
	var offset := wrist - SHOULDER
	var horizontal := Vector2(offset.x, offset.z).length()
	_work_yaw = atan2(offset.x, offset.z)
	var distance := offset.length()
	_work_extension = clampf(distance + 0.25 - UPPER_LENGTH - LOWER_LENGTH, MIN_EXTENSION, MAX_EXTENSION)
	var forearm := LOWER_LENGTH + _work_extension
	var reach := clampf(distance, absf(UPPER_LENGTH - forearm) + 0.02, UPPER_LENGTH + forearm - 0.02)
	var angle := atan2(offset.y, horizontal)
	_work_upper = angle + acos(clampf((UPPER_LENGTH * UPPER_LENGTH + reach * reach - forearm * forearm) / (2.0 * UPPER_LENGTH * reach), -1.0, 1.0))
	_work_lower = angle - acos(clampf((forearm * forearm + reach * reach - UPPER_LENGTH * UPPER_LENGTH) / (2.0 * forearm * reach), -1.0, 1.0))

func _pose_arm(delta: float) -> void:
	var working := arm_extended and intake_target_clear()
	if working:
		_solve_target()
	# Raise the folded boom first, slew above the roof, then unfold outward.
	# Retraction follows the same clear path in reverse before driving is allowed.
	_deployment = move_toward(_deployment, 1.0 if working else 0.0, delta * 0.55)
	var lift := smoothstep(0.0, 0.20, _deployment)
	var slew := smoothstep(0.20, 0.45, _deployment)
	var reach := smoothstep(0.45, 1.0, _deployment)
	var upper_goal := lerpf(lerpf(FOLD_UPPER, 0.65, lift), _work_upper, reach)
	var lower_goal := lerpf(lerpf(FOLD_LOWER, PI - 0.48, lift), _work_lower, reach)
	_yaw = rotate_toward(_yaw, lerp_angle(0.0, _work_yaw, slew), delta * 2.2)
	_upper_pitch = move_toward(_upper_pitch, upper_goal, delta * 2.6)
	_lower_pitch = move_toward(_lower_pitch, lower_goal, delta * 3.8)
	_extension = move_toward(_extension, lerpf(MIN_EXTENSION, _work_extension, reach), delta * 3.0)
	_head_pitch = move_toward(_head_pitch, reach * PI / 2.0, delta * 2.6)
	_apply_pose()

func _apply_pose() -> void:
	var flat := Vector3(sin(_yaw), 0, cos(_yaw))
	var upper_direction := flat * cos(_upper_pitch) + Vector3.UP * sin(_upper_pitch)
	var lower_direction := flat * cos(_lower_pitch) + Vector3.UP * sin(_lower_pitch)
	var elbow := SHOULDER + upper_direction * UPPER_LENGTH
	var outer_end := elbow + lower_direction * LOWER_LENGTH
	var wrist := outer_end + lower_direction * _extension
	_place_link(_upper, SHOULDER, elbow)
	_place_link(_lower, elbow, outer_end)
	# A fixed-length inner section slides inside the outer housing.
	_place_link(_slider, wrist - lower_direction * MAX_EXTENSION, wrist)
	_joint.position = elbow
	_joint.basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.FORWARD, PI / 2)
	_wrist.position = wrist
	_wrist.basis = _joint.basis
	var hose_offset := Basis(Vector3.UP, _yaw) * Vector3(0.33, 0.06, 0)
	_place_link(_hose, elbow + hose_offset, wrist + hose_offset)
	_hose.scale.y = elbow.distance_to(wrist)
	_head.position = wrist
	_head.basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _head_pitch)
	_tip = wrist + _head.basis * Vector3(0, 0, HEAD_LENGTH)

func _place_link(part: Node3D, a: Vector3, b: Vector3) -> void:
	part.position = (a + b) * 0.5
	var direction := (b - a).normalized()
	var right := Basis(Vector3.UP, _yaw) * Vector3.RIGHT
	part.basis = Basis(right, direction, right.cross(direction).normalized())
