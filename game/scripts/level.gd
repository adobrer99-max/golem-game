class_name Level
extends Node2D
## Builds the town from a text map in levels/. Edit the text file to change the town:
## the legend at the bottom of the file explains each character.

const TILE := 16
enum T { STREET, DIRT, GRASS, ROOF, HOUSE_WALL, DOOR, WINDOW, BARREL, HAY, WATER, DOCK, GATE,
	STONE_TOP, STONE_FRONT, WELL, TREE, SYN_ROOF, SYN_WALL, CRATES, WINDOW_LIGHTS, SYN_STAR, SYN_MENORAH }
const SOLID := [T.ROOF, T.HOUSE_WALL, T.DOOR, T.WINDOW, T.WATER, T.STONE_TOP, T.STONE_FRONT,
	T.WELL, T.TREE, T.SYN_ROOF, T.SYN_WALL, T.CRATES, T.WINDOW_LIGHTS, T.SYN_STAR, T.SYN_MENORAH]
const HIDING := [T.BARREL, T.HAY]
const MARKERS := "PgNE123456789abcdefhijklmnopqrsuvxyz"

var width := 0
var height := 0
var cells: Array = []                 # tile type for every cell, cells[y][x]
var player_start := Vector2i.ZERO
var golem_start := Vector2i.ZERO
var neighbours: Array = []            # [cell, kind]
var mobs: Dictionary = {}             # "1" -> cell
var points: Dictionary = {}           # "b" -> cell
var patrols: Dictionary = {}          # "1" -> ["b", "c"]
var exits: Array[Vector2i] = []
var lit_windows: Array[Vector2i] = []   # windows with a Hanukkah menorah (L), which glow at night
var astar := AStarGrid2D.new()
var tilemap: TileMapLayer


func load_map(path: String) -> void:
	var rows: Array[String] = []
	var section := "map"
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line: String = raw.strip_edges(false, true)
		if line.begins_with("["):
			section = line
			continue
		if section == "map":
			if line != "":
				rows.append(line)
		elif section == "[patrols]" and not line.begins_with("#") and "=" in line:
			var parts := line.split("=")
			patrols[parts[0].strip_edges()] = Array(parts[1].strip_edges().split(" ", false))
	height = rows.size()
	for r in rows:
		width = maxi(width, r.length())
	for y in height:
		var row: Array = []
		for x in width:
			var ch := _ch(rows, x, y)
			row.append(_tile_for(ch, x, y, rows))
			var cell := Vector2i(x, y)
			match ch:
				"P": player_start = cell
				"g": golem_start = cell
				"N": neighbours.append([cell, "neighbour"])
				"E": neighbours.append([cell, "elder"])
				"X": exits.append(cell)
				"L", "U": lit_windows.append(cell)
			if ch.is_valid_int():
				mobs[ch] = cell
			elif ch in "abcdefhijklmnopqrsuvxyz":
				points[ch] = cell
		cells.append(row)


func _ch(rows: Array[String], x: int, y: int) -> String:
	if y < 0 or y >= rows.size() or x < 0 or x >= rows[y].length():
		return " "
	return rows[y][x]


func _tile_for(ch: String, x: int, y: int, rows: Array[String]) -> int:
	var below := _ch(rows, x, y + 1)
	match ch:
		",": return T.DIRT
		"\"": return T.GRASS
		"~": return T.WATER
		"=": return T.DOCK
		"X": return T.GATE
		"B": return T.BARREL
		"H": return T.HAY
		"C": return T.CRATES
		"O": return T.WELL
		"t": return T.TREE
		"D": return T.DOOR
		"w": return T.WINDOW
		"L": return T.WINDOW_LIGHTS
		"S": return T.SYN_STAR
		"U": return T.SYN_MENORAH
		"#": return T.ROOF if below in ["#", "D", "w", "L"] else T.HOUSE_WALL
		"T": return T.SYN_ROOF if below in ["T", "D", "S", "U"] else T.SYN_WALL
		"W": return T.STONE_TOP if below == "W" else T.STONE_FRONT
	if ch != " " and ch in MARKERS:
		# people and patrol points stand on whatever ground is around them
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var n := _ch(rows, x + d.x, y + d.y)
			if n == ",": return T.DIRT
			if n == "\"": return T.GRASS
			if n == "=": return T.DOCK
	return T.STREET


