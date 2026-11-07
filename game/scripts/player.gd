class_name Player
extends Actor

const WALK := 58.0
const SPRINT := 92.0

var stamina := 1.0
var stamina_drain := 0.45
var sprinting := false
var in_hiding := false
var safe_time := 0.0       # after being caught, a moment where nobody can grab you


func _ready() -> void:
	collision_layer = 1 << 1
	collision_mask = 1
	var cam := Camera2D.new()
	cam.zoom = Vector2(3, 3)
	cam.position = Vector2(0, -8)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 7.0
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = level.width * Level.TILE
	cam.limit_bottom = level.height * Level.TILE
	add_child(cam)
	make_light(0.55, 0.8, Color(0.75, 0.82, 1.0)).position = Vector2(0, -8)


func _physics_process(delta: float) -> void:
	safe_time = maxf(0.0, safe_time - delta)
	sprite.modulate.a = 0.35 if in_hiding else (0.5 + 0.5 * absf(sin(safe_time * 12.0)) if safe_time > 0 else 1.0)
	if main.state != "play" or in_hiding:
		velocity = Vector2.ZERO
		sprinting = false
		animate(false)
		if in_hiding and Input.get_vector("left", "right", "up", "down").length() > 0.5:
			unhide()
		return
	var v := Input.get_vector("left", "right", "up", "down")
	sprinting = Input.is_action_pressed("sprint") and v != Vector2.ZERO and stamina > 0.02
	stamina = clampf(stamina + (-stamina_drain if sprinting else 0.22) * delta, 0.0, 1.0)
	velocity = v * (SPRINT if sprinting else WALK)
	if v != Vector2.ZERO:
		facing = v
	move_and_slide()
	animate(v != Vector2.ZERO)
	sprite.speed_scale = 1.6 if sprinting else 1.0


func hide_in(spot_pos: Vector2) -> void:
	global_position = spot_pos
	in_hiding = true
	facing = Vector2.DOWN


func unhide() -> void:
	in_hiding = false
