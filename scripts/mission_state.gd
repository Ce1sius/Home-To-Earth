extends RefCounted

const CrewWork := preload("res://scripts/crew_work.gd")
const PowerGrid := preload("res://scripts/power_grid.gd")
const CampLayout := preload("res://scripts/camp_layout.gd")
const HighlandRadar := preload("res://scripts/highland_radar.gd")
const FieldGear := preload("res://scripts/field_gear.gd")
const Expeditions := preload("res://scripts/field_expeditions.gd")
const Requests := preload("res://scripts/station_requests.gd")

signal reported(message: String)
signal radar_delivered(cargo: Dictionary)
signal crew_transferred(id: String, destination: String)
signal checkpoint
signal work_started(site: String, inputs: Dictionary)
signal work_completed(site: String, recipe: String, output: Dictionary)
signal rations_used(amount: int)

const CAMP := "camp"
const HIGHLANDS := "highlands"

const ITEMS := {
	"food": "口粮", "scrap": "残件", "ore": "矿样",
	"ice": "水冰", "plate": "结构件", "circuit": "电路",
}

const SITES := {
	"wreck": {"at": Vector2(246, 133), "title": "着陆舱残骸", "kind": "回收点",
		"detail": "迫降后散落的舱体。回收金属残件，作为制造与交换的原料。"},
	"ore": {"at": Vector2(496, 108), "title": "露天矿脉", "kind": "采样点",
		"detail": "采集矿样，分析矿物性质，也可用于制造电路。"},
	"ice": {"at": Vector2(746, 145), "title": "浅层冰脉", "kind": "采集点",
		"detail": "采集水冰，为温室提供水源。"},
	"casualty": {"at": Vector2(571, 290), "title": "受伤勘探员", "kind": "求救信号",
		"detail": "其他勘探队的一名队员发来了求救信号。救助后，对方愿意加入。"},
	"bench": {"at": Vector2(225, 438), "title": "制造工作台", "kind": "生产设施",
		"detail": "加工结构件。研究解锁后，可在这里用结构件和矿样制造电路。"},
	"greenhouse": {"at": Vector2(478, 449), "title": "密封温室", "kind": "生产设施",
		"detail": "堆叠队员与水冰，循环补充口粮。缺水时停工，补水后自动继续。"},
	"lab": {"at": Vector2(715, 440), "title": "蓝图研究站", "kind": "研发设施",
		"detail": "分析矿样和残件，解锁信标维修蓝图与电路配方。"},
	"relay": {"at": Vector2(862, 302), "title": "曙光勘探站", "kind": "邻近队伍",
		"detail": "独立生产电路和消耗口粮。双方接通短距通信后，可交换物资。"},
	"beacon": {"at": Vector2(854, 479), "title": "通信信标", "kind": "任务设施",
		"detail": "完成蓝图研究并备齐结构件和电路，恢复与轨道的通信。"},
	"radar_lens": {"title": "水冰透镜", "kind": "高地开挖点", "detail": "开挖雷达定位的透镜状冰体，样本暂存高地接驳点。"},
	"radar_cache": {"title": "坠落货箱", "kind": "高地回收点", "detail": "打开埋在沉积层中的货箱，零件暂存高地接驳点。"},
	"trail": {"title": "高地接驳点", "kind": "区域航线"},
	"archive": {"title": "废弃测绘站", "kind": "勘察点"},
	"outpost": {"title": "高地通信前哨", "kind": "建设点"},
	"array": {"title": "旧测向阵列", "kind": "联合勘测"},
	"shelter": {"title": "应急居住舱", "kind": "营地生活"},
}

const CREW_NAMES := {"lead": "领队", "tech": "勘探员", "botanist": "农艺师"}

const RECIPES := {
	"dig_lens": {"site": "radar_lens", "label": "开挖水冰透镜", "time": 18.0, "deposit": "lens", "out": HighlandRadar.ZONES["lens"]["reward"]},
	"dig_cache": {"site": "radar_cache", "label": "起出坠落货箱", "time": 22.0, "deposit": "cache", "out": HighlandRadar.ZONES["cache"]["reward"]},
	"survey_last_record": {"site": "array", "label": "测定第三航标", "time": 48.0,
		"cost": {"food": 2, "ore": 2}, "homeward": true},
	"exchange_last_record": {"site": "relay", "label": "交换第三航标", "time": 18.0,
		"cost": {"plate": 2, "circuit": 1}, "homeward": true},
	"assemble_return_craft": {"site": "wreck", "label": "整备归航舱", "time": 38.0,
		"cost": {"plate": 3, "circuit": 2}, "homeward": true},
	"launch_homeward": {"site": "beacon", "label": "领队登舱归航", "time": 18.0,
		"cost": {"food": 3, "ice": 2}, "homeward": true},
	"aid_water": Requests.RECIPES["aid_water"],
	"aid_repair": Requests.RECIPES["aid_repair"],
	"aid_food": Requests.RECIPES["aid_food"],
	"aid_vehicle": Requests.RECIPES["aid_vehicle"],
	"aid_samples": Requests.RECIPES["aid_samples"],
	"aid_analysis": Requests.RECIPES["aid_analysis"],
	"camp_care": {"site": "shelter", "label": "营地护理 · 完成后归岗", "time": 20.0, "cost": {"food": 1, "ice": 1}},
	"patrol_ice": Expeditions.RECIPES["patrol_ice"],
	"patrol_ridge": Expeditions.RECIPES["patrol_ridge"],
	"scout_scrap": Expeditions.RECIPES["scout_scrap"],
	"scout_parts": Expeditions.RECIPES["scout_parts"],
	"scout_ice": Expeditions.RECIPES["scout_ice"],
	"scout_ore": Expeditions.RECIPES["scout_ore"],
	"scout_circuit": Expeditions.RECIPES["scout_circuit"],
	"scout_blueprint": Expeditions.RECIPES["scout_blueprint"],
	"trial_sampler": Expeditions.RECIPES["trial_sampler"],
	"salvage": {"site": "wreck", "label": "回收残件", "time": 9.0, "out": {"scrap": 3}},
	"recover_field_cache": {"site": "wreck", "label": "抢救野外补给箱", "time": 9.0,
		"out": {"scrap": 1, "food": 4}},
	"mine": {"site": "ore", "label": "采集矿样", "time": 10.0, "out": {"ore": 2}},
	"extract": {"site": "ice", "label": "采集水冰", "time": 9.0, "out": {"ice": 2}},
	"rescue": {"site": "casualty", "label": "救助勘探员", "time": 8.0, "cost": {"food": 1}},
	"fabricate": {"site": "bench", "label": "制造结构件", "time": 13.0, "cost": {"scrap": 2},
		"out": {"plate": 1}},
	"etch": {"site": "bench", "label": "制造电路", "time": 19.0,
		"cost": {"plate": 1, "ore": 2}, "out": {"circuit": 1}, "needs_blueprint": true},
	"build": {"site": "greenhouse", "label": "搭建温室", "time": 12.0, "cost": {"scrap": 1}},
	"grow": {"site": "greenhouse", "label": "培育口粮", "time": 14.0, "cost": {"ice": 1},
		"out": {"food": 3}, "repeat": true},
	"research": {"site": "lab", "label": "研究蓝图", "time": 16.0,
		"cost": {"ore": 1, "scrap": 1}},
	"trade_scrap": {"site": "relay", "label": "用残件换电路", "time": 9.0,
		"cost": {"scrap": 3}, "out": {"circuit": 1}, "trade": true},
	"trade_food": {"site": "relay", "label": "用口粮换电路", "time": 9.0,
		"cost": {"food": 2}, "out": {"circuit": 1}, "trade": true},
	"repair": {"site": "beacon", "label": "修复通信信标", "time": 20.0,
		"cost": {"plate": 1, "circuit": 1}, "needs_blueprint": true},
	"depart": {"site": "beacon", "label": "前往北缘高地", "time": 18.0,
		"cost": {"food": 2}, "destination": HIGHLANDS},
	"deliver": {"site": "beacon", "label": "运送前哨物资", "time": 18.0,
		"cost": {"food": 2, "plate": 1, "circuit": 1}, "destination": HIGHLANDS},
	"return": {"site": "trail", "label": "返回迫降地", "time": 15.0, "destination": CAMP},
	"survey_archive": {"site": "archive", "label": "回收航标记录", "time": 17.0},
	"establish_outpost": {"site": "outpost", "label": "架设通信前哨", "time": 20.0},
	"exchange_calibration": {"site": "relay", "label": "交换校准蓝图", "time": 16.0,
		"cost": {"plate": 2}},
	"research_calibration": {"site": "lab", "label": "研究校准蓝图", "time": 36.0,
		"cost": {"ore": 3, "circuit": 1}},
	"deliver_array": {"site": "beacon", "label": "运送阵列设备", "time": 18.0,
		"cost": {"food": 2, "plate": 2, "circuit": 1}, "destination": HIGHLANDS},
	"calibrate_array": {"site": "array", "label": "修复并校准阵列", "time": 30.0},
	"research_pump": {"site": "lab", "label": "研究循环泵蓝图", "time": 24.0,
		"cost": {"ore": 2, "scrap": 1}},
	"trial_pump": {"site": "greenhouse", "label": "试制循环水泵", "time": 22.0,
		"cost": {"plate": 1, "circuit": 1, "ice": 1}},
	"expand_shelter": {"site": "shelter", "label": "扩建居住舱", "time": 18.0, "cost": {"scrap": 2}},
	"welcome_botanist": {"site": "shelter", "label": "接纳农艺师", "time": 12.0, "cost": {"food": 2}},
	"research_power": {"site": "lab", "label": "研究能源蓝图", "time": 30.0,
		"cost": {"ore": 2, "circuit": 1}, "industry": true},
	"trade_power": {"site": "relay", "label": "交换能源蓝图", "time": 14.0,
		"cost": {"food": 4, "plate": 1}, "industry": true},
	"build_solar": {"site": "wreck", "label": "组装太阳能储能组", "time": 24.0,
		"cost": {"plate": 2, "circuit": 1}, "industry": true},
	"build_extractor": {"site": "ice", "label": "装配自动采冰机", "time": 26.0,
		"cost": {"plate": 2, "circuit": 1}, "industry": true},
	"clean_solar": {"site": "wreck", "label": "清理太阳能板", "time": 10.0,
		"cost": {"scrap": 1}, "industry": true},
	"service_extractor": {"site": "ice", "label": "维护自动采冰机", "time": 14.0,
		"cost": {"scrap": 1}, "industry": true},
}

