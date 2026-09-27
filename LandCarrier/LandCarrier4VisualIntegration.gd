extends Node
## Restores the two Blender-authored doors after GLB import flattens their
## collection hierarchy into top-level meshes.

const DOOR_SCRIPT := preload("res://LandCarrier/CarrierSlidingDoor.gd")
const DOOR_TRAVEL_M := 0.615


func _ready() -> void:
	call_deferred("_build_doors")


func _build_doors() -> void:
	_build_door("001", "ExteriorDoorForward")
	_build_door("002", "ExteriorDoorAft")


func _build_door(suffix: String, controller_name: String) -> void:
	var carrier_model := get_parent() as Node3D
	if carrier_model == null:
		return
	var frame := carrier_model.get_node_or_null("CarrierSlidingDoor_Frame_%s" % suffix) as MeshInstance3D
	var left := carrier_model.get_node_or_null("CarrierSlidingDoor_LeftLeaf_%s" % suffix) as MeshInstance3D
	var right := carrier_model.get_node_or_null("CarrierSlidingDoor_RightLeaf_%s" % suffix) as MeshInstance3D
	if frame == null or left == null or right == null:
		push_warning("[LandCarrier4VisualIntegration] Missing imported meshes for %s" % controller_name)
		return

	var frame_in_carrier := frame.transform
	var controller := Node3D.new()
	controller.name = controller_name
	controller.transform = Transform3D(frame_in_carrier.basis.orthonormalized(), frame_in_carrier.origin)
	controller.set_meta("door_type", "center_split_sliding")
	controller.set_meta("opening_width_m", 1.1)
	controller.set_meta("opening_height_m", 2.06)
	controller.set_meta("slide_distance_m", DOOR_TRAVEL_M)
	controller.set_script(DOOR_SCRIPT)

	_move_mesh_to_controller(frame, controller, frame_in_carrier)
	_move_mesh_to_controller(left, controller, left.transform)
	_move_mesh_to_controller(right, controller, right.transform)
	left.set_meta("open_offset_x_m", -DOOR_TRAVEL_M)
	right.set_meta("open_offset_x_m", DOOR_TRAVEL_M)
	carrier_model.add_child(controller)


func _move_mesh_to_controller(mesh_instance: MeshInstance3D, controller: Node3D, transform_in_carrier: Transform3D) -> void:
	get_parent().remove_child(mesh_instance)
	controller.add_child(mesh_instance)
	mesh_instance.transform = controller.transform.affine_inverse() * transform_in_carrier
