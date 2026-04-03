extends Node3D
class_name EnemyBase

const FactionPaint = preload("res://FactionPaint.gd")

@export var runway_scene: PackedScene = preload("res://Buildings/building_enemy_runway.tscn")
@export var ground_scene: PackedScene = preload("res://Buildings/building_enemy_base_ground.tscn")
@export var structure_scene: PackedScene = preload("res://Buildings/building_barracks.tscn")
@export_range(1, 12) var min_structure_count: int = 5
@export_range(1, 12) var max_structure_count: int = 6
@export var structure_ground_clearance_m: float = 0.0
@export var ground_surface_height_offset_m: float = 1.8
@export var flight_spawn_altitude_offset_m: float = 80.0
@export_range(1, 32) var total_aircraft_inventory: int = 12
@export_range(1, 64) var total_vehicle_inventory: int = 24
@export_range(1, 16) var max_active_aircraft: int = 6
@export_range(1, 32) var max_active_vehicles: int = 12
@export_range(1, 8) var patrol_flight_size: int = 2
@export_range(1, 12) var patrol_platoon_size: int = 4
@export_range(1, 8) var response_flight_size: int = 2
@export_range(1, 12) var response_platoon_size: int = 4

const BUILDING_SLOTS := [
	{"pos": Vector3(-120, 0, -220), "yaw_deg": 0.0},
	{"pos": Vector3(120, 0, -220), "yaw_deg": 0.0},
	{"pos": Vector3(-120, 0, -100), "yaw_deg": 0.0},
	{"pos": Vector3(120, 0, -100), "yaw_deg": 0.0},
	{"pos": Vector3(-120, 0, 20), "yaw_deg": 0.0},
	{"pos": Vector3(120, 0, 20), "yaw_deg": 0.0},
	{"pos": Vector3(-120, 0, 140), "yaw_deg": 0.0},
	{"pos": Vector3(120, 0, 140), "yaw_deg": 0.0},
	{"pos": Vector3(-120, 0, 260), "yaw_deg": 0.0},
	{"pos": Vector3(120, 0, 260), "yaw_deg": 0.0},
]

const FLIGHT_SPAWN_SLOTS := [
	Vector3(0, 0, -180),
	Vector3(0, 0, -100),
	Vector3(0, 0, -20),
]

const PLATOON_SPAWN_LOCAL := Vector3(170, 0, 240)

var terrain: Node3D = null
var base_ground: Node3D = null
var runway: Node3D = null
var spawned_buildings: Array[Node3D] = []
var spawned_flights: Array[Node3D] = []
var spawned_platoons: Array[Node3D] = []
var visual_identity: Dictionary = {}


func _ready() -> void:
	add_to_group("enemy_bases")
	add_to_group("enemies")
	add_to_group("team_2")
	_ensure_ground()
	_ensure_runway()
	_apply_visual_identity()
	_register_with_enemy_base_manager()

func _exit_tree() -> void:
	_unregister_from_enemy_base_manager()


func configure_layout(terrain_node: Node3D, structure_count: int = -1) -> void:
	terrain = terrain_node
	_rebuild_layout(structure_count)

func configure_visual_identity(identity: Dictionary) -> void:
	visual_identity = identity.duplicate(true)
	_apply_visual_identity()

func get_visual_identity() -> Dictionary:
	return visual_identity.duplicate(true)

func get_resource_limits() -> Dictionary:
	return {
		"total_aircraft_inventory": maxi(total_aircraft_inventory, 1),
		"total_vehicle_inventory": maxi(total_vehicle_inventory, 1),
		"max_active_aircraft": clampi(max_active_aircraft, 1, maxi(total_aircraft_inventory, 1)),
		"max_active_vehicles": clampi(max_active_vehicles, 1, maxi(total_vehicle_inventory, 1)),
		"patrol_flight_size": clampi(patrol_flight_size, 1, maxi(max_active_aircraft, 1)),
		"patrol_platoon_size": clampi(patrol_platoon_size, 1, maxi(max_active_vehicles, 1)),
		"response_flight_size": clampi(response_flight_size, 1, maxi(max_active_aircraft, 1)),
		"response_platoon_size": clampi(response_platoon_size, 1, maxi(max_active_vehicles, 1)),
	}

func get_structure_count() -> int:
	_prune_dead_nodes(spawned_buildings)
	return spawned_buildings.size()

