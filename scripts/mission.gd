extends Control

const State = preload("res://scripts/mission_state.gd")
const Card = preload("res://scripts/card_view.gd")
const Field = preload("res://scripts/field_map.gd")
const FACE := preload("res://assets/fonts/FandolHei-Regular.otf")
const BOLD := preload("res://assets/fonts/FandolHei-Bold.otf")

const SURFACE := Color("#15191f")
const EDGE := Color("#36383e")
const TEXT := Color("#f4eadf")
const MUTED := Color("#b3a49b")
const DIM := Color("#8e9299")
const ORANGE := Color("#efa775")
const TEAL := Color("#90d2c5")
const PANEL_POS := Vector2(1044, 154)
const CARD_SIZE := Vector2(126, 84)

var state := State.new()
var selected_crew := "lead"
var focus := "wreck"
var speed := 1
var paused := false
var site_cards: Dictionary = {}
var crew_cards: Dictionary = {}
var item_cards: Dictionary = {}
var events: Array[String] = []
var restart_dialog: ConfirmationDialog
var map: Control
var route_layer: Control
var actor_layer: Control
var log_label: Label
var status_label: Label
var objectives: Array[Label] = []
var tip: Label
var detail_kind: Label
var detail_title: Label
var detail_body: Label
var detail_status: Label
var action_buttons: Array[Button] = []
var action_info: Array[Label] = []
var actions: Array[String] = []
var controls: Array[Button] = []
var seen_victory := false


func _ready() -> void:
	theme = Theme.new()
	theme.default_font = FACE
	theme.default_font_size = 15
	_build_header()
	_build_map()
	_build_panel()
	_build_footer()
	state.reported.connect(_report)
	_report("领队已在火星脱离着陆舱。归航的第一步是恢复轨道通信")
	_refresh()


func _process(delta: float) -> void:
	if not paused and not state.won and not is_instance_valid(restart_dialog):
		state.tick(delta * speed)
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_SPACE:
			_toggle_pause()
		KEY_1:
			_set_speed(1)
		KEY_2:
			_set_speed(2)
		KEY_3:
			_set_speed(3)
		_:
			return
	get_viewport().set_input_as_handled()


