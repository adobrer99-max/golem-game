extends SceneTree
# Checks the difficulty rules. From the game folder:
#   godot --headless --path . -s res://tests/difficulty.gd

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func run(level_name: String) -> void:
	Engine.set_meta("golem_difficulty", level_name)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	main.start()
	await frames(2)
	print(level_name, ": mobs=", main.mobs.size(), " lives=", main.lives, " view=", main.mobs[0].view, " golem rest=", main.golem.rest)
	# get caught while a neighbour follows you
	var n = main.neighbours[0]
	main.player.global_position = n.global_position + Vector2(0, 14)
	main.interact()
	main.player_caught(main.mobs[0])
	await frames(100)
	print("  after being caught: neighbour ", ["hiding again", "still following", "saved"][n.state], ", back home: ", n.global_position.distance_to(n.home) < 2)
	# hide right where a searching mob is looking
	main.player.safe_time = 0
	main.player.hide_in(main.level.spot(Vector2i(12, 3)))
	var m = main.mobs[0]
	m.global_position = main.level.spot(Vector2i(10, 3))
	m.hear(main.level.spot(Vector2i(12, 3)))
	var lives = main.lives
	await frames(150)
	print("  searching mob finds you in the barrel: ", main.lives < lives)
	main.queue_free()
	await frames(5)

func _initialize() -> void:
	await run("Easy")
	await run("Normal")
	await run("Hard")
	quit()
