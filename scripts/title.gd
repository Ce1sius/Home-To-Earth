extends "res://scripts/screen.gd"

const ReplacePrompt := preload("res://scripts/replace_prompt.gd")
const COVER := preload("res://assets/art/title_mars.png")
const ARROW := preload("res://assets/icons/arrow.svg")
const MOUSE := preload("res://assets/icons/mouse.svg")
const POWER := preload("res://assets/icons/power.svg")
const LANDING := "res://scenes/opening.tscn"
const Save := preload("res://scripts/campaign_save.gd")

var replace_prompt: Control
var instructions: Control
var start_button: Button
var help_button: Button
var exit_button: Button
var continue_button: Button


func _ready() -> void:
	super._ready()
	get_tree().auto_accept_quit = true
	var backdrop := art_at(self, COVER, Rect2(Vector2.ZERO, SIZE))
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fill_at(self, Rect2(0, 0, 1440, 900), Color(0.08, 0.04, 0.045, 0.20))
	fill_at(self, Rect2(83, 97, 35, 2), ORANGE)
	text_at(self, "火星地表勘探任务", Rect2(130, 82, 318, 30), 17, ORANGE)
	text_at(self, "星火归航", Rect2(77, 161, 530, 124), 101, INK, true)
	text_at(self, "S T A R F I R E   H O M E B O U N D", Rect2(88, 294, 450, 30), 15, ORANGE)
	text_at(self, "着陆舱坠毁，你独自走上火星地表。\n把营地建起来，找齐三份航标，登舱归航。",
		Rect2(88, 367, 460, 67), 21, MUTED)
	start_button = button_at(self, "开始新游戏", Rect2(88, 513, 302, 60), _start, true, ARROW)
	start_button.tooltip_text = "开启新进度并替换当前存档"
	help_button = button_at(self, "操作说明", Rect2(88, 587, 302, 52), _show_instructions, false, MOUSE)
	exit_button = button_at(self, "退出游戏", Rect2(88, 653, 302, 52), get_tree().quit, false, POWER)
	continue_button = button_at(self, "继续游戏", Rect2(88, 439, 302, 60), _continue_game, true, ARROW)
	var saved := Save.read_game()
	continue_button.visible = not saved.is_empty()
	if continue_button.visible:
		if saved["state"].homeward_launched:
			continue_button.text = "查看归航记录"
		continue_button.grab_focus()
	else:
		start_button.grab_focus()
	if not Save.last_error.is_empty():
		text_at(self, Save.last_error, Rect2(88, 455, 480, 38), 17, MUTED)
	fill_at(self, Rect2(88, 795, 302, 1), EDGE)
	text_at(self, "迫降地点  /  阿耳古瑞平原", Rect2(88, 810, 350, 34), 15, MUTED)


func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(instructions) and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_instructions()
		get_viewport().set_input_as_handled()


func _start() -> void:
	if is_instance_valid(replace_prompt):
		return
	if FileAccess.file_exists(Save.path):
		replace_prompt = ReplacePrompt.new()
		add_child(replace_prompt)
		replace_prompt.accepted.connect(_new_campaign)
		replace_prompt.canceled.connect(start_button.grab_focus)
	else:
		_new_campaign()


func _new_campaign() -> void:
	Save.pending = {}
	get_tree().change_scene_to_file(LANDING)


func _continue_game() -> void:
	Save.pending = Save.read_game()
	if Save.pending.is_empty():
		continue_button.disabled = true
		continue_button.text = "存档暂时无法读取"
		return
	get_tree().change_scene_to_file(LANDING)


func _show_instructions() -> void:
	if is_instance_valid(instructions):
		return
	start_button.disabled = true
	help_button.disabled = true
	exit_button.disabled = true
	continue_button.disabled = true
	instructions = fill_at(self, Rect2(Vector2.ZERO, SIZE), Color(0.07, 0.04, 0.05, 0.68))
	instructions.mouse_filter = MOUSE_FILTER_STOP
	var panel := panel_at(instructions, Rect2(421, 215, 598, 470))
	text_at(panel, "操作说明", Rect2(31, 22, 496, 51), 32, INK, true)
	text_at(panel, "左键选择  ·  右键目标查看可执行任务\n拖叠队员卡  ·  预览配方并设置持续岗位\n拖动闲置设施  ·  在空地布置营地\n顶部队员栏  ·  定位队员、查看外出与召回\n周边勘探  ·  首批收获后拼装背架、派人出发\n工作安排  ·  统一选择生产、研究与工程\n任务栏下方  ·  定位当前目标或补给缺口\n数字键 1 / 2 / 3 调速  ·  空格暂停  ·  Esc 保存",
		Rect2(32, 91, 534, 270), 20)
	var close := button_at(panel, "返回", Rect2(32, 390, 534, 51), _close_instructions)
	close.grab_focus()


func _close_instructions() -> void:
	instructions.queue_free()
	start_button.disabled = false
	help_button.disabled = false
	exit_button.disabled = false
	continue_button.disabled = false
	help_button.grab_focus()