const DEFAULT_RECIPES := {
	"radar_lens": "dig_lens", "radar_cache": "dig_cache",
	"wreck": "salvage", "ore": "mine", "ice": "extract", "casualty": "rescue",
	"bench": "fabricate", "greenhouse": "grow", "lab": "research",
	"relay": "trade_scrap", "beacon": "repair", "trail": "return",
	"archive": "survey_archive", "outpost": "establish_outpost",
	"array": "calibrate_array",
	"shelter": "expand_shelter",
}
const CAMPAIGN_SITES := {
	"radar_lens": Vector2(170, 160), "radar_cache": Vector2(812, 135),
	"wreck": Vector2(457, 218), "ore": Vector2(748, 348), "casualty": Vector2(772, 150),
	"greenhouse": Vector2(176, 178), "ice": Vector2(500, 443),
	"bench": Vector2(172, 476), "lab": Vector2(754, 126),
	"relay": Vector2(899, 490), "beacon": Vector2(910, 210),
	"trail": Vector2(163, 311), "archive": Vector2(505, 167), "outpost": Vector2(765, 348),
	"array": Vector2(500, 458),
	"shelter": Vector2(474, 62),
}
const CAMPAIGN_SITE_SIZE := Vector2(188, 153)
const OUTPOST_SITE_SIZE := Vector2(142, 116)
const COMPACT_SITES := ["bench", "lab", "relay", "beacon", "radar_lens", "radar_cache"]
const HIGHLANDS_SITES := ["trail", "archive", "outpost", "array", "radar_lens", "radar_cache"]
const CAMPAIGN_ONLY := ["trail", "archive", "outpost", "array", "shelter", "radar_lens", "radar_cache"]
const TRANSFER_ARRIVALS := {
	CAMP: [Vector2(904, 344), Vector2(680, 505)],
	HIGHLANDS: [Vector2(339, 311), Vector2(435, 435)],
}
const CAMPAIGN_CREW_SIZE := Vector2(116, 122)
const CAMPAIGN_WALK_BOUNDS := Rect2(60, 64, 879, 475)
const CAMPAIGN_MAP_LABEL := Rect2(16, 16, 211, 57)
const CAMPAIGN_MAP_HELP := Rect2(16, 546, 424, 42)
const CAMPAIGN_MAP_SCOUT := Rect2(244, 16, 144, 40)
const SURVEY_TARGETS := ["wreck", "ore"]
const STARTING_TOOL := "tool"
const TOOL_JOBS := ["salvage", "recover_field_cache", "mine", "extract", "fabricate", "etch"]
const MAP_SIZE := Vector2(998, 604)
const MOVE_SPEED := 108.0

var campaign: bool
var power := PowerGrid.new()
var layout := CampLayout.new()
var radar := HighlandRadar.new()
var field_gear := FieldGear.new()
var expeditions := Expeditions.new()
var requests := Requests.new()
var recovered := {}
var inventory := {"food": 6, "scrap": 0, "ore": 0, "ice": 0, "plate": 0, "circuit": 0}
var crew := {
	"lead": {"pos": Vector2(99, 293), "dest": Vector2(99, 293), "job": "", "phase": "",
		"elapsed": 0.0, "reserved": {}},
}
var salvaged := false
var tool_holder := ""
var recruited := false
var blueprint := false
var greenhouse_built := false
var first_harvest := false
var won := false
var highlands_visited := false
var outpost_supplied := false
var outpost_built := false
var navigation_record := false
var calibration_blueprint := false
var calibration_source := ""
var array_supplied := false
var array_calibrated := false
var third_record_source := ""
var return_craft_ready := false
var homeward_launched := false
var neighbor_parts := 0
var shelter_expanded := false
var pump_blueprint := false
var pump_built := false
var botanist_joined := false
var neighbor_upgraded := false
var neighbor_trades := 0
var clock := 0.0
var neighbor_stock := 1
var neighbor_food := 3
var neighbor_scrap := 4
var _neighbor_clock := 0.0
var _ration_clock := 0.0


