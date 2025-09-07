extends Node3D
# InstrumentPanel.gd - Virtual cockpit instrument display

@export var aircraft_path: NodePath
@export var panel_size: Vector2 = Vector2(0.4, 0.3)  # Size in meters (40cm x 30cm)
@export var viewport_resolution: Vector2i = Vector2i(400, 300)

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
	var material = StandardMaterial3D.new()
	material.flags_unshaded = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = viewport.get_texture()
	material.emission_enabled = true
	material.emission_texture = viewport.get_texture()
	material.emission_energy = 2.0
	panel_mesh.material_override = material
	
	print("Instrument Panel initialized")

func _process(_delta: float) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	
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
	var gear_modules = aircraft.find_modules_by_type("landingGear")
	if gear_modules.size() > 0:
		var gear = gear_modules[0]
		if gear.gear_position >= 0.9:
			gear_label.text = "GEAR\nDOWN"
			gear_label.modulate = Color.GREEN
		elif gear.gear_position <= 0.1:
			gear_label.text = "GEAR\nUP"
			gear_label.modulate = Color.WHITE
		else:
			gear_label.text = "GEAR\nMOVING"
			gear_label.modulate = Color.YELLOW
	else:
		gear_label.text = "GEAR\nN/A"
		gear_label.modulate = Color.GRAY
	
	# Update engine status
	var engine_modules = aircraft.find_modules_by_type("engine")
	if engine_modules.size() > 0:
		var engine = engine_modules[0]
		if engine.is_engine_working:
			var power_percent = int(engine.current_power * 100)
			engine_label.text = "ENG\n" + str(power_percent) + "%"
			engine_label.modulate = Color.GREEN
		else:
			engine_label.text = "ENG\nOFF"
			engine_label.modulate = Color.RED
	else:
		engine_label.text = "ENG\nN/A"
		engine_label.modulate = Color.GRAY
