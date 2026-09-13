extends Node3D
## Run the accompanying scene: B sips; W toggles walking.
var officer: Node3D
var camera: Camera3D
var walking := false

func _ready() -> void:
	officer = load("res://Models/Characters/OfficerFemaleCoffee.tscn").instantiate()
	add_child(officer)
	var world = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.09,0.115,0.15)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.8,0.86,1)
	world.environment.ambient_light_energy = 0.65
	add_child(world)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-35,0)
	light.light_energy = 1.5
	add_child(light)
	var floor_mesh = MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(200,200)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.12,0.15,0.18)
	material.roughness = 0.9
	floor_mesh.material_override = material
	add_child(floor_mesh)
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.position = Vector3(-2.4,2.1,4)
	camera.look_at(Vector3(0,0.95,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.15
	camera.current = true
	var label = Label.new()
	label.text = "B: sip coffee    W: toggle carrying walk"
	label.position = Vector2(24,24)
	add_child(label)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_B:
		officer.play_sip()
	elif event.physical_keycode == KEY_W:
		walking = not walking
		officer.set_walking(walking)
