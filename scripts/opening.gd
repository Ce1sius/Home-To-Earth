extends "res://scripts/screen.gd"

const State := preload("res://scripts/mission_state.gd")
const Save := preload("res://scripts/campaign_save.gd")
const Card := preload("res://scripts/landing_card.gd")
const Feedback := preload("res://scripts/board_feedback.gd")
const CampField := preload("res://scripts/camp_field.gd")
const ReplacePrompt := preload("res://scripts/replace_prompt.gd")
const FlightLog := preload("res://scripts/flight_log.gd")
const GearBoard := preload("res://scripts/gear_board.gd")
const RadarBoard := preload("res://scripts/radar_board.gd")
const Guide := preload("res://scripts/campaign_guide.gd")
const GROUND := preload("res://assets/art/argyre_terrain.png")
const HIGHLAND_GROUND := preload("res://assets/art/northern_highlands.png")
const COMPASS := preload("res://assets/icons/compass.svg")
const MOUSE := preload("res://assets/icons/mouse.svg")
const MENU := "res://scenes/title.tscn"
const MAP_POS := Vector2(32, 105)
const CREW_SIZE := State.CAMPAIGN_CREW_SIZE
const ITEM_INFO := {
	"food": ["应急口粮", "生命保障", "从着陆舱带出的六份应急口粮。"],
	"tool": ["简易工具", "拖给队员装备", "装备后回收、采冰、采矿和工作台制造速度提高 25%。可以在营地队员之间转交。"],
	"scrap": ["金属残件", "回收材料", "从着陆舱外壳和破损设备中拆下的可用材料。"],
	"ore": ["矿物样本", "采集材料", "从露天矿脉带回的第一批火星矿物样本。"],
	"ice": ["浅层水冰", "生产材料", "从冰脉采回的水冰，每份可供温室生产一轮。"],
	"plate": ["结构件", "维修材料", "在工作台加工的结构件，用于制造电路或修复信标。"],
	"circuit": ["电路", "维修材料", "可在工作台制造，或与曙光勘探站交换，用于修复信标。"],
}

var state := State.new(true)
var paused := false
var game_speed := 1
var speed_button: Button
var flight_log: Control
var replace_prompt: Control
var focus := "wreck"
var focus_is_item := false
var viewed_region := State.CAMP
var field: Control
var terrain: TextureRect
var location_label: Label
var local_map_label: Label
var field_help: Label
var inventory_title: Label
var region_button: Button
var routes: Control
var crew_cards: Dictionary = {}
var crew_buttons: Dictionary = {}
var selected_crew := "lead"
var sites: Dictionary = {}
var items: Dictionary = {}
var status: Label
var objective_title: Label
var objective: Label
var goal_button: Button
var aid_button: Button
var detail_kind: Label
var detail_title: Label
var detail_body: Label
var detail_hint: Label
var log_line: Label
var action_button: Button
var alternate_button: Button
var pause_button: Button
var pause_overlay: Control
var save_button: Button
var back_button: Button
var restart_button: Button
var orders_button: Button
var energy_label: Label
var auto_button: Button
var orders_overlay: Control
var order_recipe: OptionButton
var order_mode: OptionButton
var order_amount: SpinBox
var order_confirm: Button
var order_feedback: Label
var _order_recipes: Array[String] = []
var _pause_before_orders := false
var _pause_before_menu := false
var _save_elapsed := 0.0
var _save_due := false
var feedback: Control
var drag_hint: Panel
var drag_text: Label
var context_overlay: Control
var context_buttons: Dictionary = {}
var context_duties: Dictionary = {}
var _context_pause := false
var _drag_payload: Dictionary = {}
var _settings_path := "user://board_settings.cfg"
var scout_button: Button
var radar_button: Button
var radar_board: Control
var _radar_previous_pause := false
var _marks_before_scan := {}
var gear_button: Button
var gear_board: Control
var patrol_buttons: Dictionary = {}
var route_details: Dictionary = {}
var patrol_status: Label
var exploration_overlay: Control
var expedition_buttons: Dictionary = {}
var expedition_recall: Button
var _exploration_pause := false
var _placement_point := Vector2.ZERO
var _placement_valid := false


func _ready() -> void:
	super._ready()
	get_tree().auto_accept_quit = false
	var continuing := not Save.pending.is_empty()
	if continuing:
		state = Save.pending["state"]
		viewed_region = Save.pending["region"]
		selected_crew = Save.pending["selected"]
		focus = "array" if state.first_record_uploaded() and viewed_region == State.HIGHLANDS else ("trail" if viewed_region == State.HIGHLANDS else "wreck")
		if not selected_crew.is_empty() and state.crew_away(selected_crew):
			focus = selected_crew
		Save.pending = {}
	fill_at(self, Rect2(Vector2.ZERO, SIZE), Color("#141215"))
	_build_top()
	_build_field()
	_build_sidebar()
	_build_inventory()
	_build_feedback()
	state.reported.connect(_report)
	state.work_started.connect(_work_started)
	state.work_completed.connect(_work_completed)
	state.rations_used.connect(_rations_used)
	state.crew_transferred.connect(_follow_crew)
	state.radar_delivered.connect(_radar_delivery)
	state.checkpoint.connect(_queue_save)
	_report("已恢复勘探进度，队员继续原有工作。" if continuing else "已确认领队安全。携带 6 份口粮和 1 套简易工具。")
	_refresh()
	if not continuing:
		_save_game()


func _process(delta: float) -> void:
	if _drag_payload.get("kind") == "facility":
		_placement_offer(_drag_payload["id"], field.get_local_mouse_position())
	if not paused:
		for step in range(game_speed):
			state.tick(delta)
			_save_elapsed += delta
			if state.homeward_launched:
				break
		_refresh()
		if _save_due or _save_elapsed >= 30.0:
			_save_game()


func _queue_save() -> void:
	_save_due = true


func _save_game() -> bool:
	_save_due = false
	_save_elapsed = 0.0
	if not Save.write_game(state, viewed_region, selected_crew):
		_report(Save.last_error)
		return false
	return true


func _manual_save() -> void:
	var saved := _save_game()
	save_button.text = "进度已保存" if saved else "保存失败 · 再试一次"
	if saved:
		_report("进度已保存，可以从主菜单继续游戏。")


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drag()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _save_game():
			get_tree().quit()
		elif not paused:
			_toggle_pause()


func _input(event: InputEvent) -> void:
	if is_instance_valid(flight_log) or is_instance_valid(replace_prompt):
		return
	if is_instance_valid(radar_board):
		return
	if is_instance_valid(gear_board):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and not get_viewport().gui_is_dragging():
			_close_gear_board()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_1, KEY_2, KEY_3] and not _menu_open() and not get_viewport().gui_is_dragging():
		game_speed = [1, 2, 4][event.keycode - KEY_1]
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ESCAPE]:
		if get_viewport().gui_is_dragging():
			return
		if is_instance_valid(exploration_overlay):
			_close_exploration()
		elif is_instance_valid(context_overlay):
			_close_context()
		elif is_instance_valid(orders_overlay):
			_close_orders()
		elif event.keycode == KEY_ESCAPE or is_instance_valid(pause_overlay):
			_toggle_pause()
		else:
			paused = not paused
			_refresh()
		get_viewport().set_input_as_handled()


func _menu_open() -> bool:
	return is_instance_valid(flight_log) or is_instance_valid(pause_overlay) or is_instance_valid(orders_overlay) or is_instance_valid(context_overlay) or is_instance_valid(exploration_overlay) or is_instance_valid(radar_board)


func _build_top() -> void:
	text_at(self, "星火归航", Rect2(32, 20, 214, 62), 37, INK, true)
	fill_at(self, Rect2(214, 29, 1, 44), EDGE)
	location_label = text_at(self, "迫降地 · 阿耳古瑞平原", Rect2(236, 23, 485, 30), 21, INK)
	for index in range(State.CREW_NAMES.size()):
		var id: String = State.CREW_NAMES.keys()[index]
		var button := button_at(self, "", Rect2(237 + index * 150, 57, 144, 30), _select_roster.bind(id))
		button.add_theme_font_size_override("font_size", 13)
		crew_buttons[id] = button
	region_button = button_at(self, "查看北缘高地", Rect2(694, 28, 200, 46), _toggle_region)
	region_button.hide()
	speed_button = button_at(self, "1×", Rect2(1132, 28, 98, 46), _cycle_speed)
	speed_button.tooltip_text = "切换时间速度（数字键 1 / 2 / 3）"
	status = text_at(self, "", Rect2(895, 30, 224, 43), 15, MUTED)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pause_button = button_at(self, "暂停  Esc", Rect2(1244, 28, 164, 46), _toggle_pause)


func _cycle_speed() -> void:
	if not _menu_open():
		game_speed = 1 if game_speed == 4 else game_speed * 2
		_refresh()


