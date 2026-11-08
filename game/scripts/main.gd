extends Node2D
## Runs one chapter: sets up the map and everyone in it, and the rules. Get every neighbour to the
## way out, then go yourself. The story text for each chapter is in levels/chapters.json.

const SPRITES := {
	"player": "res://art/player/player.tscn",
	"golem": "res://art/golem/golem.tscn",
	"mob": "res://art/mob/mob.tscn",
	"neighbour": "res://art/neighbour/neighbour.tscn",
	"elder": "res://art/elder/elder.tscn",
}
const PROGRESS_FILE := "user://progress.cfg"

# Easy is the first version of the game. Normal and Hard add more patrols (mobs 6 and up on the map),
# and make the mob see further, notice you faster, chase harder and check hiding places. The Golem
# shoves less often, and when you're caught your neighbours scatter back to where they hid.
const DIFFICULTY := {
	"Easy":   {"view": 92.0, "alert": 1.0, "chase": 64.0, "give_up": 2.5, "golem_rest": 1.0, "knockdown": 3.5, "lives": 3,
		"scatter": false, "extra_mobs": false, "check_hiding": false, "hearing": 100.0, "stamina_drain": 0.45},
	"Normal": {"view": 112.0, "alert": 1.5, "chase": 70.0, "give_up": 3.5, "golem_rest": 1.8, "knockdown": 2.6, "lives": 3,
		"scatter": true, "extra_mobs": true, "check_hiding": true, "hearing": 125.0, "stamina_drain": 0.55},
	"Hard":   {"view": 126.0, "alert": 2.0, "chase": 76.0, "give_up": 4.5, "golem_rest": 2.6, "knockdown": 1.8, "lives": 2,
		"scatter": true, "extra_mobs": true, "check_hiding": true, "hearing": 150.0, "stamina_drain": 0.7},
}

# remembered while the game is open
var difficulty: String = Engine.get_meta("golem_difficulty", "Normal")
var chapter: int = Engine.get_meta("golem_chapter", 0)
var diff: Dictionary
var story: Dictionary
var ch: Dictionary
var unlocked := 0

var level: Level
var player: Player
var golem: Golem
var mobs: Array[Mob] = []
var neighbours: Array[Neighbour] = []
var followers: Array[Neighbour] = []
var hud: Hud
var light_texture: GradientTexture2D
var cone_layer: CanvasLayer
var state := "title"     # title, intro, play, caught, won, lost
var lives := 3
var saved := 0
var told_exit := false


func _ready() -> void:
	_setup_input()
	story = load("res://levels/chapters.json").data
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_FILE) == OK:
		unlocked = cfg.get_value("progress", "unlocked", 0)
	chapter = clampi(chapter, 0, story.chapters.size() - 1)
	ch = story.chapters[chapter]
	diff = DIFFICULTY[difficulty]
	light_texture = _make_light_texture()
	level = Level.new()
	add_child(level)
	level.load_map("res://levels/" + ch.map)
	level.build(load("res://art/tiles/tiles.png"))

	var night := CanvasModulate.new()
	night.color = Color(ch.night[0], ch.night[1], ch.night[2])
	add_child(night)
	for c in level.lit_windows:   # Hanukkah lights in the windows
		_lamp(level.center(c) + Vector2(0, 10), Color(1, 0.78, 0.45), 0.7, 0.38)
	for c in level.exits:         # lanterns at the way out
		_lamp(level.center(c), Color(1, 0.85, 0.5), 0.9, 0.9)

	cone_layer = CanvasLayer.new()
	cone_layer.follow_viewport_enabled = true
	cone_layer.layer = 1
	add_child(cone_layer)
	var actors := Node2D.new()
	actors.y_sort_enabled = true
	add_child(actors)
	player = _spawn(Player.new(), "player", level.player_start, actors) as Player
	golem = _spawn(Golem.new(), "golem", level.golem_start, actors, 7.0) as Golem
	for n in level.neighbours:
		var nb := _spawn(Neighbour.new(), n[1], n[0], actors) as Neighbour
		nb.home = nb.global_position
		if n[1] == "elder":
			nb.speed = 50.0
		neighbours.append(nb)
		if n[2]:   # already with you at the start of the chapter
			_follow(nb)
	for id in level.mobs:
		var m := _spawn(Mob.new(), "mob", level.mobs[id], actors) as Mob
		m.start = m.global_position
		m.id = id
		for p in level.patrols.get(id, []):
			if level.points.has(p):
				m.route.append(level.spot(level.points[p]))
		m.route.append(m.start)
		m.facing = Vector2.RIGHT
		mobs.append(m)
	var body := player.body_area()
	if body:
		body.area_entered.connect(_on_player_touched)

	hud = Hud.new()
	add_child(hud)
	if Engine.get_meta("golem_in_game", false):
		_show_intro()
	else:
		_show_title()


