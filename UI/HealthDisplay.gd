extends Control
class_name HealthDisplay

@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel

var aircraft: Node3D

func _ready():
	# Find the aircraft
	aircraft = get_tree().get_first_node_in_group("aircraft")
	
	if aircraft:
		# Connect to aircraft damage signal
		aircraft.connect("damaged", Callable(self, "_on_aircraft_damaged"))
		aircraft.connect("destroyed", Callable(self, "_on_aircraft_destroyed"))
		
		# Initialize display
		update_health_display()
	else:
		print("HealthDisplay: No aircraft found!")

func _on_aircraft_damaged(damage_amount: float, current_health: float):
	update_health_display()

func _on_aircraft_destroyed():
	health_label.text = "DESTROYED!"
	health_bar.value = 0

func update_health_display():
	if not aircraft:
		return
	
	var health_percentage = aircraft.current_health / aircraft.max_health
	health_bar.value = health_percentage * 100
	
	health_label.text = "Health: " + str(int(aircraft.current_health)) + "/" + str(int(aircraft.max_health))
	
	# Change color based on health
	if health_percentage > 0.6:
		health_bar.modulate = Color.GREEN
	elif health_percentage > 0.3:
		health_bar.modulate = Color.YELLOW
	else:
		health_bar.modulate = Color.RED