func _build_field() -> void:
	field = panel_at(self, Rect2(MAP_POS, State.MAP_SIZE))
	field.set_script(CampField)
	field.placement_check = _placement_offer
	field.facility_placed.connect(_place_facility)
	field.clip_contents = true
	field.mouse_filter = MOUSE_FILTER_STOP
	field.mouse_default_cursor_shape = CURSOR_CROSS
	field.gui_input.connect(_field_input)
	terrain = art_at(field, GROUND, Rect2(Vector2.ZERO, State.MAP_SIZE))
	terrain.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	terrain.modulate = Color("#dcbcab")
	routes = Control.new()
	routes.mouse_filter = MOUSE_FILTER_IGNORE
	field.add_child(routes)
	routes.draw.connect(_draw_routes)
	var map_label := panel_at(field, State.CAMPAIGN_MAP_LABEL, Color(0.15, 0.10, 0.09, 0.87))
	art_at(map_label, COMPASS, Rect2(12, 14, 29, 29)).modulate = ORANGE
	local_map_label = text_at(map_label, "着陆区", Rect2(52, 8, 143, 39), 18, INK, true)
	scout_button = button_at(field, "周边勘探", State.CAMPAIGN_MAP_SCOUT, _open_exploration)
	scout_button.add_theme_font_size_override("font_size", 16)
	radar_button = button_at(field, "浅层雷达", State.CAMPAIGN_MAP_SCOUT, _open_radar)
	radar_button.add_theme_font_size_override("font_size", 16)
	var controls := panel_at(field, State.CAMPAIGN_MAP_HELP, Color(0.15, 0.10, 0.09, 0.90))
	art_at(controls, MOUSE, Rect2(13, 11, 20, 20)).modulate = ORANGE
	field_help = text_at(controls, "", Rect2(43, 2, 376, 38), 15, INK)
	for id in State.CAMPAIGN_SITES:
		var card_size := state.campaign_site_size(id)
		var card := _card(id, "site", _site_title(id),
			Rect2(state.site_position(id) - card_size / 2, card_size), field)
		card.picked.connect(_pick_site)
		card.ordered.connect(_open_context)
		card.stacked.connect(_stack)
		card.drop_check = _drop_offer.bind(id)
		sites[id] = card
	_add_crew_card("lead")


func _build_sidebar() -> void:
	var sidebar := panel_at(self, Rect2(1050, 105, 358, 604))
	text_at(sidebar, "当前任务", Rect2(20, 18, 318, 29), 15, ORANGE, true)
	objective_title = text_at(sidebar, "勘察迫降点", Rect2(20, 49, 318, 46), 30, INK, true)
	objective = text_at(sidebar, "", Rect2(20, 100, 318, 58), 16, INK)
	goal_button = button_at(sidebar, "查看阶段任务", Rect2(20, 162, 318, 29), _show_goal)
	goal_button.add_theme_font_size_override("font_size", 14)
	aid_button = button_at(sidebar, "邻站互助", Rect2(219, 162, 119, 29), _show_aid)
	aid_button.add_theme_font_size_override("font_size", 14)
	aid_button.tooltip_text = "查看曙光站当前请求和交付回报"
	fill_at(sidebar, Rect2(20, 195, 318, 1), EDGE)
	detail_kind = text_at(sidebar, "", Rect2(20, 212, 318, 27), 14, TEAL)
	detail_title = text_at(sidebar, "", Rect2(20, 240, 318, 44), 27, INK, true)
	detail_body = text_at(sidebar, "", Rect2(20, 293, 318, 75), 17, MUTED)
	detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_button = button_at(sidebar, "", Rect2(20, 383, 318, 49), _act, true)
	alternate_button = button_at(sidebar, "", Rect2(20, 433, 318, 32), _act_alternate)
	alternate_button.add_theme_font_size_override("font_size", 15)
	alternate_button.hide()
	detail_hint = text_at(sidebar, "", Rect2(20, 438, 318, 43), 14, ORANGE)
	detail_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fill_at(sidebar, Rect2(20, 502, 318, 1), EDGE)
	text_at(sidebar, "地表日志", Rect2(20, 511, 318, 23), 14, MUTED, true)
	log_line = text_at(sidebar, "", Rect2(20, 540, 318, 48), 14, INK)
	log_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_inventory() -> void:
	var tray := panel_at(self, Rect2(32, 730, 1376, 137))
	inventory_title = text_at(tray, "随身物资", Rect2(18, 12, 235, 35), 22, INK, true)
	energy_label = text_at(tray, "", Rect2(250, 9, 682, 35), 15, TEAL)
	auto_button = button_at(tray, "暂停自动采冰", Rect2(944, 8, 148, 36), _toggle_auto)
	auto_button.add_theme_font_size_override("font_size", 14)
	orders_button = button_at(tray, "工作安排 / 生产订单", Rect2(1104, 8, 254, 36), _open_orders)
	orders_button.add_theme_font_size_override("font_size", 17)
	var x := 18.0
	for id in ITEM_INFO:
		var card := _card(id, "item", ITEM_INFO[id][0], Rect2(x, 52, 323, 72), tray)
		card.picked.connect(_pick_item)
		items[id] = card
		x += 339.0


func _add_crew_card(id: String) -> void:
	var title: String = "勘探领队" if id == "lead" else State.CREW_NAMES[id]
	var card := _card(id, "crew", title, Rect2(Vector2.ZERO, CREW_SIZE), field)
	card.picked.connect(_pick_crew)
	card.ordered.connect(_pick_crew)
	card.stacked.connect(_give_tool)
	card.drop_check = _tool_drop_offer.bind(id)
	crew_cards[id] = card


func _card(id: String, type: String, title: String, bounds: Rect2, parent: Control) -> Control:
	var node := Card.new()
	node.configure(id, type, title, FACE, BOLD)
	node.position = bounds.position
	node.size = bounds.size
	parent.add_child(node)
	node.drag_started.connect(_begin_drag)
	return node


func _build_feedback() -> void:
	feedback = Feedback.new()
	feedback.face = FACE
	feedback.size = SIZE
	feedback.z_index = 120
	add_child(feedback)
	var settings := ConfigFile.new()
	if settings.load(_settings_path) == OK:
		feedback.reduced_motion = settings.get_value("feedback", "reduced_motion", false)
		feedback.sound_enabled = settings.get_value("feedback", "sound", true)
	drag_hint = panel_at(self, Rect2(48, 630, 760, 66), Color("#172226"))
	drag_hint.z_index = 130
	drag_text = text_at(drag_hint, "", Rect2(14, 5, 732, 56), 17, TEAL)
	drag_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drag_hint.hide()


func _resource_text(resources: Dictionary) -> String:
	var words := PackedStringArray()
	for item in resources:
		words.append("%s×%d" % [State.ITEMS.get(item, item), resources[item]])
	return "、".join(words)


func _job_summary(recipe: String) -> String:
	var cost := _resource_text(state.recipe_cost(recipe))
	var output := _resource_text(state.production_output(recipe))
	if recipe in ["dig_lens", "dig_cache"]:
		return "送至高地接驳点 · %s\n基础 %.0f 秒 · 随下一趟返程入库" % [output, state._duration(recipe)]
	if recipe == "return" and not state.radar.depot_cargo().is_empty():
		return "出发装载 · %s\n抵达迫降地后入库" % _resource_text(state.radar.depot_cargo())
	if recipe == "launch_homeward":
		return "%s · 领队起航，完成后本局结束" % cost
	if recipe == "camp_care":
		return "%s → 健康+%.0f、体力+35（上限100）\n护理 %.0f秒 · 完成后恢复原岗位" % [cost, state.requests.care_health(), state._duration(recipe)]
	if State.RECIPES[recipe].has("request"):
		return "%s → %s\n二选一 · 作业 %.0f秒 · 限时 %d秒（含路程）" % [cost, output, state._duration(recipe), ceili(state.requests.remaining)]
	var summary := "%s → %s · 基础 %.0f秒" % ["无需物资" if cost.is_empty() else cost,
		State.RECIPES[recipe]["label"] if output.is_empty() else output, state._duration(recipe)]
	return summary


func _drop_offer(payload: Dictionary, show_hint: bool, site: String) -> Dictionary:
	var recipe := ""
	var worker: String = payload.get("id", "") if payload.get("kind") == "crew" else selected_crew
	if payload.get("kind") == "crew":
		recipe = state.default_recipe(site)
	elif payload.get("kind") == "item":
		recipe = state.recipe_for_material(site, payload.get("id", ""), worker)
	var why := "此处不使用这项物资"
	var waiting := false
	if not recipe.is_empty():
		var duty: bool = payload.get("kind") == "crew" and recipe in State.CrewWork.JOBS
		why = state.reason(worker, recipe, duty)
		waiting = why.is_empty() and duty and not state.missing(recipe).is_empty()
	if _menu_open():
		why = "请先关闭菜单"
	var allowed := why.is_empty()
	if show_hint and is_instance_valid(drag_hint):
		drag_hint.show()
		if allowed:
			drag_text.text = ("放下设岗位 · 缺料时等待补给\n" if waiting else "放下即可安排 · ") + _job_summary(recipe)
		else:
			drag_text.text = "无法放置 · " + why
	return {"allowed": allowed, "waiting": waiting, "recipe": recipe, "reason": why}


func _begin_drag(payload: Dictionary) -> void:
	_drag_payload = payload
	if payload.get("kind") == "item" and payload.get("id") == "tool":
		for worker in crew_cards:
			var actor: Control = crew_cards[worker]
			actor.drop_active = actor.visible
			actor.drop_valid = state.tool_transfer_reason(worker).is_empty()
			actor.queue_redraw()
		drag_hint.show()
		drag_text.text = "拖给营地队员 · 回收、采集和制造速度 +25%"
		return
	if payload.get("kind") == "facility":
		drag_hint.show()
		_placement_offer(payload["id"], field.get_local_mouse_position())
		return
	for site in sites:
		var card: Control = sites[site]
		var offer := _drop_offer(payload, false, site)
		card.drop_active = card.visible
		card.drop_valid = offer["allowed"]
		card.drop_waiting = offer["waiting"]
		card.queue_redraw()
	drag_hint.show()
	drag_text.text = "拖到亮框目标上松手 · 黄色目标会等待材料\n移到目标上可预览投入、产出和耗时"


