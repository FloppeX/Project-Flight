@tool
extends SceneTree

func _init():
    print("Beginning scene upgrades...")
    
    # Let's add the TurretController to vehicle_friendly_light.tscn and vehicle_enemy_light.tscn
    # wait... we shouldn't modify the text files directly here, but we can write an editor script.
    
    var scenes_to_modify = [
        "res://GroundVehicle/vehicle_friendly_light.tscn",
        "res://GroundVehicle/GroundVehicle.tscn"
        # Others can be added by the user
    ]
    
    for path in scenes_to_modify:
        var scene = ResourceLoader.load(path)
        if scene:
            print("Upgrading ", path)
            var instance = scene.instantiate()
            
            # Add controller
            var controller = Node3D.new()
            controller.name = "TurretController"
            controller.set_script(load("res://Weapons/Turrets/turret_controller.gd"))
            
            # Since Turret needs a mesh, and we have a new GLB, the user will have to manually attach 
            # the visual model in the editor. But we can at least provide the controller logic.
            
            instance.add_child(controller)
            controller.owner = instance
            
            var new_scene = PackedScene.new()
            new_scene.pack(instance)
            ResourceSaver.save(new_scene, path)
            print("Successfully saved upgraded ", path)
        else:
            print("Could not load ", path)
            
    quit()
