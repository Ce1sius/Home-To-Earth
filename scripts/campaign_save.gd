extends RefCounted

const State := preload("res://scripts/mission_state.gd")
const VERSION := 8
const FLAGS := ["salvaged", "recruited", "blueprint", "greenhouse_built", "first_harvest",
	"won", "highlands_visited", "outpost_supplied", "outpost_built", "navigation_record",
	"calibration_blueprint", "array_supplied", "array_calibrated", "shelter_expanded",
	"pump_blueprint", "pump_built", "botanist_joined", "neighbor_upgraded",
	"return_craft_ready", "homeward_launched"]
const COUNTERS := ["neighbor_stock", "neighbor_food", "neighbor_scrap", "neighbor_parts", "neighbor_trades"]
const CLOCKS := ["clock", "_neighbor_clock", "_ration_clock"]

# Tests use an isolated temporary path and never touch the player's campaign.
static var path := "user://campaign_v1.json"
static var pending: Dictionary = {}
static var last_error := ""


static func write_game(state: RefCounted, region: String, selected: String) -> bool:
	var snapshot := {"version": VERSION, "state": _encode(state), "region": region, "selected": selected}
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "存档写入失败，请检查保存目录"
		return false
	file.store_string(JSON.stringify(snapshot))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),
			ProjectSettings.globalize_path(path)) != OK:
		last_error = "保存失败，原有存档仍保留"
		return false
	last_error = ""
	return true


static func read_game() -> Dictionary:
	last_error = ""
	if not FileAccess.file_exists(path):
		return {}
	last_error = "存档无法读取，可开始新游戏"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1024 * 1024:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var data: Variant = parser.data
	if not data is Dictionary or not _number(data.get("version")) or data["version"] != floorf(data["version"]) or data["version"] < 1 or data["version"] > VERSION or not data.get("state") is Dictionary:
		return {}
	if data["version"] == 1:
		_migrate_v1(data["state"])
	if data["version"] == 1 or data["version"] == 2:
		data["state"]["power"] = State.PowerGrid.new().snapshot()
	if data["version"] < 4:
		data["state"]["layout"] = {}
		data["state"]["expeditions"] = State.Expeditions.new().snapshot()
	if data["version"] < 5:
		data["state"]["requests"] = State.Requests.new().snapshot()
	if data["version"] < 6:
		data["state"]["tool_holder"] = ""
		data["state"]["third_record_source"] = ""
		data["state"]["return_craft_ready"] = false
		data["state"]["homeward_launched"] = false
	if data["version"] < 7:
		data["state"]["field_gear"] = State.FieldGear.new().snapshot()
	if data["version"] < 8:
		data["state"]["radar"] = State.HighlandRadar.new(hash(data["state"])).snapshot()
	var state := _decode(data["state"])
	if state == null:
		return {}
	if data["version"] == 1:
		var shelter := Rect2(state.site_position("shelter") - state.campaign_site_size("shelter") / 2, state.campaign_site_size("shelter"))
		for id in state.crew:
			if state.crew_region(id) != State.CAMP:
				continue
			for key in ["pos", "dest"]:
				var unit: Dictionary = state.crew[id]
				if shelter.intersects(Rect2(unit[key] - State.CAMPAIGN_CREW_SIZE / 2, State.CAMPAIGN_CREW_SIZE)):
					var free: Vector2 = state._campaign_move_position(id, unit[key], State.CAMP)
					if free == Vector2.INF:
						return {}
					unit[key] = free
	var region: Variant = data.get("region")
	var selected: Variant = data.get("selected")
	if region not in [State.CAMP, State.HIGHLANDS] or not selected is String:
		return {}
	if region == State.HIGHLANDS and not state.highlands_visited:
		return {}
	if not selected.is_empty() and (not state.crew.has(selected) or state.crew_region(selected) != region):
		return {}
	last_error = ""
	return {"state": state, "region": region, "selected": selected}


static func _encode(state: RefCounted) -> Dictionary:
	var data := {"inventory": state.inventory.duplicate(), "recovered": state.recovered.duplicate(),
		"crew": {}, "calibration_source": state.calibration_source, "power": state.power.snapshot(),
		"layout": state.layout.snapshot(), "expeditions": state.expeditions.snapshot(),
		"field_gear": state.field_gear.snapshot(), "requests": state.requests.snapshot(), "third_record_source": state.third_record_source,
		"tool_holder": state.tool_holder, "radar": state.radar.snapshot()}
	for key in FLAGS + COUNTERS + CLOCKS:
		data[key] = state.get(key)
	for id in state.crew:
		State.CrewWork.ensure(state.crew[id])
		var unit: Dictionary = state.crew[id].duplicate(true)
		for key in ["pos", "dest"]:
			var point: Vector2 = unit[key]
			unit[key] = [point.x, point.y]
		unit["region"] = state.crew_region(id)
		data["crew"][id] = unit
	return data


