class_name World
extends Node
## The open-world chapter: the people of the city, their errands, day and night, and what happens
## when the watch or the toughs catch you. Everything it says comes from levels/city.json.

const SAVE_FILE := "user://city.cfg"
const ITEMS := ["bucket", "galls", "flour", "letter", "purse"]

var main: Node
var data: Dictionary
var choice := ""                  # what you chose in the village (F or L)
var npcs: Dictionary = {}         # id -> Npc
var followers: Dictionary = {}    # id -> Neighbour (the goat, or the midwife when you bring her)
var clock := 0.0                  # 0..1 through a full day; night is the last part
var day_fraction := 0.65
var night := false
var done: Array = []              # errands finished
var active := ""                  # errand under way
var step := 0
var carrying := ""
var has_home := false
var pickup: Node2D                # the item waiting to be picked up, if any
var carried_icon: Sprite2D
var items_tex: Texture2D
var talk_lines: Array = []
var talk_name := ""
var after_talk: Callable
var tint: CanvasModulate


func setup(m: Node, d: Dictionary, village_choice: String) -> void:
	main = m
	data = d
	choice = village_choice
	items_tex = load("res://art/items/items.png")
	day_fraction = d.day_seconds / float(d.day_seconds + d.night_seconds)
	clock = d.get("start_hour", 0.1)
	for id in d.npcs:
		var info: Dictionary = d.npcs[id]
		var n := Npc.new()
		n.id = id
		n.display_name = info.name
		main._spawn(n, info.sprite, Vector2i(info.at[0], info.at[1]), main.actors)
		npcs[id] = n
	for id in d.followers:
		_make_follower(id, d.followers[id].sprite, Vector2i(d.followers[id].at[0], d.followers[id].at[1]))
	carried_icon = Sprite2D.new()
	carried_icon.texture = AtlasTexture.new()
	carried_icon.texture.atlas = items_tex
	carried_icon.position = Vector2(0, -30)
	carried_icon.visible = false
	main.player.add_child(carried_icon)
	_load()
	# anyone you've already brought home stays there
	for q in data.quests:
		if q.id in done:
			for s in q.steps:
				if s.do == "lead" and followers.has(s.who):
					followers[s.who].global_position = npcs[s.to].global_position + Vector2(16, 4)
					followers[s.who].home = followers[s.who].global_position
	_refresh_step()


func _make_follower(id: String, sprite: String, cell: Vector2i) -> Neighbour:
	var f := Neighbour.new()
	main._spawn(f, sprite, cell, main.actors)
	f.home = f.global_position
	f.prompt.text = ""
	followers[id] = f
	return f


# ---------------------------------------------------------------- time

func process(delta: float) -> void:
	if main.state == "play":
		clock = fmod(clock + delta / (data.day_seconds + data.night_seconds), 1.0)
	var was_night := night
	night = clock > day_fraction
	if night != was_night and main.state == "play":
		main.hud.say("Night falls. The watch is out: stay in the Jewish street, or stay out of sight." if night else "Morning. The city wakes up, and the watch goes home.", 5.0)
	# light: bright by day, dark blue by night, with a little dusk and dawn either side
	var dusk := 0.04
	var dark := 0.0
	if clock > day_fraction:
		dark = clampf((clock - day_fraction) / dusk, 0.0, 1.0) * clampf((1.0 - clock) / dusk, 0.0, 1.0)
	main.night_tint.color = Color(0.95, 0.92, 0.85).lerp(Color(0.24, 0.27, 0.42), dark)
	# errands that finish by arriving somewhere
	_check_lead()
	_update_marks()


func time_label() -> String:
	if night:
		return "Night"
	var t := clock / day_fraction
	return "Morning" if t < 0.33 else ("Afternoon" if t < 0.75 else "Evening")


func is_safe(pos: Vector2) -> bool:
	var a: Array = data.safe_area
	var c: Vector2i = main.level.cell_of(pos)
	return c.x >= a[0] and c.y >= a[1] and c.x <= a[2] and c.y <= a[3]


func mob_kind(id: String) -> String:
	return data.mobs.get(id, "watch")


# ---------------------------------------------------------------- errands

func quest() -> Dictionary:
	for q in data.quests:
		if q.id == active:
			return q
	return {}


func current_step() -> Dictionary:
	var q := quest()
	return q.steps[step] if not q.is_empty() and step < q.steps.size() else {}


func available(q: Dictionary) -> bool:
	if q.id in done or active != "":
		return false
	for r in q.get("requires", []):
		if not r in done:
			return false
	return night if q.get("night_only", false) else true


