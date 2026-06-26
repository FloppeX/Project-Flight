extends Node3D
# InstrumentPanel.gd - Virtual cockpit instrument display

const MFD_MODULE_SCRIPT := preload("res://HUD/Instruments/MFDModule.gd")
const TEXT_MODULE_SCRIPT := preload("res://HUD/Instruments/TextInstrumentModule.gd")
const WARNING_LIGHT_MODULE_SCRIPT := preload("res://HUD/Instruments/WarningLightModule.gd")
const SLIP_BALL_MODULE_SCRIPT := preload("res://HUD/Instruments/SlipBallModule.gd")

@export var aircraft_path: NodePath
@export var panel_size: Vector2 = Vector2(0.4, 0.3)  # Size in meters (40cm x 30cm)
@export var viewport_resolution: Vector2i = Vector2i(800, 600)
@export var auto_build_default_modules: bool = true
@export var update_only_when_viewed: bool = true
@export var module_layout: Array[Dictionary] = []
@export var show_interaction_cursor: bool = true
@export var interaction_cursor_radius_px: float = 4.0
@export var interaction_cursor_color: Color = Color(0.75, 1.0, 0.85, 0.95)
@export var interaction_cursor_outline_color: Color = Color(0.0, 0.0, 0.0, 0.8)
@export var render_to_model_surface: bool = false
@export var model_panel_mesh_path: NodePath
@export var model_panel_mesh_name: String = "instrument panel"
@export var model_panel_material_names: PackedStringArray = PackedStringArray(["Instrument panel material"])
@export var hide_panel_quad_when_rendering_to_model: bool = true
@export var auto_fit_model_panel_local_rect: bool = true
@export var model_panel_local_rect: Rect2 = Rect2(-0.5, -0.5, 1.0, 1.0)

@onready var aircraft: Aircraft = get_node(aircraft_path) as Aircraft
@onready var viewport: SubViewport = $SubViewport
@onready var panel_mesh: MeshInstance3D = $PanelScreen

# UI Elements
@onready var altitude_label: Label = $SubViewport/InstrumentDisplay/AltitudePanel/AltitudeLabel
@onready var speed_label: Label = $SubViewport/InstrumentDisplay/SpeedPanel/SpeedLabel
@onready var fuel_label: Label = $SubViewport/InstrumentDisplay/FuelPanel/FuelLabel
@onready var fuel_bar: ProgressBar = $SubViewport/InstrumentDisplay/FuelPanel/FuelBar
@onready var gear_label: Label = $SubViewport/InstrumentDisplay/GearPanel/GearLabel
@onready var engine_label: Label = $SubViewport/InstrumentDisplay/EnginePanel/EngineLabel
@onready var display_root: Control = $SubViewport/InstrumentDisplay

# STRUCT indicator (created dynamically)
var struct_label: Label

# Radar/Target UI
var radar_panel: PanelContainer
var radar_canvas: Control
var target_panel: Control
var target_texture_rect: TextureRect
var target_viewport: SubViewport
var target_camera: Camera3D
var target_placeholder: TextureRect
var target_info_label: Label  # Text overlay for enemy name and distance
var missile_camera_mode: bool = false  # Whether we're following a missile
var tracked_missile: Node3D = null     # Reference to the missile we're following
var test_pattern_tex: Texture2D
@export var camera_target_path: NodePath
var camera_target: Node3D
var camera_target_cam: Camera3D
@export var assumed_target_width_m: float = 10.0
@export var min_fov_deg: float = 10.0
@export var max_fov_deg: float = 60.0
@export var fov_lerp_speed: float = 8.0
@export var idle_fov_deg: float = 30.0
@export var target_camera_slew_deg_s: float = 120.0
@export var target_camera_zoom_lerp_speed: float = 6.0
@export var zoom_distance: float = 50.0
@export var obstacle_margin: float = 1.0
@export var scan_spacing_px: float = 3.0
@export var scan_thickness_px: float = 1.0
@export var scan_strength: float = 0.35
@export var grayscale_strength: float = 1.0
@export var destroyed_target_hold_s: float = 10.0
var target_effect_material: ShaderMaterial
var nv_mode_enabled: bool = false
var _watched_display_target: Node3D = null
var _last_display_target_position: Vector3 = Vector3.ZERO
var _last_display_target_name: String = ""
var _destroyed_target_hold_position: Vector3 = Vector3.ZERO
var _destroyed_target_hold_name: String = ""
var _destroyed_target_hold_until_s: float = -INF
var _target_camera_pose_initialized: bool = false
var _camera_target_rest_transform: Transform3D = Transform3D.IDENTITY
var _camera_target_cam_rest_transform: Transform3D = Transform3D.IDENTITY
var module_root: Control = null
var instrument_modules: Array[InstrumentModule] = []
var mfd_modules: Array[MFDModule] = []
var interaction_cursor: Panel = null
var _panel_updates_active: bool = true
var model_panel_mesh: MeshInstance3D = null
var model_panel_surface_indices: PackedInt32Array = PackedInt32Array()

func _ready():
	# Set up the panel screen mesh
	var quad = QuadMesh.new()
	quad.size = panel_size
	panel_mesh.mesh = quad
	
	# Set up viewport
	viewport.size = viewport_resolution
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	
	# Create material for the panel screen
	var material := _create_panel_material()
	panel_mesh.material_override = material
	_bind_model_panel_surface(material)
	
	# Create a top row container and move the five value labels into it
	_relayout_top_row()
	_setup_lower_displays()
	if auto_build_default_modules:
		_build_module_panel()
	_ensure_interaction_cursor()
	# Resolve camera target on aircraft
	if aircraft:
		if camera_target_path != NodePath():
			camera_target = aircraft.get_node_or_null(camera_target_path) as Node3D
		if camera_target == null:
			camera_target = aircraft.find_child("CameraTarget", true, false) as Node3D
		# If CameraTarget has a child Camera3D, use it as source pose (but do not make it current)
		if camera_target:
			_camera_target_rest_transform = camera_target.transform
			camera_target_cam = camera_target.find_child("Camera3D", true, false) as Camera3D
			if camera_target_cam:
				_camera_target_cam_rest_transform = camera_target_cam.transform
				camera_target_cam.current = false
	_update_lower_layout_sizes()
	# Auto-bind aircraft if not provided via export, so radar works by default
	if aircraft == null:
		aircraft = get_tree().get_first_node_in_group("aircraft") as Aircraft
	# Also defer one more bind in case aircraft registers after us
	call_deferred("_ensure_aircraft_bound")
	
	# Add to group so weapon systems can find us for missile camera
	add_to_group("instrument_panel")
	
	pass

func _create_panel_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D panel_texture : source_color;
uniform bool use_local_panel_projection = false;
uniform vec4 panel_local_rect = vec4(-0.5, -0.5, 1.0, 1.0);
uniform float emission_energy = 2.0;
varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec2 sample_uv = UV;
	if (use_local_panel_projection) {
		vec2 rect_size = vec2(max(panel_local_rect.z, 0.0001), max(panel_local_rect.w, 0.0001));
		sample_uv = vec2(
			(local_position.x - panel_local_rect.x) / rect_size.x,
			1.0 - ((local_position.y - panel_local_rect.y) / rect_size.y)
		);
	}
	sample_uv = clamp(sample_uv, vec2(0.0), vec2(1.0));
	vec4 tex = texture(panel_texture, sample_uv);
	ALBEDO = tex.rgb;
	EMISSION = tex.rgb * emission_energy;
	ALPHA = tex.a;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("panel_texture", viewport.get_texture())
	_apply_panel_material_local_rect(material, model_panel_local_rect)
	material.set_shader_parameter("use_local_panel_projection", false)
	return material


