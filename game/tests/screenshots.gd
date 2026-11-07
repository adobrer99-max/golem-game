extends SceneTree
# Saves a few screenshots to the user data folder. From the game folder:
#   godot --path . -s res://tests/screenshots.gd
var main
func f(n): for i in n: await process_frame
func snap(name):
	await f(3)
	root.get_texture().get_image().save_png("user://" + name + ".png")
func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await f(10)
	await snap("1_intro")
	main.start()
	await f(90)
	await snap("2_start")
	# walk over to a neighbour near a patrol
	main.player.global_position = main.level.spot(Vector2i(46, 9))
	main.golem.global_position = main.level.spot(Vector2i(44, 9))
	main.player.safe_time = 0
	await f(60)
	main.player.global_position = main.neighbours[1].global_position + Vector2(-10, 12)
	main.interact()
	main.player.safe_time = 99
	await f(70)
	await snap("3_neighbour")
	main.player.global_position = main.level.spot(Vector2i(28, 27))
	await f(120)
	await snap("4_river")
	quit()
