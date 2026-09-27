extends SceneTree
## Rebuild the lightweight gameplay wrapper around the authored carrier GLB.

const SOURCE := "res://Models/LandCarrier/Land carrier 4.glb"
const OUTPUT := "res://Models/LandCarrier/CarrierWithInterior.tscn"
const REQUIRED_NODES := [
	"Flight deck", "main hull", "superstructure main island",
	"superstructure floor lower", "superstructure floor upper",
	"Superstructure elevator", "human",
	"CarrierSlidingDoor_Frame_001", "CarrierSlidingDoor_LeftLeaf_001",
	"CarrierSlidingDoor_RightLeaf_001", "CarrierSlidingDoor_Frame_002",
	"CarrierSlidingDoor_LeftLeaf_002", "CarrierSlidingDoor_RightLeaf_002",
]

func _initialize() -> void:
	var base := load(SOURCE).instantiate() as Node3D
	if base == null:
		push_error("Carrier model unavailable: %s" % SOURCE)
		quit(1)
		return
	for node_name in REQUIRED_NODES:
		if base.get_node_or_null(node_name) == null:
			push_error("Land carrier 4 is missing required node: %s" % node_name)
			base.free()
			quit(1)
			return
	base.free()
	var lines := PackedStringArray([
		'[gd_scene load_steps=4 format=3]', '',
		'[ext_resource type="PackedScene" path="res://Models/LandCarrier/Land carrier 4.glb" id="1"]',
		'[ext_resource type="Script" path="res://LandCarrier/CarrierIslandIntegration.gd" id="2"]',
		'[ext_resource type="Script" path="res://LandCarrier/LandCarrier4VisualIntegration.gd" id="3"]', '',
		'[node name="CarrierWithInterior" instance=ExtResource("1")]',
		'script = ExtResource("2")',
		'metadata/island_baked = true', '',
		'[node name="DoorIntegrator" type="Node" parent="."]',
		'script = ExtResource("3")', '',
	])
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % OUTPUT)
		quit(1)
		return
	file.store_string("\n".join(lines))
	file.close()
	print("CARRIER_4_MODEL_BUILT")
	quit()