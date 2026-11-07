class_name Actor
extends CharacterBody2D
## Shared by everyone who walks around: plays the right animation for the way they face,
## and follows paths through the streets.

const AREAS_LAYER := 1 << 5   # the Body / Attack areas from Sprite Studio talk to each other on this layer

var main: Node
var level: Level
var sprite: AnimatedSprite2D
var facing := Vector2.DOWN
var path := PackedVector2Array()
var path_i := 0


func setup(main_node: Node, sprite_scene: PackedScene, radius := 5.0) -> void:
	main = main_node
	level = main_node.level
	sprite = sprite_scene.instantiate()
	add_child(sprite)
	for n in ["Body", "Attack"]:
		var a := sprite.get_node_or_null(n) as Area2D
		if a:
			a.collision_layer = AREAS_LAYER
			a.collision_mask = AREAS_LAYER
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	shape.position = Vector2(0, -radius + 1)
	add_child(shape)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


func body_area() -> Area2D:
	return sprite.get_node_or_null("Body") as Area2D


func dir_name() -> String:
	if absf(facing.y) > absf(facing.x) * 1.1:
		return "down" if facing.y > 0 else "up"
	return "side"


func animate(moving: bool, state := "") -> void:
	var d := dir_name()
	sprite.flip_h = d == "side" and facing.x < 0
	var anim := (state if state != "" else ("walk" if moving else "idle")) + "_" + d
	if sprite.animation != anim and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)


func go_to(target: Vector2) -> void:
	path = level.path(global_position, target)
	path_i = 0
	if path.size() > 1:
		path_i = 1


## Walks along the current path. Returns true while still walking.
func move_along(speed: float) -> bool:
	while path_i < path.size() and global_position.distance_to(path[path_i]) < 3.0:
		path_i += 1
	if path_i >= path.size():
		velocity = Vector2.ZERO
		return false
	var d := (path[path_i] - global_position).normalized()
	velocity = d * speed
	facing = d
	move_and_slide()
	return true


func make_light(energy: float, size: float, color: Color) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = main.light_texture
	l.energy = energy
	l.texture_scale = size
	l.color = color
	add_child(l)
	return l