func _clear_drag() -> void:
	_drag_payload = {}
	if is_instance_valid(drag_hint):
		drag_hint.hide()
	for card in sites.values() + crew_cards.values():
		card.drop_active = false
		card.queue_redraw()
	if is_instance_valid(routes):
		routes.queue_redraw()


func _placement_offer(site: String, at: Vector2) -> bool:
	_placement_point = state.layout.snap_point(at)
	var why := state.layout.reason(state, site, _placement_point)
	if _menu_open() or viewed_region != State.CAMP:
		why = "请在营地地图关闭菜单后布置"
	_placement_valid = why.is_empty()
	drag_text.text = ("可以放置 · 松手调整位置\n设施升级保留，队员之后前往新位置" if _placement_valid else "无法放置 · " + why)
	routes.queue_redraw()
	return _placement_valid


func _place_facility(site: String, at: Vector2) -> void:
	if _menu_open() or viewed_region != State.CAMP:
		return
	if state.layout.move_site(state, site, at):
		focus = site
		focus_is_item = false
		feedback.toast("位置已调整", MAP_POS + state.site_position(site))
		feedback.cue()
	_refresh()


func _work_started(site: String, inputs: Dictionary) -> void:
	if state.site_region(site) != viewed_region:
		return
	var at: Vector2 = MAP_POS + state.site_position(site)
	for item in inputs:
		feedback.transfer(item, inputs[item], items[item].get_global_rect().get_center(), at, false)
	sites[site].pop()
	feedback.cue(420)


func _work_completed(site: String, recipe: String, output: Dictionary) -> void:
	if state.site_region(site) != viewed_region:
		return
	var at: Vector2 = MAP_POS + state.site_position(site)
	if recipe in ["dig_lens", "dig_cache"]:
		var loadout := state.production_output(recipe)
		var depot := MAP_POS + state.site_position("trail")
		for item in loadout:
			feedback.transfer(item, loadout[item], at, depot, true)
		sites["trail"].pop()
		feedback.cue(640)
		return
	for item in output:
		items[item].mark_received(output[item])
		feedback.transfer(item, output[item], at, items[item].get_global_rect().get_center(), true)
	if output.is_empty():
		feedback.toast(State.RECIPES[recipe]["label"] + " · 完成", at)
	sites[site].pop()
	feedback.cue(920 if output.is_empty() else 640)


func _rations_used(amount: int) -> void:
	feedback.toast("营地用餐 −%d" % amount, items["food"].get_global_rect().get_center() - Vector2(0, 48), false)


func _radar_delivery(cargo: Dictionary) -> void:
	for item in cargo:
		items[item].mark_received(cargo[item])
		if viewed_region == State.CAMP:
			feedback.transfer(item, cargo[item], MAP_POS + state.site_position("beacon"), items[item].get_global_rect().get_center(), true)
	feedback.cue(920)


func _open_context(site: String, preferred: String = "") -> void:
	if _menu_open():
		return
	_pick_site(site)
	_context_pause = paused
	paused = true
	context_overlay = fill_at(self, Rect2(Vector2.ZERO, SIZE), Color(0, 0, 0, 0.12))
	context_overlay.mouse_filter = MOUSE_FILTER_STOP
	context_overlay.z_index = 200
	context_overlay.gui_input.connect(_context_background)
	context_buttons.clear()
	context_duties.clear()
	var recipes := state.site_actions(site)
	var height := 78.0 + recipes.size() * 90
	if site == "archive":
		height += 52
	var origin: Vector2 = MAP_POS + state.site_position(site) + Vector2(32, 14)
	origin.x = clampf(origin.x, 40, SIZE.x - 572)
	origin.y = clampf(origin.y, 90, SIZE.y - height - 24)
	var panel := panel_at(context_overlay, Rect2(origin, Vector2(532, height)))
	panel.mouse_filter = MOUSE_FILTER_STOP
	var heading := text_at(panel, _site_title(site) + " · 选择行动", Rect2(16, 8, 440, 35), 21, INK, true)
	if site == "relay" and not state.requests.active.is_empty():
		heading.text = "曙光站 · " + State.Requests.OFFERS[state.requests.active]["title"]
		heading.tooltip_text = State.Requests.OFFERS[state.requests.active]["detail"]
	var close := button_at(panel, "×", Rect2(480, 8, 36, 34), _close_context)
	for index in range(recipes.size()):
		var recipe: String = recipes[index]
		var why := state.reason(selected_crew, recipe)
		var y := 51.0 + index * 90
		var job := button_at(panel, State.RECIPES[recipe]["label"], Rect2(16, y, 398, 40), _choose_context.bind(site, recipe, false), why.is_empty())
		job.disabled = not why.is_empty()
		job.tooltip_text = why
		context_buttons[recipe] = job
		var caption := _job_summary(recipe) if why.is_empty() else why
		if State.RECIPES[recipe].has("request") and not why.is_empty():
			caption = "%s → %s\n%s · 剩余 %d秒" % [_resource_text(State.RECIPES[recipe]["cost"]), _resource_text(state.production_output(recipe)), why, ceili(state.requests.remaining)]
		var caption_label := text_at(panel, "", Rect2(20, y + 42, 492, 42), 14, MUTED if why.is_empty() else ORANGE)
		caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption_label.text = caption
		if State.RECIPES[recipe].has("request"):
			job.tooltip_text = _job_summary(recipe) + ("\n" + why if not why.is_empty() else "")
		if recipe in State.CrewWork.JOBS:
			var duty := button_at(panel, "设岗位", Rect2(422, y, 94, 40), _choose_context.bind(site, recipe, true))
			duty.add_theme_font_size_override("font_size", 16)
			duty.disabled = not state.reason(selected_crew, recipe, true).is_empty()
			context_duties[recipe] = duty
	if site == "archive":
		var scan := button_at(panel, "启动浅层雷达", Rect2(16, height - 61, 500, 43), _open_radar_from_archive)
		scan.tooltip_text = state.radar.operator_reason(state)
		scan.disabled = not scan.tooltip_text.is_empty()
	close.grab_focus()
	for button in context_buttons.values():
		if not button.disabled:
			button.grab_focus()
			break
	if context_buttons.has(preferred) and not context_buttons[preferred].disabled:
		context_buttons[preferred].grab_focus()
	_trap_focus(panel)
	_refresh()