func _apply_panel_material_local_rect(material: Material, local_rect: Rect2) -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return
	var rect_size := Vector2(maxf(local_rect.size.x, 0.0001), maxf(local_rect.size.y, 0.0001))
	shader_material.set_shader_parameter(
		"panel_local_rect",
		Vector4(local_rect.position.x, local_rect.position.y, rect_size.x, rect_size.y)
	)


func _bind_model_panel_surface(material: Material) -> void:
	model_panel_mesh = null
	model_panel_surface_indices = PackedInt32Array()
	if not render_to_model_surface:
		return
	var mesh_instance := _resolve_model_panel_mesh()
	if mesh_instance == null:
		push_warning("[InstrumentPanel] render_to_model_surface enabled, but no model panel mesh was found.")
		return
	var mesh := mesh_instance.mesh
	if mesh == null:
		push_warning("[InstrumentPanel] model panel mesh has no mesh resource: %s" % mesh_instance.name)
		return
	for surface_index in range(mesh.get_surface_count()):
		if _surface_material_matches(mesh_instance, surface_index):
			model_panel_surface_indices.append(surface_index)
	if model_panel_surface_indices.is_empty():
		push_warning("[InstrumentPanel] no matching model panel material found on mesh %s." % mesh_instance.name)
		return
	if auto_fit_model_panel_local_rect:
		model_panel_local_rect = _calculate_surface_local_xy_bounds(mesh, model_panel_surface_indices)
		_apply_panel_material_local_rect(material, model_panel_local_rect)
	var shader_material := material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("use_local_panel_projection", true)
	for surface_index in model_panel_surface_indices:
		mesh_instance.set_surface_override_material(surface_index, material)
	model_panel_mesh = mesh_instance
	if hide_panel_quad_when_rendering_to_model and panel_mesh != null:
		panel_mesh.visible = false


func _calculate_surface_local_xy_bounds(mesh: Mesh, surface_indices: PackedInt32Array) -> Rect2:
	var found_vertex := false
	var min_xy := Vector2.ZERO
	var max_xy := Vector2.ZERO
	for surface_index in surface_indices:
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var xy := Vector2(vertex.x, vertex.y)
			if not found_vertex:
				min_xy = xy
				max_xy = xy
				found_vertex = true
			else:
				min_xy = Vector2(minf(min_xy.x, xy.x), minf(min_xy.y, xy.y))
				max_xy = Vector2(maxf(max_xy.x, xy.x), maxf(max_xy.y, xy.y))
	if not found_vertex:
		return Rect2(-0.5, -0.5, 1.0, 1.0)
	return Rect2(min_xy, max_xy - min_xy)


func _resolve_model_panel_mesh() -> MeshInstance3D:
	if model_panel_mesh_path != NodePath():
		var explicit_node := get_node_or_null(model_panel_mesh_path) as MeshInstance3D
		if explicit_node != null:
			return explicit_node
	if aircraft != null and is_instance_valid(aircraft):
		var named := aircraft.find_child(model_panel_mesh_name, true, false) as MeshInstance3D
		if named != null:
			return named
	var root := get_parent()
	if root != null:
		return root.find_child(model_panel_mesh_name, true, false) as MeshInstance3D
	return null


func _surface_material_matches(mesh_instance: MeshInstance3D, surface_index: int) -> bool:
	if model_panel_material_names.is_empty():
		return true
	var material := mesh_instance.get_surface_override_material(surface_index)
	if material == null and mesh_instance.mesh != null:
		material = mesh_instance.mesh.surface_get_material(surface_index)
	if material == null:
		return false
	var material_name := material.resource_name.strip_edges()
	for expected_name in model_panel_material_names:
		if material_name == expected_name.strip_edges():
			return true
	return false


func _ensure_aircraft_bound() -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		var a := get_tree().get_first_node_in_group("aircraft") as Aircraft
		if a:
			aircraft = a

## Called by FlightDirector when switching spectated aircraft.
## Rebinds the instrument panel so all gauges reflect the new plane.
func bind_to_aircraft(new_aircraft: Node3D) -> void:
	if not is_instance_valid(new_aircraft):
		return
	aircraft = new_aircraft as Aircraft
	# Re-resolve the camera target on the new aircraft
	var ct := new_aircraft.get_node_or_null("CameraTarget") as Node3D
	if ct:
		camera_target = ct
		_camera_target_rest_transform = camera_target.transform
		camera_target_cam = ct.find_child("Camera3D", true, false) as Camera3D
		if camera_target_cam:
			_camera_target_cam_rest_transform = camera_target_cam.transform
			camera_target_cam.current = false
	_target_camera_pose_initialized = false
	for module in instrument_modules:
		if module != null and is_instance_valid(module):
			module.set_aircraft_reference(aircraft)


func _physics_process(delta: float) -> void:
	if not _should_update_panel_this_frame():
		return
	# Update missile camera in physics process for better sync with missile movement
	if missile_camera_mode and is_instance_valid(tracked_missile):
		_update_missile_camera()