func _refresh_step() -> void:
	if pickup:
		pickup.queue_free()
		pickup = null
	var s := current_step()
	if s.get("do", "") == "get" and carrying != s.item:
		pickup = _make_pickup(s.item, Vector2i(s.at[0], s.at[1]))
	carried_icon.visible = carrying != ""
	if carrying != "":
		carried_icon.texture.region = Rect2(ITEMS.find(carrying) * 16, 0, 16, 16)
	if s.get("do", "") == "lead":
		_prepare_lead(s)


func _make_pickup(item: String, cell: Vector2i) -> Node2D:
	var node := Node2D.new()
	node.position = main.level.spot(cell)
	var sp := Sprite2D.new()
	sp.texture = AtlasTexture.new()
	sp.texture.atlas = items_tex
	sp.texture.region = Rect2(ITEMS.find(item) * 16, 0, 16, 16)
	sp.position = Vector2(0, -8)
	node.add_child(sp)
	var l := PointLight2D.new()
	l.texture = main.light_texture
	l.color = Color(1, 0.9, 0.5)
	l.energy = 0.8
	l.texture_scale = 0.4
	node.add_child(l)
	var t := node.create_tween().set_loops()
	t.tween_property(sp, "position:y", -12.0, 0.6)
	t.tween_property(sp, "position:y", -8.0, 0.6)
	main.actors.add_child(node)
	return node


func _prepare_lead(s: Dictionary) -> void:
	if s.who in npcs and not s.who in followers:
		# someone who normally stands still (the midwife) comes with you: swap them for a follower
		var n: Npc = npcs[s.who]
		var f := _make_follower(s.who, data.npcs[s.who].sprite, main.level.cell_of(n.global_position))
		n.visible = false
		n.set_physics_process(false)
		f.home = n.global_position


func _check_lead() -> void:
	var s := current_step()
	if s.get("do", "") != "lead":
		return
	var f: Neighbour = followers.get(s.who)
	if f and f.state == Neighbour.S.FOLLOWING and f.global_position.distance_to(npcs[s.to].global_position) < 34.0:
		f.state = Neighbour.S.HIDING
		f.velocity = Vector2.ZERO
		main.followers.erase(f)
		f.home = f.global_position
		_talk(npcs[s.to].display_name, _lines(s.get("lines", [])), _advance)


func _lines(l) -> Array:
	if l is String:   # a name of choice-dependent lines, e.g. letter_lines
		return data[l].get(choice, data[l].values()[0])
	return l


func _advance() -> void:
	var q := quest()
	step += 1
	if step >= q.steps.size():
		done.append(q.id)
		active = ""
		step = 0
		if q.get("unlocks", "") == "home":
			has_home = true
		main.hud.say("Errand done: %s. %s" % [q.title, q.get("reward", "")], 6.0)
		if done.size() == data.quests.size():
			await main.get_tree().create_timer(6.5).timeout
			main.hud.say(data.all_done, 8.0)
	else:
		main.hud.say(current_step().text, 5.0)
	_save()
	_refresh_step()


## E: talk to someone nearby, pick something up, call a follower, or sleep. Returns true if it did something.
func interact() -> bool:
	var p: Vector2 = main.player.global_position
	var s := current_step()
	if pickup and pickup.global_position.distance_to(p) < 22.0:
		carrying = s.item
		_advance()
		return true
	for id in followers:
		var f: Neighbour = followers[id]
		if f.state == Neighbour.S.HIDING and f.visible and f.global_position.distance_to(p) < 26.0 and s.get("who", "") == id:
			main._follow(f)
			main.hud.say("She follows you." if id != "goat" else "The goat bleats and trots after you.")
			return true
	for id in npcs:
		var n: Npc = npcs[id]
		if not n.visible or n.global_position.distance_to(p) > 28.0:
			continue
		_talk_to(id)
		return true
	if has_home and npcs.has("widow") and npcs.widow.global_position.distance_to(p) < 40.0 and (night or clock / day_fraction > 0.75):
		_sleep()
		return true
	return false


