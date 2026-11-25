extends SceneTree

const Mission = preload("res://scenes/mission.tscn")
const State = preload("res://scripts/mission_state.gd")

var game: Control
var failures := 0
var pointer := Vector2.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	game = Mission.instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	_expect(not game.site_cards["casualty"].visible, "求救卡在回收之前隐藏")
	_expect(game.state.inventory["food"] == 6, "开局有六份口粮")

	_click(game.map.position + Vector2(364, 270), MOUSE_BUTTON_RIGHT)
	_expect(game.state.crew["lead"]["phase"] == "move", "右键空地发送移动指令")
	_click(_center(game.site_cards["wreck"]), MOUSE_BUTTON_RIGHT)
	_expect(game.state.crew["lead"]["phase"] == "travel", "右键残骸派工")
	_advance(game.state, 0.2)
	_expect(game.state.inventory["scrap"] == 0, "到场之前不产出")
	_advance(game.state, 15)
	game._refresh()
	_expect(game.state.inventory["scrap"] == 3 and game.site_cards["casualty"].visible,
		"回收残件后显示求救信号")

	await _drag(_center(game.crew_cards["lead"]), _center(game.site_cards["casualty"]))
	_expect(game.state.crew["lead"]["job"] == "rescue", "拖叠队员卡发出救助指令")
	_advance(game.state, 14)
	game._refresh()
	_expect(game.state.recruited and game.crew_cards.has("tech"), "救助后队员加入")
	if not game.crew_cards.has("tech"):
		quit(1)
		return

	_click(_center(game.crew_cards["tech"]))
	await _drag(_center(game.item_cards["scrap"]), _center(game.site_cards["bench"]))
	_expect(game.state.crew["tech"]["job"] == "fabricate", "拖残件到工作台为选中队员安排配方")
	_click(_center(game.crew_cards["lead"]))
	_click(_center(game.site_cards["ore"]), MOUSE_BUTTON_RIGHT)
	_advance(game.state, 19)
	game._refresh()
	_expect(game.state.inventory["plate"] == 1 and game.state.inventory["ore"] == 2,
		"两名队员可以同时制造和采样")

	_click(_center(game.site_cards["lab"]), MOUSE_BUTTON_RIGHT)
	_advance(game.state, 22)
	game._refresh()
	_expect(game.state.blueprint and game.state.neighbor_stock >= 2, "研究解锁且邻队后台生产")

	_press_key(KEY_SPACE)
	_expect(game.paused, "空格暂停")
	_press_key(KEY_3)
	_expect(game.speed == 3 and not game.paused, "快捷键恢复并切到三倍速")

	_click(_center(game.site_cards["relay"]))
	_click(_center(game.action_buttons[1]))
	_expect(game.state.crew["lead"]["job"] == "trade_food", "选择口粮交易配方")
	_advance(game.state, 15)
	game._refresh()
	_expect(game.state.inventory["circuit"] == 1, "交易获得电路")

	_click(_center(game.site_cards["beacon"]), MOUSE_BUTTON_RIGHT)
	_advance(game.state, 46)
	game._refresh()
	_expect(game.state.won and game.seen_victory, "交易路线修复信标并显示完成画面")

	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		_expect(image.save_png(arguments[0]) == OK, "完成界面截图")

	_test_production()
	_test_local_circuit()
	if failures == 0:
		print("PASS: UI controls, both repair routes, greenhouse, and inventory checks")
	quit(0 if failures == 0 else 1)


func _test_production() -> void:
	var state := State.new()
	_order(state, "lead", "salvage", 15)
	_order(state, "lead", "rescue", 14)
	_order(state, "lead", "build", 18)
	_expect(state.greenhouse_built, "搭建温室")
	_order(state, "lead", "extract", 16)
	_expect(state.assign("tech", "grow"), "为勘探员分配温室")
	_expect(not state.assign("lead", "grow"), "一个工位只接收一名队员")
	_advance(state, 40)
	_expect(state.inventory["ice"] == 0 and state.crew["tech"]["phase"] == "waiting",
		"连续生产消耗两份水冰并在缺水时停工")
	_order(state, "lead", "extract", 16)
	_expect(state.crew["tech"]["phase"] == "working" and state.inventory["ice"] == 1,
		"补充水冰后自动继续生产")
	state.stop_crew("tech")
	_expect(state.inventory["ice"] == 2, "取消时返还预留物资")
	_expect(state.neighbor_food == 0 and state.neighbor_stock == 4, "邻队生产受库存约束")


func _test_local_circuit() -> void:
	var state := State.new()
	_expect(not state.assign("lead", "repair"), "禁止越过救助和研究直接维修")
	_order(state, "lead", "salvage", 15)
	_order(state, "lead", "rescue", 14)
	_order(state, "lead", "salvage", 15)
	_order(state, "lead", "mine", 16)
	_order(state, "lead", "research", 23)
	_order(state, "lead", "mine", 24)
	_order(state, "lead", "fabricate", 30)
	_order(state, "lead", "etch", 42)
	_expect(state.inventory["circuit"] == 1 and state.inventory["plate"] == 0, "自制电路消耗结构件")
	_order(state, "lead", "fabricate", 30)
	_order(state, "lead", "repair", 45)
	_expect(state.won and state.inventory["circuit"] == 0, "自制路线修复信标并消耗电路")


func _order(state: RefCounted, crew: String, recipe: String, seconds: int) -> void:
	_expect(state.assign(crew, recipe), "派工 " + recipe)
	_advance(state, seconds)


func _advance(state: RefCounted, seconds: float) -> void:
	for i in range(roundi(seconds * 20.0)):
		state.tick(0.05)


func _center(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


func _press_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _click(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_motion(at)
	_mouse_button(at, button, true)
	_mouse_button(at, button, false)


func _drag(from: Vector2, to: Vector2) -> void:
	_motion(from)
	_mouse_button(from, MOUSE_BUTTON_LEFT, true)
	_motion(from.lerp(to, 0.2), MOUSE_BUTTON_MASK_LEFT)
	await process_frame
	_motion(to, MOUSE_BUTTON_MASK_LEFT)
	await process_frame
	_mouse_button(to, MOUSE_BUTTON_LEFT, false)


func _motion(at: Vector2, mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = at - pointer
	event.button_mask = mask
	pointer = at
	root.push_input(event, true)


func _mouse_button(at: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.button_mask = (1 << (button - 1)) if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