func _process(delta: float) -> void:
	# Keep aircraft reference alive if it spawns late or was freed
	if aircraft == null or not is_instance_valid(aircraft):
		_ensure_aircraft_bound()
	if aircraft == null or not is_instance_valid(aircraft):
		_set_interaction_cursor_visible(false)
		_set_panel_updates_active(false)
		return
	if not _should_update_panel_this_frame():
		_set_interaction_cursor_visible(false)
		_set_panel_updates_active(false)
		return
	_set_panel_updates_active(true)

	# Update altitude display
	var altitude = aircraft.local_altitude
	altitude_label.text = "ALT\n" + str(int(altitude)) + " m"
	
	# Update speed display  
	var speed = aircraft.air_velocity
	speed_label.text = "SPD\n" + str(int(speed)) + " m/s"
	
	# Update fuel display (get from energy containers)
	var fuel_percent = 0.0
	if "fuel" in aircraft.available_energy:
		# Find total fuel capacity from fuel containers
		var total_capacity = 0.0
		var current_fuel = aircraft.available_energy["fuel"]
		
		for container in aircraft.energy_containers:
			if container == null:
				continue
			if container is Object and not is_instance_valid(container):
				continue
			if container.EnergyType == "fuel":
				total_capacity += container.MaxCapacity
		
		if total_capacity > 0:
			fuel_percent = (current_fuel / total_capacity) * 100.0
	
	fuel_label.text = "FUEL\n" + str(int(fuel_percent)) + "%"
	fuel_bar.value = fuel_percent
	
	# Update fuel bar color based on level
	if fuel_percent > 25:
		fuel_bar.modulate = Color.GREEN
	elif fuel_percent > 10:
		fuel_bar.modulate = Color.YELLOW
	else:
		fuel_bar.modulate = Color.RED
	
	# Update gear status (check for landing gear modules)
	var gear_modules = aircraft.find_modules_by_type("landing_gear")
	if gear_modules.size() > 0:
		var gear = gear_modules[0]
		if gear == null or (gear is Object and not is_instance_valid(gear)):
			gear = null
		if gear == null:
			gear_label.text = "GEAR\nN/A"
			gear_label.modulate = Color.GRAY
		elif gear.is_deployed:
			gear_label.text = "GEAR\nDOWN"
			gear_label.modulate = Color.GREEN
		elif gear.is_stowed:
			gear_label.text = "GEAR\nUP"
			gear_label.modulate = Color.WHITE
		elif gear.is_deploying or gear.is_stowing:
			gear_label.text = "GEAR\nMOVING"
			gear_label.modulate = Color.YELLOW
		else:
			gear_label.text = "GEAR\nUNKNOWN"
			gear_label.modulate = Color.GRAY
	else:
		gear_label.text = "GEAR\nN/A"
		gear_label.modulate = Color.GRAY
	
	# Update engine status
	var engine_modules = aircraft.find_modules_by_type("engine")
	if engine_modules.size() > 0:
		var engine = engine_modules[0]
		if engine == null or (engine is Object and not is_instance_valid(engine)):
			engine = null
		if engine == null:
			engine_label.text = "ENG\nN/A"
			engine_label.modulate = Color.GRAY
		elif engine.is_engine_working:
			var power_percent = int(engine.current_power * 100)
			engine_label.text = "ENG\n" + str(power_percent) + "%"
			engine_label.modulate = Color.GREEN
		else:
			engine_label.text = "ENG\nOFF"
			engine_label.modulate = Color.RED
	else:
		engine_label.text = "ENG\nN/A"
		engine_label.modulate = Color.GRAY
	
	# Update STRUCT indicator with aircraft health
	if struct_label:
		var health_percent = int((aircraft.current_health / aircraft.max_health) * 100)
		struct_label.text = "STRUCT\n" + str(health_percent)
		
		# Color coding based on health
		if health_percent > 60:
			struct_label.modulate = Color.GREEN
		elif health_percent > 30:
			struct_label.modulate = Color.YELLOW
		elif health_percent > 0:
			struct_label.modulate = Color.RED
		else:
			struct_label.modulate = Color.DARK_RED

	_update_instrument_modules(delta)
	_update_interaction_cursor()

	# Update target camera to look at current target if module present
	if target_camera and is_instance_valid(target_camera):
		# MISSILE CAMERA MODE: Follow missile if one is being tracked
		if missile_camera_mode and is_instance_valid(tracked_missile):
			_update_missile_camera()
			return  # Skip normal target camera logic
		var target_focus := _get_target_camera_focus()
		# Prefer explicit CameraTarget provided on the aircraft
		if camera_target and is_instance_valid(camera_target):
			var source_xform: Transform3D = _get_target_camera_rest_global_transform()
			if camera_target_cam and is_instance_valid(camera_target_cam):
				source_xform = source_xform * _camera_target_cam_rest_transform
			if not target_focus.is_empty():
				var focus_pos: Vector3 = target_focus["position"]
				# Keep the target feed as a true aircraft-mounted sensor.
				# Earlier versions slid the camera toward the target for zoom/composition,
				# which made the feed feel like it was lagging behind the aircraft and could
				# jitter when obstruction tests changed frame-to-frame.
				_slew_target_camera_look_at(source_xform.origin, focus_pos, delta)
				_ensure_target_view_camera_current()
				if target_placeholder:
					target_placeholder.visible = false
				# Update target info label
				if target_info_label:
					var distance = _get_node_visual_position(aircraft).distance_to(focus_pos)
					var suffix := " DESTROYED" if bool(target_focus.get("destroyed", false)) else ""
					target_info_label.text = String(target_focus["name"]) + suffix + "\n" + str(int(distance)) + "m"
			else:
				# No target: slew the target feed back to the aircraft's forward camera mount.
				_slew_target_camera_to_transform(source_xform, delta)
				_ensure_target_view_camera_current()
				if target_placeholder:
					target_placeholder.visible = false
				# Update target info label for no target
				if target_info_label:
					target_info_label.text = "NO TARGET"
		else:
			# Fallback: derive from targeting module if available, else look forward
			if not target_focus.is_empty():
				var focus_pos: Vector3 = target_focus["position"]
				var aircraft_xform := _get_node_visual_transform(aircraft)
				var cam_pos = aircraft_xform.origin + aircraft_xform.basis.z * 1.0 + Vector3(0, 0.3, 0)
				_slew_target_camera_look_at(cam_pos, focus_pos, delta)
				if target_placeholder:
					target_placeholder.visible = false
				# Update target info label for targeting module target
				if target_info_label:
					var distance = aircraft_xform.origin.distance_to(focus_pos)
					var suffix := " DESTROYED" if bool(target_focus.get("destroyed", false)) else ""
					target_info_label.text = String(target_focus["name"]) + suffix + "\n" + str(int(distance)) + "m"
			else:
				# Idle: look forward
				var aircraft_xform := _get_node_visual_transform(aircraft)
				var cam_pos2 = aircraft_xform.origin + aircraft_xform.basis.z * 1.0 + Vector3(0, 0.3, 0)
				var forward_xform := Transform3D(aircraft_xform.basis, cam_pos2)
				_slew_target_camera_to_transform(forward_xform, delta)
				if target_placeholder:
					target_placeholder.visible = false
				# Update target info label for no target (idle state)
				if target_info_label:
					target_info_label.text = "NO TARGET"

		# Auto-zoom to fit target width assuming ~assumed_target_width_m across
		if not target_focus.is_empty():
			var dist: float = max(0.1, target_camera.global_position.distance_to(target_focus["position"]))
			var aspect: float = float(viewport_resolution.x) / float(viewport_resolution.y)
			var desired_vfov_rad: float = 2.0 * atan( (assumed_target_width_m) / (2.0 * dist * aspect) )
			var desired_vfov_deg: float = rad_to_deg(desired_vfov_rad)
			desired_vfov_deg = clamp(desired_vfov_deg, min_fov_deg, max_fov_deg)
			_slew_target_camera_fov(desired_vfov_deg, delta)
		else:
			_slew_target_camera_fov(idle_fov_deg, delta)
	

func _should_update_panel_this_frame() -> bool:
	if not update_only_when_viewed:
		return true
	return _is_panel_aircraft_currently_viewed()


func _set_panel_updates_active(active: bool) -> void:
	if _panel_updates_active == active:
		return
	_panel_updates_active = active
	if not active and target_placeholder != null and is_instance_valid(target_placeholder):
		target_placeholder.visible = false
	if viewport != null and is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if target_viewport != null and is_instance_valid(target_viewport):
		target_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED


