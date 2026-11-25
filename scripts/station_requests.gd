extends RefCounted

const WINDOW := 150.0
const INTERVAL := 90.0
const OFFERS := {
	"water": {"title": "净水系统检修", "short": "送水冰或维修件", "detail": "曙光站检修净水设备，需要应急水冰，也可用维修组件帮助恢复供水。", "choices": ["aid_water", "aid_repair"]},
	"supplies": {"title": "补给车整备", "short": "补充口粮或运输组件", "detail": "补给队即将出发，可以补充口粮，或提供组件修好运输车。", "choices": ["aid_food", "aid_vehicle"]},
	"samples": {"title": "联合地质测绘", "short": "送矿样或分析套件", "detail": "邻站正在比对地层，接受整批矿样，也接受少量矿样与分析支架。", "choices": ["aid_samples", "aid_analysis"]},
}
const RECIPES := {
	"aid_water": {"site": "relay", "label": "互助 · 送去应急水冰", "time": 20.0, "cost": {"ice": 4}, "out": {"circuit": 2}, "request": "water"},
	"aid_repair": {"site": "relay", "label": "互助 · 提供净水维修件", "time": 24.0, "cost": {"scrap": 2, "plate": 1}, "out": {"circuit": 1, "food": 3}, "request": "water"},
	"aid_food": {"site": "relay", "label": "互助 · 补充车队口粮", "time": 20.0, "cost": {"food": 5}, "out": {"plate": 2}, "request": "supplies"},
	"aid_vehicle": {"site": "relay", "label": "互助 · 提供运输组件", "time": 26.0, "cost": {"plate": 2, "circuit": 1}, "out": {"scrap": 8, "food": 4}, "request": "supplies"},
	"aid_samples": {"site": "relay", "label": "互助 · 交付整批矿样", "time": 24.0, "cost": {"ore": 6}, "out": {"circuit": 2}, "request": "samples"},
	"aid_analysis": {"site": "relay", "label": "互助 · 配送分析套件", "time": 26.0, "cost": {"ore": 3, "plate": 1}, "out": {"food": 5, "circuit": 1}, "request": "samples"},
}

var active := ""
var remaining := 0.0
var cooldown := 45.0
var next_offer := 0
var completed := 0
var expired := 0


func choices() -> Array:
	return OFFERS[active]["choices"] if not active.is_empty() else []


func reason(recipe: String) -> String:
	return "这项互助已结束，请查看当前需求" if recipe not in choices() or remaining <= 0 else ""


func care_health() -> float:
	return 45.0 if completed > 0 else 30.0


func tick(state: RefCounted, delta: float) -> void:
	if not state.first_harvest:
		return
	if active.is_empty():
		cooldown = maxf(0, cooldown - delta)
		if cooldown > 0:
			return
		active = OFFERS.keys()[next_offer]
		next_offer = (next_offer + 1) % OFFERS.size()
		remaining = WINDOW
		state.reported.emit("曙光站发来互助请求：%s。150 秒内完成任一方案，可获回礼" % OFFERS[active]["title"])
		state.checkpoint.emit()
		return
	remaining = maxf(0, remaining - delta)
	if remaining > 0:
		return
	var title: String = OFFERS[active]["title"]
	var jobs := choices().duplicate()
	_close()
	expired += 1
	# Expire before crew work is advanced; an unfinished delivery never earns its reward.
	for id in state.crew:
		if state.crew[id]["job"] in jobs:
			state._clear_job(state.crew[id])
			state._resume_duty(id)
	state.reported.emit("%s互助逾期，未交付物资已退回，原岗位继续" % title)
	state.checkpoint.emit()


func finish(state: RefCounted, recipe: String) -> bool:
	if not reason(recipe).is_empty():
		return false
	_close()
	completed += 1
	var cost: Dictionary = RECIPES[recipe]["cost"]
	state.neighbor_food += cost.get("food", 0)
	state.neighbor_scrap += cost.get("scrap", 0)
	state.neighbor_parts += cost.get("plate", 0)
	return true


func _close() -> void:
	active = ""
	remaining = 0.0
	cooldown = INTERVAL


func snapshot() -> Dictionary:
	return {"active": active, "remaining": remaining, "cooldown": cooldown,
		"next_offer": next_offer, "completed": completed, "expired": expired}


func restore(data: Dictionary) -> bool:
	if not data.get("active") is String or (not data["active"].is_empty() and not OFFERS.has(data["active"])):
		return false
	for key in ["remaining", "cooldown", "next_offer", "completed", "expired"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value < 0 or value > 100000000:
			return false
		if key in ["next_offer", "completed", "expired"] and value != floorf(value):
			return false
	if data["remaining"] > WINDOW or data["cooldown"] > INTERVAL or data["next_offer"] >= OFFERS.size():
		return false
	if data["active"].is_empty():
		if data["remaining"] != 0 or data["cooldown"] <= 0:
			return false
	elif data["remaining"] <= 0 or data["cooldown"] != 0 or int(data["next_offer"]) != (OFFERS.keys().find(data["active"]) + 1) % OFFERS.size():
		return false
	active = data["active"]
	remaining = float(data["remaining"])
	cooldown = float(data["cooldown"])
	next_offer = int(data["next_offer"])
	completed = int(data["completed"])
	expired = int(data["expired"])
	return true
