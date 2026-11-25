extends RefCounted

const LOCATIONS := {
	"cargo": {"title": "散落货舱", "detail": "破裂舱体只能回收一次：带走金属，或耐心拆出完整组件。", "choices": ["scout_scrap", "scout_parts"]},
	"rift": {"title": "冰层裂隙", "detail": "浅层水冰容易取得。深处矿样更丰富，但攀爬会损伤队员健康。", "choices": ["scout_ice", "scout_ore"]},
	"relay": {"title": "废弃勘测车", "detail": "剩余电源只够拆卸电路或读取资料，选择一项后设备将报废。", "choices": ["scout_circuit", "scout_blueprint"]},
}
const PATROLS := ["patrol_ice", "patrol_ridge"]
const PATROL_INTERVAL := 90.0
const RECIPES := {
	"patrol_ice": {"site": "shelter", "label": "沿冰沟收取补给", "time": 48.0,
		"cost": {"food": 2}, "out": {"ice": 3, "scrap": 2}, "expedition": "patrol", "patrol": true},
	"patrol_ridge": {"site": "shelter", "label": "上山脊回收测绘桩", "time": 60.0,
		"cost": {"food": 2, "ice": 1}, "out": {"ore": 3, "plate": 1},
		"injury": 8, "winch_injury": 2, "expedition": "patrol", "patrol": true},
	"scout_scrap": {"site": "shelter", "label": "快速回收金属", "time": 30.0, "cost": {"food": 1}, "out": {"scrap": 5}, "expedition": "cargo"},
	"scout_parts": {"site": "shelter", "label": "拆取完整组件", "time": 50.0, "cost": {"food": 2}, "out": {"plate": 2}, "expedition": "cargo"},
	"scout_ice": {"site": "shelter", "label": "采集浅层水冰", "time": 40.0, "cost": {"food": 1}, "out": {"ice": 5}, "expedition": "rift"},
	"scout_ore": {"site": "shelter", "label": "深入裂隙采样", "time": 50.0, "cost": {"food": 2}, "out": {"ore": 6}, "injury": 12.0, "expedition": "rift"},
	"scout_circuit": {"site": "shelter", "label": "拆取剩余电路", "time": 45.0, "cost": {"food": 2}, "out": {"circuit": 2}, "expedition": "relay"},
	"scout_blueprint": {"site": "shelter", "label": "读取精密采样蓝图", "time": 60.0, "cost": {"food": 2, "scrap": 1}, "expedition": "relay"},
	"trial_sampler": {"site": "lab", "label": "试制精密采样器", "time": 24.0, "cost": {"scrap": 2, "circuit": 1}},
}
var resolved: Dictionary = {}
var sampler_blueprint := false
var sampler_built := false
var patrol_count := 0
var next_patrol_at := 0.0


func patrol_wait(clock: float) -> int:
	return maxi(0, ceili(next_patrol_at - clock))


func reason(state: RefCounted, worker: String, recipe: String) -> String:
	if not state.campaign:
		return "请在正式营地中安排勘探"
	if not state.first_harvest:
		return "先收获首批口粮，准备野外补给"
	if recipe == "trial_sampler":
		if not sampler_blueprint:
			return "需要从废弃勘测车取得采样蓝图"
		return "采样器已完成试制" if sampler_built else ""
	var point: String = RECIPES[recipe]["expedition"]
	if point == "patrol":
		if resolved.is_empty():
			return "先完成一处周边勘探，标出安全的进山路线"
		if patrol_wait(state.clock) > 0:
			return "等待下一次巡线窗口"
	if resolved.has(point):
		return "这里已经回收过，无法重复领取"
	for other in state.crew:
		if other != worker and state.crew[other]["job"] in RECIPES and RECIPES[state.crew[other]["job"]].get("expedition", "") == point:
			return "已有队员正在勘探这里"
	if RECIPES[recipe].has("injury") and state.crew[worker].get("health", 100) < 40:
		return "需要至少 40 健康；可改走安全路线或先休整"
	return ""


func complete(state: RefCounted, worker: String, recipe: String) -> void:
	if recipe == "trial_sampler":
		sampler_built = true
		state.reported.emit("精密采样器试制成功，矿脉每批矿样从 2 份提升至 3 份")
		return
	var spec: Dictionary = RECIPES[recipe]
	if spec.get("patrol", false):
		patrol_count += 1
		next_patrol_at = state.clock + PATROL_INTERVAL
	else:
		resolved[spec["expedition"]] = recipe
	if recipe == "scout_blueprint":
		sampler_blueprint = true
		state.reported.emit("勘探队带回精密采样蓝图，可在研究站试制")
	if spec.has("injury"):
		var injury: float = state.expedition_injury(recipe)
		state.crew[worker]["health"] = maxf(1, state.crew[worker]["health"] - injury)


func snapshot() -> Dictionary:
	return {"resolved": resolved.duplicate(), "sampler_blueprint": sampler_blueprint, "sampler_built": sampler_built,
		"patrol_count": patrol_count, "next_patrol_at": next_patrol_at}


func restore(data: Dictionary) -> bool:
	if not data.get("resolved") is Dictionary or not data.get("sampler_blueprint") is bool or not data.get("sampler_built") is bool:
		return false
	for point in data["resolved"]:
		if not LOCATIONS.has(point) or data["resolved"][point] not in LOCATIONS[point]["choices"]:
			return false
	if data["sampler_blueprint"] != (data["resolved"].get("relay") == "scout_blueprint") or (data["sampler_built"] and not data["sampler_blueprint"]):
		return false
	var count: Variant = data.get("patrol_count", 0)
	var next: Variant = data.get("next_patrol_at", 0.0)
	if not (count is int or count is float) or not (next is int or next is float):
		return false
	if not is_finite(float(count)) or count < 0 or count > 100000000 or count != floorf(count):
		return false
	if not is_finite(float(next)) or next < 0 or ((count == 0) != (next == 0)):
		return false
	if count > 0 and data["resolved"].is_empty():
		return false
	patrol_count = int(count)
	next_patrol_at = float(next)
	resolved = data["resolved"].duplicate()
	sampler_blueprint = data["sampler_blueprint"]
	sampler_built = data["sampler_built"]
	return true