func _init(is_campaign: bool = false) -> void:
	campaign = is_campaign
	power.notice.connect(_power_notice)
	if campaign:
		inventory[STARTING_TOOL] = 1
		crew["lead"]["pos"] = Vector2(226, 402)
		crew["lead"]["dest"] = crew["lead"]["pos"]
		CrewWork.ensure(crew["lead"])


func survey_complete() -> bool:
	return recovered.has_all(SURVEY_TARGETS)


func first_record_uploaded() -> bool:
	return navigation_record and outpost_built


func navigation_count() -> int:
	return int(first_record_uploaded()) + int(array_calibrated) + int(not third_record_source.is_empty())


func crew_region(id: String) -> String:
	return crew[id].get("region", CAMP)


func site_region(site: String) -> String:
	return HIGHLANDS if site in HIGHLANDS_SITES else CAMP


func site_position(site: String) -> Vector2:
	return layout.positions.get(site, CAMPAIGN_SITES[site]) if campaign else SITES[site]["at"]


func crew_away(id: String) -> bool:
	var unit: Dictionary = crew[id]
	var spec: Dictionary = RECIPES.get(unit["job"], {})
	return unit["phase"] == "working" and (spec.has("expedition") or spec.has("destination"))


func tool_transfer_reason(id: String) -> String:
	if not campaign or homeward_launched or inventory.get(STARTING_TOOL, 0) != 1:
		return "当前无法转交工具"
	if not crew.has(id):
		return "请先选择营地队员"
	if id == tool_holder:
		return "%s正在携带工具" % CREW_NAMES[id]
	for person in [id, tool_holder]:
		if person == "":
			continue
		if crew_region(person) != CAMP or crew_away(person):
			return "%s需先返回营地才能交接" % CREW_NAMES[person]
		if crew[person]["phase"] in ["travel", "move"]:
			return "等%s抵达工位或停步后交接" % CREW_NAMES[person]
	return ""


func equip_tool(id: String) -> bool:
	var why := tool_transfer_reason(id)
	if not why.is_empty():
		reported.emit(why)
		return false
	tool_holder = id
	reported.emit("%s已接过简易工具，回收、采集和制造效率提高 25%%" % CREW_NAMES[id])
	checkpoint.emit()
	return true


func camp_diners() -> int:
	var count := 0
	for id in crew:
		if crew_region(id) == CAMP and not crew_away(id):
			count += 1
	return count


func campaign_site_size(site: String) -> Vector2:
	if site == "shelter":
		return Vector2(142, 98)
	return OUTPOST_SITE_SIZE if site in COMPACT_SITES else CAMPAIGN_SITE_SIZE


func site_visible(site: String) -> bool:
	if not campaign:
		return site not in CAMPAIGN_ONLY and (site != "casualty" or (salvaged and not recruited))
	match site:
		"wreck", "ore":
			return true
		"casualty":
			return survey_complete() and not recruited
		"greenhouse", "ice":
			return recruited
		"bench", "lab", "relay":
			return first_harvest
		"beacon":
			return blueprint
		"radar_lens": return highlands_visited and radar.marked["lens"]
		"radar_cache": return highlands_visited and radar.marked["cache"]
		"trail", "archive", "outpost":
			return highlands_visited
		"array":
			return first_record_uploaded()
		"shelter":
			return true
	return false


func default_recipe(site: String) -> String:
	if campaign and site == "array" and array_calibrated and third_record_source.is_empty():
		return "survey_last_record"
	if site == "greenhouse" and not greenhouse_built:
		return "build"
	if campaign:
		if site == "shelter" and shelter_expanded:
			return "welcome_botanist"
		if site == "relay":
			return "exchange_calibration" if first_record_uploaded() and not calibration_blueprint else "trade_food"
		if site == "beacon" and won:
			return "depart"
		if site == "lab" and first_record_uploaded():
			return "research_calibration"
	return DEFAULT_RECIPES[site]


func alternate_recipe(site: String) -> String:
	if site == "wreck" and field_cache_available():
		return "recover_field_cache"
	if campaign and site == "lab" and expeditions.sampler_blueprint and not expeditions.sampler_built:
		return "trial_sampler"
	if campaign and site == "lab" and first_harvest and not pump_blueprint:
		return "research_pump"
	if campaign and site == "greenhouse" and pump_blueprint and not pump_built:
		return "trial_pump"
	if campaign and site == "lab" and pump_built and not power.blueprint:
		return "research_power"
	if campaign and site == "wreck" and power.blueprint:
		return "clean_solar" if power.solar_built else "build_solar"
	if campaign and site == "ice" and power.solar_built:
		return "service_extractor" if power.extractor_built else "build_extractor"
	if site == "bench" and blueprint:
		return "etch"
	if site == "relay":
		return "trade_food" if default_recipe(site) == "exchange_calibration" else "trade_scrap"
	if campaign and site == "beacon" and won and not (outpost_supplied or outpost_built):
		return "deliver"
	if campaign and site == "beacon" and calibration_blueprint and not (array_supplied or array_calibrated):
		return "deliver_array"
	return ""


func survey_site_exhausted(site: String) -> bool:
	return campaign and recovered.has(site) and not recruited


func field_cache_available() -> bool:
	return campaign and not recovered.has("wreck") and not recruited


func site_actions(site: String) -> Array[String]:
	var actions: Array[String] = [default_recipe(site)]
	var alternate := alternate_recipe(site)
	if not alternate.is_empty() and alternate not in actions:
		actions.append(alternate)
	for recipe in industry_actions():
		if RECIPES[recipe]["site"] == site and recipe not in actions:
			actions.append(recipe)
	# A newly found blueprint must not hide another unfinished research branch.
	if campaign and site == "lab" and first_harvest and not pump_blueprint and "research_pump" not in actions:
		actions.append("research_pump")
	# Keep both circuit offers reachable while cooperation is available.
	if campaign and site == "relay":
		for recipe in ["trade_food", "trade_scrap"]:
			if recipe not in actions:
				actions.append(recipe)
		for recipe in requests.choices():
			actions.append(recipe)
	if campaign and site == "shelter" and recruited:
		actions.append("camp_care")
	if campaign and array_calibrated:
		if site == "relay" and third_record_source.is_empty():
			actions.append("exchange_last_record")
		if site == "wreck" and not third_record_source.is_empty() and not return_craft_ready:
			actions.append("assemble_return_craft")
		if site == "beacon" and return_craft_ready and not homeward_launched:
			actions.append("launch_homeward")
	return actions


func recipe_completed(recipe: String) -> bool:
	var spec: Dictionary = RECIPES.get(recipe, {})
	if spec.has("deposit"):
		return radar.collected[spec["deposit"]]
	match recipe:
		"survey_last_record", "exchange_last_record": return not third_record_source.is_empty()
		"assemble_return_craft": return return_craft_ready
		"launch_homeward": return homeward_launched
		"rescue": return recruited
		"build": return greenhouse_built
		"research": return blueprint
		"repair": return won
		"research_pump": return pump_blueprint
		"trial_pump": return pump_built
		"expand_shelter": return shelter_expanded
		"welcome_botanist": return botanist_joined
		"trial_sampler": return expeditions.sampler_built
		"research_power", "trade_power": return power.blueprint
		"build_solar": return power.solar_built
		"build_extractor": return power.extractor_built
		"survey_archive": return navigation_record
		"establish_outpost": return outpost_built
		"research_calibration", "exchange_calibration": return calibration_blueprint
		"deliver": return outpost_supplied or outpost_built
		"deliver_array": return array_supplied or array_calibrated
		"calibrate_array": return array_calibrated
	return false


