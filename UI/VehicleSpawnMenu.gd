extends CanvasLayer
## Modal development picker opened with S during gameplay. It reuses the
## Technical Index catalog and supplements it with any numbered aircraft scenes
## that have not been catalogued yet.

signal vehicle_spawned(vehicle: Node3D, entry: Dictionary)
signal enemy_force_spawned(force: Node, entry: Dictionary, member_count: int)
signal spawn_failed(message: String)

const Catalog: Script = preload("res://UI/TechnicalIndexCatalog.gd")
const HEADLINE_FONT: FontFile = preload("res://UI/Fonts/ArchivoNarrow-Variable.ttf")
const DATA_FONT: FontFile = preload("res://UI/Fonts/JetBrainsMono-Variable.ttf")

const CATEGORY_ORDER: Array[String] = ["AIRPLANES", "HELICOPTERS", "GROUND VEHICLES", "ENEMY FORCES"]
const TEXT_COLOR := Color("e5e2e1")
const STATUS_COLOR := Color("c4c7c7")
const BORDER_COLOR := Color("434747")
const CYAN_COLOR := Color("76c7c7")
const AMBER_COLOR := Color("ffb000")
const DIM_COLOR := Color("7d8282")
const PANEL_BG := Color("141313")
const ROW_BG := Color("1c1b1b")
const MODAL_BACKDROP := Color(0.035, 0.035, 0.035, 0.90)
const TOAST_DURATION_S := 2.5

@export var aircraft_spawn_distance_m: float = 260.0
@export var aircraft_spawn_agl_m: float = 220.0
@export var aircraft_spawn_height_above_view_m: float = 60.0
@export var airplane_spawn_speed_mps: float = 95.0
@export var helicopter_spawn_speed_mps: float = 22.0
@export var ground_vehicle_spawn_distance_m: float = 75.0

var _modal_root: Control
var _panel: Panel
var _title: Label
var _subtitle: Label
var _description: Label
var _columns: HBoxContainer
var _footer: Label
var _toast_panel: Panel
var _toast_label: Label
var _toast_hide_at_s: float = 0.0
var _buttons: Array[Button] = []
var _is_open: bool = false
var _tree_was_paused: bool = false
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _spawn_serial: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 220
	_build_ui()
	set_process(true)
	set_process_input(true)


func _exit_tree() -> void:
	if _is_open and get_tree() != null:
		get_tree().paused = _tree_was_paused
		Input.mouse_mode = _previous_mouse_mode


func _process(_delta: float) -> void:
	if _toast_panel != null and _toast_panel.visible \
			and Time.get_ticks_msec() / 1000.0 >= _toast_hide_at_s:
		_toast_panel.visible = false


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if _is_spawn_key_event(event) or event.is_action_pressed("ui_cancel", false):
		set_open(false)
		get_viewport().set_input_as_handled()


func set_open(value: bool) -> void:
	if _is_open == value:
		return
	_is_open = value
	_modal_root.visible = value
	if value:
		_tree_was_paused = get_tree().paused
		_previous_mouse_mode = int(Input.mouse_mode)
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if not _buttons.is_empty():
			_buttons[0].call_deferred("grab_focus")
		return

	get_viewport().gui_release_focus()
	get_tree().paused = _tree_was_paused
	Input.mouse_mode = _previous_mouse_mode


func is_open() -> bool:
	return _is_open


func get_spawn_entries() -> Array[Dictionary]:
	return _build_spawn_catalog()


func get_spawn_button_count() -> int:
	return _buttons.size()


