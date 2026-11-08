extends SceneTree
# Loads each chapter, checks it's set up right, and plays it to the end. From the game folder:
#   godot --headless --path . -s res://tests/chapters.gd

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	var story = load("res://levels/chapters.json").data
	for i in story.chapters.size():
		Engine.set_meta("golem_chapter", i)
		Engine.set_meta("golem_in_game", true)
		var main = load("res://main.tscn").instantiate()
		root.add_child(main)
		await frames(2)
		var start_state = main.state
		main.start()
		var with_you = main.followers.size()
		await frames(120)
		var walked = main.mobs.filter(func(m): return m.global_position.distance_to(m.start) > 16).size()
		print("%s: map %dx%d, neighbours %d (with you at start %d), mobs %d (%d walking), exits %d, opens on %s, golem %s" % [
			main._chapter_label(i), main.level.width, main.level.height, main.neighbours.size(), with_you,
			main.mobs.size(), walked, main.level.exits.size(), start_state, main.golem != null])
		# nobody should spot you in the first two seconds
		print("  safe start: ", main.lives == main.diff.lives and main.state == "play")
		# play it through: collect anyone hiding, then go to the way out
		for m in main.mobs: m.set_physics_process(false)
		for n in main.neighbours:
			if n.state == 0:
				main.player.global_position = n.global_position + Vector2(0, 12)
				main.interact()
		if not main.listen.is_empty() or main.clay_needed > 0:
			# going back early shouldn't finish the chapter
			main.player.global_position = main.nearest_exit(main.player.global_position)
			await frames(10)
			var early = main.state
			main.player.global_position = main.level.spot(main.level.listen_spots[0])
			await frames(int(60 * main.listen.seconds_per_line * main.listen.lines.size()) + 20)
			print("  overheard ", main.lines_heard, " / ", main.listen.lines.size(), " lines")
			for c in main.level.clay.duplicate():
				main.player.global_position = main.level.spot(c)
				main.interact()
			print("  clay dug ", main.clay_dug, " / ", main.clay_needed, ";  stepping back early finished it: ", early != "play")
		var gate = main.nearest_exit(main.player.global_position)
		main.player.global_position = gate
		for n in main.followers: n.global_position = gate + Vector2(-30, 0)
		await frames(240)
		print("  finished: ", main.state, "  saved ", main.saved, "/", main.neighbours.size())
		main.queue_free()
		await frames(3)
	var cfg := ConfigFile.new()
	cfg.load("user://progress.cfg")
	print("chapters unlocked: ", cfg.get_value("progress", "unlocked", 0))
	quit()