func get_flight_count() -> int:
	_prune_dead_nodes(spawned_flights)
	return spawned_flights.size()

func get_platoon_count() -> int:
	_prune_dead_nodes(spawned_platoons)
	return spawned_platoons.size()

func get_status_summary() -> Dictionary:
	var resource_limits: Dictionary = get_resource_limits()
	var status := {
		"kind": "enemy_base",
		"name": name,
		"position": global_position,
		"flight_count": get_flight_count(),
		"platoon_count": get_platoon_count(),
		"structure_count": get_structure_count(),
		"has_runway": is_instance_valid(runway),
		"runway_position": runway.global_position if is_instance_valid(runway) else global_position,
		"total_aircraft_inventory": int(resource_limits.get("total_aircraft_inventory", total_aircraft_inventory)),
		"total_vehicle_inventory": int(resource_limits.get("total_vehicle_inventory", total_vehicle_inventory)),
		"max_active_aircraft": int(resource_limits.get("max_active_aircraft", max_active_aircraft)),
		"max_active_vehicles": int(resource_limits.get("max_active_vehicles", max_active_vehicles)),
		"patrol_flight_size": int(resource_limits.get("patrol_flight_size", patrol_flight_size)),
		"patrol_platoon_size": int(resource_limits.get("patrol_platoon_size", patrol_platoon_size)),
		"response_flight_size": int(resource_limits.get("response_flight_size", response_flight_size)),
		"response_platoon_size": int(resource_limits.get("response_platoon_size", response_platoon_size)),
	}
	if not visual_identity.is_empty():
		status["primary_color"] = visual_identity.get("primary_color", Color(0.0, 0.0, 0.0, 1.0))
		status["secondary_color"] = visual_identity.get("secondary_color", Color(0.0, 0.0, 0.0, 1.0))
		status["insignia_index"] = int(visual_identity.get("insignia_index", -1))
	return status


func get_runway() -> Node3D:
	_ensure_runway()
	return runway


func get_launch_direction() -> Vector3:
	var forward := global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


func get_flight_spawn_transform(slot_index: int = 0) -> Transform3D:
	var slot: Vector3 = FLIGHT_SPAWN_SLOTS[clampi(slot_index, 0, FLIGHT_SPAWN_SLOTS.size() - 1)]
	var world_origin := to_global(slot)
	world_origin.y = _get_surface_world_y() + flight_spawn_altitude_offset_m
	return Transform3D(global_transform.basis, world_origin)


func get_platoon_spawn_position() -> Vector3:
	var world_origin := to_global(PLATOON_SPAWN_LOCAL)
	world_origin.y = _get_surface_world_y()
	return world_origin


func spawn_flight(spawner: Node, aircraft_count: int = 2) -> void:
	if spawner != null and spawner.has_method("spawn_enemy_flight_from_base"):
		spawner.call("spawn_enemy_flight_from_base", self, aircraft_count)


func spawn_platoon(spawner: Node, vehicle_count: int = 4) -> void:
	if spawner != null and spawner.has_method("spawn_enemy_platoon_from_base"):
		spawner.call("spawn_enemy_platoon_from_base", self, vehicle_count)


func register_flight(flight_node: Node3D) -> void:
	if flight_node != null and is_instance_valid(flight_node):
		spawned_flights.append(flight_node)
		_prune_dead_nodes(spawned_flights)
		_apply_visual_identity_to_flight(flight_node)


func register_platoon(platoon_node: Node3D) -> void:
	if platoon_node != null and is_instance_valid(platoon_node):
		spawned_platoons.append(platoon_node)
		_prune_dead_nodes(spawned_platoons)
		_apply_visual_identity_to_platoon(platoon_node)


func _rebuild_layout(structure_count: int = -1) -> void:
	_clear_layout()
	_ensure_ground()
	_ensure_runway()

	var count := structure_count
	if count < 0:
		count = randi_range(min_structure_count, max_structure_count)
	count = clampi(count, min_structure_count, min(max_structure_count, BUILDING_SLOTS.size()))
	_spawn_structures(count)
	_apply_visual_identity()


func _clear_layout() -> void:
	for structure in spawned_buildings:
		if is_instance_valid(structure):
			structure.queue_free()
	spawned_buildings.clear()


