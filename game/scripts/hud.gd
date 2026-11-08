class_name Hud
extends CanvasLayer
## Lives, how many neighbours are safe, the Golem's orders, a stamina bar, messages,
## and the intro / ending screens.

var info: Label
var message: Label
var stamina_back: ColorRect
var stamina_bar: ColorRect
var overlay: ColorRect
var title: Label
var body: Label
var message_time := 0.0
var dialogue: ColorRect
var speaker: Label
var speech: Label
var arrow: Polygon2D


func _ready() -> void:
	layer = 10
	info = _label(18, Vector2(20, 14))
	stamina_back = ColorRect.new()
	stamina_back.color = Color(0, 0, 0, 0.5)
	stamina_back.position = Vector2(20, 110)
	stamina_back.size = Vector2(160, 8)
	add_child(stamina_back)
	stamina_bar = ColorRect.new()
	stamina_bar.color = Color(0.65, 0.94, 0.44)
	stamina_bar.position = stamina_back.position
	stamina_bar.size = stamina_back.size
	add_child(stamina_bar)
	message = _label(22, Vector2(0, 640))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.size = Vector2(1280, 40)
	# a box for conversations
	dialogue = ColorRect.new()
	dialogue.color = Color(0.05, 0.05, 0.1, 0.88)
	dialogue.position = Vector2(190, 520)
	dialogue.size = Vector2(900, 170)
	dialogue.visible = false
	add_child(dialogue)
	speaker = _label(22, Vector2(24, 14), dialogue)
	speaker.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	speech = _label(21, Vector2(24, 50), dialogue)
	speech.size = Vector2(852, 90)
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var more := _label(15, Vector2(800, 140), dialogue)
	more.text = "E  continue"
	more.modulate.a = 0.6
	# an arrow pointing at the errand you're on
	arrow = Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(14, 0), Vector2(-8, -9), Vector2(-4, 0), Vector2(-8, 9)])
	arrow.color = Color(1, 0.85, 0.3)
	arrow.visible = false
	add_child(arrow)
	overlay = ColorRect.new()
	overlay.color = Color(0.04, 0.04, 0.08, 0.86)
	overlay.size = Vector2(1280, 720)
	add_child(overlay)
	title = _label(52, Vector2(0, 70), overlay)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(1280, 80)
	title.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	body = _label(20, Vector2(240, 160), overlay)
	body.size = Vector2(800, 520)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _label(size: int, pos: Vector2, parent: Node = null) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	(parent if parent else self).add_child(l)
	return l


func show_screen(t: String, b: String) -> void:
	message_time = 0.0
	info.visible = false
	stamina_back.visible = false
	stamina_bar.visible = false
	title.text = t
	body.text = b
	overlay.visible = true


func hide_screen() -> void:
	overlay.visible = false
	info.visible = true
	stamina_back.visible = true
	stamina_bar.visible = true


func show_dialogue(who: String, text: String) -> void:
	speaker.text = who
	speech.text = text
	dialogue.visible = true
	message_time = 0.0


func hide_dialogue() -> void:
	dialogue.visible = false


## Point at a spot in the world: an arrow at the screen edge when it's off screen, a marker over it when it isn't.
func point_at(world_pos: Vector2, canvas: Transform2D) -> void:
	if world_pos == Vector2.INF or overlay.visible:
		arrow.visible = false
		return
	var screen := canvas * world_pos
	var size := Vector2(1280, 720)
	var inside := Rect2(Vector2(40, 40), size - Vector2(80, 80)).has_point(screen + Vector2(0, -40))
	arrow.visible = true
	if inside:
		arrow.position = screen + Vector2(0, -64 + sin(Time.get_ticks_msec() / 200.0) * 4.0)
		arrow.rotation = PI / 2
	else:
		var center := size / 2.0
		var d := (screen - center).normalized()
		var t := minf((size.x / 2.0 - 40) / maxf(absf(d.x), 0.001), (size.y / 2.0 - 40) / maxf(absf(d.y), 0.001))
		arrow.position = center + d * t
		arrow.rotation = d.angle()


func say(text: String, seconds := 3.5) -> void:
	message.text = text
	message_time = seconds


func refresh(lives: int, max_lives: int, lines: Array, stamina: float, hidden: bool) -> void:
	var t := "Lives  %d / %d" % [lives, max_lives] if max_lives > 0 else ""
	for l in lines:
		t += ("\n" if t != "" else "") + l
	if hidden:
		t += "\nHidden. Move or press E to come out"
	info.text = t
	stamina_back.position.y = info.position.y + info.get_minimum_size().y + 4
	stamina_bar.position.y = stamina_back.position.y
	stamina_bar.size.x = 160.0 * stamina
	stamina_bar.color = Color(0.65, 0.94, 0.44) if stamina > 0.25 else Color(1, 0.45, 0.3)


func _process(delta: float) -> void:
	message_time -= delta
	message.modulate.a = clampf(message_time, 0.0, 1.0)