func spawn_entry(entry: Dictionary) -> Node3D:
	if not str(entry.get("spawn_kind", "")).is_empty():
		_report_failure("FORMATION PRESETS MUST BE DEPLOYED AS A GROUP")
		return null
	var scene_path := str(entry.get("scene", ""))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_report_failure("SCENE UNAVAILABLE: %s" % scene_path)
		return null
	var vehicle := packed.instantiate() as Node3D
	if vehicle == null:
		_report_failure("SCENE IS NOT A 3D VEHICLE: %s" % scene_path)
		return null

	_spawn_serial += 1
	vehicle.name = "Spawned_%s_%02d" % [
		scene_path.get_file().get_basename(),
		_spawn_serial,
	]
	vehicle.set_meta("spawned_from_vehicle_menu", true)
	vehicle.set_meta("source_scene_path", scene_path)
	var world_root := _get_world_root()
	if world_root == null:
		vehicle.free()
		_report_failure("NO ACTIVE WORLD FOR VEHICLE SPAWN")
		return null

	var category := str(entry.get("category", ""))
	var is_aircraft := category == "AIRPLANES" or category == "HELICOPTERS"
	if is_aircraft and "team" in vehicle:
		vehicle.set("team", 1)
	world_root.add_child(vehicle)
	if is_aircraft:
		_place_aircraft(vehicle, category == "HELICOPTERS")
		_finalize_aircraft.call_deferred(vehicle, category == "HELICOPTERS")
	else:
		_place_ground_vehicle(vehicle)

	var display_name := str(entry.get("name", vehicle.name))
	_show_toast("SPAWNED  //  %s" % display_name)
	print("[VehicleSpawnMenu] spawned %s scene=%s position=%s" % [
		display_name,
		scene_path,
		str(vehicle.global_position.snapped(Vector3.ONE * 0.1)),
	])
	vehicle_spawned.emit(vehicle, entry.duplicate(true))
	return vehicle


func _build_ui() -> void:
	_modal_root = Control.new()
	_modal_root.name = "VehicleSpawnModal"
	_modal_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = MODAL_BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_root.add_child(backdrop)

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _make_style(PANEL_BG, BORDER_COLOR, 2, 4))
	_modal_root.add_child(_panel)

	_title = _make_label("VEHICLE SPAWN", 28, TEXT_COLOR, HEADLINE_FONT)
	_panel.add_child(_title)
	_subtitle = _make_label(
		"SELECT A UNIT OR HOSTILE FORMATION // AIRCRAFT SPAWN AIRBORNE",
		12,
		CYAN_COLOR,
		DATA_FONT
	)
	_panel.add_child(_subtitle)
	_description = _make_label(
		"Single aircraft spawn friendly. Enemy presets deploy complete hostile formations.",
		13,
		STATUS_COLOR,
		DATA_FONT
	)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_description)

	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 14)
	_panel.add_child(_columns)
	_populate_columns()

	_footer = _make_label(
		"UP / DOWN: SELECT    ENTER: SPAWN    S / ESC: CLOSE",
		12,
		DIM_COLOR,
		DATA_FONT,
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	_panel.add_child(_footer)

	_toast_panel = Panel.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_theme_stylebox_override("panel", _make_style(PANEL_BG, AMBER_COLOR, 2, 3))
	add_child(_toast_panel)
	_toast_label = _make_label("", 13, AMBER_COLOR, DATA_FONT, HORIZONTAL_ALIGNMENT_CENTER)
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_panel.add_child(_toast_label)
	_toast_panel.visible = false

	_modal_root.resized.connect(_layout_ui)
	_layout_ui()
	_modal_root.visible = false


func _populate_columns() -> void:
	var entries := _build_spawn_catalog()
	for category in CATEGORY_ORDER:
		var column_panel := PanelContainer.new()
		column_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column_panel.add_theme_stylebox_override("panel", _make_style(ROW_BG, BORDER_COLOR, 1, 2))
		_columns.add_child(column_panel)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_top", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_bottom", 10)
		column_panel.add_child(margin)

		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 5)
		margin.add_child(list)
		var heading := _make_label(category, 17, AMBER_COLOR, HEADLINE_FONT)
		heading.custom_minimum_size.y = 30.0
		list.add_child(heading)

		for entry in entries:
			if str(entry.get("category", "")) != category:
				continue
			var button := _make_vehicle_button(entry)
			list.add_child(button)
			_buttons.append(button)


