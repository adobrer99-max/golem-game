extends AnimatedSprite2D
## Made by Sprite Studio. Keeps the Body and Attack areas in step with the animation,
## using the hit areas drawn for each frame. Boxes are measured from the origin point,
## which sits at this node's position, and they flip with flip_h / flip_v.

const BOXES_FILE := "boatman-boxes.json"
var _data: Dictionary = {}
var _base_offset := Vector2.ZERO
var _flip := Vector2i.ZERO

func _ready() -> void:
	var res = load(get_script().resource_path.get_base_dir().path_join(BOXES_FILE))
	if res is JSON and res.data is Dictionary:
		_data = res.data
	var o: Dictionary = _data.get("origin", {"x": 0, "y": 0})
	_base_offset = Vector2(_data.get("frameWidth", 0) / 2.0 - o["x"], _data.get("frameHeight", 0) / 2.0 - o["y"] - 1)
	frame_changed.connect(_update_boxes)
	animation_changed.connect(_update_boxes)
	_apply_flip()

func _process(_delta: float) -> void:
	if Vector2i(int(flip_h), int(flip_v)) != _flip:
		_apply_flip()

# Flipping mirrors the sprite around the origin point, so it turns on the spot.
func _apply_flip() -> void:
	_flip = Vector2i(int(flip_h), int(flip_v))
	offset = Vector2(-_base_offset.x if flip_h else _base_offset.x, -_base_offset.y if flip_v else _base_offset.y)
	_update_boxes()

## The boxes of one kind ("body" or "attack") on the current frame, relative to this node.
func get_boxes(kind: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var anim: Dictionary = _data.get("animations", {}).get(String(animation), {})
	var frames: Array = anim.get("frames", [])
	if frame >= frames.size():
		return out
	var o: Dictionary = _data.get("origin", {"x": 0, "y": 0})
	for b in frames[frame].get("boxes", []):
		if b["kind"] != kind:
			continue
		var r := Rect2(b["x"] - o["x"], b["y"] - o["y"] - 1, b["w"], b["h"])
		if flip_h:
			r.position.x = -r.position.x - r.size.x
		if flip_v:
			r.position.y = -r.position.y - r.size.y
		out.append(r)
	return out

func _update_boxes() -> void:
	for kind in ["body", "attack"]:
		var area := get_node_or_null(kind.capitalize()) as Area2D
		if area == null:
			continue
		for child in area.get_children():
			if child is CollisionShape2D:
				area.remove_child(child)
				child.queue_free()
		for r in get_boxes(kind):
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = r.size
			shape.shape = rect
			shape.position = r.position + r.size / 2.0
			area.add_child(shape)