func order_actions(region: String) -> Array[String]:
	var actions: Array[String] = []
	for site in CAMPAIGN_SITES:
		if not site_visible(site) or site_region(site) != region:
			continue
		for recipe in site_actions(site):
			if recipe_completed(recipe) or (recipe == "etch" and not blueprint):
				continue
			if recipe not in actions:
				actions.append(recipe)
	return actions


func active_at(site: String) -> String:
	for id in crew:
		var job: String = crew[id]["job"]
		if not job.is_empty() and RECIPES[job]["site"] == site:
			return id
	return ""


func recipe_cost(recipe: String) -> Dictionary:
	var spec: Dictionary = RECIPES[recipe]
	var cost: Dictionary = spec.get("cost", {})
	if spec.has("expedition") and field_gear.equipped == "cooler" and cost.has("food"):
		cost = cost.duplicate()
		cost["food"] = maxi(1, cost["food"] - 1)
	return cost


func expedition_injury(recipe: String) -> float:
	var spec: Dictionary = RECIPES[recipe]
	var injury := float(spec.get("injury", 0.0))
	if injury > 0 and spec.has("expedition") and field_gear.equipped == "winch":
		return minf(injury, spec.get("winch_injury", 4.0))
	return injury


func missing(recipe: String, credit: Dictionary = {}) -> String:
	var inputs := recipe_cost(recipe)
	for item in inputs:
		if inventory.get(item, 0) + credit.get(item, 0) < inputs[item]:
			return "需要%s × %d" % [ITEMS[item], inputs[item]]
	return ""


func reason(id: String, recipe: String, for_order: bool = false) -> String:
	if homeward_launched:
		return "领队已归航，本次任务已完成"
	if won and (not campaign or recipe == "repair"):
		return "通信信标已上线"
	if not crew.has(id) or not RECIPES.has(recipe):
		return "请先选择一名队员"
	var spec: Dictionary = RECIPES[recipe]
	var site: String = spec["site"]
	if spec.get("industry", false) and (not campaign or not pump_built):
		return "先完成循环泵试制，恢复营地工程能力"
	if not site_visible(site):
		return "尚未定位目标"
	if campaign and crew_region(id) != site_region(site):
		return "请先派队员前往这一区域"
	if survey_site_exhausted(site):
		return "这个点位已采集完毕"
	if recipe == "recover_field_cache" and not field_cache_available():
		return "只有首次打捞时能抢救补给箱"
	if spec.has("deposit") and radar.collected[spec["deposit"]]:
		return "此处样本已全部回收"
	var occupant := active_at(site)
	if not occupant.is_empty() and occupant != id:
		return "已有队员执行此项工作"
	if crew[id]["job"] == recipe and not for_order:
		return "该队员已接受这项任务"
	if recipe in Expeditions.RECIPES:
		var expedition_reason := expeditions.reason(self, id, recipe)
		if not expedition_reason.is_empty():
			return expedition_reason
	if crew_away(id):
		return "队员已外出，请先从顶部队员栏召回或等待抵达"
	if spec.has("request"):
		if not campaign:
			return "请在正式营地中参加互助"
		var request_reason := requests.reason(recipe)
		if not request_reason.is_empty():
			return request_reason
	if recipe == "camp_care":
		if not campaign or not recruited:
			return "先救助勘探员，建立营地护理点"
		if crew[id].get("health", 100) >= 100 and crew[id].get("stamina", 100) >= 90:
			return "队员状态良好，暂不需要护理"
	if recipe == "repair" and not recruited:
		return "请先救助发出求救信号的队员"
	if recipe == "build" and greenhouse_built:
		return "温室已搭建"
	if recipe == "grow" and not greenhouse_built:
		return "请先搭建温室"
	if recipe == "research" and blueprint:
		return "蓝图已解锁"
	match recipe:
		"survey_last_record", "exchange_last_record":
			if not campaign or not array_calibrated:
				return "先在北缘高地恢复第二份航标"
			if not third_record_source.is_empty():
				return "三份航标已集齐"
			for other in crew:
				if other != id and crew[other]["job"] in ["survey_last_record", "exchange_last_record"]:
					return "另一名队员正在取得第三份航标"
		"assemble_return_craft":
			if not campaign or third_record_source.is_empty():
				return "先集齐三份归航航标"
			if return_craft_ready:
				return "归航舱已就绪"
		"launch_homeward":
			if not campaign or not return_craft_ready:
				return "先在着陆舱残骸整备归航舱"
			if id != "lead":
				return "需要领队本人返回迫降地登舱"
		"research_power", "trade_power":
			if power.blueprint:
				return "能源蓝图已取得"
			for other in crew:
				if other != id and crew[other]["job"] in ["research_power", "trade_power"]:
					return "另一名队员正在获取能源蓝图"
		"build_solar":
			if not power.blueprint:
				return "先研究或交换能源蓝图"
			if power.solar_built:
				return "太阳能储能组已建成"
		"build_extractor":
			if not power.solar_built:
				return "需要先建成太阳能储能组"
			if power.extractor_built:
				return "自动采冰机已装配"
		"clean_solar":
			if not power.solar_built:
				return "尚未建成太阳能储能组"
			if power.cleanliness >= 99:
				return "太阳能板目前很干净"
		"service_extractor":
			if not power.extractor_built:
				return "尚未装配自动采冰机"
			if power.condition >= 100:
				return "采冰机状态良好"
		"expand_shelter":
			if shelter_expanded:
				return "居住舱已扩建"
		"research_pump":
			if pump_blueprint:
				return "循环泵蓝图已取得"
		"trial_pump":
			if pump_built:
				return "循环泵已通过试制"
			if not pump_blueprint:
				return "先交易取得蓝图，或到研究站自行研究"
		"welcome_botanist":
			if botanist_joined:
				return "农艺师已加入营地"
			if not shelter_expanded:
				return "需要扩建居住舱，准备第三个床位"
			if not pump_built:
				return "先试制循环泵，建立更充足的食物供应"
		"depart", "deliver", "deliver_array":
			if not won:
				return "需要先恢复轨道通信"
			if recipe == "deliver" and (outpost_supplied or outpost_built):
				return "前哨已有物资"
			if recipe == "deliver_array":
				if not calibration_blueprint:
					return "先在曙光站交换或研究站研究校准蓝图"
				if array_supplied or array_calibrated:
					return "阵列设备已送达"
		"exchange_calibration", "research_calibration":
			if not campaign or not first_record_uploaded():
				return "先上传旧测绘站的航标记录"
			if calibration_blueprint:
				return "校准蓝图已解锁"
			var other := "research_calibration" if recipe == "exchange_calibration" else "exchange_calibration"
			for worker in crew:
				if worker != id and crew[worker]["job"] == other:
					return "另一名队员正在获取校准蓝图"
		"calibrate_array":
			if array_calibrated:
				return "第二份航标已同步"
			if not calibration_blueprint:
				return "需要先获得校准蓝图"
			if not array_supplied:
				return "请从迫降地运送阵列设备"
		"survey_archive":
			if navigation_record:
				return "航标记录已回收"
		"establish_outpost":
			if outpost_built:
				return "通信前哨已启用"
			if not outpost_supplied:
				return "请从迫降地运送前哨物资"
	if spec.get("needs_blueprint", false) and not blueprint:
		return "需要先研究蓝图"
	if spec.get("trade", false):
		if not recruited:
			return "救助勘探员后接通短距通信"
		if neighbor_stock < 1:
			return "对方暂时没有电路库存"
	return "" if for_order else missing(recipe, crew[id]["reserved"])