func _talk_to(id: String) -> void:
	var name: String = npcs[id].display_name
	var s := current_step()
	if s.get("do", "") == "receive" and s.from == id:
		carrying = s.item
		_talk(name, _lines(s.get("lines", [])), _advance)
		return
	if s.get("do", "") == "bring" and s.to == id and carrying == s.item:
		carrying = ""
		_talk(name, _lines(s.get("lines", [])), _advance)
		return
	if active == "":
		for q in data.quests:
			if q.giver == id and available(q):
				active = q.id
				step = 0
				_talk(name, q.offer, func():
					main.hud.say("New errand: %s. %s" % [q.title, current_step().text], 6.0)
					_save()
					_refresh_step())
				return
	if id == "widow" and has_home and (night or clock / day_fraction > 0.75):
		_sleep()   # in the evening, Gitl's door is your own
		return
	var info: Dictionary = data.npcs[id]
	var lines: Array = info.get("lines_before_home", info.lines) if not has_home else info.lines
	_talk(name, [lines[randi() % lines.size()]], Callable())


func _talk(name: String, lines: Array, then: Callable) -> void:
	talk_name = name
	talk_lines = lines.duplicate()
	after_talk = then
	main.state = "talk"
	next_line()


func next_line() -> void:
	if talk_lines.is_empty():
		main.hud.hide_dialogue()
		main.state = "play"
		if after_talk.is_valid():
			after_talk.call()
		return
	main.hud.show_dialogue(talk_name, talk_lines.pop_front())


func _sleep() -> void:
	main.state = "talk"
	main.hud.show_screen("", "You sleep.")
	await main.get_tree().create_timer(1.5).timeout
	clock = 0.02
	night = false
	for m in main.mobs:
		m.reset()
	main.player.global_position = npcs.widow.global_position + Vector2(0, 10)
	main.hud.hide_screen()
	main.state = "play"
	main.hud.say("Morning.", 3.0)
	_save()


## Caught by the watch or the toughs: no game over, but you lose what you carry and wake up at home.
func caught(by: Mob) -> void:
	main.state = "caught"
	main.hud.say(data.caught.get(mob_kind(by.id), "They catch you."), 6.0)
	await main.get_tree().create_timer(1.6).timeout
	var s := current_step()
	if carrying != "" and s.get("do", "") == "bring":
		# start the errand's carrying part again
		var lost := carrying
		carrying = ""
		step = maxi(0, step - 1)
		main.hud.say(main.hud.message.text + "  You've lost the %s." % lost, 6.0)
	for f in main.followers.duplicate():
		f.go_home()
	main.followers.clear()
	main.player.unhide()
	main.player.global_position = npcs.widow.global_position + Vector2(0, 10) if has_home else main.level.spot(main.level.player_start)
	for m in main.mobs:
		m.reset()
	main.player.safe_time = 3.0
	main.state = "play"
	_save()
	_refresh_step()


# ---------------------------------------------------------------- on screen

func hud_lines() -> Array:
	var lines := ["%s   (%d of %d errands done)" % [time_label(), done.size(), data.quests.size()]]
	var q := quest()
	if not q.is_empty():
		lines.append(q.title + ": " + current_step().get("text", ""))
	elif done.size() < data.quests.size():
		lines.append("Talk to people with a ! over their head")
	if carrying != "":
		lines.append("Carrying: " + carrying)
	return lines


## Where the arrow should point.
func target() -> Vector2:
	var s := current_step()
	match s.get("do", ""):
		"get":
			return pickup.global_position if pickup else Vector2.INF
		"receive":
			return npcs[s.from].global_position
		"bring":
			return npcs[s.to].global_position
		"lead":
			var f: Neighbour = followers.get(s.who)
			return f.global_position if f and f.state != Neighbour.S.FOLLOWING else npcs[s.to].global_position
	return Vector2.INF


func _update_marks() -> void:
	var s := current_step()
	for id in npcs:
		var n: Npc = npcs[id]
		var mark := ""
		if s.get("from", "") == id or (s.get("to", "") == id and (s.get("do") == "lead" or carrying == s.get("item", ""))):
			mark = "?"
		elif active == "":
			for q in data.quests:
				if q.giver == id and available(q):
					mark = "!"
		n.mark.text = mark


# ---------------------------------------------------------------- saving

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("city", "done", done)
	cfg.set_value("city", "active", active)
	cfg.set_value("city", "step", step)
	cfg.set_value("city", "carrying", carrying)
	cfg.set_value("city", "home", has_home)
	cfg.set_value("city", "clock", clock)
	cfg.save(SAVE_FILE)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_FILE) != OK:
		return
	done = cfg.get_value("city", "done", [])
	active = cfg.get_value("city", "active", "")
	step = cfg.get_value("city", "step", 0)
	carrying = cfg.get_value("city", "carrying", "")
	has_home = cfg.get_value("city", "home", false)
	clock = cfg.get_value("city", "clock", clock)
