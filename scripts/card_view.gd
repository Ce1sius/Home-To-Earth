extends Control

signal picked(id: String)
signal ordered(id: String)
signal stacked(target: String, payload: Dictionary)

const INK := Color("#f5eadf")
const MUTED := Color("#ad9b90")
const MARS := Color("#eda878")
const ICE := Color("#8bcfc7")
const ORE := Color("#e1c18a")
const RED := Color("#f19785")

const TONES := {
	"wreck": MARS, "ore": ORE, "ice": ICE, "casualty": RED, "bench": MARS,
	"greenhouse": ICE, "lab": ORE, "relay": ICE, "beacon": MARS,
	"lead": MARS, "tech": ICE, "food": ICE, "scrap": MARS, "plate": ORE, "circuit": ICE,
}

const MARKS := {
	"wreck": "W", "ore": "M", "ice": "I", "casualty": "+", "bench": "F",
	"greenhouse": "G", "lab": "R", "relay": "D", "beacon": "B",
	"lead": "01", "tech": "02", "food": "FD", "scrap": "SC", "plate": "PL", "circuit": "IC",
}

var key := ""
var kind := ""
var heading := ""
var caption := ""
var amount := ""
var ratio := -1.0
var selected := false
var hovered := false
var font_face: Font
var title_face: Font


func configure(id: String, type: String, name_text: String, face: Font, bold_face: Font) -> void:
	key = id
	kind = type
	heading = name_text
	font_face = face
	title_face = bold_face
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))


func update_display(detail: String, status: String, progress: float, focused: bool) -> void:
	if detail == caption and status == amount and is_equal_approx(progress, ratio) and focused == selected:
		return
	caption = detail
	amount = status
	ratio = progress
	selected = focused
	queue_redraw()


func _hover(is_hovered: bool) -> void:
	hovered = is_hovered
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(key)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			ordered.emit(key)
			accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if kind == "site" or (kind == "item" and amount == "0"):
		return null
	var preview: Control = get_script().new()
	preview.configure(key, kind, heading, font_face, title_face)
	preview.size = size
	preview.caption = caption
	preview.amount = amount
	preview.selected = true
	preview.modulate.a = 0.88
	preview.position = -size / 2.0
	preview.mouse_filter = MOUSE_FILTER_IGNORE
	var wrapper := Control.new()
	wrapper.add_child(preview)
	set_drag_preview(wrapper)
	return {"kind": kind, "id": key}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return kind == "site" and data is Dictionary and data.get("kind") in ["crew", "item"]


func _drop_data(_at: Vector2, data: Variant) -> void:
	stacked.emit(key, data)


func _draw() -> void:
	if font_face == null:
		return
	var tone: Color = TONES.get(key, ORE)
	var border := Color("#705045")
	var base := Color("#252122")
	if kind == "item":
		base = Color("#171c21")
		border = Color("#394047")
	elif kind == "crew":
		base = Color("#262a2d")
		border = Color("#776458")
	if selected or hovered:
		border = tone
	var shell := StyleBoxFlat.new()
	shell.bg_color = base
	shell.border_color = border
	shell.set_border_width_all(1 if not selected else 2)
	shell.set_corner_radius_all(6)
	if kind != "item":
		shell.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
		shell.shadow_size = 5
		shell.shadow_offset = Vector2(0, 3)
	draw_style_box(shell, Rect2(Vector2.ZERO, size))
	if kind == "item":
		_draw_item(tone)
	elif kind == "crew":
		_draw_crew(tone)
	else:
		_draw_site(tone)