func recipe_for_material(site: String, item: String, worker: String = "") -> String:
	var recipes := RECIPES.keys()
	if campaign:
		recipes = site_actions(site)
	var fallback := ""
	for recipe in recipes:
		# Launch ends this campaign. Require the player to choose it by name.
		if recipe.is_empty() or recipe == "launch_homeward":
			continue
		var spec: Dictionary = RECIPES[recipe]
		if spec["site"] == site and spec.get("cost", {}).has(item):
			if fallback.is_empty() or (recipe_completed(fallback) and not recipe_completed(recipe)):
				fallback = recipe
			if crew.has(worker) and reason(worker, recipe).is_empty():
				return recipe
	return fallback


func assign(id: String, recipe: String) -> bool:
	var why := reason(id, recipe)
	if not why.is_empty():
		reported.emit(why)
		return false
	var site: String = RECIPES[recipe]["site"]
	var at := site_position(site)
	var destination := _campaign_work_position(id, site) if campaign else _arrival_point(id, at + Vector2(0, 64))
	if destination == Vector2.INF:
		reported.emit("作业点附近没有空位。请先移开其他队员")
		return false
	_clear_job(crew[id])
	crew[id]["dest"] = destination
	crew[id]["job"] = recipe
	crew[id]["phase"] = "travel"
	reported.emit("%s前往%s · %s" % [CREW_NAMES[id], SITES[site]["title"], RECIPES[recipe]["label"]])
	return true


func set_order(id: String, recipe: String, mode: String, amount: int = 1) -> bool:
	if not campaign or recipe not in CrewWork.JOBS or mode not in ["continuous", "batch", "stock"] or amount < 1 or amount > 99:
		return false
	var why := reason(id, recipe, true)
	if not why.is_empty():
		reported.emit(why)
		return false
	var unit: Dictionary = crew[id]
	if unit["job"] != recipe:
		var destination := _campaign_work_position(id, RECIPES[recipe]["site"])
		if destination == Vector2.INF:
			reported.emit("工位附近没有空位，请先移开其他队员")
			return false
		_clear_job(unit)
		unit["job"] = recipe
		unit["dest"] = destination
		unit["phase"] = "travel"
	unit["duty"] = {"recipe": recipe, "mode": mode, "remaining": amount, "target": amount}
	reported.emit("%s · %s" % [CREW_NAMES[id], CrewWork.duty_text(unit, RECIPES)])
	checkpoint.emit()
	return true


func _stock_satisfied(unit: Dictionary) -> bool:
	var duty: Dictionary = unit.get("duty", {})
	if duty.is_empty() or duty["recipe"] != unit["job"] or duty["mode"] != "stock":
		return false
	var item: String = RECIPES[unit["job"]]["out"].keys()[0]
	return inventory[item] >= duty["target"]


func _resume_duty(id: String) -> void:
	var unit: Dictionary = crew[id]
	var duty: Dictionary = unit.get("duty", {})
	if duty.is_empty() or crew_region(id) != CAMP or not unit["phase"].is_empty():
		return
	if not reason(id, duty["recipe"], true).is_empty():
		return
	var destination := _campaign_work_position(id, RECIPES[duty["recipe"]]["site"])
	if destination == Vector2.INF:
		return
	unit["job"] = duty["recipe"]
	unit["dest"] = destination
	unit["phase"] = "travel"


func rest_crew(id: String) -> void:
	if not crew.has(id) or not campaign or homeward_launched:
		return
	if crew_away(id):
		reported.emit("野外队员需要先返营才能休整")
		return
	_clear_job(crew[id])
	crew[id]["phase"] = "resting"
	reported.emit("%s开始休整，体力恢复后继续原岗位" % CREW_NAMES[id])
	checkpoint.emit()


func beds() -> int:
	return 3 if shelter_expanded else 2


func production_output(recipe: String) -> Dictionary:
	if campaign and recipe == "mine" and expeditions.sampler_built:
		return {"ore": 3}
	if campaign and recipe == "grow" and pump_built:
		return {"food": 5}
	return RECIPES[recipe].get("out", {})


func neighbor_interval() -> float:
	return 20.0 if neighbor_upgraded else 28.0


func industry_actions() -> Array[String]:
	var actions: Array[String] = []
	if not campaign:
		return actions
	if expeditions.sampler_blueprint and not expeditions.sampler_built:
		actions.append("trial_sampler")
	if not pump_built:
		return actions
	if not power.blueprint:
		actions.append_array(["research_power", "trade_power"])
	elif not power.solar_built:
		actions.append("build_solar")
	else:
		if not power.extractor_built:
			actions.append("build_extractor")
		elif power.condition < 100:
			actions.append("service_extractor")
		if power.cleanliness < 99:
			actions.append("clean_solar")
	return actions


func toggle_extractor() -> void:
	if not power.extractor_built or homeward_launched:
		return
	power.extractor_enabled = not power.extractor_enabled
	power.extractor_status = "等待下一轮供电" if power.extractor_enabled else "已手动暂停"
	reported.emit("自动采冰已启用，将按库存与电量运行" if power.extractor_enabled else "自动采冰已暂停，未完成批次进度保留")
	checkpoint.emit()


func _power_notice(message: String) -> void:
	reported.emit(message)
	checkpoint.emit()


func _working_recipe(site: String) -> String:
	var worker := active_at(site)
	return crew[worker]["job"] if not worker.is_empty() and crew[worker]["phase"] == "working" else ""


func _tick_power(delta: float) -> void:
	var produced := power.tick(delta, inventory["ice"], _working_recipe("bench") in ["fabricate", "etch"],
		_working_recipe("wreck") == "clean_solar", _working_recipe("ice") == "service_extractor")
	if produced > 0:
		inventory["ice"] += produced
		work_completed.emit("ice", "automatic_ice", {"ice": produced})
		reported.emit("自动采冰完成 · 水冰 × %d" % produced)


func _arrival_point(id: String, at: Vector2) -> Vector2:
	var bounds := Rect2(Vector2(76, 60), MAP_SIZE - Vector2(152, 112))
	var point := at.clamp(bounds.position, bounds.end)
	for other in crew:
		if other == id:
			continue
		var dest: Vector2 = crew[other]["dest"]
		var pos: Vector2 = crew[other]["pos"]
		var near_dest := Rect2(dest - Vector2(152, 50), Vector2(304, 100))
		var near_pos := Rect2(pos - Vector2(152, 50), Vector2(304, 100))
		if near_dest.has_point(point) or near_pos.has_point(point):
			for offset in [Vector2(0, 52), Vector2(0, -52), Vector2(-156, 0), Vector2(156, 0)]:
				var candidate: Vector2 = point + offset
				if bounds.has_point(candidate) and not near_dest.has_point(candidate) and not near_pos.has_point(candidate):
					return candidate
	return point