func _setup_lower_displays() -> void:
	if display_root == null:
		return
	var lower := display_root.get_node_or_null("LowerRow") as Control
	if lower == null:
		lower = Control.new()  # Use regular Control instead of HBoxContainer
		lower.name = "LowerRow"
		display_root.add_child(lower)
		lower.anchor_left = 0.0
		lower.anchor_right = 0.0
		lower.anchor_top = 0.0
		lower.anchor_bottom = 0.0
		lower.offset_top = 55  # Moved down 10 pixels to avoid overlap
		lower.offset_bottom = 250  # Fixed height: 55 + 195
		lower.offset_left = 0
		lower.offset_right = 400  # Fixed width
		# No automatic layout - we'll position manually

	# Left: Radar panel - manually positioned
	if radar_panel == null:
		radar_panel = PanelContainer.new()  # Keep as PanelContainer for radar functionality
		radar_panel.name = "RadarPanel"
		lower.add_child(radar_panel)
		# Fixed position and size - left side
		radar_panel.position = Vector2(0, 0)
		radar_panel.custom_minimum_size = Vector2(195, 195)
		radar_panel.size = Vector2(195, 195)
		radar_panel.clip_contents = true  # Clip content to panel bounds
		# Remove default panel padding to match sizes exactly
		radar_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var radar = preload("res://HUD/RadarCanvas.gd").new()
		radar.name = "RadarCanvas"
		radar_panel.add_child(radar)
		radar_canvas = radar
		radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		radar.set_anchors_preset(Control.PRESET_FULL_RECT)
		radar.offset_left = 0.0
		radar.offset_top = 0.0
		radar.offset_right = 0.0
		radar.offset_bottom = 0.0
		radar.custom_minimum_size = radar_panel.size
		radar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		radar.size_flags_vertical = Control.SIZE_EXPAND_FILL
		radar.set_provider(self)

	# Right: Target view panel - manually positioned
	if target_panel == null:
		target_panel = Control.new()  # Use Control instead of PanelContainer
		target_panel.name = "TargetPanel"
		lower.add_child(target_panel)
		# Fixed position and size - right side (195 + 10 separation = 205)
		target_panel.position = Vector2(205, 0)
		target_panel.custom_minimum_size = Vector2(195, 195)
		target_panel.size = Vector2(195, 195)
		target_panel.clip_contents = true  # Clip content to panel bounds
		# Create viewport and camera for target feed
		target_viewport = SubViewport.new()
		target_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		target_viewport.size = Vector2i(200, 200)  # Larger viewport size for better quality
		target_viewport.transparent_bg = false
		# Share the main 3D world so the camera renders the scene
		target_viewport.world_3d = get_world_3d()
		# IMPORTANT: Add SubViewport to the scene tree so it renders
		add_child(target_viewport)
		var vp_container = Node3D.new()
		vp_container.name = "TargetRig"
		target_viewport.add_child(vp_container)
		target_camera = Camera3D.new()
		target_camera.fov = 20.0
		vp_container.add_child(target_camera)
		_ensure_target_view_camera_current()
		# TextureRect to display
		target_texture_rect = TextureRect.new()
		target_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE  # Match placeholder stretch mode
		target_texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target_texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		target_texture_rect.add_theme_constant_override("margin_left", 0)
		target_texture_rect.add_theme_constant_override("margin_right", 0)
		target_texture_rect.add_theme_constant_override("margin_top", 0)
		target_texture_rect.add_theme_constant_override("margin_bottom", 0)
		target_texture_rect.texture = target_viewport.get_texture()
		# Post-process material (grayscale + scan lines)
		target_effect_material = ShaderMaterial.new()
		target_effect_material.shader = _create_target_effect_shader()
		target_effect_material.set_shader_parameter("texture_size", Vector2(viewport_resolution.x, viewport_resolution.y))
		target_effect_material.set_shader_parameter("scan_spacing_px", scan_spacing_px)
		target_effect_material.set_shader_parameter("scan_thickness_px", scan_thickness_px)
		target_effect_material.set_shader_parameter("scan_strength", scan_strength)
		target_effect_material.set_shader_parameter("grayscale_strength", grayscale_strength)
		target_effect_material.set_shader_parameter("nv_enabled", nv_mode_enabled)
		target_texture_rect.material = target_effect_material
		target_panel.add_child(target_texture_rect)
		# Dark placeholder avoids flashing debug color bars if the panel texture
		# captures an early frame before the target camera has updated.
		test_pattern_tex = _generate_dark_placeholder_texture(viewport_resolution)
		target_placeholder = TextureRect.new()
		target_placeholder.stretch_mode = TextureRect.STRETCH_SCALE  # Keep consistent with live feed
		target_placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target_placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
		target_placeholder.add_theme_constant_override("margin_left", 0)
		target_placeholder.add_theme_constant_override("margin_right", 0)
		target_placeholder.add_theme_constant_override("margin_top", 0)
		target_placeholder.add_theme_constant_override("margin_bottom", 0)
		target_placeholder.texture = test_pattern_tex
		target_placeholder.visible = false
		target_panel.add_child(target_placeholder)
		# Ensure placeholder sits behind/over depending on visibility ordering
		target_panel.move_child(target_placeholder, 0)
		
		# Create text overlay for enemy name and distance
		target_info_label = Label.new()
		target_info_label.name = "TargetInfoLabel"
		target_info_label.text = "NO TARGET"
		target_info_label.position = Vector2(5, 5)  # Top-left corner with small margin
		target_info_label.size = Vector2(185, 40)  # Fit within panel width, allow for 2 lines
		target_info_label.add_theme_color_override("font_color", Color.WHITE)
		target_info_label.add_theme_font_size_override("font_size", 12)
		target_info_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		target_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Add black outline for better visibility
		target_info_label.add_theme_color_override("font_outline_color", Color.BLACK)
		target_info_label.add_theme_constant_override("outline_size", 2)
		target_panel.add_child(target_info_label)
	
	# Force initial layout update to ensure consistent sizing
	call_deferred("_update_lower_layout_sizes")

func _update_lower_layout_sizes() -> void:
	if module_root != null:
		return
	# MANUAL LAYOUT: Fixed positioning, no dynamic calculations
	var lower := display_root.get_node_or_null("LowerRow") as Control
	if lower == null:
		return
	
	# Ensure panels maintain fixed positions and sizes
	if radar_panel:
		radar_panel.position = Vector2(0, 0)
		radar_panel.custom_minimum_size = Vector2(195, 195)
		radar_panel.size = Vector2(195, 195)
	if radar_canvas:
		radar_canvas.custom_minimum_size = Vector2(195, 195)
	if target_panel:
		target_panel.position = Vector2(205, 0)  # 195 + 10 separation
		target_panel.custom_minimum_size = Vector2(195, 195)
		target_panel.size = Vector2(195, 195)


func _build_module_panel() -> void:
	if display_root == null:
		return

	for child in display_root.get_children():
		var control := child as Control
		if control != null and control.name != "Background":
			control.visible = false

	if module_root != null and is_instance_valid(module_root):
		module_root.queue_free()
	module_root = Control.new()
	module_root.name = "ModulePanelRoot"
	module_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display_root.add_child(module_root)
	module_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	module_root.visible = true

	instrument_modules.clear()
	mfd_modules.clear()

	var layout := module_layout
	if layout.is_empty():
		layout = _default_module_layout()

	for entry in layout:
		var module := _create_module_from_layout(entry)
		if module == null:
			continue
		module_root.add_child(module)
		_position_module(module, entry)
		module.set_context(self, aircraft)
		instrument_modules.append(module)
		if module is MFDModule:
			mfd_modules.append(module as MFDModule)

	_attach_existing_display_views_to_mfds()
	_ensure_interaction_cursor()
	_update_instrument_modules(0.0)


func _ensure_interaction_cursor() -> void:
	if display_root == null:
		return
	if interaction_cursor != null and is_instance_valid(interaction_cursor):
		display_root.move_child(interaction_cursor, display_root.get_child_count() - 1)
		return

	interaction_cursor = Panel.new()
	interaction_cursor.name = "InteractionCursor"
	interaction_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_cursor.visible = false
	interaction_cursor.z_index = 100
	display_root.add_child(interaction_cursor)
	_update_interaction_cursor_style()


func _update_interaction_cursor_style() -> void:
	if interaction_cursor == null:
		return
	var radius := maxf(interaction_cursor_radius_px, 1.0)
	var style := StyleBoxFlat.new()
	style.bg_color = interaction_cursor_color
	style.border_color = interaction_cursor_outline_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = int(radius)
	style.corner_radius_top_right = int(radius)
	style.corner_radius_bottom_left = int(radius)
	style.corner_radius_bottom_right = int(radius)
	interaction_cursor.add_theme_stylebox_override("panel", style)
	interaction_cursor.size = Vector2.ONE * radius * 2.0