func _context_background(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_context()


func _choose_context(site: String, recipe: String, duty: bool) -> void:
	_close_context()
	if duty:
		state.set_order(selected_crew, recipe, "continuous")
		_refresh()
	else:
		_assign(site, recipe)


func _close_context() -> void:
	if not is_instance_valid(context_overlay):
		return
	context_overlay.hide()
	context_overlay.queue_free()
	context_overlay = null
	paused = _context_pause
	_refresh()
	goal_button.grab_focus()


func _open_radar_from_archive() -> void:
	_close_context()
	_open_radar()


func _open_radar() -> void:
	if _menu_open() or viewed_region != State.HIGHLANDS or not state.radar.operator_reason(state).is_empty():
		return
	_radar_previous_pause = paused
	paused = true
	_marks_before_scan = state.radar.marked.duplicate()
	radar_board = RadarBoard.new()
	add_child(radar_board)
	radar_board.close_requested.connect(_close_radar)
	radar_board.present(state)
	_refresh()


func _close_radar() -> void:
	if not is_instance_valid(radar_board):
		return
	radar_board.hide()
	radar_board.queue_free()
	radar_board = null
	paused = _radar_previous_pause
	for zone in state.radar.ZONES:
		if state.radar.marked[zone] and not _marks_before_scan.get(zone, false):
			focus = state.radar.ZONES[zone]["site"]
			focus_is_item = false
			sites[focus].pop()
			feedback.toast("已标出开挖点", MAP_POS + state.site_position(focus))
			feedback.cue(920)
	_refresh()
	if _save_due:
		_save_game()
	radar_button.grab_focus()


func _open_exploration() -> void:
	if _menu_open() or not state.first_harvest or viewed_region != State.CAMP:
		return
	_exploration_pause = paused
	paused = true
	exploration_overlay = fill_at(self, Rect2(Vector2.ZERO, SIZE), Color(0.03, 0.04, 0.05, 0.78))
	exploration_overlay.mouse_filter = MOUSE_FILTER_STOP
	exploration_overlay.z_index = 200
	var panel := panel_at(exploration_overlay, Rect2(70, 96, 1300, 708))
	text_at(panel, "周边勘探", Rect2(24, 14, 400, 42), 29, INK, true)
	var module: String = state.field_gear.equipped
	var loadout := "未装载" if module.is_empty() else str(State.FieldGear.MODULES[module]["title"])
	text_at(panel, "背架 · %s      每处遗址只回收一次；口粮包含往返。" % loadout, Rect2(25, 61, 1200, 32), 17, MUTED)
	gear_button = button_at(panel, "野外整备", Rect2(628, 20, 160, 40), _open_gear_board)
	gear_button.tooltip_text = "将物资卡放上拼装托盘，组装并选择本次外出的背架"
	var close := button_at(panel, "返回营地", Rect2(1120, 20, 154, 40), _close_exploration)
	var choose := OptionButton.new()
	choose.position = Vector2(815, 20)
	choose.size = Vector2(280, 40)
	panel.add_child(choose)
	var workers: Array[String] = []
	for id in state.crew:
		if state.crew_region(id) == State.CAMP:
			workers.append(id)
			choose.add_item(State.CREW_NAMES[id] + " · " + _crew_short_status(id))
			if selected_crew == id:
				choose.select(workers.size() - 1)
	if selected_crew not in workers and not workers.is_empty():
		selected_crew = workers[0]
	choose.item_selected.connect(func(index: int):
		selected_crew = workers[index]
		_close_exploration()
		_open_exploration())
	expedition_buttons.clear()
	patrol_buttons.clear()
	route_details.clear()
	expedition_recall = null
	var index := 0
	for point in State.Expeditions.LOCATIONS:
		var location: Dictionary = State.Expeditions.LOCATIONS[point]
		var card := panel_at(panel, Rect2(24 + index * 422, 110, 408, 400), Color("#242024"))
		text_at(card, "%02d  %s" % [index + 1, location["title"]], Rect2(18, 12, 372, 40), 25, TEAL, true)
		var description := text_at(card, "", Rect2(18, 58, 372, 63), 17, MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.text = location["detail"]
		var active := ""
		for id in state.crew:
			if state.crew[id]["job"] in location["choices"]:
				active = id
		if state.expeditions.resolved.has(point):
			var done: String = state.expeditions.resolved[point]
			var completed := text_at(card, "", Rect2(18, 149, 372, 55), 20, TEAL)
			completed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			completed.text = "已完成 · " + State.RECIPES[done]["label"]
			var result := "精密采样蓝图已带回\n在研究站试制：每批矿样 +1" if done == "scout_blueprint" else "已带回 " + _resource_text(state.production_output(done))
			if done == "scout_blueprint" and state.expeditions.sampler_built:
				result = "采样器已完成试制\n矿脉产量：每批 3 份矿样"
			text_at(card, result, Rect2(18, 220, 372, 85), 19, INK)
		elif not active.is_empty():
			var job: String = state.crew[active]["job"]
			text_at(card, State.CREW_NAMES[active] + " · " + State.RECIPES[job]["label"], Rect2(18, 145, 372, 52), 20, TEAL)
			text_at(card, _field_activity(active), Rect2(18, 207, 372, 65), 19, INK)
			expedition_recall = button_at(card, "召回队员 · 退回未结算补给" if state.crew_away(active) else "取消派遣 · 保留岗位", Rect2(18, 310, 372, 52), _recall_expedition.bind(active))
			expedition_recall.add_theme_font_size_override("font_size", 17)
		else:
			for option in range(2):
				var recipe: String = location["choices"][option]
				var why := state.reason(selected_crew, recipe)
				var y := 134.0 + option * 126
				var button := button_at(card, State.RECIPES[recipe]["label"], Rect2(18, y, 372, 46), _dispatch_expedition.bind(recipe), why.is_empty())
				button.disabled = not why.is_empty()
				button.add_theme_font_size_override("font_size", 18)
				expedition_buttons[recipe] = button
				var summary := _field_summary(recipe)
				if not why.is_empty():
					summary += "\n" + why
				var info := text_at(card, "", Rect2(18, y + 49, 372, 74), 15, MUTED if why.is_empty() else ORANGE)
				info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				info.text = summary
				route_details[recipe] = info
		index += 1
	_build_patrol_row(panel)
	close.grab_focus()
	_trap_focus(panel)
	_refresh()


func _field_summary(recipe: String) -> String:
	var cost := _resource_text(state.recipe_cost(recipe))
	var reward := _resource_text(state.production_output(recipe))
	if recipe == "scout_blueprint":
		reward = "精密采样蓝图"
	var details := "作业约 %d 秒" % ceili(state._duration(recipe))
	var injury := state.expedition_injury(recipe)
	if injury > 0:
		details += "  ·  健康 −%d" % roundi(injury)
	return "%s  →  %s\n%s" % [cost, reward, details]


func _field_activity(worker: String) -> String:
	if state.crew_away(worker):
		return "途中进度 %d%%\n返营后发放回收物资" % roundi(100 * state.progress(worker))
	return "%s\n正式出发后预留补给" % state.activity(worker)


func _build_patrol_row(panel: Control) -> void:
	var row := panel_at(panel, Rect2(24, 526, 1252, 156), Color("#1d2829"))
	text_at(row, "营地补给巡线", Rect2(18, 10, 310, 37), 23, TEAL, true)
	patrol_status = text_at(row, "", Rect2(18, 55, 307, 91), 17, MUTED)
	patrol_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var active := state.active_at("shelter")
	if not active.is_empty() and state.crew[active]["job"] in State.Expeditions.PATROLS:
		var job: String = state.crew[active]["job"]
		patrol_status.text = "%s · %s\n%s" % [State.CREW_NAMES[active], State.RECIPES[job]["label"], _field_activity(active)]
		expedition_recall = button_at(row, "召回巡线队员" if state.crew_away(active) else "取消派遣", Rect2(388, 52, 340, 54), _recall_expedition.bind(active))
		text_at(row, "未结算补给退回，原岗位保留", Rect2(756, 52, 455, 54), 17, MUTED)
		return
	var wait := state.expeditions.patrol_wait(state.clock)
	if state.expeditions.resolved.is_empty():
		patrol_status.text = "完成任一处勘探后开放。巡线可重复，每次只派一人。"
	elif wait > 0:
		patrol_status.text = "已巡线 %d 次。补给车将在 %d 秒后发来下一次坐标。" % [state.expeditions.patrol_count, wait]
	else:
		patrol_status.text = "已巡线 %d 次。两条路线任选其一，返营 90 秒后再出发。" % state.expeditions.patrol_count
	for index in range(State.Expeditions.PATROLS.size()):
		var recipe: String = State.Expeditions.PATROLS[index]
		var x := 350 + index * 443
		var reason := state.reason(selected_crew, recipe)
		var button := button_at(row, State.RECIPES[recipe]["label"], Rect2(x, 17, 421, 42), _dispatch_expedition.bind(recipe), reason.is_empty())
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason
		patrol_buttons[recipe] = button
		var info := text_at(row, "", Rect2(x + 2, 65, 414, 78), 15, MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.text = _field_summary(recipe)
		if not reason.is_empty() and wait == 0 and not state.expeditions.resolved.is_empty():
			info.text += "\n" + reason
		route_details[recipe] = info


func _open_gear_board() -> void:
	if not is_instance_valid(exploration_overlay) or is_instance_valid(gear_board):
		return
	exploration_overlay.hide()
	gear_board = GearBoard.new()
	add_child(gear_board)
	gear_board.close_requested.connect(_close_gear_board)
	gear_board.present(state)


func _close_gear_board() -> void:
	if not is_instance_valid(gear_board):
		return
	gear_board.hide()
	gear_board.queue_free()
	gear_board = null
	if _save_due:
		_save_game()
	_close_exploration()
	_open_exploration()
	gear_button.grab_focus()


func _close_exploration() -> void:
	if not is_instance_valid(exploration_overlay):
		return
	exploration_overlay.hide()
	exploration_overlay.queue_free()
	exploration_overlay = null
	paused = _exploration_pause
	_refresh()
	scout_button.grab_focus()


func _dispatch_expedition(recipe: String) -> void:
	_close_exploration()
	_assign("shelter", recipe)


func _recall_expedition(worker: String) -> void:
	_close_exploration()
	state.recall_crew(worker)
	selected_crew = worker
	focus = worker
	focus_is_item = false
	_refresh()


func _field_input(event: InputEvent) -> void:
	if not _menu_open() and not selected_crew.is_empty() and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		state.move_crew(selected_crew, event.position)
		_pick_crew(selected_crew)
		field.accept_event()


func _draw_routes() -> void:
	if _drag_payload.get("kind") == "facility":
		for x in range(16, 998, 32):
			routes.draw_line(Vector2(x, 8), Vector2(x, 596), Color(0.7, 0.9, 0.85, 0.10))
		for y in range(16, 604, 32):
			routes.draw_line(Vector2(8, y), Vector2(990, y), Color(0.7, 0.9, 0.85, 0.10))
		var extent := state.campaign_site_size(_drag_payload["id"])
		var ghost := Rect2(_placement_point - extent / 2, extent)
		var tone := TEAL if _placement_valid else Color("#ed806b")
		routes.draw_rect(ghost, Color(tone, 0.2))
		routes.draw_rect(ghost, tone, false, 3)
	for id in state.crew:
		var unit: Dictionary = state.crew[id]
		if state.crew_away(id) and viewed_region == State.CAMP:
			routes.draw_arc(unit["dest"], 16, 0, TAU, 24, TEAL, 2, true)
			var caption := "区域运输" if State.RECIPES[unit["job"]].has("destination") else "野外勘探"
			routes.draw_string(FACE, unit["dest"] + Vector2(-34, 35), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEAL)
		if state.crew_region(id) == viewed_region and unit["phase"] in ["travel", "move"]:
			var tone := ORANGE if id == "lead" else TEAL
			routes.draw_dashed_line(unit["pos"], unit["dest"], tone, 1.8, 7)
			routes.draw_arc(unit["dest"], 12, 0, TAU, 32, tone, 1.5, true)


func _toggle_region() -> void:
	if _menu_open() or not state.highlands_visited:
		return
	viewed_region = State.HIGHLANDS if viewed_region == State.CAMP else State.CAMP
	selected_crew = ""
	focus = "trail" if viewed_region == State.HIGHLANDS else "beacon"
	focus_is_item = false
	for id in state.crew:
		if state.crew_region(id) == viewed_region:
			selected_crew = id
			break
	_refresh()


func _follow_crew(id: String, destination: String) -> void:
	if id == selected_crew:
		viewed_region = destination
		focus = "archive" if destination == State.HIGHLANDS else "beacon"
		focus_is_item = false
	elif selected_crew.is_empty() and destination == viewed_region:
		selected_crew = id


func _pick_crew(id: String) -> void:
	if not _menu_open():
		selected_crew = id
		_pick_site(id)


func _select_roster(id: String) -> void:
	if _menu_open() or not state.crew.has(id):
		return
	viewed_region = state.crew_region(id)
	_pick_crew(id)


func _crew_short_status(id: String) -> String:
	var unit: Dictionary = state.crew[id]
	if state.crew_away(id):
		return "外出 %d%%" % roundi(state.progress(id) * 100)
	if state.crew_region(id) == State.HIGHLANDS:
		return "高地"
	match unit["phase"]:
		"travel", "move": return "行进"
		"working": return "作业"
		"waiting": return "达标" if state._stock_satisfied(unit) else "缺料"
		"resting": return "休整"
	return "待命"


func _pick_site(id: String) -> void:
	if _menu_open():
		return
	focus = id
	focus_is_item = false
	_refresh()


func _pick_item(id: String) -> void:
	if _menu_open():
		return
	focus = id
	focus_is_item = true
	_refresh()


func _tool_drop_offer(_payload: Dictionary, show_hint: bool, id: String) -> Dictionary:
	var why := state.tool_transfer_reason(id)
	if _menu_open():
		why = "请先关闭菜单"
	if show_hint:
		drag_hint.show()
		drag_text.text = ("松手交给%s · 回收、采集和制造速度 +25%%" % State.CREW_NAMES[id]) if why.is_empty() else why
	return {"allowed": why.is_empty()}


func _give_tool(id: String, payload: Dictionary) -> void:
	if _menu_open() or viewed_region != State.CAMP or payload.get("kind") != "item" or payload.get("id") != "tool":
		return
	if state.equip_tool(id):
		selected_crew = id
		focus = "tool"
		focus_is_item = true
		crew_cards[id].pop()
		feedback.cue()
	_refresh()


func _stack(id: String, payload: Dictionary) -> void:
	if _menu_open():
		return
	if payload["kind"] == "crew":
		selected_crew = payload["id"]
		var recipe := state.default_recipe(id)
		if recipe in State.CrewWork.JOBS:
			state.set_order(selected_crew, recipe, "continuous")
			focus = id
			focus_is_item = false
			_refresh()
		else:
			_order(id)
	else:
		var recipe := state.recipe_for_material(id, payload["id"], selected_crew)
		if not recipe.is_empty():
			_assign(id, recipe)


func _order(id: String) -> void:
	_assign(id, state.default_recipe(id))


func _assign(id: String, recipe: String) -> void:
	if _menu_open():
		return
	focus = id
	focus_is_item = false
	state.assign(selected_crew, recipe)
	_refresh()


func _act() -> void:
	if _menu_open():
		return
	if focus_is_item:
		if focus == "tool":
			_give_tool(selected_crew, {"kind": "item", "id": "tool"})
		return
	if state.crew.has(focus):
		if state.crew_away(focus):
			state.recall_crew(focus)
		else:
			state.stop_crew(focus)
		_refresh()
	elif state.site_visible(focus):
		_order(focus)


func _act_alternate() -> void:
	if _menu_open() or focus_is_item:
		return
	if state.crew.has(focus):
		state.rest_crew(focus)
		_refresh()
	elif state.site_visible(focus):
		var recipe := state.alternate_recipe(focus)
		if not recipe.is_empty():
			_assign(focus, recipe)


func _report(message: String) -> void:
	log_line.text = message


func _toggle_auto() -> void:
	if not _menu_open():
		state.toggle_extractor()
		_refresh()


func _refresh() -> void:
	if state.homeward_launched:
		if not is_instance_valid(flight_log):
			paused = true
			flight_log = FlightLog.new()
			add_child(flight_log)
			flight_log.present(state, feedback.reduced_motion)
			flight_log.menu_requested.connect(_back)
			_trap_focus(flight_log)
			_save_game()
		return
	speed_button.text = "%d×" % game_speed
	speed_button.disabled = _menu_open()
	var seconds := int(state.clock)
	var in_highlands := viewed_region == State.HIGHLANDS
	var local_crew := 0
	var deployed := 0
	scout_button.visible = state.first_harvest and viewed_region == State.CAMP
	scout_button.text = "勘探 / 巡线" if state.expeditions.resolved.size() == 3 else "周边勘探 %d/3" % state.expeditions.resolved.size()
	radar_button.visible = in_highlands and state.highlands_visited
	if radar_button.visible:
		var why := state.radar.operator_reason(state)
		radar_button.disabled = not why.is_empty() or _menu_open()
		radar_button.tooltip_text = why if not why.is_empty() else "布设探针，在回波交点标记可开挖的位置"
	for id in state.crew:
		if state.crew_region(id) == viewed_region:
			if state.crew_away(id):
				deployed += 1
			else:
				local_crew += 1
	status.text = "时间 %02d:%02d · 本区 %d" % [int(seconds / 60.0), seconds % 60, local_crew]
	if paused:
		status.text = "已暂停 · 本区 %d" % local_crew
	if deployed > 0:
		status.text += " · 外出 %d" % deployed
	orders_button.visible = state.recruited
	orders_button.disabled = selected_crew.is_empty() or state.crew_away(selected_crew)
	goal_button.disabled = _menu_open()
	for id in crew_buttons:
		var button: Button = crew_buttons[id]
		button.visible = state.crew.has(id)
		if not button.visible:
			continue
		button.disabled = _menu_open()
		button.text = State.CREW_NAMES[id] + " · " + _crew_short_status(id)
		button.add_theme_color_override("font_color", TEAL if id == selected_crew else MUTED)
		button.tooltip_text = "%s · %s\n点击定位；%s" % [State.CREW_NAMES[id], state.activity(id), State.CrewWork.duty_text(state.crew[id], State.RECIPES)]
	auto_button.visible = state.power.extractor_built
	auto_button.text = "暂停自动采冰" if state.power.extractor_enabled else "恢复自动采冰"
	energy_label.visible = in_highlands or state.pump_built
	if in_highlands:
		var cargo: Dictionary = state.radar.depot_cargo()
		energy_label.text = "接驳点暂存 · %s" % _resource_text(cargo) if not cargo.is_empty() else "接驳点货架空闲"
	elif state.power.solar_built:
		var equipment := "采冰机 %d%%" % state.power.condition if state.power.extractor_built else "可装配自动采冰机"
		energy_label.text = "营地电量 %d/40 · %s · %s" % [floori(state.power.energy), state.power.forecast(), equipment]
	elif state.power.blueprint:
		energy_label.text = "能源蓝图已取得 · 在残骸处组装储能组"
	else:
		energy_label.text = "能源蓝图可研究或交换 · 从工作安排中选择"
	location_label.text = "北缘高地 · 旧测绘站" if in_highlands else "迫降地 · 阿耳古瑞平原"
	local_map_label.text = "北缘高地" if in_highlands else "着陆区"
	field_help.text = "雷达定位 · 拖队员开挖 · 接驳点返运" if in_highlands else "右键选任务 · 拖队员设岗 · 拖设施布置"
	region_button.visible = state.highlands_visited
	region_button.text = "查看迫降地" if in_highlands else "查看北缘高地"
	terrain.texture = HIGHLAND_GROUND if in_highlands else GROUND
	terrain.modulate = Color("#c7c3bc") if in_highlands else Color("#dcbcab")
	if state.power.solar_built:
		if state.power.weather_stage() == "storm":
			terrain.modulate *= Color("#b89a78")
		elif not state.power.daylight():
			terrain.modulate *= Color("#898ba7")
	inventory_title.text = "迫降地库存" if in_highlands else "随身物资"
	routes.queue_redraw()
	if focus == "casualty" and state.recruited and not focus_is_item:
		focus = "tech"
		selected_crew = focus
	for id in state.crew:
		if not crew_cards.has(id):
			_add_crew_card(id)
		var card: Control = crew_cards[id]
		var unit: Dictionary = state.crew[id]
		card.visible = state.crew_region(id) == viewed_region and not state.crew_away(id)
		card.tool_equipped = state.tool_holder == id
		card.position = unit["pos"] - CREW_SIZE / 2
		card.reduced_motion = feedback.reduced_motion
		card.update_display(state.activity(id), "", state.progress(id), selected_crew == id)
	for id in sites:
		var card: Control = sites[id]
		card.visible = state.site_visible(id) and state.site_region(id) == viewed_region
		if not card.visible:
			continue
		card.position = state.site_position(id) - card.size / 2
		card.relocatable = id in State.CampLayout.MOVABLE and viewed_region == State.CAMP and state.active_at(id).is_empty() and not _menu_open()
		card.tooltip_text = "可拖到空地调整设施位置" if card.relocatable else ("停止工作后可调整位置" if id in State.CampLayout.MOVABLE else "")
		card.heading = _site_title(id)
		card.finished = state.survey_site_exhausted(id) or (id == "lab" and state.alternate_recipe(id).is_empty() and (state.calibration_blueprint if state.first_record_uploaded() else state.blueprint))
		card.finished = card.finished or (id == "archive" and state.navigation_record) or (id == "outpost" and state.outpost_built)
		card.finished = card.finished or (id == "array" and not state.third_record_source.is_empty())
		card.finished = card.finished or (id == "shelter" and state.botanist_joined)
		var recipe := state.default_recipe(id)
		if recipe in ["dig_lens", "dig_cache"]:
			card.finished = state.recipe_completed(recipe)
		var alternative := state.alternate_recipe(id)
		var inputs := PackedStringArray(State.RECIPES[recipe].get("cost", {}).keys())
		if not alternative.is_empty():
			inputs.append_array(PackedStringArray(State.RECIPES[alternative].get("cost", {}).keys()))
		card.accepted_items = inputs
		var worker := state.active_at(id)
		card.show_work_stack(state, worker)
		card.reduced_motion = feedback.reduced_motion
		var progress := -1.0 if worker.is_empty() else state.progress(worker)
		if id == "ice" and state.power.extractor_built and worker.is_empty():
			progress = state.power.progress / State.PowerGrid.AUTO_BATCH_TIME
		card.update_display(_site_caption(id, worker), "", progress, not focus_is_item and focus == id)
	_refresh_inventory()
	_refresh_objective()
	_refresh_detail()


func _refresh_inventory() -> void:
	var x := 18.0
	var count := 7 if state.first_harvest else (5 if state.recruited else 4)
	var width := floorf((1340.0 - 16 * (count - 1)) / count)
	for id in items:
		var card: Control = items[id]
		card.visible = _item_visible(id)
		if card.visible:
			card.position.x = x
			card.size.x = width
			var caption: String = ITEM_INFO[id][1]
			if id == "tool" and not state.tool_holder.is_empty():
				caption = State.CREW_NAMES[state.tool_holder] + "携带"
			card.update_display(caption, str(state.inventory[id]), -1, focus_is_item and focus == id)
			if id == "food" and state.recruited:
				var diners := state.camp_diners()
				card.caption = "%d秒后用餐 −%d" % [ceili(60 - state._ration_clock), diners]
				card.queue_redraw()
			x += width + 16.0


func _item_visible(id: String) -> bool:
	match id:
		"ice": return state.recruited
		"plate", "circuit": return state.first_harvest
	return true


func _refresh_objective() -> void:
	var goal := Guide.current(state)
	objective_title.text = goal["title"]
	objective.text = goal["text"]
	objective.add_theme_color_override("font_color", TEAL if state.array_calibrated else INK)
	aid_button.visible = not state.requests.active.is_empty()
	aid_button.disabled = _menu_open()
	goal_button.size.x = 192 if aid_button.visible else 318
	if aid_button.visible:
		aid_button.text = "互助 %d秒" % ceili(state.requests.remaining)
	goal_button.text = goal["cta"]
	goal_button.add_theme_color_override("font_color", ORANGE if goal["alert"] else TEAL)
	goal_button.tooltip_text = "打开对应地点的任务列表，自行选择是否派工"


func _show_goal() -> void:
	if _menu_open():
		return
	var goal := Guide.current(state)
	_locate_work(goal["site"], goal["recipe"])


func _show_aid() -> void:
	if not _menu_open() and not state.requests.active.is_empty():
		_locate_work("relay", state.requests.choices()[0])


func _locate_work(site: String, recipe: String) -> void:
	var region := state.site_region(site)
	var candidates: Array[String] = []
	for id in state.crew:
		if state.crew_region(id) == region and not state.crew_away(id):
			candidates.append(id)
	if candidates.is_empty() and region == State.HIGHLANDS:
		site = "beacon"
		recipe = "depart"
		region = State.CAMP
		for id in state.crew:
			if state.crew_region(id) == region and not state.crew_away(id):
				candidates.append(id)
	viewed_region = region
	if recipe in ["launch_homeward", "return"] and "lead" in candidates:
		selected_crew = "lead"
	elif selected_crew not in candidates:
		selected_crew = candidates[0] if not candidates.is_empty() else ""
	_refresh()
	_open_context(site, recipe)


func _site_title(id: String) -> String:
	if id == "greenhouse" and not state.greenhouse_built:
		return "温室基座"
	if id == "ice" and state.power.extractor_built:
		return "自动采冰站"
	return State.SITES[id]["title"]


func _site_caption(id: String, worker: String) -> String:
	if state.survey_site_exhausted(id):
		return "已采集"
	if not worker.is_empty():
		var phase: String = state.crew[worker]["phase"]
		match phase:
			"waiting", "resting": return state.activity(worker)
			"working": return "%s作业中" % State.CREW_NAMES[worker]
			_: return "%s前往中" % State.CREW_NAMES[worker]
	if id == "wreck" and not state.recovered.has("wreck"):
		return "舱体 / 补给箱 · 二选一"
	if state.array_calibrated:
		if id in ["array", "relay"] and state.third_record_source.is_empty():
			return "可取得末份航标"
		if id == "wreck" and state.navigation_count() == 3 and not state.return_craft_ready:
			return "归航舱待组装"
		if id == "beacon" and state.return_craft_ready:
			return "归航舱待点火"
	match id:
		"wreck": return "太阳能板 · %d%%" % state.power.cleanliness if state.power.solar_built else "残件 ×3"
		"ore": return "精密采样 · 矿样 ×3" if state.expeditions.sampler_built else "矿样 ×2"
		"casualty": return "需要口粮 ×1"
		"ice": return state.power.extractor_status if state.power.extractor_built else "水冰 ×2"
		"greenhouse": return ("循环泵 · 口粮 ×5" if state.pump_built else "水冰 → 口粮 ×3") if state.greenhouse_built else "需要残件 ×1"
		"bench": return "加工与装配" if state.blueprint else "残件 → 结构件"
		"lab":
			if state.expeditions.sampler_blueprint and not state.expeditions.sampler_built:
				return "可试制精密采样器"
			if state.pump_built and not state.power.blueprint:
				return "可研究能源蓝图"
			if state.first_record_uploaded():
				return "校准蓝图已解锁" if state.calibration_blueprint else "可研究校准蓝图"
			return "蓝图已解锁" if state.blueprint else "矿样 + 残件"
		"relay":
			if not state.requests.active.is_empty():
				return "互助请求 · 剩余 %d秒" % ceili(state.requests.remaining)
			if state.first_record_uploaded() and not state.calibration_blueprint:
				return "结构件 ×2 → 蓝图"
			return ("制造间已扩建 · %d" if state.neighbor_upgraded else "库存电路 ×%d") % state.neighbor_stock
		"shelter":
			if state.pump_built and not state.botanist_joined and state.shelter_expanded:
				return "农艺师申请加入"
			return "床位 %d / %d" % [state.crew.size(), state.beds()]
		"beacon": return "北缘高地接驳已开放" if state.won else "结构件 + 电路"
		"radar_lens", "radar_cache":
			return "已回收" if state.recipe_completed(state.default_recipe(id)) else "已定位 · 可派员开挖"
		"trail": return "有样本待返运" if not state.radar.depot_cargo().is_empty() else "通往迫降地"
		"archive": return "已回收航标" if state.navigation_record else "旧航标资料"
		"outpost":
			if state.outpost_built:
				return "已接入轨道通信"
			return "物资已到达" if state.outpost_supplied else "等待迫降地运送物资"
		"array":
			if state.array_calibrated:
				return "第二份航标已同步"
			return "设备已送达 · 可校准" if state.array_supplied else "等待校准蓝图与设备"
	return ""


func _refresh_detail() -> void:
	detail_hint.text = ""
	detail_hint.position.y = 438
	detail_hint.size.y = 43
	if focus_is_item or state.crew.has(focus):
		alternate_button.hide()
	if focus_is_item:
		action_button.hide()
		detail_kind.text = "随身物资 · 库存 %d" % state.inventory[focus]
		detail_title.text = ITEM_INFO[focus][0]
		detail_body.text = ITEM_INFO[focus][2]
		if focus == "tool":
			detail_kind.text = "唯一装备 · " + ("营地保管" if state.tool_holder.is_empty() else State.CREW_NAMES[state.tool_holder] + "携带")
			var why := state.tool_transfer_reason(selected_crew)
			detail_hint.text = "可直接将工具卡拖到队员牌上" if why.is_empty() else why
			_set_action("交给%s" % State.CREW_NAMES.get(selected_crew, "队员"), not why.is_empty() or viewed_region != State.CAMP)
	elif state.crew.has(focus):
		var unit: Dictionary = state.crew[focus]
		detail_kind.text = "健康 %d · 体力 %d · 士气 %d" % [unit.get("health", 100), unit.get("stamina", 100), unit.get("morale", 80)]
		detail_title.text = crew_cards[focus].heading
		var profile: Dictionary = State.CrewWork.PROFILES[focus]
		detail_body.text = "%s · %s\n%s" % [profile["trait"], profile["specialty"], State.CrewWork.duty_text(unit, State.RECIPES)]
		detail_hint.text = state.activity(focus)
		alternate_button.show()
		alternate_button.text = "安排休整 · 恢复后归岗"
		alternate_button.disabled = unit["phase"] == "resting" or state.crew_away(focus)
		detail_hint.position.y = 469
		detail_hint.size.y = 28
		if unit["phase"].is_empty() and unit.get("duty", {}).is_empty():
			action_button.hide()
		else:
			_set_action("召回 · 退回补给并保留岗位" if state.crew_away(focus) else "停止行动并解除岗位", false)
		if state.crew_away(focus):
			detail_kind.text = "外出进度 %d%% · 补给已携带" % roundi(state.progress(focus) * 100)
			detail_body.text = "%s\n原岗位保留，返回营地后恢复。" % state.activity(focus)
			if unit["job"] == "return":
				action_button.text = "取消返程 · 返回高地出发点"
				var cargo: Dictionary = state.radar.aboard_cargo(focus)
				if not cargo.is_empty():
					detail_body.text = "返运营地 · %s\n取消返程会把货物放回高地接驳点。" % _resource_text(cargo)
	else:
		var id := focus
		var recipe := state.default_recipe(id)
		var reason := state.reason(selected_crew, recipe)
		detail_kind.text = "%s · 当前队员 %s" % [State.SITES[id]["kind"], State.CREW_NAMES.get(selected_crew, "无")]
		detail_title.text = _site_title(id)
		detail_body.text = _site_description(id)
		_set_action(State.RECIPES[recipe]["label"], not reason.is_empty())
		var alternative := state.alternate_recipe(id)
		alternate_button.visible = not alternative.is_empty()
		if alternate_button.visible:
			alternate_button.text = _recipe_caption(alternative)
			var alternate_reason := state.reason(selected_crew, alternative)
			alternate_button.disabled = not alternate_reason.is_empty()
			alternate_button.tooltip_text = alternate_reason if not alternate_reason.is_empty() else _job_summary(alternative)
			detail_hint.position.y = 469
			detail_hint.size.y = 28
		if not reason.is_empty():
			detail_hint.text = reason
		elif id == "trail":
			detail_hint.text = "接驳点装货，抵达迫降地后计入下方库存。"
		elif State.RECIPES[recipe].has("cost"):
			detail_hint.text = "投入 " + _recipe_cost(recipe)
		else:
			detail_hint.text = "右键目标或拖叠队员卡，抵达后开始作业。"
		if id == "relay":
			detail_kind.text = "邻站库存 · 电路 %d / 粮 %d / 残件 %d" % [state.neighbor_stock, state.neighbor_food, state.neighbor_scrap]
		elif id == "ice" and state.power.extractor_built:
			detail_kind.text = "自动设备 · 状态 %d%% · 批次 %d%%" % [state.power.condition, 100 * state.power.progress / State.PowerGrid.AUTO_BATCH_TIME]
		elif id == "wreck" and state.power.solar_built:
			detail_kind.text = "营地能源 · 发电 %.1f/秒 · 板面 %d%%" % [state.power.generation(), state.power.cleanliness]


func _recipe_cost(recipe: String) -> String:
	var inputs: Dictionary = State.RECIPES[recipe].get("cost", {})
	var parts := PackedStringArray()
	for item in inputs:
		parts.append("%s ×%d" % [State.ITEMS[item], inputs[item]])
	return " + ".join(parts)


func _recipe_caption(recipe: String) -> String:
	if _recipe_cost(recipe).is_empty() or recipe in ["deliver", "deliver_array", "trial_pump", "research_pump", "trial_sampler"] or State.RECIPES[recipe].get("industry", false):
		return State.RECIPES[recipe]["label"]
	return "%s · %s" % [State.RECIPES[recipe]["label"], _recipe_cost(recipe)]


func _site_description(id: String) -> String:
	if id == "wreck" and not state.recovered.has("wreck"):
		return "舱体正在下沉。拆下外壳得 3 残件，或抢救补给箱得 1 残件和 4 口粮。右键选择一次。"
	if state.array_calibrated:
		match id:
			"array":
				return "可在这里用 2 口粮、2 矿样追踪最后一份航标。也可派人去曙光站交换。" if state.third_record_source.is_empty() else "三份航标已同步，返回营地准备归航。"
			"relay":
				if state.third_record_source.is_empty():
					return "邻站愿交出末份航标，报价 2 结构件、1 电路。高地阵列也能测出同一航线。"
			"wreck":
				if state.navigation_count() == 3:
					return "归航舱已组装，选中领队，到通信信标起航。" if state.return_craft_ready else "用 3 结构件、2 电路修复舱体，在这里组装归航舱。"
			"beacon":
				if state.return_craft_ready:
					return "领队携 3 口粮、2 水冰即可起航。起航完成后，本次旅程结束，归航记录会保存。"
	match id:
		"wreck":
			if state.power.solar_built:
				return "白天发电、夜间使用蓄电。沙尘会降低输出，可用 1 份残件清理。回收残件仍可进行。"
			if state.power.blueprint:
				return "可用 2 份结构件、1 份电路组装太阳能储能组。白天发电，蓄电上限 40。"
			return "可继续拆取散落设备中的残件，用于研究或加工。" if state.first_harvest else "撞击后散落的舱体和设备。可用随身工具拆取金属残件。"
		"ore":
			return "可继续在岩层采样，用于制造电路。" if state.first_harvest else "地表露出的含铁岩层。采样后，矿物会放入随身物资。"
		"casualty": return "附近有一名受伤的勘探员。带 1 份口粮前往救助，对方愿意加入队伍。"
		"ice":
			if state.power.extractor_built:
				return "自动维持 6 份水冰，每批 20 秒产 2 份、耗 20 电。每批磨损 5%，用 1 残件维护。下方可停机。"
			if state.power.solar_built:
				return "可用 2 份结构件和 1 份电路装配自动采冰机。设备消耗电力，无需队员值守。"
			return "浅层冻土中有可提取的水冰。冰脉可反复采集，用于温室补给。"
		"greenhouse":
			if state.pump_built:
				return "循环泵试制完成，每份水冰产出 5 份口粮。拖入队员设岗，或设置库存目标自动补产。"
			if state.pump_blueprint:
				return "试制循环泵需结构件、电路、水冰各 1 份。通过试制后，每份水冰产粮从 3 提升到 5。"
			if state.greenhouse_built:
				return "每轮消耗 1 份水冰，产出 3 份口粮。缺水时停工，补水后自动继续。"
			return "用 1 份金属残件搭建密封温室。可以让另一名队员同时前往冰脉采集水冰。"
		"bench":
			if state.power.solar_built:
				return "供电时制造速度提高 25%，优先使用电力。电量耗尽时继续手工加工，可暂停采冰为制造蓄电。"
			return "用 2 份残件加工结构件。解锁蓝图后，也能用结构件和矿样制造电路。"
		"lab":
			if state.expeditions.sampler_blueprint and not state.expeditions.sampler_built:
				return "采样蓝图已带回。用 2 残件、1 电路试制后，矿脉每批产出增至 3。右键可选择其他研究。"
			if state.pump_built and not state.power.blueprint:
				return "用 2 份矿样和 1 份电路研究能源蓝图。也可在工作安排中向曙光站交换。"
			if not state.pump_blueprint:
				return "主任务研究通信蓝图。另可用 2 矿样和 1 残件研究循环泵，也能从首次电路交易取得泵图。"
			if state.first_record_uploaded():
				return "投入 3 份矿样和 1 份电路，自行研究校准蓝图。也可向曙光站交换同一蓝图。"
			return "分析 1 份矿样和 1 份残件，解锁信标维修蓝图与电路配方。"
		"relay":
			if not state.requests.active.is_empty():
				var offer: Dictionary = State.Requests.OFFERS[state.requests.active]
				return "%s：%s。\n%d秒内完成交付，右键二选一。%s" % [offer["title"], offer["short"], ceili(state.requests.remaining), "首次完成提升护理。" if state.requests.completed == 0 else ""]
			if state.pump_built and not state.power.blueprint:
				return "能源蓝图报价为 4 口粮和 1 结构件，可从底部工作安排选择。原有电路交易继续开放。"
			if state.first_record_uploaded() and not state.calibration_blueprint:
				return "曙光站愿用校准蓝图交换 2 份结构件，用于维修本站设备。电路交易仍可进行。"
			if state.requests.completed > 0:
				return "互助已完成 %d 次，护理健康恢复提升至 45。\n下一次请求 %d 秒后到来，常规电路贸易继续开放。" % [state.requests.completed, ceili(state.requests.cooldown)]
			if state.neighbor_upgraded:
				return "制造间已扩建，每 20 秒用口粮、残件各 1 份生产电路。可用 2 口粮或 3 残件交易。"
			return "首次交易分享循环泵蓝图。两次交易后，本站备齐粮、残件、电路各 1 份可扩建制造间。"
		"shelter":
			if state.recruited:
				return "床位 %d/%d。护理用口粮、水冰各1，健康+%.0f、体力+35，完成后归岗。右键可扩建或接纳农艺师。" % [state.crew.size(), state.beds(), state.requests.care_health()]
			return "自带 2 个应急床位。用 2 份残件扩建至 3 床，循环泵试制后可用 2 份口粮接纳农艺师。"
		"beacon":
			if state.calibration_blueprint and not state.array_calibrated:
				return "运送阵列设备需 2 份口粮、2 份结构件和 1 份电路。队员随货抵达高地后，可修复阵列。"
			if state.won:
				return "轨道站发来旧测绘站的坐标。可用 2 份口粮派人前往，或同时带上 1 份结构件和 1 份电路。"
			return "使用 1 份结构件和 1 份电路，让轨道接收站收到火星营地的信号。"
		"trail":
			var cargo: Dictionary = state.radar.depot_cargo()
			if not cargo.is_empty():
				return "待运 %s。返程队员出发时装货，抵达营地入库；途中召回会将货物放回本站。" % _resource_text(cargo)
			return "返程队员会把接驳点暂存的发掘物资带回营地。返程口粮已随出发补给携带。"
		"archive":
			return "从旧站回收航标记录。右键本站或点击地图左上的「浅层雷达」，还能自行勘测高地埋藏物。"
		"radar_lens", "radar_cache":
			var recipe := state.default_recipe(id)
			if state.recipe_completed(recipe):
				return "该处已发掘完毕。接驳点可以查看待返运的物资。"
			return "把当地队员卡拖到此处，回收%s。物资先暂存接驳点，再随返程队员运回营地。" % _resource_text(state.production_output(recipe))
		"outpost":
			if state.outpost_built:
				return "前哨已与轨道站建立联络，可上传从高地回收的航标记录。"
			return "从迫降地的通信信标选择「运送前哨物资」，物资到达后可安排队员架设前哨。"
		"array":
			if state.array_calibrated:
				return "阵列已完成轨道信号校准。第二份航标资料已通过前哨上传，距离恢复归航航路还需一份记录。"
			return "先在曙光站交换或在研究站研究校准蓝图，再从信标运送设备。修复阵列可取得第二份航标。"
	return ""


func _set_action(label: String, disabled: bool) -> void:
	action_button.text = label
	action_button.disabled = disabled
	action_button.show()


func _open_orders() -> void:
	if _menu_open() or selected_crew.is_empty() or state.crew_away(selected_crew):
		return
	_pause_before_orders = paused
	paused = true
	orders_overlay = fill_at(self, Rect2(Vector2.ZERO, SIZE), Color(0.08, 0.05, 0.05, 0.72))
	orders_overlay.mouse_filter = MOUSE_FILTER_STOP
	orders_overlay.z_index = 200
	var panel := panel_at(orders_overlay, Rect2(420, 205, 600, 490))
	text_at(panel, "%s · 工作安排" % State.CREW_NAMES[selected_crew], Rect2(28, 20, 544, 45), 29, INK, true)
	text_at(panel, "生产可设岗位或库存目标，工程与研究按次执行。\n临时任务结束后自动归岗，跨区外出保留岗位。", Rect2(28, 74, 544, 60), 17, MUTED)
	text_at(panel, "工作内容", Rect2(28, 151, 140, 38), 19)
	order_recipe = OptionButton.new()
	order_recipe.position = Vector2(178, 151)
	order_recipe.size = Vector2(394, 40)
	panel.add_child(order_recipe)
	_order_recipes.clear()
	for recipe in state.order_actions(viewed_region):
		_order_recipes.append(recipe)
		order_recipe.add_item(State.RECIPES[recipe]["label"])
		if not focus_is_item and not state.crew.has(focus) and state.default_recipe(focus) == recipe:
			order_recipe.select(_order_recipes.size() - 1)
	text_at(panel, "生产方式", Rect2(28, 211, 140, 38), 19)
	order_mode = OptionButton.new()
	order_mode.position = Vector2(178, 211)
	order_mode.size = Vector2(394, 40)
	panel.add_child(order_mode)
	for label in ["持续岗位", "完成指定批数", "维持目标库存", "单次任务"]:
		order_mode.add_item(label)
	text_at(panel, "批数 / 库存", Rect2(28, 271, 140, 38), 19)
	order_amount = SpinBox.new()
	order_amount.position = Vector2(178, 271)
	order_amount.size = Vector2(394, 40)
	order_amount.min_value = 1
	order_amount.max_value = 99
	order_amount.value = 6
	panel.add_child(order_amount)
	order_amount.editable = false
	order_mode.item_selected.connect(_order_mode_changed)
	order_feedback = text_at(panel, "", Rect2(28, 328, 544, 62), 15, ORANGE)
	order_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	order_recipe.item_selected.connect(_order_recipe_changed)
	order_confirm = button_at(panel, "确认安排", Rect2(28, 401, 260, 54), _confirm_orders, true)
	button_at(panel, "返回", Rect2(312, 401, 260, 54), _close_orders)
	_order_recipe_changed(order_recipe.selected)
	_refresh()
	order_recipe.grab_focus()
	_trap_focus(panel)


func _order_recipe_changed(index: int) -> void:
	if index < 0 or index >= _order_recipes.size():
		_order_mode_changed(0)
		return
	var recipe := _order_recipes[index]
	var single := recipe not in State.CrewWork.JOBS
	order_mode.disabled = single
	if single:
		order_mode.select(3)
	elif order_mode.selected == 3:
		order_mode.select(0)
	_order_mode_changed(order_mode.selected)


func _order_mode_changed(index: int) -> void:
	order_amount.editable = index in [1, 2]
	if _order_recipes.is_empty():
		order_confirm.disabled = true
		order_feedback.text = "当前区域暂无可安排任务"
		return
	var recipe := _order_recipes[order_recipe.selected]
	var duty := recipe in State.CrewWork.JOBS and index != 3
	var why := state.reason(selected_crew, recipe, duty)
	order_confirm.disabled = not why.is_empty()
	var description := "%s · %s" % [State.SITES[State.RECIPES[recipe]["site"]]["title"], _job_summary(recipe)]
	if not why.is_empty():
		description += "\n" + why
	elif duty and not state.missing(recipe).is_empty():
		description += "\n缺料时保留岗位，等待补给"
	elif index == 2:
		description += "\n按产出物计算目标，完整批次可能略超目标"
	order_feedback.text = description
	_trap_focus(order_recipe.get_parent())


func _confirm_orders() -> void:
	if _order_recipes.is_empty():
		return
	var recipe := _order_recipes[order_recipe.selected]
	var accepted := false
	if recipe not in State.CrewWork.JOBS or order_mode.selected == 3:
		accepted = state.assign(selected_crew, recipe)
	else:
		var mode: String = ["continuous", "batch", "stock"][order_mode.selected]
		accepted = state.set_order(selected_crew, recipe, mode, int(order_amount.value))
	if accepted:
		_close_orders()
		focus = selected_crew
		focus_is_item = false
		_refresh()
	else:
		order_feedback.text = log_line.text


func _close_orders() -> void:
	if not is_instance_valid(orders_overlay):
		return
	orders_overlay.hide()
	orders_overlay.queue_free()
	orders_overlay = null
	paused = _pause_before_orders
	_refresh()
	orders_button.grab_focus()


func _toggle_pause() -> void:
	if is_instance_valid(pause_overlay):
		pause_overlay.queue_free()
		pause_overlay = null
		paused = _pause_before_menu
		pause_button.disabled = false
		region_button.disabled = false
		action_button.focus_mode = FOCUS_ALL
		alternate_button.focus_mode = FOCUS_ALL
		_refresh()
		pause_button.grab_focus()
		return
	if _menu_open():
		return
	_pause_before_menu = paused
	paused = true
	pause_button.disabled = true
	region_button.disabled = true
	action_button.focus_mode = FOCUS_NONE
	alternate_button.focus_mode = FOCUS_NONE
	pause_overlay = fill_at(self, Rect2(Vector2.ZERO, SIZE), Color(0.08, 0.05, 0.05, 0.72))
	pause_overlay.mouse_filter = MOUSE_FILTER_STOP
	pause_overlay.z_index = 200
	var panel := panel_at(pause_overlay, Rect2(495, 230, 450, 490))
	text_at(panel, "游戏暂停", Rect2(26, 21, 398, 56), 36, INK, true)
	var resume := button_at(panel, "继续勘探", Rect2(26, 98, 398, 55), _toggle_pause, true)
	restart_button = button_at(panel, "重新开始", Rect2(26, 166, 398, 52), _request_restart)
	back_button = button_at(panel, "返回主菜单", Rect2(26, 233, 398, 52), _back)
	save_button = button_at(panel, "保存进度", Rect2(26, 300, 398, 52), _manual_save)
	var quiet := CheckBox.new()
	quiet.text = "操作音效"
	quiet.position = Vector2(26, 365)
	quiet.size = Vector2(398, 42)
	quiet.button_pressed = feedback.sound_enabled
	quiet.toggled.connect(_feedback_setting.bind("sound"))
	panel.add_child(quiet)
	var motion := CheckBox.new()
	motion.text = "减少动态效果"
	motion.position = Vector2(26, 415)
	motion.size = Vector2(398, 42)
	motion.button_pressed = feedback.reduced_motion
	motion.toggled.connect(_feedback_setting.bind("reduced_motion"))
	panel.add_child(motion)
	resume.grab_focus()
	_trap_focus(panel)
	_refresh()


func _request_restart() -> void:
	if is_instance_valid(replace_prompt):
		return
	replace_prompt = ReplacePrompt.new()
	add_child(replace_prompt)
	replace_prompt.accepted.connect(get_tree().reload_current_scene)
	replace_prompt.canceled.connect(restart_button.grab_focus)


func _feedback_setting(value: bool, key: String) -> void:
	if key == "sound":
		feedback.sound_enabled = value
	else:
		feedback.reduced_motion = value
		if value:
			for card in sites.values() + crew_cards.values():
				card.reduced_motion = true
				card.pop()
	var settings := ConfigFile.new()
	settings.set_value("feedback", "sound", feedback.sound_enabled)
	settings.set_value("feedback", "reduced_motion", feedback.reduced_motion)
	settings.save(_settings_path)


func _trap_focus(panel: Control) -> void:
	var buttons: Array[Control] = []
	for node in panel.find_children("*", "Control", true, false):
		if node is SpinBox and node.editable and node.is_visible_in_tree():
			var edit: LineEdit = node.get_line_edit()
			if edit not in buttons:
				buttons.append(edit)
		if not node.is_visible_in_tree() or node.focus_mode == FOCUS_NONE:
			continue
		if node is BaseButton and node.disabled:
			continue
		if node is LineEdit and not node.editable:
			continue
		if node not in buttons:
			buttons.append(node)
	for index in range(buttons.size()):
		var current: Control = buttons[index]
		current.focus_neighbor_top = buttons[(index - 1 + buttons.size()) % buttons.size()].get_path()
		current.focus_neighbor_bottom = buttons[(index + 1) % buttons.size()].get_path()
		current.focus_neighbor_left = current.get_path()
		current.focus_neighbor_right = current.get_path()
		current.focus_previous = buttons[(index - 1 + buttons.size()) % buttons.size()].get_path()
		current.focus_next = buttons[(index + 1) % buttons.size()].get_path()


func _back() -> void:
	if _save_game():
		get_tree().change_scene_to_file(MENU)
