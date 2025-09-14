extends Node3D

@export var hook_area: NodePath
@export var hook_body_collision: NodePath
@export var hook_mesh: NodePath

# Identify this module for external systems (e.g., FlightDeckManager)
var ModuleType: String = "tailhook"

# Simple spring/damper to let the hook flex on deck contact
@export var spring_strength: float = 2500.0       # N/m (small compared to landing gear)
@export var spring_damping: float = 1200.0        # N*s/m
@export var wheel_rest_height: float = 0.2        # m from hook tip to deck at rest
@export var max_compression: float = 0.15         # m
@export var ray_length_margin: float = 0.4        # m ray length (rest + margin)

var _area: Area3D
var _body_col: CollisionShape3D
var _mesh_node: Node3D
var _aircraft: RigidBody3D
var _is_deployed: bool = false

func _ready():
	add_to_group("tailhook")
	_area = get_node_or_null(hook_area)
	_body_col = get_node_or_null(hook_body_collision) as CollisionShape3D
	_mesh_node = get_node_or_null(hook_mesh) as Node3D
	# Ensure the hook Area is in the expected group for the cable to detect
	if _area and not _area.is_in_group("tailhook"):
		_area.add_to_group("tailhook")
	_aircraft = _find_aircraft()
	# Default to stowed on start
	stow()

func deploy():
	_is_deployed = true
	if _area:
		_area.monitoring = true
		var cs := _area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs:
			cs.disabled = false
	if _body_col:
		_body_col.disabled = false
	if _mesh_node and _mesh_node.has_method("set_visible"):
		_mesh_node.visible = true

func stow():
	_is_deployed = false
	if _area:
		_area.monitoring = false
		var cs := _area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs:
			cs.disabled = true
	if _body_col:
		_body_col.disabled = true
	if _mesh_node and _mesh_node.has_method("set_visible"):
		_mesh_node.visible = false

func _physics_process(delta: float) -> void:
	if not _is_deployed:
		return
	if not _aircraft or not is_instance_valid(_aircraft):
		_aircraft = _find_aircraft()
		if not _aircraft:
			return
	# Raycast from hook tip toward down to detect deck/contact
	var tip_pos = global_position
	var space_state = get_world_3d().direct_space_state
	var ray_to = tip_pos + Vector3.DOWN * (wheel_rest_height + ray_length_margin)
	var query = PhysicsRayQueryParameters3D.create(tip_pos, ray_to)
	query.exclude = []
	if _aircraft:
		query.exclude.append(_aircraft)
	# Check default and terrain layers (1 and 10)
	query.collision_mask = (1 << 0) | (1 << 9)
	var hit = space_state.intersect_ray(query)
	if hit:
		var dist = tip_pos.distance_to(hit.position)
		var compression = wheel_rest_height - dist
		compression = clamp(compression, 0.0, max_compression)
		if compression > 0.001:
			# Apply spring force along hit normal
			var n: Vector3 = hit.normal.normalized()
			# Damping based on aircraft velocity component toward the surface
			var v = _aircraft.linear_velocity
			var v_toward = -v.dot(n)  # positive when moving into surface
			var spring_force = spring_strength * compression
			var damping_force = spring_damping * v_toward
			var total = spring_force + damping_force
			if total < 0.0:
				total = 0.0
			var force_vec = n * total
			var lever = tip_pos - _aircraft.global_position
			_aircraft.apply_force(force_vec, lever)

func _find_aircraft() -> RigidBody3D:
	var n: Node = self
	while n:
		if n is RigidBody3D:
			return n
		n = n.get_parent()
	return null
