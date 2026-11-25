extends "res://scripts/screen.gd"

signal close_requested

const Gear := preload("res://scripts/field_gear.gd")
const BlueprintArt := preload("res://scripts/gear_illustration.gd")
const SURFACE := Color("#222124")
const RECESS := Color("#172022")
const BLUEPRINT := Color("#1b292b")
const GROOVE := Color("#465858")
const TINTS := {"scrap": Color("#dcab83"), "ice": Color("#a5dfe9"),
	"plate": Color("#e0c9a4"), "ore": Color("#e8ae79")}

var material_cards := {}
var tray_target: Panel
var tray_cards: Array[Button] = []
var assemble_button: Button
var clear_button: Button
var equip_buttons := {}
var close_button: Button

var _state: RefCounted
var _stock_labels := {}
var _slot_frames: Array[Panel] = []
var _slot_buttons: Array[Button] = []
var _slot_art: Array[Control] = []
var _owned_labels := {}
var _backpack_label: Label
var _tray_label: Label
var _hint: Label
var _tray_glow: Panel
var _drag_item := ""


func present(state: RefCounted) -> void:
	_state = state
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	z_index = 210
	fill_at(self, Rect2(Vector2.ZERO, SIZE), Color(0.05, 0.04, 0.055, 0.78))
	var board := panel_at(self, Rect2(116, 119, 1208, 662))
	text_at(board, "野外整备", Rect2(32, 20, 410, 50), 34, INK, true)
	text_at(board, "把营地材料拖入托盘，按图纸拼装，再将模块装上探险背架。", Rect2(34, 73, 858, 35), 18, MUTED)
	close_button = button_at(board, "返回勘探", Rect2(1002, 34, 174, 48), close_requested.emit)
	fill_at(board, Rect2(32, 119, 1144, 1), EDGE)
	_build_work_area(board)
	_build_blueprints(board)
	_refresh()
	close_button.grab_focus()