func _update_interaction_cursor() -> void:
	if not show_interaction_cursor:
		_set_interaction_cursor_visible(false)
		return
	if interaction_cursor == null or not is_instance_valid(interaction_cursor):
		_ensure_interaction_cursor()
	if interaction_cursor == null:
		return

	var active_camera := get_viewport().get_camera_3d()
	if active_camera == null or not is_instance_valid(active_camera):
		_set_interaction_cursor_visible(false)
		return
	if not _is_panel_aircraft_currently_viewed():
		_set_interaction_cursor_visible(false)
		return

	var point_variant: Variant = _project_camera_to_panel_point(active_camera, 2.5)
	if point_variant == null:
		_set_interaction_cursor_visible(false)
		return
	var point: Vector2 = point_variant

	var radius := maxf(interaction_cursor_radius_px, 1.0)
	interaction_cursor.size = Vector2.ONE * radius * 2.0
	interaction_cursor.position = Vector2(
		clampf(point.x - radius, 0.0, maxf(float(viewport_resolution.x) - radius * 2.0, 0.0)),
		clampf(point.y - radius, 0.0, maxf(float(viewport_resolution.y) - radius * 2.0, 0.0))
	)
	_set_interaction_cursor_visible(true)


func _set_interaction_cursor_visible(is_visible: bool) -> void:
	if interaction_cursor != null and is_instance_valid(interaction_cursor):
		interaction_cursor.visible = is_visible


func _default_module_layout() -> Array[Dictionary]:
	return [
		{
			"type": "warning_lights",
			"id": "warning_strip",
			"title": "WARNINGS",
			"rect": Rect2(10, 8, 780, 54),
			"lights": ["ENGINE", "WEAPONS", "CONTROLS", "GEAR", "STALL", "MISSILE"],
		},
		{
			"type": "mfd",
			"id": "mfd_left",
			"title": "MFD L",
			"rect": Rect2(10, 72, 270, 270),
			"modes": ["MAP", "WEAPONS", "DAMAGE", "SYSTEMS"],
		},
		{
			"type": "mfd",
			"id": "mfd_right",
			"title": "MFD R",
			"rect": Rect2(520, 72, 270, 270),
			"modes": ["TARGET", "MAP", "WEAPONS", "DAMAGE", "SYSTEMS"],
		},
		{"type": "readout", "id": "speed", "title": "SPEED", "instrument": "speed", "rect": Rect2(294, 72, 100, 62)},
		{"type": "readout", "id": "altitude", "title": "ALT", "instrument": "altitude", "rect": Rect2(406, 72, 100, 62)},
		{"type": "readout", "id": "vertical_speed", "title": "V/S", "instrument": "vertical_speed", "rect": Rect2(294, 144, 100, 62)},
		{"type": "readout", "id": "fuel", "title": "FUEL", "instrument": "fuel", "rect": Rect2(406, 144, 100, 62)},
		{"type": "readout", "id": "gear", "title": "GEAR", "instrument": "gear", "rect": Rect2(294, 216, 100, 62)},
		{"type": "readout", "id": "flaps", "title": "FLAPS", "instrument": "flaps", "rect": Rect2(406, 216, 100, 62)},
		{"type": "readout", "id": "stall", "title": "STALL", "instrument": "stall", "rect": Rect2(294, 288, 100, 54)},
		{"type": "readout", "id": "missile_lock", "title": "M LOCK", "instrument": "missile_lock", "rect": Rect2(406, 288, 100, 54)},
		{"type": "slip_ball", "id": "slip_ball", "title": "BALL", "rect": Rect2(10, 356, 270, 78)},
		{"type": "readout", "id": "engine", "title": "ENGINE", "instrument": "engine", "rect": Rect2(294, 356, 100, 78)},
		{"type": "readout", "id": "damage", "title": "STRUCT", "instrument": "damage", "rect": Rect2(406, 356, 100, 78)},
		{"type": "readout", "id": "g_force", "title": "G", "instrument": "g_force", "rect": Rect2(520, 356, 128, 78)},
		{"type": "readout", "id": "weapons", "title": "WEAPONS", "instrument": "weapons", "rect": Rect2(662, 356, 128, 78)},
	]


func _create_module_from_layout(entry: Dictionary) -> InstrumentModule:
	var module_type := str(entry.get("type", "readout"))
	var module: InstrumentModule = null
	match module_type:
		"mfd":
			module = MFD_MODULE_SCRIPT.new()
		"warning_lights":
			module = WARNING_LIGHT_MODULE_SCRIPT.new()
		"slip_ball":
			module = SLIP_BALL_MODULE_SCRIPT.new()
		"readout":
			module = TEXT_MODULE_SCRIPT.new()
		_:
			push_warning("Unknown instrument module type: %s" % module_type)
			return null
	module.configure(entry)
	return module


func _position_module(module: Control, entry: Dictionary) -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(100.0, 60.0))
	if entry.has("rect"):
		rect = entry.get("rect")
	module.position = rect.position
	module.custom_minimum_size = rect.size
	module.size = rect.size


func _attach_existing_display_views_to_mfds() -> void:
	if mfd_modules.is_empty():
		return

	var map_attached := false
	if radar_panel != null and is_instance_valid(radar_panel):
		for mfd in mfd_modules:
			if mfd.available_modes.has("MAP"):
				mfd.add_mode_view("MAP", radar_panel)
				map_attached = true
				break
	if not map_attached and radar_panel != null:
		radar_panel.visible = false

	var target_attached := false
	if target_panel != null and is_instance_valid(target_panel):
		for mfd in mfd_modules:
			if mfd.module_id == "mfd_right" and mfd.available_modes.has("TARGET"):
				mfd.add_mode_view("TARGET", target_panel)
				target_attached = true
				break
		if not target_attached:
			for mfd in mfd_modules:
				if mfd.available_modes.has("TARGET"):
					mfd.add_mode_view("TARGET", target_panel)
					target_attached = true
					break
	if not target_attached and target_panel != null:
		target_panel.visible = false


func _update_instrument_modules(delta: float) -> void:
	for module in instrument_modules:
		if module != null and is_instance_valid(module):
			module.update_from_aircraft(delta)


func interact_from_camera(camera: Camera3D, max_distance_m: float = 2.5) -> bool:
	if camera == null or not is_instance_valid(camera):
		return false
	var point_variant: Variant = _project_camera_to_panel_point(camera, max_distance_m)
	if point_variant == null:
		return false
	var point: Vector2 = point_variant
	return interact_at_panel_point(point)


func interact_from_ray(ray_origin: Vector3, ray_direction: Vector3, max_distance_m: float = 2.5) -> bool:
	var point_variant: Variant = _project_ray_to_panel_point(ray_origin, ray_direction, max_distance_m)
	if point_variant == null:
		return false
	var point: Vector2 = point_variant
	return interact_at_panel_point(point)


func _project_camera_to_panel_point(camera: Camera3D, max_distance_m: float = 2.5) -> Variant:
	if camera == null or not is_instance_valid(camera):
		return null
	return _project_ray_to_panel_point(
		camera.global_position,
		-camera.global_transform.basis.z.normalized(),
		max_distance_m
	)


func _project_ray_to_panel_point(ray_origin: Vector3, ray_direction: Vector3, max_distance_m: float = 2.5) -> Variant:
	if ray_direction.length_squared() <= 0.0001:
		return null
	if render_to_model_surface and model_panel_mesh != null and is_instance_valid(model_panel_mesh):
		var model_point: Variant = _project_ray_to_model_panel_point(ray_origin, ray_direction, max_distance_m)
		if model_point != null:
			return model_point
	var inv := global_transform.affine_inverse()
	var local_origin := inv * ray_origin
	var local_dir := inv.basis * ray_direction.normalized()
	if absf(local_dir.z) <= 0.0001:
		return null
	var t := -local_origin.z / local_dir.z
	if t < 0.0:
		return null
	var hit := local_origin + local_dir * t
	var world_hit := global_transform * hit
	if ray_origin.distance_to(world_hit) > max_distance_m:
		return null
	if absf(hit.x) > panel_size.x * 0.5 or absf(hit.y) > panel_size.y * 0.5:
		return null
	var uv := Vector2((hit.x / panel_size.x) + 0.5, 0.5 - (hit.y / panel_size.y))
	return Vector2(
		clampf(uv.x, 0.0, 1.0) * float(viewport_resolution.x),
		clampf(uv.y, 0.0, 1.0) * float(viewport_resolution.y)
	)


