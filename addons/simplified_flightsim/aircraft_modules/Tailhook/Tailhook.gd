# removed @tool to avoid editor load crashes; capture poses manually for now
extends AircraftModuleSpatial
class_name AircraftModule_Tailhook

signal update_interface(values)

@export var hook_root: NodePath # Area3D's CollisionShape3D (for cable detection)
@export var hook_collider: NodePath # Area3D's CollisionShape3D (for cable detection)
@export var hook_body_collider: NodePath # CollisionShape3D attached to aircraft body (for deck collision)

@export var deploy_time: float = 0.6
@export var stowed_local_transform: Transform3D
@export var deployed_local_transform: Transform3D

# Editor helpers
@export var capture_stowed_from_current: bool:
	set(value):
		if value and Engine.is_editor_hint() and hook_root != NodePath():
			if _hook_node == null:
				_hook_node = get_node_or_null(hook_root)
			if _hook_node:
				stowed_local_transform = _hook_node.transform
		set_deferred("capture_stowed_from_current", false)

@export var capture_deployed_from_current: bool:
	set(value):
		if value and Engine.is_editor_hint() and hook_root != NodePath():
			if _hook_node == null:
				_hook_node = get_node_or_null(hook_root)
			if _hook_node:
				deployed_local_transform = _hook_node.transform
		set_deferred("capture_deployed_from_current", false)

@export var preview_stowed: bool:
	set(value):
		if value and Engine.is_editor_hint() and hook_root != NodePath():
			if _hook_node == null:
				_hook_node = get_node_or_null(hook_root)
			if _hook_node:
				_hook_node.transform = stowed_local_transform
		set_deferred("preview_stowed", false)

@export var preview_deployed: bool:
	set(value):
		if value and Engine.is_editor_hint() and hook_root != NodePath():
			if _hook_node == null:
				_hook_node = get_node_or_null(hook_root)
			if _hook_node:
				_hook_node.transform = deployed_local_transform
		set_deferred("preview_deployed", false)

var _hook_node: Node3D
var _collider_node: CollisionShape3D
var _body_collider_node: CollisionShape3D
var is_deployed: bool = false
var is_stowed: bool = true
var is_deploying: bool = false
var is_stowing: bool = false

var _tween: Tween

func _ready():
	ModuleType = "tailhook"
	ProcessPhysics = false
	# Avoid editor-time resolution in _ready to prevent load-order crashes
	if Engine.is_editor_hint():
		return

func setup(aircraft_node):
	super.setup(aircraft_node)
	_resolve_nodes()
	# Ensure initial state matches 'stowed_local_transform'
	if _hook_node:
		_hook_node.transform = stowed_local_transform
	_set_collider_enabled(false)
	is_deployed = false
	is_stowed = true
	is_deploying = false
	is_stowing = false

func _resolve_nodes():
	_hook_node = get_node_or_null(hook_root)
	_collider_node = get_node_or_null(hook_collider)
	_body_collider_node = get_node_or_null(hook_body_collider)

func deploy():
	if is_deployed or is_deploying:
		return
	_start_move(deployed_local_transform, true)

func stow():
	if is_stowed or is_stowing:
		return
	_start_move(stowed_local_transform, false)

func _start_move(target_xform: Transform3D, to_deploy: bool):
	if not _hook_node:
		return
	if _tween and _tween.is_running():
		_tween.kill()
	is_deploying = to_deploy
	is_stowing = not to_deploy
	_tween = create_tween()
	_tween.tween_property(_hook_node, "transform", target_xform, deploy_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func():
		is_deployed = to_deploy
		is_stowed = not to_deploy
		is_deploying = false
		is_stowing = false
		_set_collider_enabled(to_deploy)
		emit_signal("update_interface", {"tailhook_deployed": is_deployed})
	)

func _set_collider_enabled(enabled: bool):
	if _collider_node:
		_collider_node.disabled = not enabled
	if _body_collider_node:
		_body_collider_node.disabled = not enabled
