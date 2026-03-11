@tool
extends SceneTree

func _init():
    # Attempt to load the GLB to build a tscn natively
    var glTF_scene = ResourceLoader.load("res://Models/Turrets/turret.glb", "PackedScene")
    
    if glTF_scene:
        print("Success loading GLB.")
        var instance = glTF_scene.instantiate()
        
        # Build out the logic nodes on top:
        var root = Node3D.new()
        root.name = "TurretScene"
        root.set_script(load("res://Weapons/Turrets/turret.gd"))
        
        # Add the 3D model as a child
        instance.name = "TurretModel"
        root.add_child(instance)
        instance.owner = root
        
        # Attempt to find common node names for base and barrel if they exist
        # We'll just leave them null in the script export by default so the user can assign them
        # if the model structure is unknown, or we can try a basic guess:
        var possible_base = instance.find_child("*base*", true, false)
        var possible_barrel = instance.find_child("*barrel*", true, false)
        
        if possible_base:
            root.base_mesh = possible_base
            print("Found base mesh: ", possible_base.name)
            
        if possible_barrel:
            root.barrel_mount = possible_barrel
            print("Found barrel mount: ", possible_barrel.name)
            
            # Add a firing point
            var fp = Node3D.new()
            fp.name = "FiringPoint"
            possible_barrel.add_child(fp)
            fp.owner = root
            fp.position = Vector3(0, 0, 1.0) # Guessing 1m forward
            root.firing_points.append(fp)
        
        # Save as TSCN
        var packed_scene = PackedScene.new()
        packed_scene.pack(root)
        var err = ResourceSaver.save(packed_scene, "res://Weapons/Turrets/turret.tscn")
        if err == OK:
            print("Saved turret.tscn successfully")
        else:
            print("Error saving turret.tscn: ", err)
        
    else:
        print("Failed to load turret.glb")

    quit()