func _project_ray_to_model_panel_point(ray_origin: Vector3, ray_direction: Vector3, max_distance_m: float) -> Variant:
	var mesh_instance := model_panel_mesh
	if mesh_instance == null or not is_instance_valid(mesh_instance):
		return null
	var mesh := mesh_instance.mesh
	if mesh == null:
		return null
	var inv := mesh_instance.global_transform.affine_inverse()
	var local_origin := inv * ray_origin
	var local_dir := inv.basis * ray_direction.normalized()
	if local_dir.length_squared() <= 0.0001:
		return null
	local_dir = local_dir.normalized()
	var closest_t := INF
	var found := false
	for surface_index in model_panel_surface_indices:
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for vertex_index in range(0, vertices.size() - 2, 3):
				var direct_t := _ray_triangle_t(local_origin, local_dir, vertices, vertex_index, vertex_index + 1, vertex_index + 2)
				if is_inf(direct_t):
					continue
				if direct_t < closest_t:
					closest_t = direct_t
					found = true
		else:
			for index_offset in range(0, indices.size() - 2, 3):
				var indexed_t := _ray_triangle_t(local_origin, local_dir, vertices, indices[index_offset], indices[index_offset + 1], indices[index_offset + 2])
				if is_inf(indexed_t):
					continue
				if indexed_t < closest_t:
					closest_t = indexed_t
					found = true
	if not found:
		return null
	var local_hit := local_origin + local_dir * closest_t
	var world_hit := mesh_instance.global_transform * local_hit
	if ray_origin.distance_to(world_hit) > max_distance_m:
		return null
	var rect_size := Vector2(maxf(model_panel_local_rect.size.x, 0.0001), maxf(model_panel_local_rect.size.y, 0.0001))
	var panel_uv := Vector2(
		(local_hit.x - model_panel_local_rect.position.x) / rect_size.x,
		1.0 - ((local_hit.y - model_panel_local_rect.position.y) / rect_size.y)
	)
	return Vector2(
		clampf(panel_uv.x, 0.0, 1.0) * float(viewport_resolution.x),
		clampf(panel_uv.y, 0.0, 1.0) * float(viewport_resolution.y)
	)


func _ray_triangle_t(
	origin: Vector3,
	direction: Vector3,
	vertices: PackedVector3Array,
	i0: int,
	i1: int,
	i2: int
) -> float:
	if i0 < 0 or i1 < 0 or i2 < 0:
		return INF
	if i0 >= vertices.size() or i1 >= vertices.size() or i2 >= vertices.size():
		return INF
	var a := vertices[i0]
	var b := vertices[i1]
	var c := vertices[i2]
	var edge1 := b - a
	var edge2 := c - a
	var pvec := direction.cross(edge2)
	var det := edge1.dot(pvec)
	if absf(det) <= 0.000001:
		return INF
	var inv_det := 1.0 / det
	var tvec := origin - a
	var u := tvec.dot(pvec) * inv_det
	if u < 0.0 or u > 1.0:
		return INF
	var qvec := tvec.cross(edge1)
	var v := direction.dot(qvec) * inv_det
	if v < 0.0 or u + v > 1.0:
		return INF
	var t := edge2.dot(qvec) * inv_det
	if t < 0.0:
		return INF
	return t


func interact_at_panel_uv(uv: Vector2) -> bool:
	var point := Vector2(
		clampf(uv.x, 0.0, 1.0) * float(viewport_resolution.x),
		clampf(uv.y, 0.0, 1.0) * float(viewport_resolution.y)
	)
	return interact_at_panel_point(point)


func interact_at_panel_point(point_px: Vector2) -> bool:
	for i in range(instrument_modules.size() - 1, -1, -1):
		var module := instrument_modules[i]
		if module == null or not is_instance_valid(module) or not module.visible:
			continue
		var rect := Rect2(module.position, module.size)
		if rect.has_point(point_px):
			return module.interact(point_px - module.position)
	return false

func _compute_top_row_content_width() -> float:
	var tr := display_root.get_node_or_null("TopRow") as HBoxContainer
	if tr == null:
		return 0.0
	var sep: float = tr.get_theme_constant("separation")
	var total: float = 0.0
	var count: int = 0
	for c in tr.get_children():
		if c is Control and (c as Control).visible:
			total += (c as Control).get_combined_minimum_size().x
			count += 1
	if count > 1:
		total += sep * float(count - 1)
	return total


func _draw_radar():
	pass

func _get_target_camera_rest_global_transform() -> Transform3D:
	if aircraft != null and is_instance_valid(aircraft):
		return _get_node_visual_transform(aircraft) * _camera_target_rest_transform
	if camera_target != null and is_instance_valid(camera_target):
		return _get_node_visual_transform(camera_target)
	return Transform3D.IDENTITY

func _get_node_visual_transform(node: Node3D) -> Transform3D:
	if node == null or not is_instance_valid(node):
		return Transform3D.IDENTITY
	return node.get_global_transform_interpolated()

func _get_node_visual_position(node: Node3D) -> Vector3:
	return _get_node_visual_transform(node).origin

func _slew_target_camera_look_at(desired_pos: Vector3, focus_pos: Vector3, delta: float) -> void:
	if target_camera == null or not is_instance_valid(target_camera):
		return
	if desired_pos.distance_squared_to(focus_pos) <= 0.0001:
		return
	var desired_xform := Transform3D(Basis(), desired_pos).looking_at(focus_pos, Vector3.UP)
	_slew_target_camera_to_transform(desired_xform, delta)

func _slew_target_camera_to_transform(desired_xform: Transform3D, delta: float) -> void:
	if target_camera == null or not is_instance_valid(target_camera):
		return
	if not _target_camera_pose_initialized:
		target_camera.global_transform = desired_xform
		_target_camera_pose_initialized = true
		return
	# Position must stay rigid to the aircraft/mount; smoothing it causes the
	# target feed to lag into the plane during hard manoeuvres.
	target_camera.global_position = desired_xform.origin
	target_camera.global_transform.basis = _slew_basis_toward(
		target_camera.global_transform.basis,
		desired_xform.basis,
		target_camera_slew_deg_s,
		delta
	)

func _slew_basis_toward(from_basis: Basis, to_basis: Basis, max_deg_s: float, delta: float) -> Basis:
	var from_q := from_basis.orthonormalized().get_rotation_quaternion()
	var to_q := to_basis.orthonormalized().get_rotation_quaternion()
	var angle := from_q.angle_to(to_q)
	if angle <= 0.0001:
		return to_basis.orthonormalized()
	var max_step := deg_to_rad(maxf(max_deg_s, 1.0)) * maxf(delta, 0.0)
	var blend := clampf(max_step / angle, 0.0, 1.0)
	return Basis(from_q.slerp(to_q, blend)).orthonormalized()

func _slew_target_camera_fov(desired_fov_deg: float, delta: float) -> void:
	if target_camera == null or not is_instance_valid(target_camera):
		return
	var blend := _smooth_blend(target_camera_zoom_lerp_speed, delta)
	target_camera.fov = lerpf(target_camera.fov, desired_fov_deg, blend)

func _ensure_target_view_camera_current() -> void:
	if target_viewport == null or not is_instance_valid(target_viewport):
		return
	if target_camera == null or not is_instance_valid(target_camera):
		return
	if target_viewport.get_camera_3d() == target_camera:
		return
	target_camera.current = true

