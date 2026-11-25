extends "res://scripts/screen.gd"

signal close_requested

const RadarGrid := preload("res://scripts/radar_grid.gd")
const PANEL := Color("#191c1e")
const SLATE := Color("#20292a")
const EDGE_LIGHT := Color("#445652")

var close_button: Button
var zone_buttons := {}
var grid_control: Control
var mark_button: Button
var undo_button: Button

var _state: RefCounted
var _zone := "lens"
var _marking := false
var _survey_name: Label
var _cargo: Label
var _sample_count: Label
var _rows: Array[Label] = []
var _ranges: Array[Label] = []
var _notice: Label


func present(state: RefCounted) -> void:
	_state = state
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	z_index = 210
	fill_at(self, Rect2(Vector2.ZERO, SIZE), Color(0.025, 0.035, 0.045, 0.78))
	var base := panel_at(self, Rect2(72, 58, 1296, 784), PANEL)
	text_at(base, "高地地质雷达", Rect2(32, 20, 540, 62), 36, INK, true)
	text_at(base, "点击格心放置探针，回波圆经过埋藏点。用至少两个回波的交点定位。", Rect2(34, 82, 1090, 37), 19, MUTED)
	close_button = button_at(base, "返回高地", Rect2(1088, 34, 172, 49), close_requested.emit)
	fill_at(base, Rect2(30, 133, 1236, 1), EDGE_LIGHT)
	for i in range(2):
		var id: String = ["lens", "cache"][i]
		zone_buttons[id] = button_at(base, "", Rect2(32 + i * 343, 151, 326, 44), _select_zone.bind(id))
	grid_control = RadarGrid.new()
	grid_control.position = Vector2(32, 211)
	grid_control.size = Vector2(746, 508)
	base.add_child(grid_control)
	grid_control.cell_chosen.connect(_select_cell)
	text_at(base, "方向键移动格心  ·  回车确认  ·  Tab 切换控件", Rect2(42, 727, 730, 32), 17, MUTED)
	_build_readout(base)
	_refresh()
	grid_control.grab_focus()


func _build_readout(base: Control) -> void:
	var rail := panel_at(base, Rect2(798, 151, 464, 604), SLATE)
	_survey_name = text_at(rail, "", Rect2(22, 15, 417, 47), 27, INK, true)
	_cargo = text_at(rail, "", Rect2(23, 64, 420, 31), 18, ORANGE)
	fill_at(rail, Rect2(22, 109, 420, 1), EDGE_LIGHT)
	text_at(rail, "探针回波", Rect2(22, 124, 279, 38), 22, TEAL, true)
	_sample_count = text_at(rail, "", Rect2(340, 127, 101, 30), 18, MUTED)
	_sample_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for i in range(3):
		var y := 176 + i * 55
		var accent: Color = RadarGrid.TONES[i]
		fill_at(rail, Rect2(23, y + 8, 4, 27), accent)
		text_at(rail, "%02d" % (i + 1), Rect2(36, y, 53, 42), 18, accent, true)
		_rows.append(text_at(rail, "", Rect2(108, y, 101, 42), 22, INK, true))
		var distance := text_at(rail, "", Rect2(207, y, 232, 42), 19, MUTED)
		distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_ranges.append(distance)
		fill_at(rail, Rect2(23, y + 50, 417, 1), EDGE_LIGHT)
	_notice = text_at(rail, "", Rect2(24, 352, 416, 88), 19, INK)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mark_button = button_at(rail, "标记埋藏点", Rect2(21, 454, 421, 55), _toggle_mark, true)
	undo_button = button_at(rail, "撤回上一枚探针", Rect2(21, 519, 421, 49), _undo)


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_requested.emit()


func _select_zone(id: String) -> void:
	_zone = id
	_marking = false
	_refresh()
	grid_control.grab_focus()


func _select_cell(cell: Vector2i) -> void:
	var radar: RefCounted = _state.radar
	var unavailable: String = radar.operator_reason(_state)
	if radar.marked[_zone] or not unavailable.is_empty():
		_refresh()
		return
	var point := RadarGrid.coord(cell)
	var samples: Array = radar.probes[_zone]
	if _marking:
		if radar.mark(_state, _zone, cell):
			_marking = false
			_refresh()
		else:
			_refresh("%s 没有匹配的埋藏回波。探针与物资均保留，选另一个格心再试。" % point, true)
	elif samples.has(cell):
		_refresh("%s 已经布设探针，请到另一个格心取样。" % point)
	elif samples.size() >= 3:
		_refresh("三枚探针都在工作。点击「标记埋藏点」，或先撤回最后一枚再换位置。")
	elif radar.place(_state, _zone, cell):
		_refresh()
	else:
		_refresh("这次未能取得读数，请重新选点。", true)


