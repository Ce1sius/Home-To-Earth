extends Control

const LandingCard := preload("res://scripts/landing_card.gd")
const CYAN := Color("#a4cfc7")
const PALE := Color("#d5e8db")
const STEEL := Color("#688482")
const SHADOW := Color("#354c50")
const AMBER := Color("#ddab7f")

var item := ""


func _draw() -> void:
	match item:
		"scrap", "ore":
			var region: Rect2 = LandingCard.REGIONS["scrap" if item == "scrap" else "sample"]
			var fit := region.size * minf(size.x / region.size.x, size.y / region.size.y)
			draw_texture_rect_region(LandingCard.ATLAS, Rect2((size - fit) / 2, fit), region)
		"ice", "plate":
			draw_set_transform(Vector2.ZERO, 0, size / 100)
			if item == "ice":
				_facet([Vector2(10, 66), Vector2(27, 31), Vector2(48, 19), Vector2(77, 41), Vector2(92, 63), Vector2(56, 84), Vector2(24, 81)], Color("#6fa1b3"))
				_facet([Vector2(10, 66), Vector2(27, 31), Vector2(48, 19), Vector2(52, 45), Vector2(36, 65)], Color("#c3e6e9"))
				_facet([Vector2(36, 65), Vector2(52, 45), Vector2(77, 41), Vector2(92, 63), Vector2(64, 70)], Color("#a4cbd5"))
			else:
				_facet([Vector2(7, 49), Vector2(62, 23), Vector2(94, 36), Vector2(94, 54), Vector2(39, 81), Vector2(7, 67)], Color("#8f8176"))
				_facet([Vector2(7, 49), Vector2(62, 23), Vector2(94, 36), Vector2(39, 64)], Color("#c5b8a3"))
				for x in [23, 56]:
					draw_line(Vector2(x, 49 - (x - 23) * 0.46), Vector2(x + 22, 57 - (x - 23) * 0.46), Color("#8d8170"), 2, true)
		"cooler", "winch":
			draw_set_transform(Vector2.ZERO, 0, size / 100)
			draw_rect(Rect2(0, 0, 100, 100), Color("#203234"))
			for step in range(0, 101, 10):
				draw_line(Vector2(step, 0), Vector2(step, 100), Color("#2b4040"))
				draw_line(Vector2(0, step), Vector2(100, step), Color("#2b4040"))
			if item == "cooler":
				_draw_cooler()
			else:
				_draw_winch()


func _draw_cooler() -> void:
	_facet([Vector2(13, 42), Vector2(43, 25), Vector2(85, 36), Vector2(58, 54)], STEEL)
	_facet([Vector2(13, 42), Vector2(58, 54), Vector2(58, 80), Vector2(15, 67)], SHADOW)
	_facet([Vector2(58, 54), Vector2(85, 36), Vector2(83, 62), Vector2(58, 80)], Color("#466461"))
	draw_polyline(PackedVector2Array([Vector2(13, 42), Vector2(43, 25), Vector2(85, 36), Vector2(83, 62), Vector2(58, 80), Vector2(15, 67), Vector2(13, 42), Vector2(58, 54), Vector2(85, 36)]), CYAN, 1.6, true)
	draw_polyline(PackedVector2Array([Vector2(24, 46), Vector2(24, 52), Vector2(29, 53), Vector2(29, 47)]), AMBER, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(42, 51), Vector2(42, 57), Vector2(47, 59), Vector2(47, 52)]), AMBER, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(35, 36), Vector2(42, 31), Vector2(60, 36), Vector2(53, 41)]), PALE, 2, true)


func _draw_winch() -> void:
	_facet([Vector2(9, 73), Vector2(59, 88), Vector2(90, 74), Vector2(39, 63)], SHADOW)
	draw_polyline(PackedVector2Array([Vector2(16, 71), Vector2(25, 43), Vector2(32, 43), Vector2(40, 77), Vector2(16, 71)]), STEEL, 3, true)
	draw_circle(Vector2(30, 41), 17, STEEL)
	draw_line(Vector2(30, 41), Vector2(62, 49), CYAN, 23, true)
	for i in range(6):
		var x := 34 + 5 * i
		var y := 41 + i
		draw_line(Vector2(x, y - 11), Vector2(x - 4, y + 11), SHADOW, 2, true)
	draw_circle(Vector2(64, 50), 17, SHADOW)
	draw_arc(Vector2(64, 50), 17, 0, TAU, 32, PALE, 2, true)
	draw_circle(Vector2(64, 50), 3, AMBER)
	draw_polyline(PackedVector2Array([Vector2(64, 50), Vector2(77, 47), Vector2(83, 36), Vector2(90, 38)]), AMBER, 3, true)
	draw_polyline(PackedVector2Array([Vector2(48, 80), Vector2(57, 54), Vector2(64, 51), Vector2(73, 77)]), STEEL, 3, true)


func _facet(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)