func _lamp(pos: Vector2, color: Color, energy: float, size: float) -> void:
	var l := PointLight2D.new()
	l.texture = light_texture
	l.color = color
	l.energy = energy
	l.texture_scale = size
	l.position = pos
	add_child(l)


func _spawn(a: Actor, sprite: String, cell: Vector2i, parent: Node, radius := 5.0) -> Actor:
	a.position = level.spot(cell)
	a.setup(self, load(SPRITES[sprite]), radius)
	parent.add_child(a)
	return a


func _make_light_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


func _setup_input() -> void:
	var keys := {
		"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT], "up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN],
		"sprint": [KEY_SHIFT], "interact": [KEY_E, KEY_SPACE], "golem": [KEY_G], "confirm": [KEY_ENTER, KEY_KP_ENTER],
		"restart": [KEY_R], "menu": [KEY_ESCAPE],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- screens

func _chapter_label(i: int) -> String:
	return "Chapter %d: %s" % [i + 1, story.chapters[i].name]


func _show_title() -> void:
	state = "title"
	var choose := "   (press C to change)" if unlocked > 0 else ""
	hud.show_screen(story.title,
		"A medieval Jewish adventure.\n\n" +
		"%s%s\nDifficulty: %s   (press 1 Easy, 2 Normal, 3 Hard)\n\n" % [_chapter_label(chapter), choose, difficulty] +
		"Move  WASD / arrows      Run  Shift (they'll hear you)\nE  call someone, hide      G  Golem: hold here / follow\n" +
		"R  restart the chapter      Esc  back to this screen\n\nPress Enter to begin")


func _show_intro() -> void:
	state = "intro"
	hud.show_screen(_chapter_label(chapter), ch.intro + "\n\nPress Enter to begin")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		match state:
			"title":
				Engine.set_meta("golem_in_game", true)
				_show_intro()
			"intro":
				start()
			"won":
				_go_to_chapter(chapter + 1)
			"ending":
				Engine.set_meta("golem_in_game", false)
				_go_to_chapter(0)
			"lost":
				get_tree().reload_current_scene()
		return
	if state == "title" and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_1, KEY_2, KEY_3]:
			difficulty = ["Easy", "Normal", "Hard"][event.physical_keycode - KEY_1]
			Engine.set_meta("golem_difficulty", difficulty)
			_show_title()
		elif event.physical_keycode == KEY_C and unlocked > 0:
			_go_to_chapter((chapter + 1) % (unlocked + 1))
		return
	if event.is_action_pressed("menu") and state != "title":
		Engine.set_meta("golem_in_game", false)
		get_tree().reload_current_scene()
	elif event.is_action_pressed("restart") and state in ["play", "lost", "caught"]:
		get_tree().reload_current_scene()
	elif state == "play":
		if event.is_action_pressed("interact"):
			interact()
		elif event.is_action_pressed("golem"):
			golem.toggle_hold()
			hud.say("The Golem stands guard here." if golem.holding else "The Golem follows you.")


func _go_to_chapter(i: int) -> void:
	Engine.set_meta("golem_chapter", i)
	get_tree().reload_current_scene()


func start() -> void:
	lives = diff.lives
	for m in mobs.duplicate():
		if not diff.extra_mobs and int(m.id) > 5:
			mobs.erase(m)
			m.cone.queue_free()
			m.queue_free()
			continue
		m.view = diff.view
		m.alert_rate = diff.alert
		m.chase_speed = diff.chase
		m.give_up = diff.give_up
		m.checks_hiding_spots = diff.check_hiding
	golem.rest = diff.golem_rest
	golem.knockdown = diff.knockdown
	player.stamina_drain = diff.stamina_drain
	state = "play"
	hud.hide_screen()
	hud.say(ch.goal, 6.0)


# ---------------------------------------------------------------- play

