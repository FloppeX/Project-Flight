extends SceneTree

const GUNS := preload("res://Weapons/Turrets/TurretGunCatalog.gd")
const WEAPONS := [
	"res://Weapons/Turrets/bullet_weapon.tscn",
	"res://Weapons/Turrets/bullet_weapon_15mm.tscn",
	"res://Weapons/Turrets/bullet_weapon_20mm.tscn",
	"res://Weapons/Turrets/heavy_gun_weapon.tscn",
	"res://Weapons/Turrets/40mm_autocannon_weapon.tscn",
]
const TURRETS := [
	"res://Weapons/Turrets/friendly_turret.tscn",
	"res://Weapons/Turrets/turret.tscn",
	"res://Weapons/Turrets/vehicle_lmg_turret.tscn",
	"res://Weapons/Turrets/vehicle_heavy_gun_turret.tscn",
	"res://Weapons/Turrets/helicopter_side_gun_turret.tscn",
]

class TeamHost extends Node3D:
	var team := 1
	func get_team() -> int:
		return team

var failures: Array[String] = []
var livery: Node
var paint_count := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func run() -> void:
	await process_frame
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_node("SaveGameManager").set("autosave_enabled", false)
	var pause := root.get_node("PauseMenu")
	pause.set("_display_mode_index", 0)
	pause.set("_resolution_index", 1)
	livery = root.get_node("Livery")
	livery.call("set_player_livery", Color("2876a8"), Color("e9c85b"), 4)
	livery.get("_team_upper_preset_indices")[2] = 4
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var hosts: Array[TeamHost] = []
	var controllers: Array[Node3D] = []
	for team in [1, 2]:
		var host := TeamHost.new()
		host.team = team
		host.position.z = (team - 1) * 7.0
		host.process_mode = Node.PROCESS_MODE_DISABLED
		world.add_child(host)
		host.add_to_group("carrier")
		hosts.append(host)
		# Give the same host personal pilot paint; turret slots must still use team paint.
		var pilot := Node3D.new()
		pilot.name = "CockpitPilot"
		host.add_child(pilot)
		var suit := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.resource_name = "Main_Color.002"
		mesh.material = material
		suit.mesh = mesh
		pilot.add_child(suit)
		pilot.hide()
		host.set_meta("pilot_livery_colors", {
			"main_color": Color("ca48a6"), "main_color_dark": Color("461633"),
			"helmet_color_1": Color.WHITE, "helmet_color_2": Color.BLACK,
		})
		# Apply before building to reproduce the carrier's initially empty build sites.
		livery.call("apply", host)
		var site := (load("res://LandCarrier/CarrierDefenseTurretPosition.tscn") as PackedScene).instantiate()
		host.add_child(site)
		check(site.build_turret(20), "build turret after host livery")
		validate(site.built_turret, team, "new build")
		site.hide()
		for index in TURRETS.size():
			var controller := (load("res://Weapons/Turrets/turret_controller.gd") as Script).new() as Node3D
			# Deliberately opposite: targeting and paint must both inherit the host.
			controller.team = 3 - team
			controller.position.x = (index - 2) * 4.5
			var turret := (load(TURRETS[index]) as PackedScene).instantiate() as Turret
			controller.add_child(turret)
			controller.weapon_scene = load(WEAPONS[2])
			host.add_child(controller)
			controllers.append(controller)
			validate(controller, team, "startup " + TURRETS[index])
			for weapon in WEAPONS:
				controller.mount_weapon(load(weapon))
				validate(controller, team, "swap " + weapon)
			var label := Label3D.new()
			label.text = ["Angular", "Round", "Light receiver", "Heavy receiver", "Side gun"][index]
			label.position = controller.position + Vector3(0, 2.7, 0)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 40
			host.add_child(label)
		livery.call("apply", host)
		check(suit.get_active_material(0).albedo_color.is_equal_approx(Color("ca48a6")), "pilot suit retains personal colour")
		for controller in controllers:
			if host.is_ancestor_of(controller):
				validate(controller, team, "parent apply with pilot palette")
	# A controller without a host must use its configured team and refresh too.
	var standalone := (load("res://LandCarrier/CarrierDefenseTurretAssembly.tscn") as PackedScene).instantiate() as Node3D
	standalone.team = 2
	world.add_child(standalone)
	standalone.hide()
	validate(standalone, 2, "standalone enemy")
	livery.call("set_player_livery", Color("358bbd"), Color("eadb85"), 18)
	for controller in controllers:
		validate(controller, controller._get_effective_team(), "palette refresh")
	validate(standalone, 2, "standalone palette refresh")
	check(paint_count > 0, "authored paint surfaces were checked")
	if DisplayServer.get_name() != "headless":
		await render(world)
	print("TURRET_TEAM_LIVERY_%s surfaces=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", paint_count, failures])
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func validate(controller: Node, team: int, label: String) -> void:
	if controller == null or controller.get("turret") == null:
		check(false, label + " has turret")
		return
	var primary: Color = livery.call("_get_team_upper_color", team)
	var counts := [0]
	inspect(controller.get("turret"), primary, label, counts)
	# Angular/round housings have paint slots. Receiver guns have only authored
	# mechanical materials, which inspect() checks remain unchanged.
	if controller.get("turret").has_method("_bind_rig"):
		check(counts[0] > 0, label + " has authored main colour")

func inspect(node: Node, primary: Color, label: String, counts: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for index in node.mesh.get_surface_count():
			var source: Material = node.mesh.surface_get_material(index)
			if source == null:
				continue
			var name: String = livery.call("_normalized_material_name", source)
			var active: Material = node.get_active_material(index)
			if name == "main color":
				counts[0] += 1
				paint_count += 1
				check(active is StandardMaterial3D, label + " solid turret paint")
				if active is StandardMaterial3D:
					check(active.albedo_color.is_equal_approx(primary), label + " team primary")
				check(active != source, label + " shared source preserved")
			else:
				check(active == source, label + " preserves authored " + name)
	for child in node.get_children():
		inspect(child, primary, label, counts)

func render(world: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("354452")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -35, 0)
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(7, 18, 28)
	camera.look_at(Vector3(0, 1, 3.5))
	camera.fov = 45
	camera.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://logs/turret_team_livery.png") == OK, "render saved")