func _campaign_work_position(id: String, site: String) -> Vector2:
	if site == "shelter" and not layout.positions.has(site):
		for candidate in [Vector2(619, 76), Vector2(331, 76)]:
			if _campaign_position_free(id, candidate, CAMP):
				return candidate
	var at := site_position(site)
	var clearance := (campaign_site_size(site) + CAMPAIGN_CREW_SIZE) / 2 + Vector2(7, 6)
	for offset in [Vector2(-clearance.x, 0), Vector2(clearance.x, 0),
			Vector2(0, clearance.y), Vector2(0, -clearance.y), Vector2(-clearance.x, 58),
			Vector2(clearance.x, 58), Vector2(-clearance.x, -58), Vector2(clearance.x, -58)]:
		var candidate: Vector2 = at + offset
		if _campaign_position_free(id, candidate, site_region(site)):
			return candidate
	# Dense camps need more than the four cardinal approaches to a worksite.
	for radius in range(160, 249, 8):
		for step in range(72):
			var candidate := at + Vector2.from_angle(step * TAU / 72.0) * radius
			if _campaign_position_free(id, candidate, site_region(site)):
				return candidate
	return Vector2.INF


func _campaign_move_position(id: String, at: Vector2, region: String) -> Vector2:
	var candidate := at.clamp(CAMPAIGN_WALK_BOUNDS.position, CAMPAIGN_WALK_BOUNDS.end - Vector2.ONE)
	if _campaign_position_free(id, candidate, region):
		return candidate
	# Nudge blocked clicks to nearby open ground.
	for radius in [48, 96, 144, 192]:
		for i in range(8):
			var around: Vector2 = candidate + Vector2.from_angle(i * TAU / 8.0) * radius
			if _campaign_position_free(id, around, region):
				return around
	return Vector2.INF


func _campaign_position_free(id: String, at: Vector2, region: String) -> bool:
	if not CAMPAIGN_WALK_BOUNDS.has_point(at):
		return false
	var body := Rect2(at - CAMPAIGN_CREW_SIZE / 2, CAMPAIGN_CREW_SIZE).grow(3)
	if body.intersects(CAMPAIGN_MAP_LABEL) or body.intersects(CAMPAIGN_MAP_HELP) or body.intersects(CAMPAIGN_MAP_SCOUT):
		return false
	for site in CAMPAIGN_SITES:
		if site_region(site) == region and (site_visible(site) or (region == HIGHLANDS and site in ["trail", "archive", "outpost", "array"])):
			var card_size := campaign_site_size(site)
			if body.intersects(Rect2(site_position(site) - card_size / 2, card_size)):
				return false
	for other in crew:
		if other != id and crew_region(other) == region:
			for key in ["pos", "dest"]:
				var occupied: Vector2 = crew[other][key]
				if body.intersects(Rect2(occupied - CAMPAIGN_CREW_SIZE / 2, CAMPAIGN_CREW_SIZE)):
					return false
	return true


func move_crew(id: String, position: Vector2) -> void:
	if homeward_launched or (won and not campaign) or not crew.has(id):
		return
	if crew_away(id):
		reported.emit("队员仍在野外，请先召回")
		return
	var destination := _campaign_move_position(id, position, crew_region(id)) if campaign else _arrival_point(id, position)
	if destination == Vector2.INF:
		reported.emit("附近没有空位")
		return
	_clear_job(crew[id])
	crew[id]["duty"] = {}
	crew[id]["dest"] = destination
	crew[id]["phase"] = "move"
	reported.emit("%s已收到移动指令" % CREW_NAMES[id])


func stop_crew(id: String) -> void:
	if homeward_launched or (won and not campaign) or not crew.has(id):
		return
	_clear_job(crew[id])
	crew[id]["duty"] = {}
	if campaign:
		reported.emit("%s已停止行动，未使用的物资已归还" % CREW_NAMES[id])
	else:
		reported.emit("%s已停止工作，未使用的投入已归还" % CREW_NAMES[id])
	checkpoint.emit()


func recall_crew(id: String) -> void:
	if homeward_launched or not crew.has(id):
		return
	var departed := crew_away(id)
	var spec: Dictionary = RECIPES.get(crew[id]["job"], {})
	if not departed and not spec.has("expedition"):
		return
	_clear_job(crew[id])
	_resume_duty(id)
	var outcome := "已返回出发点，未结算补给已退回" if departed else "已取消出发"
	reported.emit("%s%s，原岗位保留" % [CREW_NAMES[id], outcome])
	checkpoint.emit()


func _clear_job(unit: Dictionary) -> void:
	if unit["job"] == "return" and unit["phase"] == "working":
		var carrier: String = crew.find_key(unit)
		radar.move_cargo(carrier, HighlandRadar.DEPOT)
	for item in unit["reserved"]:
		inventory[item] += unit["reserved"][item]
	unit["reserved"] = {}
	unit["job"] = ""
	unit["phase"] = ""
	unit["elapsed"] = 0.0
	unit["dest"] = unit["pos"]


func tick(delta: float) -> void:
	if homeward_launched or (won and not campaign):
		return
	clock += delta
	if campaign:
		_tick_power(delta)
		requests.tick(self, delta)
	if recruited or not campaign:
		_ration_clock += delta
		while _ration_clock >= 60.0:
			_ration_clock -= 60.0
			var at_camp := camp_diners()
			var eaten := mini(inventory["food"], at_camp)
			inventory["food"] -= eaten
			if eaten > 0:
				rations_used.emit(eaten)
			if at_camp > 0 and inventory["food"] == 0:
				reported.emit("口粮不足，作业效率下降。可用温室补给")
	_neighbor_clock += delta
	while _neighbor_clock >= neighbor_interval():
		_neighbor_clock -= neighbor_interval()
		if neighbor_food > 0 and neighbor_scrap > 0 and neighbor_stock < 4:
			neighbor_food -= 1
			neighbor_scrap -= 1
			neighbor_stock += 1
	if campaign and not neighbor_upgraded and neighbor_trades >= 2 and neighbor_stock >= 1 and neighbor_food >= 1 and neighbor_scrap >= 1 and active_at("relay").is_empty():
		neighbor_stock -= 1
		neighbor_food -= 1
		neighbor_scrap -= 1
		neighbor_upgraded = true
		_neighbor_clock = 0.0
		reported.emit("曙光站投入物资扩建制造间，电路生产周期缩短至 20 秒")
		checkpoint.emit()
	for id in crew.keys():
		if campaign:
			CrewWork.tick(crew[id], delta, inventory["food"] > 0 or crew_region(id) != CAMP or crew_away(id), crew.size() <= beds())
		_tick_crew(id, delta)
		if homeward_launched or (won and not campaign):
			break


func _tick_crew(id: String, delta: float) -> void:
	var unit: Dictionary = crew[id]
	match unit["phase"]:
		"":
			if campaign:
				_resume_duty(id)
		"resting":
			if unit["stamina"] >= 85 and unit["health"] >= 95:
				if unit["job"].is_empty():
					unit["phase"] = ""
					_resume_duty(id)
				else:
					_begin(id)
		"travel", "move":
			unit["pos"] = unit["pos"].move_toward(unit["dest"], MOVE_SPEED * delta)
			if unit["pos"] == unit["dest"]:
				if unit["phase"] == "move":
					unit["phase"] = ""
				else:
					_begin(id)
		"waiting":
			if missing(unit["job"]).is_empty() and not _stock_satisfied(unit):
				_begin(id)
		"working":
			var fieldwork: bool = crew_region(id) == HIGHLANDS or RECIPES[unit["job"]].has("destination") or crew_away(id)
			var slowed: bool = not fieldwork and inventory["food"] == 0 and unit["job"] not in ["grow", "camp_care"]
			var efficiency := CrewWork.rate(id, unit["job"], unit) if campaign else 1.0
			if id == tool_holder and unit["job"] in TOOL_JOBS:
				efficiency *= 1.25
			if campaign and unit["job"] in ["fabricate", "etch"]:
				efficiency *= 1.0 + 0.25 * power.bench_fraction
			unit["elapsed"] += delta * efficiency * (0.55 if slowed else 1.0)
			var duration := _duration(unit["job"])
			if unit["elapsed"] >= duration:
				_complete(id)


