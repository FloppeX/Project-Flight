extends Node3D
class_name VehicleRamp

## Folding vehicle deployment ramp at the rear of the Land Carrier.
## Uses the three ramp meshes already present in the carrier body GLB.
## Deploy sequence: slide out → all three hinges open simultaneously.
## Press Z to toggle deploy/stow.

# --- Deploy mechanics ---
@export var slide_distance_m: float = 1.2
@export var ground_clearance_m: float = 0.3

# --- Animation timing (seconds) ---
@export var slide_duration_s: float = 1.5
@export var hinge_duration_s: float = 3.5

enum State { STOWED, DEPLOYING, DEPLOYED, STOWING }
var state: State = State.STOWED

# Measured from GLB meshes at runtime
var _panel_length: float = 10.0
var _panel_width: float = 28.0
var _panel_thickness: float = 0.4

# Node references (built in _ready)
var _slider: Node3D
var _inner_pivot: Node3D
var _middle_pivot: Node3D
var _outer_pivot: Node3D
var _tween: Tween

# Stowed rotations — zig-zag fold:
# Inner points upward, middle folds opposite direction (down), outer folds same as inner (up)
const _INNER_STOWED_X: float = PI / 2.0    # panel extends upward
const _MIDDLE_STOWED_X: float = -PI         # folded opposite direction (hangs down)
const _OUTER_STOWED_X: float = PI           # folded same direction as inner (extends up)

func _ready() -> void:
	_find_meshes_and_build()

func _unhandled_input(event: InputEvent) -> void:
	return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z:
			toggle()

func _physics_process(_delta: float) -> void:
	if state == State.DEPLOYED:
		var target_angle := _compute_deploy_angle()
		_inner_pivot.rotation.x = lerp(_inner_pivot.rotation.x, -target_angle, 0.02)

# ── Construction from GLB meshes ───────────────────────────────────────────

func _find_meshes_and_build() -> void:
	var carrier_model: Node3D = get_parent().find_child("CarrierModel")
	if not carrier_model:
		push_warning("VehicleRamp: CarrierModel not found")
		return

	var inner_src := carrier_model.find_child("Ramp inner") as MeshInstance3D
	var middle_src := carrier_model.find_child("Ramp middle") as MeshInstance3D
	var outer_src := carrier_model.find_child("Ramp outer") as MeshInstance3D
	if not inner_src or not middle_src or not outer_src:
		push_warning("VehicleRamp: Ramp mesh(es) not found in CarrierModel")
		return

	# Measure panel dimensions from the GLB mesh + scale
	var aabb: AABB = inner_src.mesh.get_aabb()
	var src_scale: Vector3 = inner_src.scale
	_panel_width = src_scale.x * aabb.size.x
	_panel_length = src_scale.y * aabb.size.y
	_panel_thickness = src_scale.z * aabb.size.z

	# Find hinge position in carrier local space
	# The model has 180° Y rotation, so model +Z maps to carrier -Z
	var model_xform: Transform3D = carrier_model.transform
	var inner_carrier_pos: Vector3 = model_xform * inner_src.position
	# Hinge is at the bottom edge of the stowed (vertical) inner panel
	var hinge_pos := Vector3(0.0, inner_carrier_pos.y - _panel_length / 2.0, inner_carrier_pos.z)

	# Position this node at the hinge point
	position = hinge_pos

	# Hide original GLB meshes — we'll use copies in the pivot hierarchy
	inner_src.visible = false
	middle_src.visible = false
	outer_src.visible = false

	# Build the animated pivot hierarchy
	_build_hierarchy(inner_src, middle_src, outer_src)
	_set_stowed()

	# Add a bay floor collider so vehicles have a surface to stand on
	_build_bay_floor(hinge_pos)

func _build_hierarchy(inner_src: MeshInstance3D, middle_src: MeshInstance3D, outer_src: MeshInstance3D) -> void:
	# Slider — handles the initial slide-out along -Z
	_slider = Node3D.new()
	_slider.name = "RampSlider"
	add_child(_slider)

	# Inner pivot — hinge at carrier floor, rotates around X
	_inner_pivot = Node3D.new()
	_inner_pivot.name = "InnerPivot"
	_slider.add_child(_inner_pivot)
	_inner_pivot.add_child(_create_panel("InnerRamp", inner_src))

	# Middle pivot — at the far end of the inner panel
	_middle_pivot = Node3D.new()
	_middle_pivot.name = "MiddlePivot"
	_middle_pivot.position = Vector3(0, 0, -_panel_length)
	_inner_pivot.add_child(_middle_pivot)
	_middle_pivot.add_child(_create_panel("MiddleRamp", middle_src))

	# Outer pivot — at the far end of the middle panel
	_outer_pivot = Node3D.new()
	_outer_pivot.name = "OuterPivot"
	_outer_pivot.position = Vector3(0, 0, -_panel_length)
	_middle_pivot.add_child(_outer_pivot)
	_outer_pivot.add_child(_create_panel("OuterRamp", outer_src))

