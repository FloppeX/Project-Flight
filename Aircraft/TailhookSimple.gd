extends Node3D

@export var hook_area: NodePath
@export var hook_body_collision: NodePath
@export var hook_mesh: NodePath

var _area: Area3D
var _body_col: CollisionShape3D
var _mesh_node: Node3D

func _ready():
	add_to_group("tailhook")
	_area = get_node_or_null(hook_area)
	_body_col = get_node_or_null(hook_body_collision)
	_mesh_node = get_node_or_null(hook_mesh)
	# Default to stowed on start
	stow()

func deploy():
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
	if _area:
		_area.monitoring = false
		var cs := _area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs:
			cs.disabled = true
	if _body_col:
		_body_col.disabled = true
	if _mesh_node and _mesh_node.has_method("set_visible"):
		_mesh_node.visible = false
