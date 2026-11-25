extends RefCounted

const MATERIALS := ["scrap", "ice", "plate", "ore"]
const CAPACITY := 3
const MODULES := {
	"cooler": {"title": "保温补给箱", "cost": {"scrap": 2, "ice": 1},
		"detail": "勘探和巡线每趟少带 1 份口粮，最低 1 份。"},
	"winch": {"title": "绞盘", "cost": {"plate": 1, "ore": 2},
		"detail": "勘探和巡线作业速度提高 25%，减轻危险路线损伤。"},
}

var tray: Array[String] = []
var built: Dictionary = {}
var equipped := ""


func _unavailable(state: RefCounted) -> String:
	if not state.campaign or not state.first_harvest:
		return "先收获首批口粮，开放野外整备"
	if state.homeward_launched:
		return "本次旅程已经结束"
	return ""


func add_reason(state: RefCounted, item: String) -> String:
	var why := _unavailable(state)
	if not why.is_empty():
		return why
	if built.size() == MODULES.size():
		return "两种模块均已组装"
	if item not in MATERIALS:
		return "这种物资无法用于野外模块"
	if tray.size() >= CAPACITY:
		return "托盘已满，点击材料可以退回"
	if state.inventory.get(item, 0) < 1:
		return "库存缺少%s" % state.ITEMS[item]
	return ""


func add(state: RefCounted, item: String) -> bool:
	var why := add_reason(state, item)
	if not why.is_empty():
		state.reported.emit(why)
		return false
	state.inventory[item] -= 1
	tray.append(item)
	state.checkpoint.emit()
	return true


func remove_at(state: RefCounted, index: int) -> bool:
	if not _unavailable(state).is_empty() or index < 0 or index >= tray.size():
		return false
	state.inventory[tray[index]] += 1
	tray.remove_at(index)
	state.checkpoint.emit()
	return true


func clear_tray(state: RefCounted) -> bool:
	if not _unavailable(state).is_empty() or tray.is_empty():
		return false
	for item in tray:
		state.inventory[item] += 1
	tray.clear()
	state.checkpoint.emit()
	return true


func match_module() -> String:
	if tray.size() != CAPACITY:
		return ""
	var contents := {}
	for item in tray:
		contents[item] = contents.get(item, 0) + 1
	for id in MODULES:
		if contents == MODULES[id]["cost"]:
			return id
	return ""


func assemble(state: RefCounted) -> bool:
	var why := _unavailable(state)
	if not why.is_empty():
		state.reported.emit(why)
		return false
	var id := match_module()
	if id.is_empty():
		state.reported.emit("材料尚未配齐，可按图纸调整托盘")
		return false
	if built.has(id):
		state.reported.emit("该模块已经组装，可退回材料")
		return false
	built[id] = true
	tray.clear()
	state.reported.emit("%s组装完成，可装上探险背架" % MODULES[id]["title"])
	state.checkpoint.emit()
	return true


func equip_reason(state: RefCounted, id: String) -> String:
	var why := _unavailable(state)
	if not why.is_empty():
		return why
	if not id.is_empty() and not built.has(id):
		return "先在托盘上组装这个模块"
	if equipped == id:
		return "当前已装备" if not id.is_empty() else "背架已卸空"
	for unit in state.crew.values():
		if state.RECIPES.get(unit["job"], {}).has("expedition"):
			return "勘探队正在使用背架，返营或取消行程后可换装"
	return ""


func equip(state: RefCounted, id: String) -> bool:
	var why := equip_reason(state, id)
	if not why.is_empty():
		state.reported.emit(why)
		return false
	equipped = id
	state.reported.emit("探险背架已卸空" if id.is_empty() else "探险背架已装上%s" % MODULES[id]["title"])
	state.checkpoint.emit()
	return true


func snapshot() -> Dictionary:
	return {"tray": tray.duplicate(), "built": built.duplicate(), "equipped": equipped}


func restore(data: Dictionary) -> bool:
	if not data.get("tray") is Array or data["tray"].size() > CAPACITY or not data.get("built") is Dictionary or not data.get("equipped") is String:
		return false
	var restored_tray: Array[String] = []
	for item in data["tray"]:
		if not item is String or item not in MATERIALS:
			return false
		restored_tray.append(item)
	for id in data["built"]:
		if not MODULES.has(id) or not data["built"][id] is bool or not data["built"][id]:
			return false
	if data["built"].size() == MODULES.size() and not restored_tray.is_empty():
		return false
	if not data["equipped"].is_empty() and not data["built"].has(data["equipped"]):
		return false
	tray = restored_tray
	built = data["built"].duplicate()
	equipped = data["equipped"]
	return true
