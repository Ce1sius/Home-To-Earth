extends RefCounted

const JOBS := ["salvage", "mine", "extract", "fabricate", "etch", "grow"]
const PROFILES := {
	"lead": {"trait": "野外经验", "specialty": "采集速度 +15%", "jobs": ["salvage", "mine", "extract"], "bonus": 1.15},
	"tech": {"trait": "精细维修", "specialty": "制造与建造速度 +25%", "jobs": ["fabricate", "etch", "build", "expand_shelter", "trial_pump", "trial_sampler", "repair", "establish_outpost", "calibrate_array", "build_solar", "build_extractor", "clean_solar", "service_extractor"], "bonus": 1.25},
	"botanist": {"trait": "温室经验", "specialty": "种植速度 +35%", "jobs": ["grow"], "bonus": 1.35},
}


static func ensure(unit: Dictionary) -> void:
	for key in ["health", "stamina", "morale"]:
		if not unit.has(key):
			unit[key] = 80.0 if key == "morale" else 100.0
	if not unit.has("duty"):
		unit["duty"] = {}


static func tick(unit: Dictionary, delta: float, fed: bool, sheltered: bool) -> void:
	ensure(unit)
	var phase: String = unit["phase"]
	var change := 0.8
	if phase == "working":
		change = -0.18
	elif phase in ["travel", "move"]:
		change = -0.06
	elif phase == "resting":
		change = 2.0
	unit["stamina"] = clampf(unit["stamina"] + change * delta, 0, 100)
	if phase in ["", "resting", "waiting"]:
		unit["health"] = minf(100, unit["health"] + delta * (0.7 if phase == "resting" else 0.1))
	unit["morale"] = clampf(unit["morale"] + delta * (0.04 if fed and sheltered else -0.1), 25, 100)


static func rate(id: String, recipe: String, unit: Dictionary) -> float:
	var profile: Dictionary = PROFILES[id]
	var speed: float = profile["bonus"] if recipe in profile["jobs"] else 1.0
	if unit.get("health", 100.0) < 90:
		speed *= 0.9
	if unit.get("morale", 80.0) < 40:
		speed *= 0.85
	return speed


static func duty_text(unit: Dictionary, recipes: Dictionary) -> String:
	var duty: Dictionary = unit.get("duty", {})
	if duty.is_empty():
		return "未设置岗位"
	var label: String = recipes[duty["recipe"]]["label"]
	match duty["mode"]:
		"batch": return "%s · 剩余 %d 批" % [label, duty["remaining"]]
		"stock": return "%s · 库存目标 %d" % [label, duty["target"]]
	return label + " · 持续岗位"