func _physics_process(_delta: float) -> void:
	if state == "play" and player.sprinting:
		for m in mobs:
			if m.global_position.distance_to(player.global_position) < diff.hearing:
				m.hear(player.global_position)
	var on_exit := level.is_exit(level.cell_of(player.global_position))
	if state == "play" and on_exit:
		if saved == neighbours.size():
			win()
		elif not told_exit and followers.is_empty():
			told_exit = true
			hud.say(ch.not_yet)
	if not on_exit:
		told_exit = false
	hud.refresh(lives, diff.lives, saved, neighbours.size(), followers.size(), golem.holding, player.stamina, player.in_hiding)


func _follow(n: Neighbour) -> void:
	n.state = Neighbour.S.FOLLOWING
	n.leader = followers.back() if followers.size() > 0 else player
	followers.append(n)


func interact() -> void:
	if player.in_hiding:
		player.unhide()
		return
	for n in neighbours:
		if n.state == Neighbour.S.HIDING and n.global_position.distance_to(player.global_position) < 30.0:
			_follow(n)
			var who := "elder" if n.speed < 60 else "neighbour"
			hud.say(ch.found % who if "%s" in ch.found else ch.found)
			return
	var here := level.cell_of(player.global_position)
	for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = here + d
		if level.is_hiding_spot(c) and level.center(c).distance_to(player.global_position) < 22.0:
			player.hide_in(level.spot(c))
			hud.say("You hide. Wait for them to pass." + (" The others can't hide with you." if followers.size() > 0 else ""))
			return
	hud.say("Nothing here. Barrels, hay carts and bushes are good places to hide.")


func nearest_exit(pos: Vector2) -> Vector2:
	var best := Vector2.INF
	for c in level.exits:
		if level.spot(c).distance_to(pos) < best.distance_to(pos):
			best = level.spot(c)
	return best


func nearest_mob(pos: Vector2, within: float) -> Mob:
	var best: Mob = null
	var bd := within
	for m in mobs:
		if m.state != Mob.S.STUNNED and m.global_position.distance_to(pos) < bd:
			bd = m.global_position.distance_to(pos)
			best = m
	return best


## Someone saw you: everyone nearby comes to look.
func shout(from: Mob) -> void:
	for m in mobs:
		if m != from and m.global_position.distance_to(from.global_position) < 140.0:
			m.hear(player.global_position)


func _on_player_touched(area: Area2D) -> void:
	var who := area.get_parent().get_parent()
	if who is Mob and who.state == Mob.S.CHASE:
		player_caught(who)


func player_caught(_by: Mob, why := "They caught you!") -> void:
	if state != "play" or player.safe_time > 0.0:
		return
	lives -= 1
	if lives <= 0:
		state = "lost"
		hud.show_screen("Caught", "They caught you too many times.\n\nPress Enter to try %s again." % _chapter_label(chapter))
		return
	state = "caught"
	if diff.scatter and followers.size() > 0:
		hud.say(why + " You break free, but the others scatter and hide.", 4.0)
		for n in followers:
			n.go_home()
		followers.clear()
	else:
		hud.say(why + " You break free and run back to where you started.", 3.0)
	await get_tree().create_timer(1.2).timeout
	player.unhide()
	player.global_position = level.spot(level.player_start)
	var i := 0
	for n in followers:
		i += 1
		n.global_position = player.global_position + Vector2(-12 * i, 6)
	golem.global_position = player.global_position + Vector2(16, 0)
	golem.holding = false
	for m in mobs:
		m.reset()
	player.safe_time = 2.0
	state = "play"


func neighbour_saved(n: Neighbour) -> void:
	if n.state == Neighbour.S.SAVED:
		return
	n.state = Neighbour.S.SAVED
	followers.erase(n)
	for i in followers.size():
		followers[i].leader = player if i == 0 else followers[i - 1]
	saved += 1
	if saved == neighbours.size():
		hud.say("Everyone is through. Now you!", 5.0)
	else:
		var left := neighbours.size() - saved - followers.size()
		hud.say("Through. %d still to find." % left if left > 0 else "Through. Bring the others with you.")


func win() -> void:
	unlocked = maxi(unlocked, mini(chapter + 1, story.chapters.size() - 1))
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.save(PROGRESS_FILE)
	if chapter == story.chapters.size() - 1:
		state = "ending"
		hud.show_screen("The End", ch.outro + "\n\nThank you for playing.\n\nPress Enter to return to the title screen.")
	else:
		state = "won"
		hud.show_screen(_chapter_label(chapter), ch.outro + "\n\nPress Enter to continue.")
