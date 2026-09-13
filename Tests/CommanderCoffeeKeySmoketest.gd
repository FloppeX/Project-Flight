extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	create_timer(30).timeout.connect(func(): quit(1))
	var stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var commander = load("res://LandCarrier/Commander.tscn").instantiate()
	stage.add_child(commander)
	await process_frame
	commander.set_physics_process(false)
	commander.get_node("Camera3D").make_current()
	var key = InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	commander._input(key)
	var coffee = commander.get_node("BodyVisualCoffee")
	var player = coffee.get_node("AnimationPlayer")
	assert(player.current_animation == "Coffee_Sip")
	player.advance(0.7)
	var time = player.current_animation_position
	commander._input(key)
	assert(is_equal_approx(time,player.current_animation_position))
	commander._set_officer_moving(false)
	assert(player.current_animation == "Coffee_Sip")
	player.advance(4.2)
	assert(player.current_animation == "Coffee_Hold")
	commander._set_officer_moving(true)
	assert(player.current_animation == "Coffee_Walk")
	commander._input(key)
	assert(player.current_animation == "Coffee_Walk")
	commander._set_officer_moving(false)
	commander._switch_officer()
	assert(commander._active_officer_index == 0)
	assert(not player.active)
	commander._input(key)
	assert(player.active and player.current_animation == "Coffee_Sip")
	commander._update_body_visibility(false)
	assert(coffee.visible and not commander.get_node("BodyVisual").visible)
	commander.queue_free()
	await process_frame
	print("COMMANDER_COFFEE_KEY_PASS")
	quit()