func _smooth_blend(speed: float, delta: float) -> float:
	return clampf(1.0 - exp(-maxf(speed, 0.0) * maxf(delta, 0.0)), 0.0, 1.0)


func _relayout_top_row() -> void:
	var display := $SubViewport/InstrumentDisplay as Control
	if display == null:
		return
	var top_row := display.get_node_or_null("TopRow") as HBoxContainer
	if top_row == null:
		top_row = HBoxContainer.new()
		top_row.name = "TopRow"
		display.add_child(top_row)
		# Anchor to top, full width, fixed small height
		top_row.anchor_left = 0.0
		top_row.anchor_right = 1.0
		top_row.anchor_top = 0.0
		top_row.anchor_bottom = 0.0
		top_row.offset_top = 4
		top_row.offset_bottom = 44
		top_row.alignment = BoxContainer.ALIGNMENT_CENTER
		top_row.add_theme_constant_override("separation", 12)  # Reduced from 16 to fit 6 indicators
	
	# Create STRUCT label if it doesn't exist
	if struct_label == null:
		struct_label = Label.new()
		struct_label.text = "STRUCT\n100"
		struct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		struct_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Reparent labels into the top row and make them expand evenly
	# Now includes 6 indicators: ALT, SPD, FUEL, GEAR, ENG, STRUCT
	var labels: Array = [altitude_label, speed_label, fuel_label, gear_label, engine_label, struct_label]
	for l in labels:
		if l != null and l.get_parent() != top_row:
			var p: Node = l.get_parent()
			if p:
				p.remove_child(l)
			top_row.add_child(l)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Hide legacy panels to remove gray boxes
	for pname in ["AltitudePanel", "SpeedPanel", "FuelPanel", "GearPanel", "EnginePanel"]:
		var panel := display.get_node_or_null(pname) as Control
		if panel:
			panel.visible = false


func _find_targeting_module():
	if aircraft == null:
		return null
	var modules = aircraft.find_modules_by_type("targeting")
	for module in modules:
		if module != null and (not (module is Object) or is_instance_valid(module)):
			return module
	return null

func _get_targeting_current_target(targeting) -> Node3D:
	if targeting == null:
		return null
	if targeting is Object and not is_instance_valid(targeting):
		return null
	if not ("current_target" in targeting):
		return null
	var raw_target = targeting.current_target
	if raw_target == null or not is_instance_valid(raw_target):
		if raw_target != null:
			targeting.current_target = null
		return null
	if not (raw_target is Node3D):
		return null
	return raw_target as Node3D

func _get_enemy_target_node() -> Node3D:
	var targeting = _find_targeting_module()
	return _get_targeting_current_target(targeting)

func _is_gear_down() -> bool:
	if aircraft == null or not is_instance_valid(aircraft):
		return false
	var gear_modules: Array = aircraft.find_modules_by_type("landing_gear")
	if gear_modules.size() > 0:
		var gear: Node = gear_modules[0] as Node
		if gear != null and is_instance_valid(gear) and "is_deployed" in gear:
			return bool(gear.get("is_deployed"))
	return false

func _has_retractable_landing_gear() -> bool:
	if aircraft == null or not is_instance_valid(aircraft):
		return false
	var gear_modules: Array = aircraft.find_modules_by_type("landing_gear")
	for gear_variant in gear_modules:
		var gear: Node = gear_variant as Node
		if gear == null or not is_instance_valid(gear):
			continue
		if "lock_deployed" in gear and bool(gear.get("lock_deployed")):
			continue
		return true

	var control_gear: Node = aircraft.find_child("ControlLandingGear", true, false)
	if control_gear != null and is_instance_valid(control_gear):
		if "LockGearDeployed" in control_gear and bool(control_gear.get("LockGearDeployed")):
			return false
	return false

func _should_show_landing_camera_target() -> bool:
	return _is_gear_down() and _has_retractable_landing_gear()

func _get_nearest_landing_target() -> Node3D:
	if aircraft == null or not is_instance_valid(aircraft):
		return null
	var best: Node3D = null
	var best_dist: float = INF
	var pos: Vector3 = aircraft.global_position
	for node in get_tree().get_nodes_in_group("carrier"):
		if node is Node3D:
			var d: float = (node as Node3D).global_position.distance_to(pos)
			if d < best_dist:
				best_dist = d
				best = node as Node3D
	return best

func _get_active_display_target() -> Node3D:
	if _should_show_landing_camera_target():
		var landing_tgt := _get_nearest_landing_target()
		if landing_tgt != null:
			return landing_tgt
	return _get_enemy_target_node()

func _get_target_camera_focus() -> Dictionary:
	var now_s: float = Time.get_ticks_msec() / 1000.0
	var live_target := _get_active_display_target()
	if live_target != null and is_instance_valid(live_target):
		_clear_destroyed_target_hold()
		_watch_display_target(live_target)
		var live_target_pos := _get_node_visual_position(live_target)
		_last_display_target_position = live_target_pos
		_last_display_target_name = live_target.name
		return {
			"target": live_target,
			"position": live_target_pos,
			"name": live_target.name,
			"destroyed": false,
		}

	if _watched_display_target != null and not is_instance_valid(_watched_display_target):
		_begin_destroyed_target_hold(_last_display_target_position, _last_display_target_name)
		_watched_display_target = null

	if _is_destroyed_target_hold_active(now_s):
		return {
			"target": null,
			"position": _destroyed_target_hold_position,
			"name": _destroyed_target_hold_name,
			"destroyed": true,
		}

	if _destroyed_target_hold_until_s > -INF:
		_clear_destroyed_target_hold()
		_advance_target_after_destroy_hold()
	return {}