func _ensure_ground() -> void:
	if is_instance_valid(base_ground):
		return
	if ground_scene == null:
		return
	base_ground = ground_scene.instantiate() as Node3D
	if base_ground == null:
		return
	base_ground.name = "EnemyBaseGround"
	add_child(base_ground)
	base_ground.transform = Transform3D.IDENTITY
	_apply_visual_identity()


func _ensure_runway() -> void:
	if is_instance_valid(runway):
		return
	if runway_scene == null:
		return
	runway = runway_scene.instantiate() as Node3D
	if runway == null:
		return
	runway.name = "EnemyRunway"
	add_child(runway)
	runway.transform = Transform3D.IDENTITY
	_apply_visual_identity()


func _spawn_structures(count: int) -> void:
	if structure_scene == null or count <= 0:
		return

	var slot_indices: Array[int] = []
	for idx in range(BUILDING_SLOTS.size()):
		slot_indices.append(idx)
	slot_indices.shuffle()

	for slot_idx in slot_indices.slice(0, count):
		var slot: Dictionary = BUILDING_SLOTS[slot_idx]
		var structure := structure_scene.instantiate() as Node3D
		if structure == null:
			continue
		add_child(structure)

		var local_pos: Vector3 = slot.get("pos", Vector3.ZERO)
		var world_pos := to_global(local_pos)
		world_pos.y = _get_surface_world_y() + structure_ground_clearance_m
		var local_yaw_deg: float = float(slot.get("yaw_deg", 0.0))
		var world_yaw_rad := global_rotation.y + deg_to_rad(local_yaw_deg)
		structure.global_transform = Transform3D(Basis(Vector3.UP, world_yaw_rad), world_pos)
		spawned_buildings.append(structure)
		_apply_visual_identity_to_building(structure)


func _get_surface_world_y() -> float:
	return global_position.y + ground_surface_height_offset_m


func _sample_ground_y(world_pos: Vector3) -> float:
	if terrain == null or not is_instance_valid(terrain) or not terrain.has_method("get_height"):
		return global_position.y
	var sampled: Variant = terrain.call("get_height", Vector3(world_pos.x, terrain.global_position.y, world_pos.z))
	if typeof(sampled) != TYPE_FLOAT:
		return global_position.y
	var h := float(sampled)
	if is_nan(h):
		return global_position.y
	return h


func _prune_dead_nodes(nodes: Array[Node3D]) -> void:
	for idx in range(nodes.size() - 1, -1, -1):
		if not is_instance_valid(nodes[idx]):
			nodes.remove_at(idx)

func _apply_visual_identity() -> void:
	if visual_identity.is_empty():
		return
	if is_instance_valid(base_ground):
		FactionPaint.apply_base_ground(base_ground, visual_identity)
	if is_instance_valid(runway):
		FactionPaint.apply_runway(runway, visual_identity)
	for structure in spawned_buildings:
		_apply_visual_identity_to_building(structure)
	for flight in spawned_flights:
		_apply_visual_identity_to_flight(flight)
	for platoon in spawned_platoons:
		_apply_visual_identity_to_platoon(platoon)

func _apply_visual_identity_to_building(building: Node3D) -> void:
	if visual_identity.is_empty() or building == null or not is_instance_valid(building):
		return
	FactionPaint.apply_building(building, visual_identity)

func _apply_visual_identity_to_flight(flight_node: Node3D) -> void:
	if visual_identity.is_empty() or flight_node == null or not is_instance_valid(flight_node):
		return
	FactionPaint.apply_aircraft(flight_node, visual_identity)

func _apply_visual_identity_to_platoon(platoon_node: Node3D) -> void:
	if visual_identity.is_empty() or platoon_node == null or not is_instance_valid(platoon_node):
		return
	if not platoon_node.has_method("get_members"):
		return
	var members_variant: Variant = platoon_node.call("get_members")
	if members_variant is Array:
		for member in members_variant:
			if member is Node3D and is_instance_valid(member):
				FactionPaint.apply_vehicle(member as Node3D, visual_identity)

func _register_with_enemy_base_manager() -> void:
	var manager := get_tree().root.get_node_or_null("EnemyBaseManager")
	if manager != null and manager.has_method("register_base"):
		manager.call("register_base", self)

func _unregister_from_enemy_base_manager() -> void:
	var manager := get_tree().root.get_node_or_null("EnemyBaseManager")
	if manager != null and manager.has_method("unregister_base"):
		manager.call("unregister_base", self)