static func _decode(data: Dictionary) -> RefCounted:
	var state := State.new(true)
	if not data.get("radar") is Dictionary or not state.radar.restore(data["radar"]):
		return null
	if not data.get("field_gear") is Dictionary or not state.field_gear.restore(data["field_gear"]):
		return null
	if not data.get("power") is Dictionary or not state.power.restore(data["power"]):
		return null
	if not data.get("layout") is Dictionary or not state.layout.restore(state, data["layout"]):
		return null
	if not data.get("expeditions") is Dictionary or not state.expeditions.restore(data["expeditions"]):
		return null
	if not data.get("requests") is Dictionary or not state.requests.restore(data["requests"]):
		return null
	for key in FLAGS:
		if not data.get(key) is bool:
			return null
		state.set(key, data[key])
	for key in COUNTERS + CLOCKS:
		if not _number(data.get(key)):
			return null
		if key in COUNTERS and float(data[key]) != floorf(float(data[key])):
			return null
		state.set(key, int(data[key]) if key in COUNTERS else float(data[key]))
	if state._ration_clock >= 60.0 or state._neighbor_clock >= state.neighbor_interval() or state.neighbor_stock > 4:
		return null
	var inventory: Variant = data.get("inventory")
	if not inventory is Dictionary or inventory.size() != state.inventory.size():
		return null
	for item in state.inventory:
		if not _number(inventory.get(item)) or float(inventory[item]) != floorf(float(inventory[item])):
			return null
		state.inventory[item] = int(inventory[item])
	if state.inventory["tool"] != 1:
		return null
	var recovered: Variant = data.get("recovered")
	if not recovered is Dictionary:
		return null
	for key in recovered:
		if key not in State.SURVEY_TARGETS or recovered[key] != true:
			return null
	state.recovered = recovered.duplicate()
	if data.get("calibration_source") not in ["", "exchange", "research"]:
		return null
	state.calibration_source = data["calibration_source"]
	if data.get("third_record_source") not in ["", "survey", "exchange"]:
		return null
	state.third_record_source = data["third_record_source"]
	if not _valid_progress(state):
		return null
	var crew: Variant = data.get("crew")
	if not crew is Dictionary or not crew.has("lead") or crew.size() != (1 + int(state.recruited) + int(state.botanist_joined)):
		return null
	if crew.has("tech") != state.recruited or crew.has("botanist") != state.botanist_joined:
		return null
	var tool_holder: Variant = data.get("tool_holder", "")
	if not tool_holder is String or (not tool_holder.is_empty() and not crew.has(tool_holder)):
		return null
	state.tool_holder = tool_holder
	state.crew.clear()
	var busy := {}
	for id in crew:
		if id not in State.CREW_NAMES or not crew[id] is Dictionary:
			return null
		var unit: Dictionary = crew[id].duplicate(true)
		if not _decode_unit(state, unit):
			return null
		var job: String = unit["job"]
		if job == "launch_homeward" and id != "lead":
			return null
		if id == "lead" and state.homeward_launched and (unit["region"] != State.CAMP or not unit["phase"].is_empty() or not unit["duty"].is_empty()):
			return null
		if not job.is_empty():
			var site: String = State.RECIPES[job]["site"]
			if busy.has(site):
				return null
			busy[site] = true
		state.crew[id] = unit
	if not state.radar.valid_carriers(state):
		return null
	if busy.has("array") and busy.has("relay"):
		var array_worker: String = state.active_at("array")
		var relay_worker: String = state.active_at("relay")
		if state.crew[array_worker]["job"] == "survey_last_record" and state.crew[relay_worker]["job"] == "exchange_last_record":
			return null
	return state


