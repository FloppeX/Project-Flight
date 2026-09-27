extends SceneTree
const CABLE = preload("res://LandCarrier/arresting_cable.tscn")
var failures: Array[String] = []
func _initialize():
 call_deferred("run")
func check(ok: bool, message: String):
 if not ok: failures.append(message)
func run():
 var host = Node3D.new()
 root.add_child(host)
 var cable = CABLE.instantiate()
 host.add_child(cable)
 cable.set_physics_process(false)
 cable.swept_hook_capture_enabled = false
 var craft = RigidBody3D.new()
 craft.freeze = true
 host.add_child(craft)
 var hook = Node3D.new()
 craft.add_child(hook)
 craft.set_meta("arresting_hold_until_manual_release", true)
 cable._aircraft = craft
 cable._hook_node = hook
 cable._engaged = true
 for mass in [900.0,16000.0]:
  for dt in [1.0/30.0,1.0/60.0,1.0/120.0]:
   craft.mass = mass
   craft.position = Vector3(0,0,0.01)
   craft.linear_velocity = Vector3(0,0,55)
   cable._force_along_prev = 0.0
   for step in range(int(8.0/dt)):
    cable._physics_process(dt)
    var force: Vector3 = cable.last_braking_force_n
    check(force.dot(craft.linear_velocity) <= 0.001, "Cable adds energy")
    craft.linear_velocity += force / mass * dt
    craft.position += craft.linear_velocity * dt
    check(craft.linear_velocity.z >= -0.0001, "Cable reversed rollout")
   check(absf(craft.linear_velocity.z) < 0.01, "Cable failed to stop aircraft")
   var stopped: Vector3 = craft.position
   for step in range(120):
    cable._physics_process(dt)
    craft.linear_velocity += cable.last_braking_force_n / mass * dt
    craft.position += craft.linear_velocity * dt
   check(craft.position.distance_to(stopped) < 0.001, "Held aircraft pulled back after stop")
 craft.position = Vector3(1,0,15)
 craft.linear_velocity = Vector3.ZERO
 cable._physics_process(1.0/60.0)
 cable.manual_release()
 check(cable._resetting, "Released cable snapped straight")
 check(cable._seg_left.visible and not cable._seg_rest.visible, "Released bend not visible")
 var before: Vector3 = cable._reset_tip_local
 var stopped: Vector3 = craft.position
 host.position += Vector3(5,0,7)
 cable._physics_process(0.1)
 check(cable._reset_tip_local.distance_to(before) <= cable.cable_reset_speed_m_s * 0.1 + 0.001, "Reset jumps on moving deck")
 for step in range(600): cable._physics_process(1.0/60.0)
 check(not cable._resetting and cable._seg_rest.visible, "Cable never straightened")
 check(craft.position == stopped, "Reset dragged released aircraft")
 host.free()
 for failure in failures: push_error(failure)
 print("ARRESTMENT_NO_REBOUND_", "PASS" if failures.is_empty() else "FAIL")
 quit(0 if failures.is_empty() else 1)
