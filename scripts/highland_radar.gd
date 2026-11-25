extends RefCounted

const GRID := Vector2i(9, 6)
const MAX_PROBES := 3
const ZONES := {
	"lens": {"title": "水冰透镜", "site": "radar_lens", "recipe": "dig_lens", "reward": {"ice": 5, "ore": 2}},
	"cache": {"title": "坠落货箱", "site": "radar_cache", "recipe": "dig_cache", "reward": {"plate": 2, "circuit": 1}},
}
const DEPOT := "depot"
const DELIVERED := "camp"

var probes: Dictionary = {"lens": [], "cache": []}
var marked := {"lens": false, "cache": false}
var collected := {"lens": false, "cache": false}
var _targets := {}
# Each deposit produces one indivisible sample load, tracked until camp receives it.
var _cargo := {"lens": "", "cache": ""}


func _init(terrain_seed: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	if terrain_seed >= 0:
		rng.seed = terrain_seed
	else:
		rng.randomize()
	for zone: String in ZONES:
		_targets[zone] = Vector2i(rng.randi_range(1, GRID.x - 2), rng.randi_range(1, GRID.y - 2))


func operator_reason(state: RefCounted) -> String:
	if not state.campaign or not state.highlands_visited:
		return "先派队员抵达北缘高地"
	if state.homeward_launched:
		return "本次地表任务已结束"
	for worker in state.crew:
		if state.crew_region(worker) == state.HIGHLANDS and not state.crew_away(worker):
			return ""
	return "需要一名留在高地的队员操作雷达"


func reading(zone: String, cell: Vector2i) -> float:
	if not ZONES.has(zone) or cell not in probes[zone]:
		return -1.0
	return cell.distance_to(_targets[zone])


func marked_cell(zone: String) -> Vector2i:
	return _targets[zone] if marked.get(zone, false) else Vector2i(-1, -1)


func _can_survey(state: RefCounted, zone: String) -> bool:
	return ZONES.has(zone) and not marked[zone] and operator_reason(state).is_empty()


func place(state: RefCounted, zone: String, cell: Vector2i) -> bool:
	if not _can_survey(state, zone) or not Rect2i(Vector2i.ZERO, GRID).has_point(cell):
		return false
	var points: Array = probes[zone]
	if points.size() == MAX_PROBES or cell in points:
		return false
	points.append(cell)
	state.checkpoint.emit()
	return true


func undo(state: RefCounted, zone: String) -> bool:
	if not _can_survey(state, zone) or probes[zone].is_empty():
		return false
	probes[zone].pop_back()
	state.checkpoint.emit()
	return true


func mark(state: RefCounted, zone: String, cell: Vector2i) -> bool:
	if not _can_survey(state, zone) or probes[zone].size() < 2 or _targets[zone] != cell:
		return false
	marked[zone] = true
	state._clear_revealed_workspaces(state.HIGHLANDS)
	state.reported.emit("已定位%s，返回高地地图可派员开挖" % ZONES[zone]["title"])
	state.checkpoint.emit()
	return true


func collect(zone: String) -> bool:
	if not marked.get(zone, false) or collected[zone]:
		return false
	collected[zone] = true
	_cargo[zone] = DEPOT
	return true


func _cargo_at(location: String) -> Dictionary:
	var total := {}
	for zone: String in ZONES:
		if _cargo[zone] == location:
			for item: String in ZONES[zone]["reward"]:
				total[item] = total.get(item, 0) + ZONES[zone]["reward"][item]
	return total


func depot_cargo() -> Dictionary:
	return _cargo_at(DEPOT)


func aboard_cargo(worker: String) -> Dictionary:
	return {} if worker in ["", DEPOT, DELIVERED] else _cargo_at(worker)


func move_cargo(origin: String, destination: String) -> Dictionary:
	var moved := _cargo_at(origin)
	for zone: String in ZONES:
		if _cargo[zone] == origin:
			_cargo[zone] = destination
	return moved


func valid_carriers(state: RefCounted) -> bool:
	for location: String in _cargo.values():
		if location in ["", DEPOT, DELIVERED]:
			continue
		if not state.crew.has(location) or state.crew[location]["job"] != "return" or not state.crew_away(location):
			return false
	return true


func snapshot() -> Dictionary:
	var data := {}
	for zone: String in ZONES:
		var samples := []
		for probe: Vector2i in probes[zone]:
			samples.append(_index(probe))
		data[zone] = {"target": _index(_targets[zone]), "probes": samples, "marked": marked[zone], "cargo": _cargo[zone]}
	return data


func restore(data: Dictionary) -> bool:
	if data.size() != ZONES.size() or not data.has_all(ZONES.keys()):
		return false
	var targets := {}
	var restored_probes := {}
	for zone: String in ZONES:
		var row: Variant = data[zone]
		if not row is Dictionary or not row.get("marked") is bool or not row.get("cargo") is String:
			return false
		var target := _cell(row.get("target"))
		if not Rect2i(Vector2i.ONE, GRID - Vector2i(2, 2)).has_point(target):
			return false
		if not row.get("probes") is Array or row["probes"].size() > MAX_PROBES:
			return false
		var samples: Array[Vector2i] = []
		for value in row["probes"]:
			var sample := _cell(value)
			if sample == Vector2i(-1, -1) or sample in samples:
				return false
			samples.append(sample)
		if (row["marked"] and samples.size() < 2) or (not row["cargo"].is_empty() and not row["marked"]):
			return false
		targets[zone] = target
		restored_probes[zone] = samples
	_targets = targets
	probes = restored_probes
	for zone: String in ZONES:
		marked[zone] = data[zone]["marked"]
		_cargo[zone] = data[zone]["cargo"]
		collected[zone] = not _cargo[zone].is_empty()
	return true


static func _index(cell: Vector2i) -> int:
	return cell.y * GRID.x + cell.x


static func _cell(value: Variant) -> Vector2i:
	if not (value is float or value is int) or not is_finite(float(value)) or value < 0 or value >= GRID.x * GRID.y or value != floorf(value):
		return Vector2i(-1, -1)
	return Vector2i(int(value) % GRID.x, floori(float(value) / GRID.x))