func _create_panel(panel_name: String, src: MeshInstance3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = panel_name

	# Visual — use the mesh resource from the GLB
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	mesh_inst.mesh = src.mesh
	# Reorient: GLB mesh length is along Y, we need it along -Z for the pivot system
	# Rotation -PI/2 around X maps: mesh +Y → frame -Z, mesh +Z → frame +Y
	var rot_basis := Basis(Vector3.RIGHT, -PI / 2.0)
	mesh_inst.transform = Transform3D(
		rot_basis * Basis.from_scale(src.scale),
		Vector3(0, 0, -_panel_length / 2.0)
	)
	# Copy material if present
	var mat: Material = src.get_surface_override_material(0)
	if not mat:
		mat = src.mesh.surface_get_material(0)
	if mat:
		mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	# Collision
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(_panel_width, _panel_thickness, _panel_length)
	col.shape = shape
	col.position = Vector3(0, 0, -_panel_length / 2.0)
	body.add_child(col)

	return body

# ── Stowed / Deploy angle ─────────────────────────────────────────────────

func _set_stowed() -> void:
	_slider.position = Vector3.ZERO
	_inner_pivot.rotation.x = _INNER_STOWED_X
	_middle_pivot.rotation.x = _MIDDLE_STOWED_X
	_outer_pivot.rotation.x = _OUTER_STOWED_X

func _compute_deploy_angle() -> float:
	## Returns the positive slope angle (radians) so the ramp tip reaches terrain.
	var total_len := _panel_length * 3.0
	var pivot_world: Vector3 = _inner_pivot.global_position
	var backward: Vector3 = -global_transform.basis.z.normalized()

	# First estimate: horizontal reach ≈ total_len
	var tip_est: Vector3 = pivot_world + backward * total_len
	var ground_y: float = TerrainNavGrid.sample_height(tip_est.x, tip_est.z)
	var h: float = pivot_world.y - ground_y - ground_clearance_m

	# Refine once with corrected horizontal reach
	var angle_est := asin(clampf(h / total_len, 0.0, 0.85))
	var horiz := total_len * cos(angle_est)
	tip_est = pivot_world + backward * horiz
	ground_y = TerrainNavGrid.sample_height(tip_est.x, tip_est.z)
	h = pivot_world.y - ground_y - ground_clearance_m

	return asin(clampf(h / total_len, 0.0, 0.85))

# ── Bay floor collider ────────────────────────────────────────────────────

func _build_bay_floor(hinge_pos: Vector3) -> void:
	## Creates a StaticBody3D floor inside the carrier for vehicles to stand on.
	## Extends from the hinge forward (+Z) into the carrier interior.
	var floor_body := StaticBody3D.new()
	floor_body.name = "BayFloor"

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var floor_overlap: float = 3.0   # extend past hinge toward ramp to close the gap
	var floor_length: float = 20.0 + floor_overlap
	shape.size = Vector3(_panel_width, 0.5, floor_length)
	col.shape = shape
	# Position: centered on bay area, shifted back by overlap so it covers the hinge seam
	col.position = Vector3(0.0, -0.25, floor_length / 2.0 - floor_overlap)
	floor_body.add_child(col)

	# Bay floor is positioned at the hinge point (same as this node)
	# but it's a child of the carrier, not the ramp pivots
	get_parent().add_child(floor_body)
	floor_body.position = hinge_pos

# ── Helpers for VehicleBayManager ─────────────────────────────────────────

## Bay spawn point in carrier-local space — inside the carrier, forward of the hinge.
func get_bay_spawn_local() -> Vector3:
	# position is the hinge point in carrier-local space.
	# Spawn 12 m forward (+Z) of the hinge and at hinge Y (deck floor level).
	return Vector3(0.0, position.y, position.z + 12.0)

## The hinge point in carrier-local space (top of deployed ramp).
func get_hinge_local() -> Vector3:
	return position

## World position of the ramp tip (bottom end) when deployed.
func get_ramp_tip_global() -> Vector3:
	if not _outer_pivot:
		return global_position
	# Tip is at the far end of the outer panel
	var tip_local := Vector3(0.0, 0.0, -_panel_length)
	return _outer_pivot.to_global(tip_local)

## Total ramp length (all three panels).
func get_total_length() -> float:
	return _panel_length * 3.0

## Panel width (for spawn offset checks).
func get_panel_width() -> float:
	return _panel_width

func is_deployed() -> bool:
	return state == State.DEPLOYED

func is_stowed() -> bool:
	return state == State.STOWED

# ── Toggle / Deploy / Stow ────────────────────────────────────────────────

func toggle() -> void:
	match state:
		State.STOWED:
			deploy()
		State.DEPLOYED:
			stow()

func deploy() -> void:
	if state != State.STOWED:
		return
	state = State.DEPLOYING

	if _tween and _tween.is_valid():
		_tween.kill()

	var target_angle := _compute_deploy_angle()

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)

	# Step 1: slide assembly out (sequential)
	_tween.tween_property(_slider, "position:z", -slide_distance_m, slide_duration_s)\
		.set_ease(Tween.EASE_IN_OUT)

	# Step 2: all three hinges open simultaneously
	_tween.set_parallel(true)
	_tween.tween_property(_inner_pivot, "rotation:x", -target_angle, hinge_duration_s)\
		.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_middle_pivot, "rotation:x", 0.0, hinge_duration_s)\
		.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_outer_pivot, "rotation:x", 0.0, hinge_duration_s)\
		.set_ease(Tween.EASE_IN_OUT)
	_tween.set_parallel(false)

	_tween.tween_callback(func(): state = State.DEPLOYED)

func stow() -> void:
	if state != State.DEPLOYED:
		return
	state = State.STOWING

	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)

	# Step 1: all three hinges close simultaneously
	_tween.set_parallel(true)
	_tween.tween_property(_outer_pivot, "rotation:x", _OUTER_STOWED_X, hinge_duration_s)\
		.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_middle_pivot, "rotation:x", _MIDDLE_STOWED_X, hinge_duration_s)\
		.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_inner_pivot, "rotation:x", _INNER_STOWED_X, hinge_duration_s)\
		.set_ease(Tween.EASE_IN_OUT)
	_tween.set_parallel(false)

	# Step 2: slide back in (sequential, after hinges finish)
	_tween.tween_property(_slider, "position:z", 0.0, slide_duration_s)\
		.set_ease(Tween.EASE_IN_OUT)

	_tween.tween_callback(func(): state = State.STOWED)
