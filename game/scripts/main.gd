extends Node2D
## Runs one chapter: sets up the map and everyone in it, and the rules. Get every neighbour to the
## way out, then go yourself. The story text for each chapter is in levels/chapters.json.

const SPRITES := {
	"player": "res://art/player/player.tscn",
	"golem": "res://art/golem/golem.tscn",
	"mob": "res://art/mob/mob.tscn",
	"neighbour": "res://art/neighbour/neighbour.tscn",
	"elder": "res://art/elder/elder.tscn",
	"rabbi": "res://art/rabbi/rabbi.tscn",
}
# the people of the city: res://art/<name>/<name>.tscn
const TOWNSFOLK := ["widow", "scribe", "baker", "midwife", "boatman", "merchant", "parnas", "rivka", "thug", "watchman", "treasurer", "goat"]
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
# chapter tasks (the prologue): overhear the plotters, dig clay
var listen: Dictionary = {}
var listen_time := 0.0
var lines_heard := 0
var clay_needed := 0
var clay_dug := 0
# a chapter with a choice (Fight or Flight); the chosen option's settings are merged into ch
var choosing := false
var mode := ""             # "defend" (Fight), "escape" (Flight) or "" for the usual
var actors: Node2D
# waves of arrivals: Fight sends them for the houses, Flight sends them searching the lanes
var waves: Array = []
var wave := 0
var to_spawn := 0
var spawn_timer := 0.0
var wave_pause := 0.0
# Fight: doors being set alight. cell -> {"heat": 0..1, "burning": bool, "burn": seconds, "lost": bool, "fire": Node2D}
var fires: Dictionary = {}
var houses_lost := 0
# the open-world chapter
var world: World
var night_tint: CanvasModulate


func _ready() -> void:
	_setup_input()
	story = load("res://levels/chapters.json").data
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_FILE) == OK:
		unlocked = cfg.get_value("progress", "unlocked", 0)
	chapter = clampi(chapter, 0, story.chapters.size() - 1)
	ch = story.chapters[chapter]
	if ch.has("choice"):
		var picked: String = Engine.get_meta("golem_choice", "")
		choosing = true
		for opt in ch.choice.options:
			if opt.key == picked:
				ch = ch.duplicate()
				for k in opt:
					ch[k] = opt[k]
				choosing = false
	mode = ch.get("mode", "")
	diff = DIFFICULTY[difficulty]
	light_texture = _make_light_texture()
	level = Level.new()
	add_child(level)
	level.load_map("res://levels/" + ch.map)
	level.build(load("res://art/tiles/tiles.png"))

	night_tint = CanvasModulate.new()
	night_tint.color = Color(ch.night[0], ch.night[1], ch.night[2])
	add_child(night_tint)
	for c in level.lit_windows:   # Hanukkah lights in the windows
		_lamp(level.center(c) + Vector2(0, 10), Color(1, 0.78, 0.45), 0.7, 0.38)
	for c in level.exits:         # lanterns at the way out
		_lamp(level.center(c), Color(1, 0.85, 0.5), 0.9, 0.9)

	cone_layer = CanvasLayer.new()
	cone_layer.follow_viewport_enabled = true
	cone_layer.layer = 1
	add_child(cone_layer)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	add_child(actors)
	player = _spawn(Player.new(), ch.get("player", "player"), level.player_start, actors) as Player
	if level.golem_start_set:   # the prologue happens before there is a Golem
		golem = _spawn(Golem.new(), "golem", level.golem_start, actors, 7.0) as Golem
	listen = ch.get("listen", {})
	clay_needed = level.clay.size()
	for n in (level.neighbours if mode != "defend" else []):   # in a Fight, the families shelter in the synagogue
		var nb := _spawn(Neighbour.new(), n[1], n[0], actors) as Neighbour
		nb.home = nb.global_position
		if n[1] == "elder":
			nb.speed = 50.0
		neighbours.append(nb)
		if n[2]:   # already with you at the start of the chapter
			_follow(nb)
	var world_data: Dictionary = load(ch.world).data if ch.has("world") else {}
	for id in level.mobs:
		var kind: String = world_data.get("mobs", {}).get(id, "")
		var m := _spawn(Mob.new(), {"watch": "watchman", "tough": "thug"}.get(kind, "mob"), level.mobs[id], actors) as Mob
		m.night_only = kind == "watch"
		m.start = m.global_position
		m.id = id
		for p in level.patrols.get(id, []):
			if level.points.has(p):
				m.route.append(level.spot(level.points[p]))
		m.route.append(m.start)
		m.facing = Vector2.RIGHT
		mobs.append(m)
	if not world_data.is_empty():
		world = World.new()
		add_child(world)
		world.setup(self, world_data, Engine.get_meta("golem_village_choice", _saved_choice()))
	var body := player.body_area()
	if body:
		body.area_entered.connect(_on_player_touched)

	hud = Hud.new()
	add_child(hud)
	for c in level.doors_at_risk:
		fires[c] = {"heat": 0.0, "burning": false, "burn": 0.0, "lost": false, "fire": null}
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
	var path: String = SPRITES.get(sprite, "res://art/%s/%s.tscn" % [sprite, sprite])
	a.setup(self, load(path), radius)
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
	var c: Dictionary = story.chapters[i]
	if c.has("label"):
		return "%s: %s" % [c.label, c.name]
	var n := 0
	for j in i + 1:
		if not story.chapters[j].has("label"):
			n += 1
	return "Chapter %d: %s" % [n, c.name]


