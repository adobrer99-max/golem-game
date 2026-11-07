class_name Neighbour
extends Actor
## Hides by a door until you reach them (E). Then follows you to the river gate.

enum S { HIDING, FOLLOWING, SAVED }

var state := S.HIDING
var leader: Node2D
var speed := 62.0
var repath := 0.0
var prompt: Label


func _ready() -> void:
	collision_layer = 1 << 4
	collision_mask = 1
	prompt = Label.new()
	prompt.text = "E"
	prompt.position = Vector2(-4, -32)
	prompt.add_theme_font_size_override("font_size", 12)
	prompt.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt.add_theme_constant_override("outline_size", 4)
	add_child(prompt)
	make_light(0.25, 0.5, Color(1.0, 0.9, 0.7)).position = Vector2(0, -8)


func _physics_process(delta: float) -> void:
	repath -= delta
	prompt.visible = state == S.HIDING and main.state == "play" and global_position.distance_to(main.player.global_position) < 30.0
	if state == S.SAVED:
		sprite.modulate.a = maxf(0.0, sprite.modulate.a - delta)
		if sprite.modulate.a <= 0.0:
			visible = false
			set_physics_process(false)
		return
	if state == S.HIDING or main.state != "play":
		velocity = Vector2.ZERO
		animate(false)
		return
	# once you reach the river gate, everyone with you heads straight onto the boat
	var to_boat: bool = level.is_exit(level.cell_of(main.player.global_position))
	var target: Vector2 = main.nearest_exit(global_position) if to_boat else leader.global_position
	var d := global_position.distance_to(target)
	if d > (2.0 if to_boat else 18.0):
		if repath <= 0.0:
			go_to(target)
			repath = 0.3
		animate(move_along(speed * (1.35 if d > 60.0 else 1.0)))
	else:
		velocity = Vector2.ZERO
		animate(false)
	if level.is_exit(level.cell_of(global_position)) or global_position.distance_to(main.nearest_exit(global_position)) < 10.0:
		main.neighbour_saved(self)