func _begin(id: String) -> void:
	var unit: Dictionary = crew[id]
	var recipe: String = unit["job"]
	var spec: Dictionary = RECIPES[recipe]
	unit["elapsed"] = 0.0
	if campaign and unit.get("stamina", 100.0) < 20 and recipe != "camp_care":
		unit["phase"] = "resting"
		return
	if _stock_satisfied(unit):
		unit["phase"] = "waiting"
		return
	var why := missing(recipe)
	if not why.is_empty():
		if (spec.get("repeat", false) and not campaign) or unit.get("duty", {}).get("recipe") == recipe:
			unit["phase"] = "waiting"
		else:
			_clear_job(unit)
		reported.emit("%s · %s" % [spec["label"], why])
		return
	unit["phase"] = "working"
	unit["elapsed"] = 0.0
	var inputs := recipe_cost(recipe)
	for item in inputs:
		inventory[item] -= inputs[item]
	unit["reserved"] = inputs.duplicate()
	if recipe == "return":
		radar.move_cargo(HighlandRadar.DEPOT, id)
	work_started.emit(spec["site"], inputs.duplicate())


func _duration(recipe: String) -> float:
	var spec: Dictionary = RECIPES[recipe]
	var seconds: float = spec["time"] * (0.6 if campaign else 1.0)
	if spec.has("expedition") and field_gear.equipped == "winch":
		return seconds / 1.25
	return seconds


func _complete(id: String) -> void:
	var unit: Dictionary = crew[id]
	var recipe: String = unit["job"]
	var reveals_sites := campaign and (recipe == "rescue" or (recipe == "grow" and not first_harvest) or (recipe == "research" and not blueprint))
	var spec: Dictionary = RECIPES[recipe]
	var recruit_at := Vector2.ZERO
	var first_salvage: bool = spec["site"] == "wreck" and field_cache_available()
	if spec.has("request") and not requests.finish(self, recipe):
		_clear_job(unit)
		_resume_duty(id)
		reported.emit("互助已结束，未交付物资已退回")
		return
	if recipe == "welcome_botanist":
		for entry in [Vector2(680, 505), Vector2(904, 344), Vector2(331, 76)]:
			recruit_at = _campaign_move_position("botanist", entry, CAMP)
			if recruit_at != Vector2.INF:
				break
		if recruit_at == Vector2.INF:
			_clear_job(unit)
			reported.emit("请为新队员腾出空地，接纳物资已退回")
			return
	if recipe == "research_pump" and pump_blueprint:
		_clear_job(unit)
		_resume_duty(id)
		reported.emit("已从交易获得循环泵蓝图，重复研究的材料已退回")
		return
	if spec.has("destination"):
		_complete_transfer(id, spec["destination"], recipe)
		return
	if spec.get("trade", false):
		neighbor_stock -= 1
		if recipe == "trade_food":
			neighbor_food += spec["cost"]["food"]
		else:
			neighbor_scrap += spec["cost"]["scrap"]
		if campaign:
			neighbor_trades += 1
	unit["reserved"] = {}
	if recipe in Expeditions.RECIPES:
		expeditions.complete(self, id, recipe)
	var output := production_output(recipe)
	var received := PackedStringArray()
	if spec.has("deposit"):
		if radar.collect(spec["deposit"]):
			received.append("样本已存高地接驳点，返营队员将捎回")
		output = {}
	for item in output:
		inventory[item] += output[item]
		received.append("%s × %d" % [ITEMS[item], output[item]])
	if spec.has("injury"):
		received.append("%s健康 −%d" % [CREW_NAMES[id], roundi(expedition_injury(recipe))])
	if spec.has("request") and requests.completed == 1:
		received.append("护理恢复提升至 45")
	if campaign and not first_harvest and spec["site"] in SURVEY_TARGETS:
		recovered[spec["site"]] = true
		if survey_complete() and not recruited:
			received.append("附近出现求救信号")
	match recipe:
		"camp_care":
			var health := minf(requests.care_health(), 100 - unit["health"])
			var stamina := minf(35, 100 - unit["stamina"])
			unit["health"] += health
			unit["stamina"] += stamina
			reported.emit("%s护理完成 · 健康 +%.0f、体力 +%.0f，恢复原岗位" % [CREW_NAMES[id], health, stamina])
		"salvage":
			if not salvaged and not campaign:
				salvaged = true
				reported.emit("残骸附近发现求救信号")
		"rescue":
			recruited = true
			var at := site_position("casualty")
			crew["tech"] = {"pos": at, "dest": at, "job": "", "phase": "", "elapsed": 0.0, "reserved": {}}
			if campaign:
				CrewWork.ensure(crew["tech"])
				crew["tech"]["health"] = 75.0
				reported.emit("勘探员加入，标出了温室基座和浅层冰脉")
			else:
				reported.emit("勘探员自愿加入，曙光站短距通信已接通")
		"research":
			blueprint = true
			reported.emit("信标维修蓝图与电路配方已解锁")
		"build":
			greenhouse_built = true
			reported.emit("密封温室搭建完成，可投入水冰培育口粮")
		"grow":
			if campaign and not first_harvest:
				received.append("科研与制造已开放")
			first_harvest = true
		"repair":
			won = true
			if not campaign:
				for other in crew:
					if other != id:
						_clear_job(crew[other])
			if campaign:
				reported.emit("轨道站已收到信号，发来北缘高地旧测绘站坐标")
			else:
				reported.emit("通信信标已上线，轨道接收站确认收到信号")
		"survey_archive":
			navigation_record = true
			if outpost_built:
				reported.emit("轨道站已收到首份航标记录")
			else:
				reported.emit("找到首份航标记录。可用通信前哨将资料传给轨道站")
		"establish_outpost":
			outpost_supplied = false
			outpost_built = true
			if navigation_record:
				reported.emit("前哨已上线，轨道站已收到首份航标记录")
			else:
				reported.emit("高地通信前哨已上线")
		"exchange_calibration":
			calibration_blueprint = true
			calibration_source = "exchange"
			neighbor_parts += 2
			reported.emit("曙光站收到结构件，分享了测向阵列校准蓝图")
		"research_calibration":
			calibration_blueprint = true
			calibration_source = "research"
			reported.emit("已根据航标记录推导出校准蓝图，可运送阵列设备")
		"calibrate_array":
			array_supplied = false
			array_calibrated = true
			reported.emit("测向阵列恢复，第二份归航航标已同步至轨道站")
		"survey_last_record":
			third_record_source = "survey"
			reported.emit("阵列捕获母星应答，第三航标已同步。返回迫降地整备归航舱")
		"exchange_last_record":
			third_record_source = "exchange"
			neighbor_parts += int(spec["cost"]["plate"])
			reported.emit("曙光站收到组件，传来了第三航标。着陆舱残骸可用于整备归航舱")
		"assemble_return_craft":
			return_craft_ready = true
			reported.emit("归航舱已就绪。让领队带上 3 口粮、2 水冰，到通信信标登舱")
		"launch_homeward":
			homeward_launched = true
			unit["duty"] = {}
			_clear_job(unit)
			reported.emit("轨道接驳完成，领队踏上归途。火星营地的探索记录已随舱发往母星")
			work_completed.emit(spec["site"], recipe, {})
			checkpoint.emit()
			return
		"research_pump":
			pump_blueprint = true
			reported.emit("循环泵蓝图已恢复，需在温室试制才能提高产量")
		"trial_pump":
			pump_built = true
			reported.emit("循环泵试制通过，每份水冰可产出 5 份口粮。农艺师发来合作申请")
		"expand_shelter":
			shelter_expanded = true
			reported.emit("居住舱扩建完成，可容纳 3 名队员")
		"welcome_botanist":
			botanist_joined = true
			crew["botanist"] = {"pos": recruit_at, "dest": recruit_at, "job": "", "phase": "", "elapsed": 0.0, "reserved": {}}
			CrewWork.ensure(crew["botanist"])
			reported.emit("农艺师自愿加入，擅长温室种植。营地每分钟需供养 3 人")
		"research_power":
			power.blueprint = true
			reported.emit("能源蓝图研究完成，可在着陆舱残骸组装太阳能储能组")
		"trade_power":
			power.blueprint = true
			neighbor_food += 4
			neighbor_parts += 1
			reported.emit("曙光站收到补给与结构件，分享太阳能储能和自动采冰蓝图")
		"build_solar":
			power.solar_built = true
			reported.emit("太阳能储能组上线，白天蓄电，工作台可获得电力加速")
		"build_extractor":
			power.extractor_built = true
			power.extractor_status = "等待供电"
			reported.emit("自动采冰机装配完成，将维持 6 份水冰库存，无需队员值守")
		"clean_solar":
			power.cleanliness = 100.0
			reported.emit("太阳能板清理完成，发电能力恢复")
		"service_extractor":
			power.condition = 100.0
			reported.emit("自动采冰机维护完成，未完成批次可继续生产")
	if campaign and spec.get("trade", false) and not pump_blueprint:
		pump_blueprint = true
		received.append("曙光站分享循环泵蓝图，可在温室试制")
	if not received.is_empty():
		reported.emit("%s完成 · %s" % [spec["label"], "、".join(received)])
	if reveals_sites:
		_clear_revealed_workspaces()
	work_completed.emit(spec["site"], recipe, output.duplicate())
	var duty: Dictionary = unit.get("duty", {})
	if not duty.is_empty() and duty["recipe"] == recipe:
		if duty["mode"] == "batch":
			duty["remaining"] -= 1
			if duty["remaining"] == 0:
				unit["duty"] = {}
		if not unit["duty"].is_empty() and not survey_site_exhausted(spec["site"]):
			_begin(id)
		else:
			unit["duty"] = {}
			_clear_job(unit)
	elif spec.get("repeat", false) and not campaign:
		_begin(id)
	else:
		_clear_job(unit)
		if campaign:
			_resume_duty(id)
	if first_salvage or spec.has("deposit") or spec.get("homeward", false) or recipe == "camp_care" or spec.has("request") or recipe in Expeditions.RECIPES or spec.get("industry", false) or recipe in ["rescue", "research", "build", "repair", "survey_archive", "establish_outpost",
			"exchange_calibration", "research_calibration", "calibrate_array", "research_pump", "trial_pump", "expand_shelter", "welcome_botanist", "trade_food", "trade_scrap"]:
		checkpoint.emit()