func _show_title() -> void:
	state = "title"
	var choose := "   (press C to change)" if unlocked > 0 else ""
	hud.show_screen(story.title,
		"A medieval Jewish adventure.\n\n" +
		"%s%s\nDifficulty: %s   (press 1 Easy, 2 Normal, 3 Hard)\n\n" % [_chapter_label(chapter), choose, difficulty] +
		"Move  WASD / arrows      Run  Shift (they'll hear you)\nE  call someone, hide      G  Golem: hold here / follow\n" +
		"R  restart the chapter      Esc  back to this screen\n\nPress Enter to begin")


func _saved_choice() -> String:
	var cfg := ConfigFile.new()
	return cfg.get_value("progress", "village_choice", "L") if cfg.load(PROGRESS_FILE) == OK else "L"


func is_night() -> bool:
	return world.night if world else true


func _show_intro() -> void:
	state = "intro"
	var intro: String = ch.intro
	if ch.has("intro_by_choice"):
		intro = ch.intro_by_choice.get(_saved_choice(), intro) + "\n\n" + intro
	hud.show_screen(_chapter_label(chapter), intro + ("\n\nPress Enter to choose" if choosing else "\n\nPress Enter to begin"))


func _show_choice() -> void:
	state = "choice"
	var t: String = ch.choice.prompt + "\n\n"
	for opt in ch.choice.options:
		t += "%s   %s\n%s\n\n" % [opt.key, opt.name, opt.summary]
	hud.show_screen(ch.choice.title, t + "Press " + " or ".join(ch.choice.options.map(func(o): return o.key)))


func _unhandled_input(event: InputEvent) -> void:
	if state == "talk":
		if event.is_action_pressed("interact") or event.is_action_pressed("confirm"):
			world.next_line()
		return
	if event.is_action_pressed("confirm"):
		match state:
			"title":
				Engine.set_meta("golem_in_game", true)
				_show_intro()
			"intro":
				if choosing:
					_show_choice()
				else:
					start()
			"won":
				_go_to_chapter(chapter + 1)
			"ending":
				Engine.set_meta("golem_in_game", false)
				_go_to_chapter(0)
			"lost":
				get_tree().reload_current_scene()
		return
	if state == "choice" and event is InputEventKey and event.pressed and not event.echo:
		for opt in ch.choice.options:
			if OS.get_keycode_string(event.physical_keycode) == opt.key:
				Engine.set_meta("golem_choice", opt.key)
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
		Engine.set_meta("golem_choice", "")
		get_tree().reload_current_scene()
	elif event.is_action_pressed("restart") and state in ["play", "lost", "caught"]:
		get_tree().reload_current_scene()
	elif state == "play":
		if event.is_action_pressed("interact"):
			interact()
		elif event.is_action_pressed("golem") and golem:
			golem.toggle_hold()
			hud.say("The Golem stands guard here." if golem.holding else "The Golem follows you.")