func _build_header() -> void:
	_rect(self, Rect2(0, 0, 1440, 900), Color("#0f1216"))
	_rect(self, Rect2(28, 27, 4, 47), ORANGE)
	_label(self, "星火归航", Rect2(45, 17, 259, 58), 39, TEXT, true)
	_label(self, "火星地表  /  通信恢复任务", Rect2(265, 39, 390, 32), 17, MUTED)
	var header := _label(self, "", Rect2(1030, 31, 382, 37), 15, ORANGE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label = header
	_rect(self, Rect2(28, 85, 1384, 1), EDGE)
	var x := 28.0
	for id in State.ITEMS:
		var card := _card(id, "item", State.ITEMS[id], Rect2(x, 95, 151, 46), self)
		card.picked.connect(_pick)
		item_cards[id] = card
		x += 164.0
	_label(self, "物资卡可拖到设施，投入配方", Rect2(1061, 101, 351, 32), 14, MUTED)


func _build_map() -> void:
	map = Field.new()
	map.name = "Field"
	map.position = Vector2(28, 154)
	map.size = State.MAP_SIZE
	add_child(map)
	map.move_requested.connect(_move)
	route_layer = Control.new()
	route_layer.mouse_filter = MOUSE_FILTER_IGNORE
	map.add_child(route_layer)
	route_layer.draw.connect(_draw_routes)
	_label(map, "阿耳古瑞平原   /   临时营地", Rect2(17, 10, 350, 30), 16, TEXT, true)
	_label(map, "MARS  ·  SURFACE OPS", Rect2(18, 39, 300, 19), 11, ORANGE)
	_label(map, "地图空地右键移动", Rect2(17, 569, 240, 23), 12, MUTED)
	for id in State.SITES:
		if id in State.CAMPAIGN_ONLY:
			continue
		var site: Dictionary = State.SITES[id]
		var at: Vector2 = site["at"]
		var card := _card(id, "site", site["title"], Rect2(at - CARD_SIZE / 2.0, CARD_SIZE), map)
		card.name = id
		card.picked.connect(_pick)
		card.ordered.connect(_order)
		card.stacked.connect(_stack)
		site_cards[id] = card
	actor_layer = Control.new()
	actor_layer.mouse_filter = MOUSE_FILTER_IGNORE
	map.add_child(actor_layer)


func _draw_routes() -> void:
	for id in state.crew:
		var unit: Dictionary = state.crew[id]
		if unit["phase"] in ["travel", "move"]:
			route_layer.draw_dashed_line(unit["pos"], unit["dest"], ORANGE, 1.4, 6.0)
			route_layer.draw_arc(unit["dest"], 9, 0, TAU, 28, ORANGE, 1.0, true)


func _build_panel() -> void:
	var panel := _panel(self, Rect2(PANEL_POS, Vector2(368, 604)), SURFACE, EDGE)
	_label(panel, "任务进度", Rect2(20, 13, 320, 31), 21, TEXT, true)
	for i in range(5):
		objectives.append(_label(panel, "", Rect2(22, 55 + i * 29, 328, 25), 15, MUTED))
	tip = _label(panel, "", Rect2(20, 209, 328, 61), 14, ORANGE)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rect(panel, Rect2(20, 280, 328, 1), EDGE)
	detail_kind = _label(panel, "", Rect2(20, 294, 328, 22), 13, TEAL)
	detail_title = _label(panel, "", Rect2(20, 317, 328, 38), 27, TEXT, true)
	detail_body = _label(panel, "", Rect2(20, 359, 328, 62), 15, MUTED)
	detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_status = _label(panel, "", Rect2(20, 422, 328, 24), 14, ORANGE)
	for i in range(2):
		var y := 454 + i * 65
		var button := _button(panel, "", Rect2(20, y, 328, 37), _act.bind(i))
		action_buttons.append(button)
		action_info.append(_label(panel, "", Rect2(22, y + 37, 324, 23), 12, DIM))


func _build_footer() -> void:
	var panel := _panel(self, Rect2(28, 777, 1384, 96), SURFACE, EDGE)
	_label(panel, "行动日志", Rect2(15, 10, 98, 23), 14, ORANGE, true)
	log_label = _label(panel, "", Rect2(111, 9, 767, 64), 14, MUTED)
	log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_rect(panel, Rect2(877, 13, 1, 70), EDGE)
	var help := _label(panel, "左键选择   ·   右键下令   ·   拖叠派工 / 投料",
		Rect2(897, 12, 470, 24), 14, MUTED)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.append(_button(panel, "暂停  Space", Rect2(916, 44, 120, 35), _toggle_pause))
	for i in range(1, 4):
		controls.append(_button(panel, "%d×" % i, Rect2(1048 + (i - 1) * 53, 44, 47, 35), _set_speed.bind(i)))
	_button(panel, "重开", Rect2(1230, 44, 136, 35), _ask_restart)


func _ask_restart() -> void:
	restart_dialog = ConfirmationDialog.new()
	restart_dialog.title = "重新开始任务"
	restart_dialog.dialog_text = "当前任务进度将清空。"
	restart_dialog.ok_button_text = "重新开始"
	restart_dialog.cancel_button_text = "继续当前任务"
	add_child(restart_dialog)
	restart_dialog.confirmed.connect(get_tree().reload_current_scene)
	restart_dialog.canceled.connect(restart_dialog.queue_free)
	restart_dialog.popup_centered()


func _pick(id: String) -> void:
	if state.crew.has(id):
		selected_crew = id
	focus = id
	_refresh()


func _order(id: String) -> void:
	if not State.DEFAULT_RECIPES.has(id):
		_pick(id)
		return
	focus = id
	state.assign(selected_crew, state.default_recipe(id))
	_refresh()


func _move(at: Vector2) -> void:
	state.move_crew(selected_crew, at)
	focus = selected_crew
	_refresh()


func _stack(site: String, data: Dictionary) -> void:
	focus = site
	if data["kind"] == "crew":
		selected_crew = data["id"]
		state.assign(selected_crew, state.default_recipe(site))
	else:
		var recipe := state.recipe_for_material(site, data["id"])
		if recipe.is_empty():
			_report("%s无需%s" % [State.SITES[site]["title"], State.ITEMS[data["id"]]])
		else:
			state.assign(selected_crew, recipe)
	_refresh()


func _act(index: int) -> void:
	if index >= actions.size():
		return
	if actions[index] == "stop":
		state.stop_crew(focus)
	else:
		state.assign(selected_crew, actions[index])
	_refresh()


func _report(message: String) -> void:
	events.push_front(message)
	if events.size() > 3:
		events.pop_back()
	log_label.text = "\n".join(events)


func _toggle_pause() -> void:
	if not state.won:
		paused = not paused
	_refresh()


func _set_speed(value: int) -> void:
	if not state.won:
		speed = value
		paused = false
	_refresh()


func _refresh() -> void:
	if focus == "casualty" and state.recruited:
		selected_crew = "tech"
		focus = selected_crew
	route_layer.queue_redraw()
	_refresh_cards()
	_refresh_objectives()
	_refresh_detail()
	_refresh_controls()
	if state.won and not seen_victory:
		_show_victory()


func _refresh_cards() -> void:
	for id in item_cards:
		item_cards[id].update_display("", str(state.inventory[id]), -1.0, focus == id)
	for id in site_cards:
		var card: Control = site_cards[id]
		card.visible = state.site_visible(id)
		var active := state.active_at(id)
		var description := _site_status(id, active)
		var ratio := -1.0 if active.is_empty() else state.progress(active)
		var tag: String = State.SITES[id]["kind"]
		if not active.is_empty() and state.crew[active]["phase"] == "working":
			var held: Dictionary = state.crew[active]["reserved"]
			if not held.is_empty():
				var labels := PackedStringArray()
				for item in held:
					labels.append("%s ×%d" % [State.ITEMS[item], held[item]])
				description = " + ".join(labels)
				tag = "投入物资"
		card.heading = _site_title(id)
		card.update_display(tag, description, ratio, focus == id)
	for id in state.crew:
		var unit: Dictionary = state.crew[id]
		var card_size := Vector2(152, 50)
		if not crew_cards.has(id):
			var card := _card(id, "crew", State.CREW_NAMES[id], Rect2(Vector2.ZERO, card_size), actor_layer)
			card.name = id
			card.picked.connect(_pick)
			card.ordered.connect(_pick)
			crew_cards[id] = card
		var card: Control = crew_cards[id]
		card.position = unit["pos"] - card_size / 2.0
		card.update_display(state.activity(id), "", state.progress(id), selected_crew == id)


func _site_title(id: String) -> String:
	if id == "greenhouse" and not state.greenhouse_built:
		return "温室基座"
	return State.SITES[id]["title"]


func _site_status(id: String, active: String) -> String:
	if not active.is_empty():
		var phase: String = state.crew[active]["phase"]
		if phase == "working":
			return "%s作业中" % State.CREW_NAMES[active]
		if phase == "waiting":
			return "等待补水"
		return "%s前往中" % State.CREW_NAMES[active]
	match id:
		"wreck": return "回收残件 ×3"
		"ore": return "采集矿样 ×2"
		"ice": return "采集水冰 ×2"
		"casualty": return "救助需口粮 ×1"
		"bench": return "残件 → 结构件"
		"greenhouse": return "水冰 → 口粮" if state.greenhouse_built else "搭建需残件 ×1"
		"lab": return "蓝图已解锁" if state.blueprint else "研发维修蓝图"
		"relay": return "电路 ×%d" % state.neighbor_stock if state.recruited else "等待接通"
		"beacon": return "信标已上线" if state.won else "待修复"
	return ""


func _refresh_objectives() -> void:
	var items := [
		["回收着陆舱残件", state.salvaged],
		["救助勘探员，扩充队伍", state.recruited],
		["研究信标维修蓝图", state.blueprint],
		["备齐结构件与电路", state.won or (state.inventory["plate"] > 0 and state.inventory["circuit"] > 0)
			or not state.active_at("beacon").is_empty()],
		["恢复与轨道的通信", state.won],
	]
	for i in range(items.size()):
		var done: bool = items[i][1]
		objectives[i].text = ("%s   %s" % ["●" if done else "○", items[i][0]])
		objectives[i].add_theme_color_override("font_color", TEAL if done else TEXT)
	if state.won:
		tip.text = "轨道已收到信号。基地可以开始寻找归航航标。"
	elif not state.salvaged:
		tip.text = "已选中领队。右键着陆舱残骸，或把领队卡拖到残骸上。"
	elif not state.recruited:
		tip.text = "求救信号已标在地图上。带 1 份口粮救助勘探员。"
	elif not state.blueprint:
		tip.text = "派一名队员采集矿样，另一名可加工结构件。留 1 份残件用于研究。"
	elif items[3][1]:
		tip.text = "维修材料齐备。把一名队员派往通信信标。"
	elif state.inventory["circuit"] == 0:
		tip.text = "可向曙光站换取电路，也可在工作台选择制造电路。"
	else:
		tip.text = "在制造工作台补齐结构件。口粮不足时，可用温室补给。"


func _refresh_detail() -> void:
	actions.clear()
	var crew_text := "当前派工 · %s" % State.CREW_NAMES[selected_crew]
	if State.SITES.has(focus) and state.site_visible(focus):
		var site: Dictionary = State.SITES[focus]
		detail_kind.text = site["kind"]
		detail_title.text = _site_title(focus)
		detail_body.text = site["detail"]
		if focus == "greenhouse" and not state.greenhouse_built:
			detail_body.text = "用残件搭建密封温室。建好后，可安排队员和水冰循环生产口粮。"
		detail_status.text = crew_text
		actions.append(state.default_recipe(focus))
		if focus == "bench":
			actions.append("etch")
		elif focus == "relay":
			actions.append("trade_food")
			detail_status.text = "曙光站库存 · 电路 %d   口粮 %d   残件 %d" % [state.neighbor_stock, state.neighbor_food, state.neighbor_scrap]
	elif state.crew.has(focus):
		detail_kind.text = "队员"
		detail_title.text = State.CREW_NAMES[focus]
		detail_body.text = "右键地图移动，右键设施执行默认任务。也可拖动队员卡，把队员叠放到设施上。"
		detail_status.text = "当前状态 · %s" % state.activity(focus)
		if not state.crew[focus]["phase"].is_empty() and not state.won:
			actions.append("stop")
	else:
		detail_kind.text = "基地物资"
		detail_title.text = State.ITEMS.get(focus, "选择地图上的目标")
		detail_body.text = "拖动有库存的物资卡到适用设施，为当前选中的队员安排相应配方。"
		detail_status.text = crew_text
	for i in range(action_buttons.size()):
		action_buttons[i].visible = i < actions.size()
		action_info[i].visible = i < actions.size()
		if i >= actions.size():
			continue
		var id := actions[i]
		if id == "stop":
			action_buttons[i].text = "停止工作"
			action_buttons[i].disabled = false
			action_info[i].text = "归还当前尚未用完的投入"
			continue
		var spec: Dictionary = State.RECIPES[id]
		var why := state.reason(selected_crew, id)
		action_buttons[i].text = spec["label"]
		action_buttons[i].disabled = not why.is_empty()
		var costs: Array[String] = []
		for item in spec.get("cost", {}):
			costs.append("%s ×%d" % [State.ITEMS[item], spec["cost"][item]])
		var requirements := " + ".join(costs) if not costs.is_empty() else "无物资消耗"
		action_info[i].text = "%s  ·  %d秒" % [requirements, spec["time"]] if why.is_empty() else why
		action_info[i].add_theme_color_override("font_color", DIM if why.is_empty() else ORANGE)


func _refresh_controls() -> void:
	var elapsed := int(state.clock)
	var clock_text := "%02d:%02d" % [elapsed / 60, elapsed % 60]
	var condition := "任务完成" if state.won else ("暂停" if paused else "地表时间")
	status_label.text = "%s   %s     ·     队员 %d" % [condition, clock_text, state.crew.size()]
	controls[0].text = "继续  Space" if paused else "暂停  Space"
	for i in range(controls.size()):
		controls[i].disabled = state.won
		var active := (paused and i == 0) or (not paused and i == speed)
		controls[i].add_theme_color_override("font_color", ORANGE if active else TEXT)


func _show_victory() -> void:
	seen_victory = true
	focus = "beacon"
	var shade := _rect(self, Rect2(0, 0, 1440, 900), Color(0.035, 0.044, 0.055, 0.73))
	shade.mouse_filter = MOUSE_FILTER_STOP
	var victory := _panel(shade, Rect2(440, 315, 560, 244), Color("#192427"), TEAL)
	_label(victory, "轨道接收站 · 已确认", Rect2(32, 25, 496, 30), 15, TEAL, true)
	_label(victory, "通信信标已上线", Rect2(32, 60, 496, 60), 38, TEXT, true)
	_label(victory, "火星营地已接入轨道通信，可以开始寻找归航航标。", Rect2(32, 129, 496, 27), 17, MUTED)
	_button(victory, "查看基地", Rect2(32, 183, 176, 40), shade.queue_free)
	_button(victory, "重新开始", Rect2(224, 183, 176, 40), get_tree().reload_current_scene)


func _card(id: String, type: String, title: String, bounds: Rect2, parent: Control) -> Control:
	var card := Card.new()
	card.position = bounds.position
	card.size = bounds.size
	card.configure(id, type, title, FACE, BOLD)
	parent.add_child(card)
	return card


func _rect(parent: Control, bounds: Rect2, tint: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = bounds.position
	rect.size = bounds.size
	rect.color = tint
	rect.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _panel(parent: Control, bounds: Rect2, tint: Color, border: Color) -> Panel:
	var panel := Panel.new()
	panel.position = bounds.position
	panel.size = bounds.size
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(tint, border))
	parent.add_child(panel)
	return panel


func _label(parent: Control, value: String, bounds: Rect2, pixels: int, tint: Color, heavy: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.position = bounds.position
	label.size = bounds.size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", pixels)
	if heavy:
		label.add_theme_font_override("font", BOLD)
	parent.add_child(label)
	return label


func _button(parent: Control, value: String, bounds: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.position = bounds.position
	button.size = bounds.size
	button.focus_mode = FOCUS_NONE
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _box(Color("#242930"), Color("#464950")))
	button.add_theme_stylebox_override("hover", _box(Color("#303138"), ORANGE))
	button.add_theme_stylebox_override("pressed", _box(Color("#40332e"), ORANGE))
	button.add_theme_stylebox_override("disabled", _box(Color("#1b1f25"), Color("#30343b")))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_disabled_color", DIM)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _box(tint: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style
