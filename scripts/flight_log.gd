extends "res://scripts/screen.gd"

signal menu_requested

const SKY := preload("res://assets/art/title_mars.png")
const FLIGHT_PATH := [Vector2(59, 250), Vector2(140, 163), Vector2(273, 142), Vector2(379, 112), Vector2(484, 57)]

var _chart: Control
var _flight_progress := 1.0
var menu_button: Button


func present(state: RefCounted, quiet_motion: bool) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 250
	var view := art_at(self, SKY, Rect2(Vector2.ZERO, SIZE))
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fill_at(self, Rect2(Vector2.ZERO, SIZE), Color(0.05, 0.04, 0.06, 0.66))
	var panel := panel_at(self, Rect2(92, 134, 1256, 610), Color("#17191e"))
	text_at(panel, "火星地表站  /  最后一份飞行日志", Rect2(46, 33, 650, 38), 19, ORANGE)
	text_at(panel, "星火归航", Rect2(42, 86, 560, 104), 78, INK, true)
	text_at(panel, "“这里是母星接引站。航线确认，欢迎回家。”", Rect2(48, 206, 567, 51), 22, INK)
	var route := "在北缘高地追踪到了最后的航标信号。" if state.third_record_source == "survey" else "与曙光站交换了最后一份航标记录。"
	var account := text_at(panel, "", Rect2(48, 271, 523, 109), 20, MUTED)
	account.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	account.text = route + "领队带着火星营地共同组装的归航舱，沿三座航标指引的航线出发。"
	fill_at(panel, Rect2(48, 401, 1160, 1), EDGE)
	var elapsed := int(state.clock)
	var values := ["%02d:%02d" % [int(elapsed / 60.0), elapsed % 60], "%d 人" % state.crew.size(), "%d 次" % state.requests.completed, "%d / 3" % state.expeditions.resolved.size()]
	var labels := ["地表任务用时", "营地队员", "邻站互助", "周边勘探"]
	for index in range(values.size()):
		var x := 48 + index * 293
		text_at(panel, labels[index], Rect2(x, 420, 260, 34), 18, MUTED)
		text_at(panel, values[index], Rect2(x, 454, 260, 50), 32, INK, true)
	if state.expeditions.patrol_count > 0:
		text_at(panel, "补给巡线 %d 次" % state.expeditions.patrol_count, Rect2(927, 505, 258, 31), 16, TEAL)
	var excavated := int(state.radar.collected["lens"]) + int(state.radar.collected["cache"])
	if excavated > 0:
		text_at(panel, "高地已发掘 %d / 2 处" % excavated, Rect2(927, 538, 258, 31), 16, TEAL)
	_chart = Control.new()
	_chart.position = Vector2(647, 65)
	_chart.size = Vector2(551, 313)
	_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_chart)
	_chart.draw.connect(_draw_chart)
	menu_button = button_at(panel, "返回主菜单", Rect2(48, 527, 272, 54), menu_requested.emit, true)
	menu_button.grab_focus()
	if not quiet_motion:
		_flight_progress = 0.0
		create_tween().tween_method(_move_ship, 0.0, 1.0, 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _move_ship(amount: float) -> void:
	_flight_progress = amount
	_chart.queue_redraw()


func _draw_chart() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 171104
	for star in range(78):
		var at := Vector2(rng.randf_range(9, 535), rng.randf_range(6, 296))
		_chart.draw_circle(at, rng.randf_range(0.7, 1.7), Color(0.84, 0.92, 0.93, rng.randf_range(0.17, 0.62)))
	var curve := Curve2D.new()
	curve.bake_interval = 3.0
	for index in range(FLIGHT_PATH.size()):
		var before: Vector2 = FLIGHT_PATH[maxi(0, index - 1)]
		var after: Vector2 = FLIGHT_PATH[mini(FLIGHT_PATH.size() - 1, index + 1)]
		var tangent := (after - before) * 0.16
		curve.add_point(FLIGHT_PATH[index], -tangent, tangent)
	var track := curve.get_baked_points()
	_chart.draw_polyline(track, Color("#536466"), 1.5, true)
	var flown := PackedVector2Array()
	var distance := curve.get_baked_length() * _flight_progress
	for point_index in range(ceili(distance / 3.0)):
		flown.append(curve.sample_baked(minf(distance, point_index * 3.0)))
	flown.append(curve.sample_baked(distance))
	if flown.size() > 1:
		_chart.draw_polyline(flown, TEAL, 2.3, true)
	for index in range(1, FLIGHT_PATH.size() - 1):
		var at: Vector2 = FLIGHT_PATH[index]
		_chart.draw_circle(at, 4.0, TEAL)
		_chart.draw_arc(at, 10.0, 0, TAU, 32, Color(TEAL, 0.5), 1.3, true)
	var mars: Vector2 = FLIGHT_PATH.front()
	var home: Vector2 = FLIGHT_PATH.back()
	_chart.draw_circle(mars, 37, Color(ORANGE, 0.09))
	_chart.draw_circle(mars, 29, Color("#ac5d42"))
	_chart.draw_circle(mars + Vector2(-10, -10), 7, Color("#924b37"))
	_chart.draw_circle(mars + Vector2(15, 7), 4, Color("#c88059"))
	_chart.draw_arc(mars, 29, 3.65, 5.82, 42, ORANGE, 2.4, true)
	_chart.draw_arc(home, 35, 0, TAU, 56, Color(TEAL, 0.24), 1, true)
	_chart.draw_circle(home, 22, Color("#42707d"))
	_chart.draw_arc(home, 21, 3.12, 5.34, 36, TEAL, 3.1, true)
	var u := clampf(distance, 0.0, curve.get_baked_length())
	var ship := curve.sample_baked(u)
	var bearing := (curve.sample_baked(minf(u + 2, curve.get_baked_length())) - curve.sample_baked(maxf(0, u - 2))).angle()
	# The vehicle stops in the reception orbit, above the surface marker.
	ship += Vector2(0, -24) * smoothstep(0.88, 1.0, _flight_progress)
	var arrow := PackedVector2Array()
	for v in [Vector2(10, 0), Vector2(-7, 5), Vector2(-3, 0), Vector2(-7, -5)]:
		arrow.append(ship + v.rotated(bearing))
	_chart.draw_colored_polygon(arrow, INK)
	_chart.draw_string(FACE, Vector2(35, 301), "火星", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ORANGE)
	_chart.draw_string(FACE, Vector2(437, 118), "母星接引站", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, TEAL)
