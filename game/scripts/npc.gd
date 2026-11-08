class_name Npc
extends Actor
## Someone in the city you can talk to (E). Shows ! when they have an errand for you, ? when they're part of the one you're on.

var id := ""
var display_name := ""
var mark: Label


func _ready() -> void:
	collision_layer = 1 << 4
	collision_mask = 1
	mark = Label.new()
	mark.position = Vector2(-4, -32)
	mark.add_theme_font_size_override("font_size", 14)
	mark.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	mark.add_theme_color_override("font_outline_color", Color.BLACK)
	mark.add_theme_constant_override("outline_size", 4)
	add_child(mark)
	make_light(0.3, 0.45, Color(1.0, 0.9, 0.75)).position = Vector2(0, -8)


func _physics_process(_delta: float) -> void:
	# face you when you come close
	var p: Vector2 = main.player.global_position
	if global_position.distance_to(p) < 40.0:
		facing = (p - global_position).normalized()
	animate(false)
