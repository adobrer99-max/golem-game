class_name Mob
extends Actor
## Someone from the mob with a torch. Walks a patrol route, looks ahead in a cone,
## gets suspicious, then chases. Loses you if you break line of sight or hide in time.

enum S { PATROL, CHASE, SEARCH, RETURN, STUNNED }

const PATROL_SPEED := 32.0
const CHASE_SPEED := 64.0
const SEARCH_SPEED := 44.0
const VIEW := 92.0
const HALF_ANGLE := 0.66        # radians either side of where they face
const RAYS := 11

var state := S.PATROL
var start := Vector2.ZERO
var route: Array[Vector2] = []
var route_i := 0
var alert := 0.0                # fills up while they can see you; at 1 they chase
var last_seen := Vector2.ZERO
var lost_time := 0.0
var search_time := 0.0
var look_time := 0.0
var stun_time := 0.0
var repath := 0.0
var cone: Polygon2D
var mark: Label
var torch: PointLight2D


func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = 1 | (1 << 2)
	# the vision cone lives on its own layer above the night tint, so it stays easy to read in the dark
	cone = Polygon2D.new()
	main.cone_layer.add_child(cone)
	mark = Label.new()
	mark.position = Vector2(-4, -30)
	mark.add_theme_font_size_override("font_size", 14)
	mark.add_theme_color_override("font_outline_color", Color.BLACK)
	mark.add_theme_constant_override("outline_size", 4)
	add_child(mark)
	torch = make_light(1.1, 1.5, Color(1.0, 0.62, 0.32))
	torch.position = Vector2(4, -10)


func reset() -> void:
	global_position = start
	state = S.PATROL
	route_i = 0
	alert = 0.0
	path = PackedVector2Array()


func _physics_process(delta: float) -> void:
	repath -= delta
	torch.energy = 1.05 + randf() * 0.15
	if main.state != "play":
		velocity = Vector2.ZERO
		animate(false)
		_update_cone()
		return
	if state == S.STUNNED:
		stun_time -= delta
		velocity *= 0.85
		move_and_slide()
		animate(false)
		if stun_time <= 0.0:
			state = S.SEARCH
			search_time = 2.5
			last_seen = global_position
		_update_cone()
		return

	var player: Player = main.player
	var sees := can_see(player)
	if sees:
		var closeness := 1.0 - clampf(global_position.distance_to(player.global_position) / VIEW, 0.0, 1.0)
		alert = minf(1.0, alert + delta * (0.9 + 3.0 * closeness))
		last_seen = player.global_position
	else:
		alert = maxf(0.0, alert - delta * 0.35)
	if state != S.CHASE and alert >= 1.0:
		_start_chase()

	var moving := false
	match state:
		S.PATROL:
			if alert > 0.3 and sees:
				facing = (player.global_position - global_position).normalized()   # stops and stares
				velocity = Vector2.ZERO
			else:
				var target := route[route_i] if route.size() > 0 else start
				if global_position.distance_to(target) < 4.0:
					route_i = (route_i + 1) % maxi(1, route.size())
					repath = 0.0
				if repath <= 0.0 or path_i >= path.size():
					go_to(target)
					repath = 1.0
				moving = move_along(PATROL_SPEED)
		S.CHASE:
			lost_time = 0.0 if sees else lost_time + delta
			if lost_time > 2.5:
				state = S.SEARCH
				search_time = 4.0
			else:
				if repath <= 0.0:
					go_to(last_seen)
					repath = 0.3
				moving = move_along(CHASE_SPEED)
				if global_position.distance_to(player.global_position) < 11.0:
					main.player_caught(self)
		S.SEARCH:
			if global_position.distance_to(last_seen) > 6.0 and path_i < path.size():
				moving = move_along(SEARCH_SPEED)
			else:
				if repath <= 0.0 and global_position.distance_to(last_seen) > 6.0:
					go_to(last_seen)
					repath = 1.0
				search_time -= delta
				look_time -= delta
				if look_time <= 0.0:
					facing = facing.rotated(PI / 2 * (1 if randf() < 0.5 else -1))
					look_time = 0.8
				velocity = Vector2.ZERO
				if search_time <= 0.0:
					state = S.RETURN
					repath = 0.0
		S.RETURN:
			var back := route[route_i] if route.size() > 0 else start
			if repath <= 0.0:
				go_to(back)
				repath = 1.5
			moving = move_along(PATROL_SPEED)
			if global_position.distance_to(back) < 6.0:
				state = S.PATROL
	animate(moving)
	_update_cone()
	mark.text = "!" if state == S.CHASE else ("?" if alert > 0.25 or state == S.SEARCH else "")
	mark.add_theme_color_override("font_color", Color(1, 0.3, 0.25) if state == S.CHASE else Color(1, 0.9, 0.4))


func can_see(player: Player) -> bool:
	var eye := global_position + Vector2(0, -10)
	var to := player.global_position + Vector2(0, -6)
	var d := eye.distance_to(to)
	if d > VIEW:
		return false
	if player.in_hiding:
		# hiding only works if they didn't watch you climb in
		return state == S.CHASE and d < 28.0
	if d > 18.0 and absf(facing.angle_to(to - eye)) > HALF_ANGLE:
		return false
	return level.clear_line(eye, to)


func _start_chase() -> void:
	state = S.CHASE
	lost_time = 0.0
	repath = 0.0
	main.shout(self)


## Another mob member shouted, or they heard running: go and look.
func hear(pos: Vector2) -> void:
	if state == S.CHASE or state == S.STUNNED:
		return
	state = S.SEARCH
	last_seen = pos
	search_time = 3.0
	alert = maxf(alert, 0.5)
	go_to(pos)
	repath = 1.0


func stun(from: Vector2) -> void:
	state = S.STUNNED
	stun_time = 3.5
	alert = 0.0
	velocity = (global_position - from).normalized() * 160.0


func _update_cone() -> void:
	if state == S.STUNNED or main.state == "intro":
		cone.visible = false
		mark.text = "*" if state == S.STUNNED else ""
		return
	cone.visible = true
	cone.position = global_position
	var eye := Vector2(0, -6)
	var pts := PackedVector2Array([eye])
	var base := facing.angle()
	for i in RAYS:
		var a := base - HALF_ANGLE + 2.0 * HALF_ANGLE * i / (RAYS - 1)
		var world_end: Vector2 = level.ray_end(global_position + eye, global_position + eye + Vector2.from_angle(a) * VIEW)
		pts.append(world_end - global_position)
	cone.polygon = pts
	var c := Color(1.0, 0.25, 0.2, 0.22) if state == S.CHASE else Color(1.0, 0.82, 0.4, 0.10 + 0.14 * alert)
	cone.color = c
