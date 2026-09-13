extends SceneTree
var scene_resource: PackedScene
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	scene_resource = load("res://LandCarrier/LandCarrier2.tscn")
	var carrier: Node3D = scene_resource.instantiate()
	carrier.process_mode = Node.PROCESS_MODE_DISABLED
	if "--baseline" in OS.get_cmdline_user_args():
		var old := carrier.get_node("CarrierModel")
		var old_index := old.get_index()
		var transform: Transform3D = old.transform
		old.free()
		var model: Node3D = load("res://Models/LandCarrier/Land carrier 3.glb").instantiate()
		model.name = "CarrierModel"
		model.transform = transform
		carrier.add_child(model)
		carrier.move_child(model, old_index)
	if "--no-doors" in OS.get_cmdline_user_args():
		for node in carrier.get_node("CarrierModel").get_children():
			if node.get_script() == load("res://LandCarrier/CarrierSlidingDoor.gd"):
				node.set_script(null)
	root.add_child(carrier)
	await create_timer(0.2).timeout
	print("TEARDOWN_BEGIN")
	carrier.queue_free()
	await create_timer(0.2).timeout
	quit()