func _clear_revealed_workspaces(region: String = CAMP) -> void:
	# Newly revealed cards must not cover a crew member at an older work position.
	# Keep job, elapsed work and reserved materials intact when moving their marker.
	for id in crew:
		if crew_region(id) != region or crew_away(id):
			continue
		var unit: Dictionary = crew[id]
		for key in ["pos", "dest"]:
			var body := Rect2(unit[key] - CAMPAIGN_CREW_SIZE / 2, CAMPAIGN_CREW_SIZE).grow(3)
			var covered := false
			for site in CAMPAIGN_SITES:
				if site_visible(site) and site_region(site) == region:
					covered = covered or body.intersects(Rect2(site_position(site) - campaign_site_size(site) / 2, campaign_site_size(site)))
			if not covered:
				continue
			var at: Vector2 = _campaign_work_position(id, RECIPES[unit["job"]]["site"]) if not unit["job"].is_empty() else _campaign_move_position(id, unit[key], region)
			if at == Vector2.INF:
				continue
			unit[key] = at
			if unit["phase"] not in ["travel", "move"]:
				unit["pos"] = at
				unit["dest"] = at


func _complete_transfer(id: String, destination: String, recipe: String) -> void:
	var unit: Dictionary = crew[id]
	var arrival := Vector2.INF
	for entry in TRANSFER_ARRIVALS[destination]:
		arrival = _campaign_move_position(id, entry, destination)
		if arrival != Vector2.INF:
			break
	if arrival == Vector2.INF:
		_clear_job(unit)
		reported.emit("接驳点被占用，运输取消，物资已退回")
		return
	var delivered := {}
	if recipe == "return":
		delivered = radar.move_cargo(id, HighlandRadar.DELIVERED)
		for item in delivered:
			inventory[item] += delivered[item]
	unit["reserved"] = {}
	unit["region"] = destination
	unit["pos"] = arrival
	_clear_job(unit)
	if destination == HIGHLANDS:
		highlands_visited = true
		if recipe == "deliver":
			outpost_supplied = true
			reported.emit("%s和前哨物资已抵达北缘高地" % CREW_NAMES[id])
		elif recipe == "deliver_array":
			array_supplied = true
			reported.emit("%s已将阵列设备运抵高地，可以安排修复校准" % CREW_NAMES[id])
		else:
			reported.emit("%s已抵达北缘高地" % CREW_NAMES[id])
	else:
		var goods := PackedStringArray()
		for item in delivered:
			goods.append("%s ×%d" % [ITEMS[item], delivered[item]])
		var receipt := "，样本入库 · " + "、".join(goods) if not delivered.is_empty() else ""
		reported.emit("%s已返回迫降地%s" % [CREW_NAMES[id], receipt])
	crew_transferred.emit(id, destination)
	if not delivered.is_empty():
		radar_delivered.emit(delivered)
	if destination == CAMP:
		_resume_duty(id)
	checkpoint.emit()


func activity(id: String) -> String:
	var unit: Dictionary = crew[id]
	match unit["phase"]:
		"travel":
			return "前往%s" % SITES[RECIPES[unit["job"]]["site"]]["title"]
		"move":
			return "移动中"
		"waiting":
			return "库存已达目标" if _stock_satisfied(unit) else missing(unit["job"])
		"resting":
			return "休整中 · 体力 %d" % unit.get("stamina", 100)
		"working":
			return RECIPES[unit["job"]]["label"]
	return "待命"


func progress(id: String) -> float:
	var unit: Dictionary = crew[id]
	if unit["phase"] != "working":
		return -1.0
	return clampf(unit["elapsed"] / _duration(unit["job"]), 0.0, 1.0)
