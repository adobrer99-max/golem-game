golem — exported from Sprite Studio for Godot 4

Unzip this folder anywhere inside your Godot project and keep the files together.

Easiest: drag golem.tscn into your level. It's an AnimatedSprite2D that plays "idle_down" on its own, with crisp pixels,
and its position is the sprite's origin point (where its feet touch the ground).
It has two Area2D children, Body and Attack, whose shapes follow the hit areas drawn on each frame.
Connect their area_entered signals to react to hits.

Or use just the animations: add an AnimatedSprite2D and drag golem.tres onto "Sprite Frames".

Animations: idle_down (2 fps, loops), walk_down (5 fps, loops), shove_down (10 fps, plays once), idle_up (2 fps, loops), walk_up (5 fps, loops), shove_up (10 fps, plays once), idle_side (2 fps, loops), walk_side (5 fps, loops), shove_side (10 fps, plays once).
Play one from a script with $Sprite.play("idle_down") (use your node's name).
Frames are 24x24px; each animation is one row of golem-sheet.png. golem-boxes.json lists every frame and its hit areas.
