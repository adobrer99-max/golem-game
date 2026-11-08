extends SceneTree
# Plays through the open-world chapter: every errand, day and night, getting caught, sleeping, saving.
# From the game folder:  godot --headless --path . -s res://tests/city.gd

var main
func frames(n: int) -> void:
	for i in n:
		await physics_frame

func talk_through() -> void:
	var guard := 0
	while main.state == "talk" and guard < 20:
		main.world.next_line()
		guard += 1
		await frames(1)

func go(pos: Vector2) -> void:
	main.player.global_position = pos
	await frames(2)

func do_e() -> void:
	main.interact()
	await frames(1)
	await talk_through()

func load_city():
	var story = load("res://levels/chapters.json").data
	Engine.set_meta("golem_chapter", story.chapters.size() - 1)
	Engine.set_meta("golem_in_game", true)
	Engine.set_meta("golem_choice", "")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await frames(3)
	return m

func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://city.cfg"))
	main = await load_city()
	var w = main.world
	print("city: map ", main.level.width, "x", main.level.height, ", people ", w.npcs.size(), ", errands ", w.data.quests.size(), ", watch+toughs ", main.mobs.size())
	print("  intro mentions your choice: ", main.hud.body.text.begins_with("Years later"))
	main.start()
	await frames(5)
	print("  ", w.hud_lines())
	var p = main.player
	# keep the watch and toughs out of the way for the errand run (tested separately below)
	for m in main.mobs: m.set_physics_process(false)
	var guard := 0
	while w.done.size() < w.data.quests.size() and guard < 60:
		guard += 1
		if w.active == "":
			var giver := ""
			for q in w.data.quests:
				if w.available(q):
					giver = q.giver
					break
			if giver == "":
				w.clock = w.day_fraction + 0.05   # some errands only come up at night
				w.process(0.0)
				for q in w.data.quests:
					if w.available(q):
						giver = q.giver
						break
			if giver == "":
				print("  stuck: nothing available"); break
			await go(w.npcs[giver].global_position + Vector2(0, 12))
			await do_e()
			print("  took on: ", w.quest().title)
			continue
		var s = w.current_step()
		match s.do:
			"get":
				await go(w.pickup.global_position)
				await do_e()
			"receive":
				await go(w.npcs[s.from].global_position + Vector2(0, 12))
				await do_e()
			"bring":
				await go(w.npcs[s.to].global_position + Vector2(0, 12))
				await do_e()
			"lead":
				var f = w.followers[s.who]
				await go(f.global_position + Vector2(0, 12))
				await do_e()
				await go(w.npcs[s.to].global_position + Vector2(0, 20))
				f.global_position = w.npcs[s.to].global_position + Vector2(0, 26)
				await frames(30)
				await talk_through()
		if w.active == "" and w.done.size() > 0:
			print("    done: ", w.done.back())
	print("  all errands done: ", w.done.size(), "/", w.data.quests.size(), "  home: ", w.has_home)
	print("  the letter mentioned the village: ", w.data.letter_lines.has(w.choice))
	# night: the watch notices you outside the Jewish street, but not inside it
	for m in main.mobs: m.set_physics_process(true)
	w.clock = w.day_fraction + 0.1
	await frames(2)
	var watch = main.mobs.filter(func(m): return m.night_only)[0]
	watch.set_physics_process(false)
	await go(main.level.spot(Vector2i(47, 30)))
	watch.global_position = p.global_position + Vector2(-40, 0)
	watch.facing = Vector2.RIGHT
	await frames(2)
	print("  at night the watch sees you in the market: ", watch.can_see(p))
	await go(main.level.spot(Vector2i(75, 32)))
	watch.global_position = p.global_position + Vector2(-40, 0)
	await frames(2)
	print("  ...but not in the Jewish street: ", not watch.can_see(p))
	watch.set_physics_process(true)
	w.clock = 0.3
	await frames(2)
	await go(main.level.spot(Vector2i(47, 30)))
	watch.global_position = p.global_position + Vector2(-40, 0)
	watch.facing = Vector2.RIGHT
	await frames(10)
	print("  by day the watch leaves you alone: ", watch.alert == 0.0)
	# getting caught: no game over, you wake up at home
	w.clock = w.day_fraction + 0.1
	main.player_caught(watch)
	await frames(150)
	print("  caught: state ", main.state, ", back home: ", p.global_position.distance_to(w.npcs.widow.global_position) < 30)
	# sleeping
	await go(w.npcs.widow.global_position + Vector2(0, 12))
	main.interact()
	await frames(150)
	print("  slept until: ", w.time_label())
	# saved progress
	main.queue_free(); await frames(3)
	main = await load_city()
	print("  after reloading: errands done ", main.world.done.size(), ", home ", main.world.has_home)
	quit()
