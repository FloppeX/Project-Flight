extends SceneTree
func _initialize(): call_deferred("run")
func run():
 create_timer(20.0).timeout.connect(func(): quit(2))
 root.get_node("SaveGameManager").set("autosave_enabled",false)
 for c in root.get_children(): c.process_mode=Node.PROCESS_MODE_DISABLED
 var n=load("res://Weapons/Turrets/UniversalReceiver.tscn").instantiate()
 root.add_child(n)
 for caliber in [10,15,20,25,40]:
  n.caliber_mm=caliber
  await process_frame
  assert(n.mounted_barrel!=null)
  assert(n.muzzle.position.z>.75)
  var rest=n.mounted_barrel.position
  var muzzle_rest=n.muzzle.position
  var body=n.get_node("ReceiverModel").transform
  n.kick_barrel_recoil(.1)
  assert(abs(n.mounted_barrel.position.z-rest.z+caliber*.01)<.00001)
  assert(abs(n.muzzle.position.z-muzzle_rest.z+caliber*.01)<.00001)
  assert(body==n.get_node("ReceiverModel").transform)
  n._recoil.reset()
  print("RECEIVER_CALIBER_PASS ",caliber," muzzle=",n.muzzle.position)
 n.free()
 quit()
