extends Control

signal move_requested(at: Vector2)

const BASE := Color("#201b1b")
const STROKE := Color("#48352e")
const ACCENT := Color("#b97c59")

func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		move_requested.emit(event.position)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BASE)
	_draw_terrain()
	for x in range(0, int(size.x), 32):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.84, 0.66, 0.52, 0.06 if x % 128 else 0.13))
	for y in range(0, int(size.y), 32):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.84, 0.66, 0.52, 0.06 if y % 128 else 0.13))
	for x in range(32, int(size.x), 128):
		for y in range(64, int(size.y), 128):
			var at := Vector2(x, y)
			draw_line(at - Vector2(3, 0), at + Vector2(3, 0), Color("#745b4d"))
			draw_line(at - Vector2(0, 3), at + Vector2(0, 3), Color("#745b4d"))
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color("#735043"), false)
	var compass := Vector2(size.x - 32.0, 42)
	draw_circle(compass, 13, STROKE, false, 1.0, true)
	draw_colored_polygon(PackedVector2Array([compass + Vector2(0, -10),
		compass + Vector2(4, 5), compass + Vector2(0, 2), compass + Vector2(-4, 5)]), ACCENT)


func _draw_terrain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1274
	var formations := [
		[Vector2(155, 276), Vector2(259, 165), 8, Color("#714434")],
		[Vector2(851, 39), Vector2(324, 165), 9, Color("#624033")],
		[Vector2(681, 625), Vector2(392, 192), 10, Color("#5b3b31")],
		[Vector2(58, 648), Vector2(212, 226), 7, Color("#684535")],
	]
	for formation in formations:
		var center: Vector2 = formation[0]
		var radius: Vector2 = formation[1]
		for contour in range(formation[2], 0, -1):
			var vertices := PackedVector2Array()
			var fraction := 0.28 + float(contour) / float(formation[2]) * 0.85
			for i in range(73):
				var angle := TAU * float(i % 72) / 72.0
				var roughness := 1.0 + 0.15 * sin(angle * 3.0 + 0.4) + 0.08 * cos(angle * 5.0 - 0.8)
				vertices.append(center + Vector2(cos(angle), sin(angle)) * radius * fraction * roughness)
			var shade: Color = formation[3]
			var fill := shade
			fill.a = 0.032
			draw_colored_polygon(vertices.slice(0, 72), fill)
			shade.a = 0.38
			draw_polyline(vertices, shade, 1.0, true)
	for i in range(390):
		var at := Vector2(rng.randf_range(1, size.x), rng.randf_range(1, size.y))
		var radius := rng.randf_range(0.35, 1.9)
		draw_circle(at, radius, Color(0.83, 0.55, 0.40, rng.randf_range(0.03, 0.13)))
