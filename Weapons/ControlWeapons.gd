extends AircraftModule
class_name ControlWeapons

@export var hardpoints: Array[Hardpoint] = []
@export var debug_print: bool = false
var weapon_types: Array[String] = []  # Available weapon types
var selected_weapon_type: String = ""
var selected_weapon_type_index: int = 0
var is_trigger_held: bool = false

func _ready():
	# We poll every frame instead of using event callbacks
	ReceiveInput = false
	ProcessPhysics = true
	
	# Add to group for easy finding
	add_to_group("ControlWeapons")

func setup(aircraft_node: Node) -> void:
	aircraft = aircraft_node
	# Find all hardpoints automatically
	find_hardpoints()
	# Categorize weapons by type
	categorize_weapons()
	# Default to guns when available so a freshly spawned plane can always fire
	# immediately without requiring missile lock.
	if weapon_types.size() > 0:
		var preferred_index: int = weapon_types.find("Guns")
		if preferred_index == -1:
			preferred_index = weapon_types.find("Autocannon")
		if preferred_index == -1:
			preferred_index = 0
		selected_weapon_type_index = preferred_index
		selected_weapon_type = weapon_types[selected_weapon_type_index]
	else:
		pass

func _effective_type(weapon_instance: Weapon) -> String:
	if not weapon_instance.weapon_category.is_empty():
		return weapon_instance.weapon_category
	return weapon_instance.weapon_name

func find_hardpoints():
	"""Find all hardpoints on the aircraft"""
	hardpoints.clear()
	if aircraft == null:
		aircraft = get_parent()
	if aircraft == null:
		return
	_collect_hardpoints_recursive(aircraft)
	pass


func _collect_hardpoints_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Hardpoint:
			hardpoints.append(child)
		_collect_hardpoints_recursive(child)

func categorize_weapons():
	"""Categorize weapons by type and build weapon type list"""
	weapon_types.clear()
	var weapon_type_set = {}
	
	for hardpoint in hardpoints:
		if not is_instance_valid(hardpoint):
			continue
		if hardpoint.weapon_instance:
			var effective = _effective_type(hardpoint.weapon_instance)
			if not effective in weapon_type_set:
				weapon_type_set[effective] = true
				weapon_types.append(effective)
	
	pass

func _input(event):
	if Input.is_action_just_pressed("fire_weapon"):
		is_trigger_held = true
		fire_selected_weapon_type()
	
	if Input.is_action_just_released("fire_weapon"):
		is_trigger_held = false

func process_physic_frame(delta):
	# Continuous firing only for automatic weapons of selected type
	if is_trigger_held:
		fire_automatic_weapons_of_type(selected_weapon_type)

func fire_selected_weapon_type():
	"""Fire all weapons of the currently selected type"""
	if selected_weapon_type == "":
		return
	
	var weapons_fired = 0
	for hardpoint in hardpoints:
		if not is_instance_valid(hardpoint):
			continue
		if hardpoint.weapon_instance and _effective_type(hardpoint.weapon_instance) == selected_weapon_type:
			if hardpoint.fire():
				weapons_fired += 1
	
	if debug_print and weapons_fired > 0:
		print("Fired ", weapons_fired, " ", selected_weapon_type, " weapons")

func fire_automatic_weapons_of_type(weapon_type: String):
	"""Fire all automatic weapons of the specified type continuously"""
	for hardpoint in hardpoints:
		if not is_instance_valid(hardpoint):
			continue
		if (hardpoint.weapon_instance and
			_effective_type(hardpoint.weapon_instance) == weapon_type and
			hardpoint.weapon_instance.automatic_fire):
			hardpoint.fire()

func cycle_weapon_type():
	"""Cycle to the next weapon type"""
	# Refresh list each time — weapons may have been swapped after setup() ran
	var previous_type = selected_weapon_type
	categorize_weapons()
	
	if weapon_types.size() <= 1:
		print("Only one weapon type available - cannot cycle")
		return
	
	# Keep the index in sync with the (possibly refreshed) type list
	var prev_idx = weapon_types.find(previous_type)
	if prev_idx == -1:
		prev_idx = 0
	
	selected_weapon_type_index = (prev_idx + 1) % weapon_types.size()
	selected_weapon_type = weapon_types[selected_weapon_type_index]
	
	print("Switched to weapon type: ", selected_weapon_type)
	
	# Count weapons of this type
	var count = 0
	for hardpoint in hardpoints:
		if not is_instance_valid(hardpoint):
			continue
		if hardpoint.weapon_instance and _effective_type(hardpoint.weapon_instance) == selected_weapon_type:
			count += 1
	
	print("Available ", selected_weapon_type, " weapons: ", count)

func get_weapon_status() -> Dictionary:
	"""Get current weapon status for UI display"""
	var status = {
		"selected_type": selected_weapon_type,
		"available_types": weapon_types,
		"weapon_count": 0,
		"total_ammo": 0
	}
	
	# Count weapons of selected type and total ammo
	for hardpoint in hardpoints:
		if not is_instance_valid(hardpoint):
			continue
		if hardpoint.weapon_instance and _effective_type(hardpoint.weapon_instance) == selected_weapon_type:
			status.weapon_count += 1
			# Add ammo count if weapon has ammo property
			if hardpoint.weapon_instance.has_method("get_ammo_count"):
				status.total_ammo += hardpoint.weapon_instance.get_ammo_count()
			else:
				# Try to access ammo_count property safely
				var ammo_count = hardpoint.weapon_instance.get("ammo_count")
				if ammo_count != null:
					status.total_ammo += ammo_count
	
	return status