func _undo() -> void:
	if _state.radar.undo(_state, _zone):
		_marking = false
		_refresh("已撤回最后一枚探针，可在另一格重新布设。")
		grid_control.grab_focus()


func _toggle_mark() -> void:
	_marking = not _marking
	_refresh()
	grid_control.grab_focus()


func _refresh(message: String = "", warn: bool = false) -> void:
	var radar: RefCounted = _state.radar
	for id: String in zone_buttons:
		var active := id == _zone
		var button: Button = zone_buttons[id]
		var phase := "已回收" if radar.collected[id] else ("已定位" if radar.marked[id] else "测区")
		button.text = "%s  ·  %s" % [radar.ZONES[id]["title"], phase]
		button.add_theme_stylebox_override("normal", _box(Color("#294541") if active else Color("#262729"), TEAL if active else EDGE_LIGHT))
	_survey_name.text = radar.ZONES[_zone]["title"]
	var goods := PackedStringArray()
	for id: String in radar.ZONES[_zone]["reward"]:
		goods.append("%s ×%d" % [_state.ITEMS[id], radar.ZONES[_zone]["reward"][id]])
	_cargo.text = "可回收   " + "、".join(goods)
	var samples: Array = radar.probes[_zone]
	_sample_count.text = "%d / 3" % samples.size()
	for i in range(3):
		if i < samples.size():
			_rows[i].text = RadarGrid.coord(samples[i])
			_ranges[i].text = _distance(float(radar.reading(_zone, samples[i])))
		else:
			_rows[i].text = "—"
			_ranges[i].text = "待布设"
	var unavailable: String = radar.operator_reason(_state)
	var marked: bool = radar.marked[_zone]
	var actionable := unavailable.is_empty() and not marked
	undo_button.disabled = not actionable or samples.is_empty()
	mark_button.disabled = not actionable or samples.size() < 2
	mark_button.text = "已定位" if marked else ("取消标记，继续布针" if _marking else "标记埋藏点")
	mark_button.tooltip_text = "至少需要两枚探针" if not marked and samples.size() < 2 else ""
	if radar.collected[_zone]:
		_notice.text = "%s 已发掘。样本由返程队员从高地捎回营地。" % RadarGrid.coord(radar.marked_cell(_zone))
	elif marked:
		_notice.text = "已定位 %s。返回高地，把队员卡拖到发掘点。样本随返程队员入库。" % RadarGrid.coord(radar.marked_cell(_zone))
	elif not unavailable.is_empty():
		_notice.text = unavailable
	elif not message.is_empty():
		_notice.text = message
	elif _marking:
		_notice.text = "标记模式：点击各条回波圆共同经过的格心。判断失误可以再试。"
	elif samples.size() >= 2:
		_notice.text = "寻找回波圆共同经过的格心。若有两个交点，可再放一枚探针确认。" if samples.size() == 2 else "三条回波已就绪。点击下方按钮，再点选共同交点所在的格心。"
	elif samples.size() == 1:
		_notice.text = "第一道回波已返回。到距离第一枚较远的格心采集第二道回波。"
	else:
		_notice.text = "在任意格心布下第一枚探针，读取它与埋藏点之间的距离。"
	_notice.add_theme_color_override("font_color", ORANGE if warn else INK)
	grid_control.display(_state, _zone, _marking)
	_focus_ring()


func _distance(value: float) -> String:
	var squared := roundi(value * value)
	var whole := roundi(value)
	if whole * whole == squared:
		return "%d 格" % whole
	return "√%d 格  ≈ %.2f" % [squared, value]


func _focus_ring() -> void:
	var controls: Array[Control] = [grid_control, zone_buttons["lens"], zone_buttons["cache"]]
	for button in [mark_button, undo_button, close_button]:
		if not button.disabled:
			controls.append(button)
	for i in range(controls.size()):
		var control := controls[i]
		var next := controls[(i + 1) % controls.size()].get_path()
		var prev := controls[posmod(i - 1, controls.size())].get_path()
		control.focus_next = next
		control.focus_previous = prev
		control.focus_neighbor_top = prev
		control.focus_neighbor_bottom = next
		control.focus_neighbor_left = prev
		control.focus_neighbor_right = next
	if get_viewport().gui_get_focus_owner() not in controls:
		grid_control.grab_focus()