func build(tiles_texture: Texture2D) -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)
	var src := TileSetAtlasSource.new()
	src.texture = tiles_texture
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	var square := PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)])
	for i in tiles_texture.get_width() / TILE:
		src.create_tile(Vector2i(i, 0))
		if i in SOLID:
			var td := src.get_tile_data(Vector2i(i, 0), 0)
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, square)
	tilemap = TileMapLayer.new()
	tilemap.tile_set = ts
	tilemap.z_index = -10
	add_child(tilemap)
	for y in height:
		for x in width:
			tilemap.set_cell(Vector2i(x, y), 0, Vector2i(cells[y][x], 0))
	# grid the townsfolk, the Golem and the mob find their way on
	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2(TILE, TILE)
	astar.offset = Vector2(TILE / 2.0, TILE / 2.0)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in height:
		for x in width:
			if blocks_walking(Vector2i(x, y)):
				astar.set_point_solid(Vector2i(x, y))
	# invisible walls around the edge of the map
	var edge := StaticBody2D.new()
	edge.collision_layer = 1
	add_child(edge)
	var w := width * TILE
	var h := height * TILE
	for r in [Rect2(-16, -16, w + 32, 16), Rect2(-16, h, w + 32, 16), Rect2(-16, 0, 16, h), Rect2(w, 0, 16, h)]:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = r.size
		shape.shape = rect
		shape.position = r.position + r.size / 2.0
		edge.add_child(shape)


func tile_at(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= width or c.y >= height:
		return T.WATER
	return cells[c.y][c.x]


func blocks_walking(c: Vector2i) -> bool:
	var t := tile_at(c)
	return t in SOLID or t in HIDING


func is_hiding_spot(c: Vector2i) -> bool:
	return tile_at(c) in HIDING


func is_exit(c: Vector2i) -> bool:
	return c in exits


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))


func center(c: Vector2i) -> Vector2:
	return Vector2(c) * TILE + Vector2(TILE / 2.0, TILE / 2.0)


## The feet of a character standing in this cell.
func spot(c: Vector2i) -> Vector2:
	return center(c) + Vector2(0, 4)


func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := cell_of(from)
	var b := cell_of(to)
	if astar.is_in_boundsv(a) and astar.is_point_solid(a):
		a = nearest_open(a)
	if not astar.is_in_boundsv(b):
		return PackedVector2Array()
	var target_solid := astar.is_point_solid(b)
	if target_solid:
		b = nearest_open(b, from)   # e.g. a barrel: walk to the free tile next to it
	var p := astar.get_point_path(a, b, true)
	for i in p.size():
		p[i] += Vector2(0, 4)
	if p.size() > 0 and not target_solid:
		p[p.size() - 1] = to   # finish exactly on the target
	return p


## The closest free tile to c, preferring the side nearest `toward` when given.
func nearest_open(c: Vector2i, toward := Vector2.INF) -> Vector2i:
	for r in range(1, 4):
		var best := c
		var bd := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if astar.is_in_boundsv(n) and not astar.is_point_solid(n):
					var d := 0.0 if toward == Vector2.INF else center(n).distance_to(toward)
					d += Vector2(dx, dy).length() * 4.0
					if d < bd:
						bd = d
						best = n
		if best != c:
			return best
	return c


## True when nothing solid (walls, houses) is between two points.
func clear_line(a: Vector2, b: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(a, b, 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


## How far a ray gets from a towards b before hitting a wall.
func ray_end(a: Vector2, b: Vector2) -> Vector2:
	var q := PhysicsRayQueryParameters2D.create(a, b, 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else b
