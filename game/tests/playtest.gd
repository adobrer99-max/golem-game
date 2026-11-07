extends SceneTree
# Scripted playtest that checks the main rules. From the game folder:
#   godot --headless --path . -s res://tests/playtest.gd

var main
func frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	print("mobs=", main.mobs.size(), " neighbours=", main.neighbours.size(), " map=", main.level.width, "x", main.level.height, " exits=", main.level.exits.size())
	print("routes: ", main.mobs.map(func(m): return m.route.size()))
	main.start()
	var before = main.mobs.map(func(m): return m.global_position)
	await frames(240)
	var moved = 0
	for i in main.mobs.size():
		if main.mobs[i].global_position.distance_to(before[i]) > 20: moved += 1
	print("mobs that walked their patrol in 4s: ", moved, "/", main.mobs.size())
	print("golem stays near player: ", main.golem.global_position.distance_to(main.player.global_position) < 40)

	# call a neighbour
	var n = main.neighbours[0]
	main.player.global_position = n.global_position + Vector2(0, 14)
	await frames(2)
	main.interact()
	print("neighbour following: ", n.state == 1, " followers=", main.followers.size())
	# walk the player to the river gate with the neighbour; the neighbour should be saved
	for m in main.mobs: m.set_physics_process(false)
	var gate = main.level.spot(main.level.exits[1])
	main.player.global_position = gate
	n.global_position = gate + Vector2(0, -50)
	await frames(150)
	print("neighbour saved at the gate: ", n.state == 2, " saved=", main.saved)
	for m in main.mobs: m.set_physics_process(true)

	# being seen: stand in front of mob 1 in the open
	main.player.global_position = main.level.spot(Vector2i(32, 20))
	var m = main.mobs[0]
	m.global_position = main.level.spot(Vector2i(28, 20))
	m.facing = Vector2.RIGHT
	m.state = Mob.S.PATROL
	m.route.assign([main.level.spot(Vector2i(40, 20))])
	m.route_i = 0
	m.repath = 0
	await frames(5)
	print("mob can see player in the open: ", m.can_see(main.player))
	var lives = main.lives
	main.golem.set_physics_process(false)
	main.golem.global_position = main.level.spot(Vector2i(10, 13))
	for i in 15:
		await frames(10)
		print("  t=", i * 10, " state=", m.state, " alert=", snappedf(m.alert, 0.01), " dist=", int(m.global_position.distance_to(main.player.global_position)), " lives=", main.lives)
	print("mob chased: ", m.state == Mob.S.CHASE or main.lives < lives, "  lives ", lives, " -> ", main.lives, " state=", main.state)
	await frames(100)

	main.golem.set_physics_process(true)
	# hiding: put the player in the barrel at (12,3) with a mob looking right at it
	main.player.unhide()
	main.player.hide_in(main.level.spot(Vector2i(12, 3)))
	var m2 = main.mobs[1]
	m2.state = Mob.S.PATROL
	m2.alert = 0
	m2.global_position = main.level.spot(Vector2i(8, 3))
	m2.facing = Vector2.RIGHT
	await frames(2)
	print("mob can see player hiding in a barrel: ", m2.can_see(main.player))
	main.player.unhide()

	# the Golem shoves a chasing mob
	main.player.global_position = main.level.spot(Vector2i(27, 13))
	main.golem.global_position = main.level.spot(Vector2i(27, 14))
	var m3 = main.mobs[2]
	m3.global_position = main.level.spot(Vector2i(27, 16))
	m3.state = Mob.S.CHASE
	m3.last_seen = main.player.global_position
	main.player.safe_time = 5.0
	await frames(90)
	print("golem shoved the mob: ", m3.state == Mob.S.STUNNED or m3.state == Mob.S.SEARCH, " (state ", m3.state, ")")
	print("golem hold toggle: ", (func(): main.golem.toggle_hold(); return main.golem.holding).call())
	# winning: bring everyone to the gate
	for mm in main.mobs: mm.set_physics_process(false)
	var gate2 = main.level.spot(main.level.exits[2])
	main.player.global_position = gate2
	for nb in main.neighbours:
		if nb.state == 0:
			main.player.global_position = nb.global_position + Vector2(0, 12)
			main.interact()
	main.player.global_position = gate2
	for nb in main.followers: nb.global_position = gate2 + Vector2(0, -40)
	await frames(200)
	print("won: ", main.state == "won", " saved=", main.saved, "/", main.neighbours.size())
	print("DONE lives=", main.lives, " state=", main.state)
	quit()