func _go_to_chapter(i: int) -> void:
	Engine.set_meta("golem_chapter", i)
	Engine.set_meta("golem_choice", "")
	get_tree().reload_current_scene()


func start() -> void:
	lives = diff.lives
	for m in mobs.duplicate():
		if not diff.extra_mobs and int(m.id) > 5 and not world:
			mobs.erase(m)
			m.cone.queue_free()
			m.queue_free()
			continue
		m.view = diff.view
		m.alert_rate = diff.alert
		m.chase_speed = diff.chase
		m.give_up = diff.give_up
		m.checks_hiding_spots = diff.check_hiding
	if golem:
		golem.rest = diff.golem_rest
		golem.knockdown = diff.knockdown
	player.stamina_drain = diff.stamina_drain
	# waves get bigger on harder settings
	var scale: float = {"Easy": 0.7, "Normal": 1.0, "Hard": 1.35}[difficulty]
	waves = ch.get("waves", []).map(func(w): return {"count": maxi(1, roundi(w.count * scale)), "after": w.get("after", 0.0)})
	wave = 0
	to_spawn = 0
	wave_pause = waves[0].after if waves.size() > 0 else 0.0
	state = "play"
	hud.hide_screen()
	hud.say(ch.get("goal", ""), 6.0)


# ---------------------------------------------------------------- play

func _physics_process(_delta: float) -> void:
	if state == "play" and player.sprinting:
		for m in mobs:
			if m.global_position.distance_to(player.global_position) < diff.hearing:
				m.hear(player.global_position)
	if world:
		world.process(_delta)
		hud.point_at(world.target(), get_viewport().get_canvas_transform())
	if state == "play":
		_listen(_delta)
		_run_waves(_delta)
		_burn(_delta)
	var on_exit := level.is_exit(level.cell_of(player.global_position))
	if state == "play" and on_exit and mode != "defend" and not world:
		if saved == neighbours.size() and tasks_done():
			win()
		elif not told_exit and followers.is_empty():
			told_exit = true
			hud.say(ch.get("not_yet", "Not everyone is here yet."))
	if not on_exit:
		told_exit = false
	hud.refresh(lives, 0 if world else diff.get("lives", 3), _hud_lines(), player.stamina, player.in_hiding)


# ---------------------------------------------------------------- arrivals and fires

func _run_waves(delta: float) -> void:
	if wave >= waves.size():
		if mode == "defend" and mobs.is_empty():
			win()
		return
	if to_spawn == 0:
		wave_pause -= delta
		if wave_pause > 0.0:
			return
		to_spawn = waves[wave].count
		if wave > 0 or mode == "defend":
			hud.say(ch.get("wave_text", "More of them are coming.") + ("  (%d of %d)" % [wave + 1, waves.size()] if mode == "defend" else ""), 4.0)
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	spawn_timer = 1.3
	_arrive()
	to_spawn -= 1
	if to_spawn == 0:
		wave += 1
		if wave < waves.size():
			wave_pause = waves[wave].after
			if mode == "defend":
				wave_pause = 99999.0   # in a Fight, the next wave comes once this one has been driven off


