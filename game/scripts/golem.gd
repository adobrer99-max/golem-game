class_name Golem
extends Actor
## Follows you, or holds a spot when told to (G). Shoves away anyone from the mob who comes close.

const SPEED := 46.0
const REACH := 30.0

var rest := 1.0          # seconds between shoves (set by the difficulty)
var knockdown := 3.5     # how long a shoved mob member stays down
var holding := false
var hold_pos := Vector2.ZERO
var shove_cooldown := 0.0
var shoving := 0.0
var repath := 0.0


func _ready() -> void:
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 3)
	make_light(0.35, 0.7, Color(1.0, 0.85, 0.55)).position = Vector2(0, -16)


func toggle_hold() -> void:
	holding = not holding
	hold_pos = global_position


func _physics_process(delta: float) -> void:
	shove_cooldown -= delta
	repath -= delta
	if main.state != "play":
		velocity = Vector2.ZERO
		animate(false)
		return
	if shoving > 0.0:
		shoving -= delta
		return
	var near: Mob = main.nearest_mob(global_position, REACH)
	if near and shove_cooldown <= 0.0:
		_shove(near)
		return
	var goal: Vector2 = hold_pos if holding else main.player.global_position
	var keep := 4.0 if holding else 24.0
	if global_position.distance_to(goal) > keep:
		if repath <= 0.0:
			go_to(goal)
			repath = 0.5
		animate(move_along(SPEED * (1.4 if global_position.distance_to(goal) > 120 else 1.0)))
	else:
		velocity = Vector2.ZERO
		animate(false)


func _shove(mob: Mob) -> void:
	facing = (mob.global_position - global_position).normalized()
	velocity = Vector2.ZERO
	animate(false, "shove")
	sprite.frame = 0
	shoving = 0.45
	shove_cooldown = rest
	get_tree().create_timer(0.15).timeout.connect(_hit)


func _hit() -> void:
	# the Attack box drawn in Sprite Studio decides who gets pushed; anyone right in front is pushed too
	var hit := {}
	var attack := sprite.get_node_or_null("Attack") as Area2D
	if attack:
		for a in attack.get_overlapping_areas():
			var who := a.get_parent().get_parent()
			if who is Mob:
				hit[who] = true
	for m in main.mobs:
		if global_position.distance_to(m.global_position) < REACH + 4 and (m.global_position - global_position).dot(facing) > 0:
			hit[m] = true
	for m in hit:
		m.stun(global_position, knockdown)
