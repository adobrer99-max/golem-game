extends SceneTree
# Checks the last chapter's choice and both paths. From the game folder:
#   godot --headless --path . -s res://tests/village.gd

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func load_village(choice: String):
	var story = load("res://levels/chapters.json").data
	Engine.set_meta("golem_chapter", story.chapters.size() - 1)
	Engine.set_meta("golem_in_game", true)
	Engine.set_meta("golem_choice", choice)
	Engine.set_meta("golem_difficulty", "Normal")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	return main

func _initialize() -> void:
	# before choosing
	var m = await load_village("")
	print("no choice yet: choosing=", m.choosing, " state=", m.state)
	m._show_choice()
	print("  choice screen: ", m.hud.title.text, " | ", m.hud.body.text.split("\n")[2])
	m.queue_free(); await frames(3)

	# FIGHT: win by letting the Golem knock everyone down
	m = await load_village("F")
	print("Fight: mode=", m.mode, " doors=", m.fires.size(), " families on the map=", m.neighbours.size(), " waves=", m.waves.size())
	m.start()
	await frames(60 * 9)
	var burning = m.fires.values().filter(func(f): return f.burning).size()
	var heating = m.fires.values().filter(func(f): return f.heat > 0).size()
	print("  after 9s: attackers=", m.mobs.size(), " doors heating=", heating, " burning=", burning)
	# put out a fire by hand
	for c in m.fires:
		if m.fires[c].burning:
			m.player.global_position = m.level.spot(c + Vector2i(0, 1))
			m.interact()
			print("  put out the fire at ", c, ": ", not m.fires[c].burning)
			break
	m.player.safe_time = 9999
	var t := 0
	while m.state == "play" and t < 60 * 120:
		for mob in m.mobs.duplicate():
			if mob.state != Mob.S.STUNNED and mob.state != Mob.S.FLEE and mob.global_position.distance_to(mob.start) > 60:
				mob.stun(mob.global_position + Vector2(0, 10), 0.5)
		for c in m.fires:
			if m.fires[c].burning:
				m.player.global_position = m.level.spot(c + Vector2i(0, 1))
				m.interact()
		await frames(10)
		t += 10
	print("  Fight result: ", m.state, " after ", t / 60, "s, waves done ", m.wave, "/", m.waves.size(), ", houses lost ", m.houses_lost)
	print("  ending starts: ", m.hud.body.text.substr(0, 60))
	m.queue_free(); await frames(3)

	# FIGHT: lose by doing nothing (the Golem stays home)
	m = await load_village("F")
	m.start()
	m.golem.set_physics_process(false)
	m.player.safe_time = 9999
	m.player.global_position = m.level.spot(Vector2i(8, 29))
	Engine.time_scale = 4.0
	t = 0
	while m.state == "play" and t < 60 * 120:
		await frames(30)
		t += 30
	Engine.time_scale = 1.0
	print("  doing nothing: ", m.state, ", houses lost ", m.houses_lost)
	m.queue_free(); await frames(3)

	# FLIGHT: gather the families, get to the ford
	m = await load_village("L")
	print("Flight: mode=", m.mode, " families=", m.neighbours.size(), " exits=", m.level.exits.size())
	m.start()
	await frames(60 * 8)
	print("  after 8s: searchers arrived=", m.mobs.size(), " roaming=", m.mobs.filter(func(x): return x.arrival == "roam").size())
	for mob in m.mobs: mob.set_physics_process(false)
	for n in m.neighbours:
		m.player.global_position = n.global_position + Vector2(0, 12)
		m.interact()
	var gate = m.nearest_exit(m.player.global_position)
	m.player.global_position = gate
	for n in m.followers: n.global_position = gate + Vector2(0, -30)
	await frames(240)
	print("  Flight result: ", m.state, ", saved ", m.saved, "/", m.neighbours.size())
	print("  ending starts: ", m.hud.body.text.substr(0, 60))
	quit()