static func _decode_unit(state: RefCounted, unit: Dictionary) -> bool:
	for key in ["pos", "dest"]:
		var point: Variant = unit.get(key)
		if not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]):
			return false
		unit[key] = Vector2(point[0], point[1])
		if not Rect2(Vector2.ZERO, State.MAP_SIZE).has_point(unit[key]):
			return false
	if unit.get("region") not in [State.CAMP, State.HIGHLANDS]:
		return false
	if unit["region"] == State.HIGHLANDS and not state.highlands_visited:
		return false
	var phase: Variant = unit.get("phase")
	var job: Variant = unit.get("job")
	if phase not in ["", "move", "travel", "waiting", "working", "resting"] or not job is String:
		return false
	if not _number(unit.get("elapsed")) or not unit.get("reserved") is Dictionary:
		return false
	for stat in ["health", "stamina", "morale"]:
		if not _number(unit.get(stat)) or unit[stat] > 100:
			return false
	var duty: Variant = unit.get("duty")
	if not duty is Dictionary:
		return false
	if not duty.is_empty():
		if duty.get("recipe") not in State.CrewWork.JOBS or duty.get("mode") not in ["continuous", "batch", "stock"]:
			return false
		for key in ["remaining", "target"]:
			if not _number(duty.get(key)) or duty[key] < 1 or duty[key] > 99 or duty[key] != floorf(duty[key]):
				return false
			duty[key] = int(duty[key])
		if not state.site_visible(State.RECIPES[duty["recipe"]]["site"]) or (duty["recipe"] == "etch" and not state.blueprint):
			return false
	if phase in ["", "move"] or (phase == "resting" and job.is_empty()):
		return job.is_empty() and unit["reserved"].is_empty() and unit["elapsed"] == 0
	if not State.RECIPES.has(job):
		return false
	var spec: Dictionary = State.RECIPES[job]
	if spec.has("deposit") and state.radar.collected[spec["deposit"]]:
		return false
	if job == "recover_field_cache" and not state.field_cache_available():
		return false
	if spec.get("homeward", false):
		if state.recipe_completed(job) or not state.array_calibrated:
			return false
		if job == "assemble_return_craft" and state.third_record_source.is_empty():
			return false
		if job == "launch_homeward" and not state.return_craft_ready:
			return false
	if spec.has("request") and not state.requests.reason(job).is_empty():
		return false
	if job == "camp_care" and not state.recruited:
		return false
	if spec.has("expedition") and (not state.first_harvest or state.expeditions.resolved.has(spec["expedition"])):
		return false
	if spec.get("patrol", false) and (state.expeditions.resolved.is_empty() or state.expeditions.patrol_wait(state.clock) > 0):
		return false
	if job == "trial_sampler" and (not state.expeditions.sampler_blueprint or state.expeditions.sampler_built):
		return false
	if not state.site_visible(spec["site"]) or state.site_region(spec["site"]) != unit["region"]:
		return false
	if phase == "waiting" and not spec.get("repeat", false) and duty.get("recipe") != job:
		return false
	var reserved: Dictionary = unit["reserved"]
	var cost: Dictionary = state.recipe_cost(job) if phase == "working" else {}
	if reserved.size() != cost.size():
		return false
	for item in reserved:
		if not cost.has(item) or not _number(reserved[item]) or reserved[item] != cost[item]:
			return false
		reserved[item] = int(reserved[item])
	return true


static func _valid_progress(state: RefCounted) -> bool:
	if not state.highlands_visited:
		for samples: Array in state.radar.probes.values():
			if not samples.is_empty():
				return false
	if state.expeditions.next_patrol_at > state.clock + State.Expeditions.PATROL_INTERVAL + 0.01:
		return false
	if not state.first_harvest and state.field_gear.snapshot() != State.FieldGear.new().snapshot():
		return false
	if not state.third_record_source.is_empty() and not state.array_calibrated:
		return false
	if state.return_craft_ready and state.third_record_source.is_empty():
		return false
	if state.homeward_launched and not state.return_craft_ready:
		return false
	if not state.first_harvest and state.requests.snapshot() != State.Requests.new().snapshot():
		return false
	if not state.expeditions.resolved.is_empty() and not state.first_harvest:
		return false
	if state.power.blueprint and not state.pump_built:
		return false
	if state.pump_blueprint and not state.first_harvest:
		return false
	if state.pump_built and not state.pump_blueprint:
		return false
	if state.botanist_joined and not (state.shelter_expanded and state.pump_built):
		return false
	if state.neighbor_upgraded and state.neighbor_trades < 2:
		return false
	if state.recruited and not state.survey_complete():
		return false
	if state.greenhouse_built and not state.recruited:
		return false
	if state.first_harvest and not state.greenhouse_built:
		return false
	if state.blueprint and not state.first_harvest:
		return false
	if state.won and not state.blueprint:
		return false
	if state.highlands_visited and not state.won:
		return false
	if (state.outpost_supplied or state.outpost_built or state.navigation_record) and not state.highlands_visited:
		return false
	if state.outpost_supplied and state.outpost_built:
		return false
	if state.calibration_blueprint != (not state.calibration_source.is_empty()):
		return false
	if state.calibration_blueprint and not state.first_record_uploaded():
		return false
	if (state.array_supplied or state.array_calibrated) and not state.calibration_blueprint:
		return false
	return not (state.array_supplied and state.array_calibrated)


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= 0 and value <= 100000000


static func _migrate_v1(data: Dictionary) -> void:
	for flag in ["shelter_expanded", "pump_blueprint", "pump_built", "botanist_joined", "neighbor_upgraded"]:
		data[flag] = false
	data["neighbor_trades"] = 0
	if data.get("crew") is Dictionary:
		for unit in data["crew"].values():
			if unit is Dictionary:
				State.CrewWork.ensure(unit)
				if unit.get("job") == "grow":
					unit["duty"] = {"recipe": "grow", "mode": "continuous", "remaining": 1, "target": 1}