func _build_work_area(board: Control) -> void:
	text_at(board, "营地材料", Rect2(32, 135, 184, 40), 23, INK, true)
	text_at(board, "点选或拖入，一次一份", Rect2(193, 138, 410, 38), 16, MUTED)
	for i in range(Gear.MATERIALS.size()):
		var item: String = Gear.MATERIALS[i]
		var card := button_at(board, "", Rect2(32 + i * 157, 185, 145, 95), _stage.bind(item))
		card.set_drag_forwarding(_start_drag.bind(item), Callable(), Callable())
		_art(card, item, Rect2(10, 10, 51, 48))
		text_at(card, _state.ITEMS[item], Rect2(66, 13, 74, 38), 22, INK, true)
		_stock_labels[item] = text_at(card, "", Rect2(14, 56, 119, 28), 17, TINTS[item])
		material_cards[item] = card
	_backpack_label = text_at(board, "", Rect2(32, 597, 627, 35), 17, TEAL)
	tray_target = panel_at(board, Rect2(32, 300, 616, 210), RECESS)
	tray_target.mouse_filter = MOUSE_FILTER_STOP
	tray_target.set_drag_forwarding(Callable(), _can_stage_drop, _accept_drop)
	_tray_glow = panel_at(tray_target, Rect2(Vector2.ZERO, tray_target.size))
	var outline := _box(Color.TRANSPARENT, TEAL)
	outline.set_border_width_all(2)
	_tray_glow.add_theme_stylebox_override("panel", outline)
	_tray_glow.hide()
	_tray_label = text_at(tray_target, "", Rect2(19, 8, 570, 38), 23, INK, true)
	for i in range(Gear.CAPACITY):
		var pos := Vector2(20 + i * 197, 54)
		var slot := panel_at(tray_target, Rect2(pos, Vector2(181, 95)), Color("#202b2c"))
		slot.add_theme_stylebox_override("panel", _box(Color("#202b2c"), GROOVE))
		var empty := text_at(slot, "＋", Rect2(0, 0, 181, 95), 27, Color("#728887"))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_slot_frames.append(slot)
		var card := button_at(tray_target, "", Rect2(pos, Vector2(181, 95)), _unstage.bind(i))
		card.set_drag_forwarding(Callable(), _can_stage_drop, _accept_drop)
		card.tooltip_text = "点击退回这份材料"
		card.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_slot_buttons.append(card)
		_slot_art.append(_art(card, "", Rect2(16, 22, 49, 50)))
	_hint = text_at(tray_target, "", Rect2(20, 154, 576, 50), 17, MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	assemble_button = button_at(board, "组装模块", Rect2(32, 526, 374, 55), _assemble, true)
	clear_button = button_at(board, "全部退回", Rect2(423, 526, 225, 55), _clear)
	fill_at(board, Rect2(675, 146, 1, 478), EDGE)


func _build_blueprints(board: Control) -> void:
	text_at(board, "模块图纸", Rect2(705, 135, 450, 40), 23, INK, true)
	var index := 0
	for id: String in Gear.MODULES:
		var spec: Dictionary = Gear.MODULES[id]
		var sheet := panel_at(board, Rect2(705, 185 + index * 223, 470, 205), BLUEPRINT)
		_art(sheet, id, Rect2(14, 16, 102, 104))
		text_at(sheet, spec["title"], Rect2(130, 12, 193, 40), 24, INK, true)
		var owned := text_at(sheet, "", Rect2(330, 12, 123, 38), 16, TEAL)
		owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_owned_labels[id] = owned
		text_at(sheet, _cost_string(spec["cost"]), Rect2(130, 56, 326, 27), 17, ORANGE)
		var effect := text_at(sheet, "", Rect2(130, 88, 323, 61), 18, MUTED)
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect.text = spec["detail"]
		equip_buttons[id] = button_at(sheet, "", Rect2(18, 151, 434, 42), _equip.bind(id))
		index += 1


func _art(parent: Control, id: String, bounds: Rect2) -> Control:
	var picture := BlueprintArt.new()
	picture.position = bounds.position
	picture.size = bounds.size
	picture.mouse_filter = MOUSE_FILTER_IGNORE
	picture.item = id
	parent.add_child(picture)
	return picture


func _cost_string(materials: Dictionary) -> String:
	var parts := PackedStringArray()
	for item in materials:
		parts.append("%s ×%d" % [_state.ITEMS[item], materials[item]])
	return "  +  ".join(parts)


func _refresh(message: String = "") -> void:
	var gear: RefCounted = _state.field_gear
	for item in material_cards:
		var card: Button = material_cards[item]
		var why: String = gear.add_reason(_state, item)
		card.disabled = not why.is_empty()
		card.tooltip_text = why if card.disabled else "放入 1 份" + _state.ITEMS[item]
		_stock_labels[item].text = "库存   %d" % _state.inventory[item]
	_tray_label.text = "拼装托盘     %d / %d" % [gear.tray.size(), Gear.CAPACITY]
	tray_cards.clear()
	for i in range(Gear.CAPACITY):
		var occupied: bool = i < gear.tray.size()
		_slot_frames[i].visible = not occupied
		var button := _slot_buttons[i]
		button.visible = occupied
		if occupied:
			var item: String = gear.tray[i]
			button.text = _state.ITEMS[item] + " ×1"
			_slot_art[i].item = item
			_slot_art[i].queue_redraw()
			tray_cards.append(button)
	var match_id: String = gear.match_module()
	assemble_button.disabled = match_id.is_empty() or gear.built.has(match_id)
	assemble_button.text = "组装模块" if match_id.is_empty() else "组装" + Gear.MODULES[match_id]["title"]
	clear_button.disabled = gear.tray.is_empty()
	var hint := _mix_hint(match_id)
	_hint.text = hint if message.is_empty() else message
	assemble_button.tooltip_text = hint
	_backpack_label.text = "背架空置 · 可装载一个模块" if gear.equipped.is_empty() else "背架已装载   " + Gear.MODULES[gear.equipped]["title"]
	for id: String in Gear.MODULES:
		var equipped: bool = gear.equipped == id
		var built: bool = gear.built.has(id)
		_owned_labels[id].text = "背架使用中" if equipped else ("已组装" if built else "待组装")
		var equip: Button = equip_buttons[id]
		var why: String = gear.equip_reason(_state, "" if equipped else id)
		equip.disabled = not why.is_empty()
		equip.text = "卸下模块" if equipped else ("装上背架" if built else "按图纸组装")
		if equip.disabled and built:
			equip.text = "勘探队返营后可换装"
		equip.tooltip_text = why if equip.disabled else equip.text
	_focus_ring()


func _mix_hint(match_id: String) -> String:
	var gear: RefCounted = _state.field_gear
	if gear.built.size() == Gear.MODULES.size():
		return "两种模块都已备齐，可以按本次行程换装。"
	if not match_id.is_empty():
		if gear.built.has(match_id):
			return "这件模块已经组装。可点击材料退回或选择全部退回。"
		return "材料已配齐，可以组装%s。" % Gear.MODULES[match_id]["title"]
	if gear.tray.is_empty():
		return "将三份材料放入槽位。点击托盘中的材料可退回库存。"
	var contents := {}
	for item in gear.tray:
		contents[item] = contents.get(item, 0) + 1
	for id in Gear.MODULES:
		if gear.built.has(id):
			continue
		var cost: Dictionary = Gear.MODULES[id]["cost"]
		var fits := true
		for item in contents:
			if contents[item] > cost.get(item, 0):
				fits = false
		if fits:
			var missing := {}
			for item in cost:
				if cost[item] > contents.get(item, 0):
					missing[item] = cost[item] - contents.get(item, 0)
			return "%s还需 %s。" % [Gear.MODULES[id]["title"], _cost_string(missing)]
	return "当前组合不符合待组装图纸，可点击材料退回。"


func _start_drag(_at: Vector2, item: String) -> Variant:
	if not _state.field_gear.add_reason(_state, item).is_empty():
		return null
	var preview := Panel.new()
	preview.add_theme_stylebox_override("panel", _box(SURFACE, TEAL))
	preview.size = Vector2(155, 57)
	preview.mouse_filter = MOUSE_FILTER_IGNORE
	_art(preview, item, Rect2(8, 6, 46, 44))
	text_at(preview, _state.ITEMS[item] + " ×1", Rect2(59, 5, 92, 47), 18, INK)
	set_drag_preview(preview)
	_drag_item = item
	_tray_glow.show()
	return {"kind": "gear_material", "item": item}


func _can_stage_drop(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("kind") == "gear_material" and _state.field_gear.add_reason(_state, data.get("item", "")).is_empty()


func _accept_drop(_at: Vector2, data: Variant) -> void:
	if _can_stage_drop(_at, data):
		_stage(data["item"])


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not _drag_item.is_empty():
		_drag_item = ""
		if is_instance_valid(_tray_glow):
			_tray_glow.hide()


func _stage(item: String) -> void:
	if _state.field_gear.add(_state, item):
		_refresh()


func _unstage(index: int) -> void:
	if _state.field_gear.remove_at(_state, index):
		_refresh()


func _clear() -> void:
	if _state.field_gear.clear_tray(_state):
		_refresh("托盘中的材料已退回营地库存。")


func _assemble() -> void:
	var id: String = _state.field_gear.match_module()
	if _state.field_gear.assemble(_state):
		_refresh("%s已组装。可在右侧装上背架。" % Gear.MODULES[id]["title"])
		if not equip_buttons[id].disabled:
			equip_buttons[id].grab_focus()


func _equip(id: String) -> void:
	var target := "" if _state.field_gear.equipped == id else id
	if _state.field_gear.equip(_state, target):
		_refresh("背架已卸空。" if target.is_empty() else "背架已装上%s。" % Gear.MODULES[id]["title"])


func _focus_ring() -> void:
	var choices: Array[Button] = [close_button]
	for card in material_cards.values() + tray_cards + [assemble_button, clear_button] + equip_buttons.values():
		if card.visible and not card.disabled:
			choices.append(card)
	for i in range(choices.size()):
		var b := choices[i]
		var next_path := choices[(i + 1) % choices.size()].get_path()
		var prev_path := choices[posmod(i - 1, choices.size())].get_path()
		b.focus_next = next_path
		b.focus_previous = prev_path
		b.focus_neighbor_right = next_path
		b.focus_neighbor_left = prev_path
		b.focus_neighbor_top = prev_path
		b.focus_neighbor_bottom = next_path
	if get_viewport().gui_get_focus_owner() not in choices:
		choices[0].grab_focus()
