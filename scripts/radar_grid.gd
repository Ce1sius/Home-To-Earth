extends Control

signal cell_chosen(cell: Vector2i)

const FACE := preload("res://assets/fonts/FandolHei-Regular.otf")
const BOLD := preload("res://assets/fonts/FandolHei-Bold.otf")
const TERRAIN := preload("res://assets/art/northern_highlands.png")
const COLUMNS := "ABCDEFGHI"
const ROWS := 6
const STEP := 76.0
const ORIGIN := Vector2(42, 35)
const FIELD_SIZE := Vector2(684, 456)
const TONES := [Color("#9bf1e4"), Color("#ffd793"), Color("#e8aeeb")]
const INK := Color("#f8eee0")
const TICK := Color("#a6c1b9")

var cursor_cell := Vector2i(4, 2)
var _state: RefCounted
var _zone := "lens"
var _marking := false
var _plot: Control


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_ALL
	mouse_default_cursor_shape = CURSOR_CROSS
	var clip := Control.new()
	clip.position = ORIGIN
	clip.size = FIELD_SIZE
	clip.clip_contents = true
	clip.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(clip)
	_plot = Control.new()
	_plot.size = FIELD_SIZE
	_plot.mouse_filter = MOUSE_FILTER_IGNORE
	clip.add_child(_plot)
	_plot.draw.connect(_draw_plot)
	focus_entered.connect(_redraw)
	focus_exited.connect(_redraw)


func display(state: RefCounted, zone: String, marking: bool) -> void:
	_state = state
	if _zone != zone:
		cursor_cell = Vector2i(4, 2)
	_zone = zone
	_marking = marking
	_redraw()


func cell_center(cell: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * STEP


static func coord(cell: Vector2i) -> String:
	return "%s%d" % [COLUMNS.substr(cell.x, 1), cell.y + 1]


func _redraw() -> void:
	queue_redraw()
	_plot.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if Rect2(ORIGIN, FIELD_SIZE).has_point(event.position):
			var cell := Vector2i(((event.position - ORIGIN) / STEP).floor())
			if cursor_cell != cell:
				cursor_cell = cell
				_redraw()
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				grab_focus()
				cell_chosen.emit(cell)
		accept_event()
		return
	var shift := Vector2i.ZERO
	var directions := {"ui_left": Vector2i.LEFT, "ui_right": Vector2i.RIGHT, "ui_up": Vector2i.UP, "ui_down": Vector2i.DOWN}
	for binding in directions:
		if event.is_action_pressed(binding, true):
			shift = directions[binding]
			break
	if shift != Vector2i.ZERO:
		cursor_cell = (cursor_cell + shift).clamp(Vector2i.ZERO, Vector2i(8, 5))
		_redraw()
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		cell_chosen.emit(cursor_cell)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#131b1e"))
	var edge := Color("#e0af78") if has_focus() else Color("#51645e")
	draw_rect(Rect2(ORIGIN - Vector2.ONE, FIELD_SIZE + Vector2(2, 2)), edge, false, 2.0)
	for x in range(COLUMNS.length()):
		draw_string(FACE, Vector2(ORIGIN.x + STEP * x, 24), COLUMNS.substr(x, 1), HORIZONTAL_ALIGNMENT_CENTER, STEP, 18, TICK)
	for y in range(ROWS):
		draw_string(FACE, Vector2(2, cell_center(Vector2i(0, y)).y + 6), str(y + 1), HORIZONTAL_ALIGNMENT_CENTER, 35, 18, TICK)


func _draw_plot() -> void:
	var frame := Rect2(Vector2.ZERO, FIELD_SIZE)
	var lens := _zone == "lens"
	var crop := Rect2(0, 187, 780, 520) if lens else Rect2(756, 0, 780, 520)
	_plot.draw_texture_rect_region(TERRAIN, frame, crop, Color("#f0d8be"))
	_plot.draw_rect(frame, Color(0.045, 0.155, 0.19, 0.44) if lens else Color(0.16, 0.10, 0.12, 0.34))
	_draw_relief(lens)
	var lines := Color(0.88, 0.89, 0.79, 0.36)
	for col in range(1, COLUMNS.length()):
		_plot.draw_line(Vector2(col * STEP, 0), Vector2(col * STEP, FIELD_SIZE.y), lines)
	for row in range(1, ROWS):
		_plot.draw_line(Vector2(0, row * STEP), Vector2(FIELD_SIZE.x, row * STEP), lines)
	for x in range(COLUMNS.length()):
		for y in range(ROWS):
			_plot.draw_circle(cell_center(Vector2i(x, y)) - ORIGIN, 2.0, Color(0.92, 0.92, 0.83, 0.67))
	if _state == null:
		return
	var radar: RefCounted = _state.radar
	var samples: Array = radar.probes[_zone]
	for i in range(samples.size()):
		var center := cell_center(samples[i]) - ORIGIN
		var radius: float = radar.reading(_zone, samples[i]) * STEP
		if radius > 0.0:
			_plot.draw_arc(center, radius, 0, TAU, 220, Color(0.07, 0.09, 0.09, 0.7), 5.5, true)
			_plot.draw_arc(center, radius, 0, TAU, 220, TONES[i], 2.6, true)
	for i in range(samples.size()):
		var center := cell_center(samples[i]) - ORIGIN
		_plot.draw_circle(center, 14, Color("#182024"))
		_plot.draw_arc(center, 13, 0, TAU, 36, TONES[i], 2.0, true)
		_plot.draw_string(BOLD, center + Vector2(-13, 6), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 26, 16, TONES[i])
	if radar.marked[_zone]:
		var point := cell_center(radar.marked_cell(_zone)) - ORIGIN
		var diamond := PackedVector2Array([point + Vector2.UP * 19, point + Vector2.RIGHT * 19, point + Vector2.DOWN * 19, point + Vector2.LEFT * 19, point + Vector2.UP * 19])
		_plot.draw_colored_polygon(diamond.slice(0, 4), Color(0.94, 0.66, 0.32, 0.28))
		_plot.draw_polyline(diamond, INK, 3, true)
	else:
		_draw_cursor()


func _draw_cursor() -> void:
	var center := cell_center(cursor_cell) - ORIGIN
	var tone := Color("#ffce81") if _marking else Color("#d0e9df")
	_plot.draw_rect(Rect2(center - Vector2.ONE * STEP / 2, Vector2.ONE * STEP), Color(tone, 0.10))
	for sign_x in [-1, 1]:
		for sign_y in [-1, 1]:
			var at := center + Vector2(sign_x * 22, sign_y * 22)
			_plot.draw_line(at, at - Vector2(sign_x * 10, 0), tone, 2, true)
			_plot.draw_line(at, at - Vector2(0, sign_y * 10), tone, 2, true)


func _draw_relief(lens: bool) -> void:
	# Parallel elevation traces remain dimmer than the three measured echo circles.
	for band in range(-3, 25):
		var line := PackedVector2Array()
		for x in range(-8, 705, 8):
			var offset := float(band * 23)
			var height := sin(x * 0.008 + offset * 0.005) * 27.0 + sin(x * 0.017 - offset * 0.007) * 13.0
			var y := offset + height + (0.11 if lens else -0.18) * x
			line.append(Vector2(x, y))
		var opacity := 0.13 if band % 4 == 0 else 0.055
		_plot.draw_polyline(line, Color(0.86, 0.76, 0.60, opacity), 1.2, true)