func _watch_display_target(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target == _watched_display_target:
		return
	_unwatch_display_target()
	_watched_display_target = target
	if target.has_signal("destroyed"):
		var destroyed_cb := _on_display_target_destroyed.bind(target)
		if not target.destroyed.is_connected(destroyed_cb):
			target.destroyed.connect(destroyed_cb)
	var exiting_cb := _on_display_target_tree_exiting.bind(target)
	if not target.tree_exiting.is_connected(exiting_cb):
		target.tree_exiting.connect(exiting_cb)

func _unwatch_display_target() -> void:
	if _watched_display_target == null or not is_instance_valid(_watched_display_target):
		_watched_display_target = null
		return
	if _watched_display_target.has_signal("destroyed"):
		var destroyed_cb := _on_display_target_destroyed.bind(_watched_display_target)
		if _watched_display_target.destroyed.is_connected(destroyed_cb):
			_watched_display_target.destroyed.disconnect(destroyed_cb)
	var exiting_cb := _on_display_target_tree_exiting.bind(_watched_display_target)
	if _watched_display_target.tree_exiting.is_connected(exiting_cb):
		_watched_display_target.tree_exiting.disconnect(exiting_cb)
	_watched_display_target = null

func _on_display_target_destroyed(arg0: Variant = null, arg1: Variant = null) -> void:
	var watched_target: Node3D = null
	if arg1 is Node3D:
		watched_target = arg1 as Node3D
	elif arg0 is Node3D:
		watched_target = arg0 as Node3D
	var target := watched_target if watched_target != null and is_instance_valid(watched_target) else _watched_display_target
	var hold_position := _last_display_target_position
	var hold_name := _last_display_target_name
	if target != null and is_instance_valid(target):
		hold_position = _get_node_visual_position(target)
		hold_name = target.name
	_begin_destroyed_target_hold(hold_position, hold_name)

func _on_display_target_tree_exiting(watched_target: Node3D = null) -> void:
	if _is_destroyed_target_hold_active():
		return
	var target := watched_target if watched_target != null and is_instance_valid(watched_target) else _watched_display_target
	var hold_position := _last_display_target_position
	var hold_name := _last_display_target_name
	if target != null and is_instance_valid(target):
		hold_position = _get_node_visual_position(target)
		hold_name = target.name
	_begin_destroyed_target_hold(hold_position, hold_name)

func _begin_destroyed_target_hold(position: Vector3, target_name: String) -> void:
	if target_name.is_empty():
		target_name = "TARGET"
	_destroyed_target_hold_position = position
	_destroyed_target_hold_name = target_name
	_destroyed_target_hold_until_s = Time.get_ticks_msec() / 1000.0 + maxf(destroyed_target_hold_s, 0.0)

func _is_destroyed_target_hold_active(now_s: float = NAN) -> bool:
	if is_nan(now_s):
		now_s = Time.get_ticks_msec() / 1000.0
	return _destroyed_target_hold_until_s > now_s

func _clear_destroyed_target_hold() -> void:
	_destroyed_target_hold_until_s = -INF
	_destroyed_target_hold_name = ""

func _advance_target_after_destroy_hold() -> void:
	var targeting = _find_targeting_module()
	if targeting != null and is_instance_valid(targeting) and targeting.has_method("target_next"):
		targeting.target_next()

func is_target_camera_focusing_node(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if missile_camera_mode:
		return false
	if aircraft == null or not is_instance_valid(aircraft):
		return false
	if target_camera == null or not is_instance_valid(target_camera):
		return false
	if not _is_panel_aircraft_currently_viewed():
		return false

	var focus_target := _get_enemy_target_node()
	if focus_target == null or not is_instance_valid(focus_target):
		return false
	return _node_matches_focus(node, focus_target)

func _is_panel_aircraft_currently_viewed() -> bool:
	if aircraft == null or not is_instance_valid(aircraft):
		return false
	var active_camera := get_viewport().get_camera_3d()
	if active_camera == null or not is_instance_valid(active_camera):
		return false
	var camera_mount := active_camera.get_parent()
	if camera_mount == null or camera_mount.name != "CameraCockpit":
		return false
	return _node_is_same_or_descendant(active_camera, aircraft)

func _node_matches_focus(candidate: Node, focus_target: Node) -> bool:
	return _node_is_same_or_descendant(candidate, focus_target) or _node_is_same_or_descendant(focus_target, candidate)

func _node_is_same_or_descendant(node: Node, ancestor: Node) -> bool:
	var current: Node = node
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false

func _create_target_effect_shader() -> Shader:
	var code := """
shader_type canvas_item;
uniform vec2 texture_size = vec2(400.0, 300.0);
uniform float scan_spacing_px = 3.0;
uniform float scan_thickness_px = 1.0;
uniform float scan_strength = 0.35;
uniform float grayscale_strength = 1.0;
uniform bool nv_enabled = false;
uniform float nv_gain = 8.0;
uniform float nv_gamma = 0.45;
uniform float nv_noise = 0.10;

float nv_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float y_px = UV.y * texture_size.y;
	float spacing = max(scan_spacing_px, 0.0001);
	float tr = clamp(scan_thickness_px / spacing, 0.0, 1.0);
	float f = fract(y_px / spacing);
	float band = 1.0 - step(tr, f);
	if (nv_enabled) {
		float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		lum = 1.0 - exp(-lum * nv_gain);
		lum = pow(lum, nv_gamma);
		lum *= mix(1.0, 1.0 - scan_strength, band);
		float grain = nv_hash(UV + vec2(TIME * 0.013, TIME * 0.007));
		lum += (grain * 2.0 - 1.0) * nv_noise;
		lum = max(lum, 0.0);
		COLOR = vec4(lum * 0.10, lum * 1.00, lum * 0.18, c.a);
	} else {
		float gray = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		c.rgb = mix(c.rgb, vec3(gray), grayscale_strength);
		c.rgb = mix(c.rgb, c.rgb * (1.0 - scan_strength), band);
		COLOR = c;
	}
}
"""
	var sh := Shader.new()
	sh.code = code
	return sh

func set_nv_mode(enabled: bool) -> void:
	nv_mode_enabled = enabled
	if target_effect_material != null:
		target_effect_material.set_shader_parameter("nv_enabled", nv_mode_enabled)

func _update_missile_camera() -> void:
	"""Update camera to use missile's built-in nose camera"""
	if not is_instance_valid(tracked_missile):
		# Missile was destroyed, exit missile camera mode
		missile_camera_mode = false
		tracked_missile = null
		return
	
	# Find the missile's nose camera
	var missile_nose_camera = tracked_missile.find_child("NoseCamera", true, false) as Camera3D
	if missile_nose_camera and is_instance_valid(missile_nose_camera):
		# Use missile camera position but create level-horizon orientation
		target_camera.global_position = missile_nose_camera.global_position
		target_camera.fov = missile_nose_camera.fov
		
		# Get missile forward direction and preserve pitch but eliminate roll
		var missile_forward = -missile_nose_camera.global_transform.basis.z.normalized()
		# Keep the full forward direction (including up/down component for pitch)
		var forward = missile_forward
		# Use world up vector and project it perpendicular to forward for level "wings"
		var up = Vector3.UP
		var right = forward.cross(up).normalized()
		# Recalculate up to ensure it's perpendicular to both forward and right (eliminates roll)
		up = right.cross(forward).normalized()
		
		# Create basis with pitch but no roll (wings always level)
		target_camera.global_transform.basis = Basis(right, up, -forward)
	else:
		# Fallback to manual calculation if no nose camera found
		var missile_transform = tracked_missile.global_transform
		var missile_forward = -missile_transform.basis.z.normalized()
		var camera_offset = missile_forward * 2.0
		target_camera.global_position = missile_transform.origin + camera_offset
		
		# Apply wings-level to fallback as well (preserve pitch, eliminate roll)
		var forward = missile_forward
		var up = Vector3.UP
		var right = forward.cross(up).normalized()
		up = right.cross(forward).normalized()
		target_camera.global_transform.basis = Basis(right, up, -forward)
	
	# Hide placeholder since we have active camera feed
	if target_placeholder:
		target_placeholder.visible = false
	
	# Update info label with missile status
	if target_info_label and is_instance_valid(aircraft):
		var missile_speed = 0.0
		if tracked_missile.has_method("get_linear_velocity"):
			missile_speed = tracked_missile.get_linear_velocity().length()
		elif "linear_velocity" in tracked_missile:
			missile_speed = tracked_missile.linear_velocity.length()
		
		target_info_label.text = "MISSILE CAM\n" + str(int(missile_speed)) + " m/s"

func start_missile_camera_tracking(missile: Node3D) -> void:
	"""Switch target view to follow the missile camera"""
	if not is_instance_valid(missile):
		return
	
	print("Starting missile camera tracking for: ", missile.name)
	missile_camera_mode = true
	tracked_missile = missile
	
	# Connect to missile destruction signal to stop tracking when it hits
	if missile.has_signal("tree_exiting"):
		missile.tree_exiting.connect(_on_missile_destroyed)
	elif missile.has_signal("destroyed"):
		missile.destroyed.connect(_on_missile_destroyed)
	
	# Update target info label
	if target_info_label:
		target_info_label.text = "MISSILE CAM\nGUIDANCE VIEW"

func _on_missile_destroyed():
	"""Called when tracked missile is destroyed, return to normal target view"""
	print("Missile destroyed, returning to normal target view")
	missile_camera_mode = false
	tracked_missile = null
	# Target info will be updated in normal _process loop

func _generate_dark_placeholder_texture(size_px: Vector2i) -> Texture2D:
	var width: int = max(8, size_px.x)
	var height: int = max(8, size_px.y)
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.01, 0.035, 0.018, 1.0))
	return ImageTexture.create_from_image(img)