func _arrive() -> void:
	var at: Vector2i = level.arrivals[randi() % level.arrivals.size()]
	var m := _spawn(Mob.new(), "mob", at, actors) as Mob
	m.start = m.global_position
	m.flee_to = m.global_position
	m.id = "w"
	m.view = diff.view
	m.alert_rate = diff.alert
	m.chase_speed = diff.chase
	m.give_up = diff.give_up
	m.checks_hiding_spots = diff.check_hiding
	m.facing = Vector2.DOWN
	if mode == "defend":
		m.arrival = "torch"
	else:
		m.arrival = "roam"
		for i in 4:
			m.route.append(level.spot(level.random_open_cell()))
		m.route.append(m.start)
	mobs.append(m)


## A knocked-down attacker has run off the map.
func mob_left(m: Mob) -> void:
	mobs.erase(m)
	m.cone.queue_free()
	m.queue_free()
	if mode == "defend" and to_spawn == 0 and wave < waves.size() and mobs.is_empty():
		wave_pause = 4.0
		hud.say(ch.get("wave_cleared", "They fall back. For now."), 4.0)


func door_can_burn(c: Vector2i) -> bool:
	return fires.has(c) and not fires[c].lost and not fires[c].burning


## The nearest door that isn't already burning.
func door_to_burn(from: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := INF
	for c in fires:
		if door_can_burn(c) and level.center(c).distance_to(from) < bd:
			bd = level.center(c).distance_to(from)
			best = c
	return best


## An attacker holding a torch to a door. Returns true once it catches.
func set_alight(c: Vector2i, delta: float) -> bool:
	var f: Dictionary = fires[c]
	f.heat += delta / 3.0
	if f.heat < 1.0:
		return false
	f.burning = true
	f.burn = 0.0
	f.fire = _make_fire(level.center(c))
	hud.say(ch.get("fire_text", "A house is on fire! Put it out: E next to the door."), 4.0)
	return true


func _burn(delta: float) -> void:
	for c in fires:
		var f: Dictionary = fires[c]
		if not f.burning:
			f.heat = maxf(0.0, f.heat - delta * 0.1)
			continue
		f.burn += delta
		if f.burn > 14.0:   # too late: the house burns down
			f.burning = false
			f.lost = true
			f.fire.queue_free()
			level.set_tile(c, Level.T.BURNT)
			houses_lost += 1
			if houses_lost >= ch.get("houses_can_lose", 3):
				state = "lost"
				hud.show_screen("The village burns", ch.get("lost_text", "Too many houses burned.") + "\n\nPress Enter to try again.")
				return
			hud.say("A house has burned down.", 3.0)


func _make_fire(pos: Vector2) -> Node2D:
	var fire := Node2D.new()
	fire.position = pos + Vector2(0, 4)
	fire.z_index = 5
	for i in 4:
		var flame := Polygon2D.new()
		flame.polygon = PackedVector2Array([Vector2(-3, 0), Vector2(0, -10), Vector2(3, 0)])
		flame.position = Vector2(-6 + i * 4, 0)
		flame.color = [Color(1, 0.3, 0.1), Color(1, 0.65, 0.1), Color(1, 0.9, 0.3), Color(1, 0.5, 0.1)][i]
		fire.add_child(flame)
	var l := PointLight2D.new()
	l.texture = light_texture
	l.color = Color(1, 0.5, 0.2)
	l.energy = 1.3
	l.texture_scale = 1.2
	fire.add_child(l)
	add_child(fire)
	var t := fire.create_tween().set_loops()   # belongs to the fire, so it stops when the fire is put out
	t.tween_property(fire, "scale", Vector2(1.1, 1.3), 0.15)
	t.tween_property(fire, "scale", Vector2(0.95, 0.85), 0.2)
	return fire


func _put_out_fire() -> bool:
	for c in fires:
		var f: Dictionary = fires[c]
		if f.burning and level.spot(c + Vector2i(0, 1)).distance_to(player.global_position) < 26.0:
			f.burning = false
			f.heat = 0.0
			f.fire.queue_free()
			f.fire = null
			hud.say("You beat out the flames.", 2.5)
			return true
	return false


func tasks_done() -> bool:
	return (listen.is_empty() or lines_heard >= listen.lines.size()) and clay_dug >= clay_needed


func _hud_lines() -> Array:
	var lines := []
	if world:
		return world.hud_lines()
	if mode == "defend":
		var on_fire := fires.values().filter(func(f): return f.burning).size()
		lines.append("Wave  %d / %d" % [mini(wave + (1 if to_spawn > 0 or not mobs.is_empty() else 0), waves.size()), waves.size()])
		lines.append("Houses lost  %d / %d" % [houses_lost, ch.get("houses_can_lose", 3)] + ("   %d ON FIRE!" % on_fire if on_fire > 0 else ""))
	if neighbours.size() > 0:
		lines.append("Neighbours safe  %d / %d" % [saved, neighbours.size()] + ("   (%d with you)" % followers.size() if followers.size() > 0 else ""))
	if not listen.is_empty():
		var done: bool = lines_heard >= listen.lines.size()
		lines.append(listen.label + ("  - done" if done else "  %d / %d" % [lines_heard, listen.lines.size()]))
	if clay_needed > 0:
		lines.append("River clay  %d / %d" % [clay_dug, clay_needed] + ("  - done" if clay_dug >= clay_needed else ""))
	if ch.has("return_label") and tasks_done():
		lines.append(ch.return_label)
	if golem:
		lines.append("Golem: %s   [G]" % ("holding this spot" if golem.holding else "following you"))
	return lines


## Stand near the plotters (or hide right by them) and you hear the plan, line by line.
func _listen(delta: float) -> void:
	if listen.is_empty() or lines_heard >= listen.lines.size():
		return
	var near := false
	for c in level.listen_spots:
		if level.center(c).distance_to(player.global_position) < listen.get("radius", 40.0):
			near = true
	for m in mobs:
		if m.state == Mob.S.CHASE:
			near = false
	if not near:
		return
	listen_time += delta
	var due := mini(listen.lines.size(), int(listen_time / listen.seconds_per_line))
	if due > lines_heard:
		lines_heard = due
		hud.say(listen.lines[lines_heard - 1], listen.seconds_per_line + 0.6)
		if lines_heard == listen.lines.size():
			await get_tree().create_timer(listen.seconds_per_line + 0.6).timeout
			hud.say(listen.done, 6.0)


func _follow(n: Neighbour) -> void:
	n.state = Neighbour.S.FOLLOWING
	n.leader = followers.back() if followers.size() > 0 else player
	followers.append(n)


func interact() -> void:
	if player.in_hiding:
		player.unhide()
		return
	if _put_out_fire():
		return
	if world and world.interact():
		return
	for n in neighbours:
		if n.state == Neighbour.S.HIDING and n.global_position.distance_to(player.global_position) < 30.0:
			_follow(n)
			var who := "elder" if n.speed < 60 else "neighbour"
			var found: String = ch.get("found", "They come with you.")
			hud.say(found % who if "%s" in found else found)
			return
	var here := level.cell_of(player.global_position)
	for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = here + d
		if c in level.clay and level.center(c).distance_to(player.global_position) < 22.0:
			level.dig(c)
			clay_dug += 1
			hud.say(ch.get("dug", "You dig.") + "  (%d / %d)" % [clay_dug, clay_needed])
			return
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
	if world:
		world.caught(_by)
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
	if golem:
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
	if ch.has("mode") and ch.has("key"):   # remember what you chose in the village, for later chapters
		cfg.set_value("progress", "village_choice", ch.key)
		cfg.save(PROGRESS_FILE)
	Engine.set_meta("golem_choice", "")
	if chapter == story.chapters.size() - 1:
		state = "ending"
		hud.show_screen("The End", ch.get("outro", "") + "\n\nThank you for playing.\n\nPress Enter to return to the title screen.")
	else:
		state = "won"
		hud.show_screen(_chapter_label(chapter), ch.get("outro", "") + "\n\nPress Enter to continue.")