func _make_vehicle_button(entry: Dictionary) -> Button:
	var button := Button.new()
	button.text = str(entry.get("name", "UNKNOWN VEHICLE"))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size = Vector2(0.0, 42.0)
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = str(entry.get("description", ""))
	button.add_theme_font_override("font", DATA_FONT)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_color_override("font_focus_color", TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", PANEL_BG)
	button.add_theme_stylebox_override("normal", _make_style(Color("242323"), BORDER_COLOR, 1, 2))
	button.add_theme_stylebox_override("hover", _make_style(Color("30302e"), CYAN_COLOR, 1, 2))
	button.add_theme_stylebox_override("focus", _make_style(Color("30302e"), AMBER_COLOR, 2, 2))
	button.add_theme_stylebox_override("pressed", _make_style(AMBER_COLOR, AMBER_COLOR, 2, 2))
	button.focus_entered.connect(_show_entry_description.bind(entry))
	button.mouse_entered.connect(_show_entry_description.bind(entry))
	button.pressed.connect(_on_entry_pressed.bind(entry))
	return button


func _layout_ui() -> void:
	if _modal_root == null:
		return
	var viewport_size := _modal_root.size
	var panel_size := Vector2(
		minf(maxf(viewport_size.x - 48.0, 720.0), 1180.0),
		minf(maxf(viewport_size.y - 48.0, 620.0), 840.0)
	)
	_panel.position = (viewport_size - panel_size) * 0.5
	_panel.size = panel_size
	_title.position = Vector2(26.0, 18.0)
	_title.size = Vector2(panel_size.x - 52.0, 34.0)
	_subtitle.position = Vector2(27.0, 54.0)
	_subtitle.size = Vector2(panel_size.x - 54.0, 20.0)
	_description.position = Vector2(27.0, 82.0)
	_description.size = Vector2(panel_size.x - 54.0, 40.0)
	_columns.position = Vector2(24.0, 130.0)
	_columns.size = Vector2(panel_size.x - 48.0, panel_size.y - 188.0)
	_footer.position = Vector2(24.0, panel_size.y - 42.0)
	_footer.size = Vector2(panel_size.x - 48.0, 22.0)

	_toast_panel.position = Vector2(maxf(viewport_size.x - 500.0, 16.0), 20.0)
	_toast_panel.size = Vector2(minf(470.0, viewport_size.x - 32.0), 48.0)
	_toast_label.position = Vector2(12.0, 0.0)
	_toast_label.size = Vector2(_toast_panel.size.x - 24.0, _toast_panel.size.y)


func _on_entry_pressed(entry: Dictionary) -> void:
	set_open(false)
	if str(entry.get("spawn_kind", "")).is_empty():
		spawn_entry.call_deferred(entry.duplicate(true))
	else:
		_spawn_enemy_force.call_deferred(entry.duplicate(true))


func _spawn_enemy_force(entry: Dictionary) -> void:
	var spawner := _get_enemy_aircraft_spawner()
	if spawner == null:
		_report_failure("ENEMY SPAWNER IS NOT AVAILABLE IN THIS SCENARIO")
		return
	var spawn_kind := str(entry.get("spawn_kind", ""))
	var display_name := str(entry.get("name", "ENEMY FORCE"))
	var requested_count := maxi(int(entry.get("count", 4)), 1)
	_show_toast("DEPLOYING  //  %s" % display_name)
	match spawn_kind:
		"enemy_flight":
			if not spawner.has_method("spawn_enemy_flight_by_role"):
				_report_failure("ENEMY FLIGHT SPAWN API IS UNAVAILABLE")
				return
			var spawned_variant: Variant = await spawner.call(
				"spawn_enemy_flight_by_role",
				str(entry.get("role", "fighter")),
				requested_count
			)
			if not (spawned_variant is Array) or (spawned_variant as Array).is_empty():
				_report_failure("NO %s AIRCRAFT COULD BE DEPLOYED" % str(entry.get("role", "enemy")).to_upper())
				return
			var spawned: Array = spawned_variant as Array
			var lead := spawned[0] as Node
			_show_toast("DEPLOYED  //  %s  //  %d AIRCRAFT" % [display_name, spawned.size()])
			enemy_force_spawned.emit(lead, entry.duplicate(true), spawned.size())
		"enemy_platoon":
			if not spawner.has_method("spawn_random_enemy_platoon"):
				_report_failure("ENEMY PLATOON SPAWN API IS UNAVAILABLE")
				return
			var platoon_variant: Variant = spawner.call("spawn_random_enemy_platoon", requested_count)
			if not is_instance_valid(platoon_variant) or not (platoon_variant is Node):
				_report_failure("NO ENEMY GROUND PLATOON COULD BE DEPLOYED")
				return
			var platoon := platoon_variant as Node
			var member_count := requested_count
			if platoon.has_method("get_members"):
				var members_variant: Variant = platoon.call("get_members")
				if members_variant is Array:
					member_count = (members_variant as Array).size()
			_show_toast("DEPLOYED  //  %s  //  %d VEHICLES" % [display_name, member_count])
			enemy_force_spawned.emit(platoon, entry.duplicate(true), member_count)
		_:
			_report_failure("UNKNOWN ENEMY FORMATION PRESET: %s" % spawn_kind)


func _show_entry_description(entry: Dictionary) -> void:
	if _description == null:
		return
	_description.text = str(entry.get("description", "No vehicle description available."))


func _place_aircraft(vehicle: Node3D, is_helicopter: bool) -> void:
	var frame := _get_spawn_frame()
	var origin: Vector3 = frame["origin"] as Vector3
	var forward: Vector3 = frame["forward"] as Vector3
	var spawn_position := origin + forward * maxf(aircraft_spawn_distance_m, 40.0)
	var ground_height := _sample_terrain_height(spawn_position)
	var terrain_clearance := aircraft_spawn_agl_m * (0.55 if is_helicopter else 1.0)
	if not is_nan(ground_height):
		spawn_position.y = maxf(
			origin.y + aircraft_spawn_height_above_view_m,
			ground_height + terrain_clearance
		)
	else:
		spawn_position.y = origin.y + maxf(aircraft_spawn_height_above_view_m, 40.0)
	vehicle.global_position = spawn_position
	vehicle.global_rotation = Vector3(0.0, atan2(forward.x, forward.z), 0.0)
	if vehicle is RigidBody3D:
		var body := vehicle as RigidBody3D
		body.linear_velocity = forward * (
			helicopter_spawn_speed_mps if is_helicopter else airplane_spawn_speed_mps
		)
		body.angular_velocity = Vector3.ZERO


func _place_ground_vehicle(vehicle: Node3D) -> void:
	var frame := _get_spawn_frame()
	var origin: Vector3 = frame["origin"] as Vector3
	var forward: Vector3 = frame["forward"] as Vector3
	var spawn_position := origin + forward * maxf(ground_vehicle_spawn_distance_m, 15.0)
	var ground_height := _sample_terrain_height(spawn_position)
	if not is_nan(ground_height):
		spawn_position.y = ground_height + 0.15
	vehicle.global_position = spawn_position
	vehicle.global_rotation = Vector3(0.0, atan2(forward.x, forward.z), 0.0)


func _finalize_aircraft(vehicle: Node3D, _is_helicopter: bool) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(vehicle) or not (vehicle is RigidBody3D):
		return
	vehicle.remove_from_group("aircraft")
	vehicle.remove_from_group("enemies")
	vehicle.add_to_group("friendlies")
	vehicle.add_to_group("ai_aircraft")
	var ai_toggle := vehicle.get_node_or_null("AIToggle")
	if ai_toggle != null and ai_toggle.has_method("enable_ai"):
		ai_toggle.call("enable_ai")
	_stow_airborne_gear(vehicle)
	var flight_director := get_node_or_null("/root/FlightDirector")
	if flight_director != null and flight_director.has_method("register_aircraft"):
		flight_director.call("register_aircraft", vehicle as RigidBody3D)


func _stow_airborne_gear(vehicle: Node3D) -> void:
	var control_gear := vehicle.find_child("ControlLandingGear", true, false)
	if control_gear == null or not control_gear.has_method("send_to_landing_gears"):
		return
	control_gear.call("send_to_landing_gears", "stow")
	if control_gear.has_method("send_to_tailhooks"):
		control_gear.call("send_to_tailhooks", "stow")
	if control_gear.has_method("send_to_tailhook_simple"):
		control_gear.call("send_to_tailhook_simple", false)
	if "gear_down_state" in control_gear:
		control_gear.set("gear_down_state", false)
	if control_gear.has_method("_set_collider_disabled"):
		control_gear.call("_set_collider_disabled", true)


func _get_spawn_frame() -> Dictionary:
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if is_instance_valid(camera):
		var camera_forward := -(camera as Camera3D).global_basis.z
		camera_forward.y = 0.0
		if camera_forward.length_squared() > 0.0001:
			return {
				"origin": (camera as Camera3D).global_position,
				"forward": camera_forward.normalized(),
			}

	var flight_director := get_node_or_null("/root/FlightDirector")
	var viewed_variant: Variant = flight_director.get("current_viewed_aircraft") \
			if flight_director != null else null
	if is_instance_valid(viewed_variant) and viewed_variant is Node3D:
		var viewed := viewed_variant as Node3D
		var viewed_forward := viewed.global_basis.z
		viewed_forward.y = 0.0
		if viewed_forward.length_squared() > 0.0001:
			return {"origin": viewed.global_position, "forward": viewed_forward.normalized()}

	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier != null:
		var carrier_forward := carrier.global_basis.z
		carrier_forward.y = 0.0
		if carrier_forward.length_squared() < 0.0001:
			carrier_forward = Vector3.FORWARD
		return {"origin": carrier.global_position, "forward": carrier_forward.normalized()}
	return {"origin": Vector3.ZERO, "forward": Vector3.FORWARD}


func _sample_terrain_height(world_position: Vector3) -> float:
	var terrain := get_tree().get_first_node_in_group("terrain_provider") as Node3D
	if terrain == null or not terrain.has_method("get_height"):
		return NAN
	var sampled: Variant = terrain.call("get_height", world_position)
	if typeof(sampled) != TYPE_FLOAT:
		return NAN
	return float(sampled)


func _get_world_root() -> Node:
	if get_tree().current_scene != null:
		return get_tree().current_scene
	return get_parent()


func _get_enemy_aircraft_spawner() -> Node:
	var grouped := get_tree().get_first_node_in_group("enemy_aircraft_spawner")
	if grouped != null and is_instance_valid(grouped):
		return grouped
	var world_root := _get_world_root()
	if world_root != null:
		var named := world_root.find_child("EnemyAircraftSpawner", true, false)
		if named != null and is_instance_valid(named):
			return named
	return null


func _show_toast(message: String) -> void:
	if _toast_panel == null or _toast_label == null:
		return
	_toast_label.text = message
	_toast_panel.visible = true
	_toast_hide_at_s = Time.get_ticks_msec() / 1000.0 + TOAST_DURATION_S


func _report_failure(message: String) -> void:
	push_warning("VehicleSpawnMenu: %s" % message)
	_show_toast("SPAWN FAILED  //  %s" % message)
	spawn_failed.emit(message)


func _is_spawn_key_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo \
			or key_event.ctrl_pressed or key_event.alt_pressed or key_event.meta_pressed:
		return false
	return key_event.physical_keycode == KEY_S or key_event.keycode == KEY_S


static func _build_spawn_catalog() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var seen_paths: Dictionary = {}
	for category in CATEGORY_ORDER:
		for source_entry_variant: Variant in Catalog.entries_for(category):
			var source_entry: Dictionary = source_entry_variant as Dictionary
			var scene_path := str(source_entry.get("scene", ""))
			# The land carrier owns world-level flight-deck and camera managers and
			# cannot safely behave like an ordinary spawned unit.
			if scene_path == "res://LandCarrier/LandCarrier2.tscn" \
					or scene_path.is_empty() or not ResourceLoader.exists(scene_path):
				continue
			var entry: Dictionary = source_entry.duplicate(true)
			entry["category"] = category
			entry["sort_index"] = _aircraft_index_from_path(scene_path)
			entries.append(entry)
			seen_paths[scene_path] = true

	for file_name in DirAccess.get_files_at("res://Aircraft"):
		if not file_name.begins_with("Aircraft_") or not file_name.ends_with(".tscn"):
			continue
		var scene_path := "res://Aircraft/%s" % file_name
		if seen_paths.has(scene_path):
			continue
		var aircraft_index := _aircraft_index_from_path(scene_path)
		if aircraft_index <= 0:
			continue
		entries.append({
			"name": "AIRCRAFT %02d" % aircraft_index,
			"scene": scene_path,
			"description": "Numbered aircraft scene not yet named in the Technical Index.",
			"stats": {"CLASS": "FIXED-WING", "CONFIGURATION": "%02d" % aircraft_index},
			"category": "AIRPLANES",
			"sort_index": aircraft_index,
		})

	entries.append_array([
		{
			"name": "BOMBER FLIGHT // AIRCRAFT 04",
			"description": "Deploy four hostile OKB TB-60 Vulture bombers inbound against the carrier.",
			"category": "ENEMY FORCES",
			"spawn_kind": "enemy_flight",
			"role": "bomber",
			"scene": "res://Aircraft/Aircraft_4.tscn",
			"count": 4,
			"sort_index": 1,
		},
		{
			"name": "FIGHTER FLIGHT // AIRCRAFT 03",
			"description": "Deploy four hostile VMFC F-9 Wasp fighters searching for friendly aircraft.",
			"category": "ENEMY FORCES",
			"spawn_kind": "enemy_flight",
			"role": "fighter",
			"scene": "res://Aircraft/Aircraft_3.tscn",
			"count": 4,
			"sort_index": 2,
		},
		{
			"name": "ATTACK FLIGHT // AIRCRAFT 06",
			"description": "Deploy four hostile OKB Sh-37 Razorback attack planes inbound with rockets.",
			"category": "ENEMY FORCES",
			"spawn_kind": "enemy_flight",
			"role": "attack",
			"scene": "res://Aircraft/Aircraft_6.tscn",
			"count": 4,
			"sort_index": 3,
		},
		{
			"name": "RANDOM GROUND PLATOON",
			"description": "Deploy four hostile ground vehicles in a random mix, ordered to attack the carrier.",
			"category": "ENEMY FORCES",
			"spawn_kind": "enemy_platoon",
			"count": 4,
			"sort_index": 4,
		},
	])

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var category_a := CATEGORY_ORDER.find(str(a.get("category", "")))
		var category_b := CATEGORY_ORDER.find(str(b.get("category", "")))
		if category_a != category_b:
			return category_a < category_b
		var index_a := int(a.get("sort_index", 0))
		var index_b := int(b.get("sort_index", 0))
		if index_a > 0 or index_b > 0:
			return index_a < index_b
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return entries


static func _aircraft_index_from_path(scene_path: String) -> int:
	var stem := scene_path.get_file().get_basename()
	if not stem.begins_with("Aircraft_"):
		return 0
	var suffix := stem.trim_prefix("Aircraft_")
	return suffix.to_int() if suffix.is_valid_int() else 0


func _make_label(
	text: String,
	size: int,
	color: Color,
	font: Font,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_style(
	background: Color,
	border: Color,
	border_width: int,
	corner_radius: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	return style