func _draw_item(tone: Color) -> void:
	var symbol: String = MARKS.get(key, "·")
	if key == "ore":
		symbol = "OR"
	elif key == "ice":
		symbol = "WI"
	draw_rect(Rect2(9, 10, 30, 26), Color(tone, 0.12))
	draw_string(title_face, Vector2(13, 28), symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tone)
	draw_string(font_face, Vector2(48, 29), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
	draw_string(title_face, Vector2(94, 30), amount, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 106, 20, INK)


func _draw_crew(tone: Color) -> void:
	draw_rect(Rect2(8, 8, 32, 34), Color(tone, 0.13))
	_draw_symbol(Vector2(24, 23), tone)
	draw_string(title_face, Vector2(49, 22), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
	draw_string(font_face, Vector2(49, 40), caption, HORIZONTAL_ALIGNMENT_LEFT, 103, 11, tone)
	_draw_progress(tone)


func _draw_site(tone: Color) -> void:
	draw_rect(Rect2(1, 1, size.x - 2, 31), Color(tone, 0.08))
	_draw_symbol(Vector2(18, 16), tone)
	draw_string(font_face, Vector2(34, 21), caption, HORIZONTAL_ALIGNMENT_LEFT, 87, 11, tone)
	draw_string(title_face, Vector2(11, 54), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	draw_string(font_face, Vector2(11, 74), amount, HORIZONTAL_ALIGNMENT_LEFT, 107, 11, MUTED)
	_draw_progress(tone)


func _draw_progress(tone: Color) -> void:
	if ratio < 0.0:
		return
	draw_rect(Rect2(5, size.y - 5, size.x - 10, 2), Color(tone, 0.18))
	draw_rect(Rect2(5, size.y - 5, (size.x - 10) * ratio, 2), tone)


func _draw_symbol(center: Vector2, tone: Color) -> void:
	match key:
		"lead", "tech", "botanist":
			draw_arc(center, 6.5, PI, TAU, 16, tone, 1.6, true)
			draw_rect(Rect2(center - Vector2(6.5, 0), Vector2(13, 6)), tone, false, 1.5)
			draw_line(center + Vector2(-4, 1), center + Vector2(4, 1), tone, 1.6, true)
		"beacon", "relay", "outpost", "trail":
			draw_line(center + Vector2(0, -1), center + Vector2(0, 8), tone, 1.5, true)
			draw_arc(center, 7, -PI * 0.83, -PI * 0.17, 14, tone, 1.5, true)
			draw_circle(center, 2, tone, true, -1, true)
		"array":
			for offset in [-12, 0, 12]:
				var mast := center + Vector2(offset, abs(offset) / 3.0)
				draw_line(mast, mast + Vector2(0, 13), tone, 1.5, true)
				draw_arc(mast + Vector2(0, -4), 5, 0, PI, 12, tone, 1.5, true)
			draw_line(center + Vector2(-16, 17), center + Vector2(16, 17), tone, 1.3, true)
		"greenhouse":
			draw_arc(center + Vector2(0, 4), 7, PI, TAU, 18, tone, 1.5, true)
			draw_line(center + Vector2(-7, 4), center + Vector2(7, 4), tone, 1.5, true)
			draw_line(center + Vector2(0, -3), center + Vector2(0, 4), tone, 1.5, true)
		"shelter":
			draw_rect(Rect2(center - Vector2(11, 6), Vector2(22, 15)), tone, false, 1.5)
			draw_line(center + Vector2(-14, -6), center + Vector2(0, -14), tone, 1.5, true)
			draw_line(center + Vector2(0, -14), center + Vector2(14, -6), tone, 1.5, true)
		"plate", "circuit":
			draw_rect(Rect2(center - Vector2(6, 5), Vector2(12, 10)), tone, false, 1.3)
			if key == "plate":
				draw_line(center - Vector2(4, 0), center + Vector2(4, 0), tone, 1.4, true)
			else:
				for pin in [-3, 0, 3]:
					draw_line(center + Vector2(pin, -8), center + Vector2(pin, -5), tone, 1.2, true)
					draw_line(center + Vector2(pin, 5), center + Vector2(pin, 8), tone, 1.2, true)
		"casualty":
			draw_line(center - Vector2(6, 0), center + Vector2(6, 0), tone, 2, true)
			draw_line(center - Vector2(0, 6), center + Vector2(0, 6), tone, 2, true)
		"ice":
			for angle in [0.0, PI / 3, PI * 2 / 3]:
				var axis := Vector2.from_angle(angle) * 7
				draw_line(center - axis, center + axis, tone, 1.5, true)
		"ore", "wreck":
			var shape := PackedVector2Array([Vector2(-7, 5), Vector2(-3, -5),
				Vector2(3, -6), Vector2(7, 1), Vector2(4, 6), Vector2(-7, 5)])
			for i in range(shape.size()):
				shape[i] += center
			draw_polyline(shape, tone, 1.5, true)
		_:
			draw_circle(center, 6, tone, false, 1.3, true)
			draw_line(center - Vector2(3, 0), center + Vector2(3, 0), tone, 1.2, true)
			draw_line(center - Vector2(0, 3), center + Vector2(0, 3), tone, 1.2, true)
