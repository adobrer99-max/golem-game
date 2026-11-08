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


func say(text: String, seconds := 3.5) -> void:
	message.text = text
	message_time = seconds


func refresh(lives: int, max_lives: int, saved: int, total: int, following: int, golem_holding: bool, stamina: float, hidden: bool) -> void:
	var t := "Lives  %d / %d\nNeighbours safe  %d / %d" % [lives, max_lives, saved, total]
	if following > 0:
		t += "   (%d with you)" % following
	t += "\nGolem: %s   [G]" % ("holding this spot" if golem_holding else "following you")
	if hidden:
		t += "\nHidden. Move or press E to come out"
	info.text = t
	stamina_bar.size.x = 160.0 * stamina
	stamina_bar.color = Color(0.65, 0.94, 0.44) if stamina > 0.25 else Color(1, 0.45, 0.3)


func _process(delta: float) -> void:
	message_time -= delta
	message.modulate.a = clampf(message_time, 0.0, 1.0)
