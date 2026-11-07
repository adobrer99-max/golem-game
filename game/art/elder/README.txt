elder — exported from Sprite Studio for Godot 4

Unzip this folder anywhere inside your Godot project and keep the files together.

Easiest: drag elder.tscn into your level. It's an AnimatedSprite2D that plays "idle_down" on its own, with crisp pixels,
and its position is the sprite's origin point (where its feet touch the ground).
It has two Area2D children, Body and Attack, whose shapes follow the hit areas drawn on each frame.
Connect their area_entered signals to react to hits.

Or use just the animations: add an AnimatedSprite2D and drag elder.tres onto "Sprite Frames".

Animations: idle_down (2 fps, loops), walk_down (6 fps, loops), idle_up (2 fps, loops), walk_up (6 fps, loops), idle_side (2 fps, loops), walk_side (6 fps, loops).
Play one from a script with $Sprite.play("idle_down") (use your node's name).
Frames are 16x16px; each animation is one row of elder-sheet.png. elder-boxes.json lists every frame and its hit areas.
