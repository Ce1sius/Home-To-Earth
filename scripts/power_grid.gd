extends RefCounted

signal notice(message: String)

const CAPACITY := 40.0
const DAY_LENGTH := 120.0
const DAYLIGHT := 80.0
const WEATHER_PERIOD := 240.0
const AUTO_BATCH_TIME := 20.0
const ICE_TARGET := 6
const FLAGS := ["blueprint", "solar_built", "extractor_built", "extractor_enabled"]
const VALUES := ["time", "energy", "cleanliness", "condition", "progress"]

var blueprint := false
var solar_built := false
var extractor_built := false
var extractor_enabled := true
var time := 0.0
var energy := 0.0
var cleanliness := 100.0
var condition := 100.0
var progress := 0.0
var bench_powered := false
var bench_fraction := 0.0
var extractor_status := "尚未装配"


func weather_stage() -> String:
	var phase := fmod(time, WEATHER_PERIOD)
	if phase >= 180.0 and phase < 210.0:
		return "storm"
	if phase >= 150.0 and phase < 180.0:
		return "warning"
	return "clear"


func daylight() -> bool:
	return fmod(time, DAY_LENGTH) < DAYLIGHT


func forecast() -> String:
	match weather_stage():
		"storm": return "沙尘中 · %d秒后结束" % ceili(210.0 - fmod(time, WEATHER_PERIOD))
		"warning": return "沙尘预警 · %d秒后抵达" % ceili(180.0 - fmod(time, WEATHER_PERIOD))
	return "日照" if daylight() else "夜间"


func generation() -> float:
	if not solar_built or not daylight():
		return 0.0
	return 2.0 * cleanliness / 100.0 * (0.25 if weather_stage() == "storm" else 1.0)


func tick(delta: float, ice: int, bench_requested: bool, cleaning: bool, servicing: bool) -> int:
	bench_fraction = 0.0
	if not solar_built:
		bench_powered = false
		return 0
	var remaining := delta
	var produced := 0
	var powered_time := 0.0
	# Bound steps so long frames cannot skip a weather event or create free output.
	while remaining > 0.000001:
		var step := minf(remaining, 0.1)
		remaining -= step
		produced += _step(step, ice + produced, bench_requested, cleaning, servicing)
		if bench_powered:
			powered_time += step
	if delta > 0:
		bench_fraction = clampf(powered_time / delta, 0, 1)
	return produced


func _step(delta: float, ice: int, bench_requested: bool, cleaning: bool, servicing: bool) -> int:
	var previous := weather_stage()
	time += delta
	var weather := weather_stage()
	if previous != weather:
		match weather:
			"warning": notice.emit("沙尘预警：30 秒后抵达，可储备水冰、蓄电或暂停自动采冰")
			"storm":
				cleanliness = maxf(0.0, cleanliness - 25.0)
				notice.emit("沙尘抵达，太阳能输出下降，板面积尘增加")
			"clear": notice.emit("沙尘已过，可安排队员清理太阳能板")
	cleanliness = maxf(0, cleanliness - delta * 0.015)
	energy = minf(CAPACITY, energy + (0.0 if cleaning else generation()) * delta)
	bench_powered = bench_requested and energy + 0.000001 >= delta
	if bench_powered:
		energy = maxf(0, energy - delta)
	if not extractor_built:
		extractor_status = "尚未装配"
	elif not extractor_enabled:
		extractor_status = "已手动暂停"
	elif servicing:
		extractor_status = "维护中"
	elif condition <= 0:
		extractor_status = "磨损停机 · 需要维护"
	elif ice >= ICE_TARGET:
		extractor_status = "库存已达 %d" % ICE_TARGET
	elif energy + 0.000001 < delta:
		extractor_status = "电量不足 · 等待供电"
	else:
		extractor_status = "自动采冰中"
		energy = maxf(0, energy - delta)
		progress += delta
		if progress + 0.000001 >= AUTO_BATCH_TIME:
			progress = maxf(0, progress - AUTO_BATCH_TIME)
			condition = maxf(0, condition - 5)
			if condition == 0:
				notice.emit("自动采冰机磨损停机，需用 1 份残件维护")
			return 2
	return 0


func snapshot() -> Dictionary:
	var data := {}
	for key in FLAGS + VALUES:
		data[key] = get(key)
	return data


func restore(data: Dictionary) -> bool:
	for key in FLAGS:
		if not data.get(key) is bool:
			return false
	for key in VALUES:
		var value: Variant = data.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or value < 0:
			return false
	if data["time"] > 100000000 or data["energy"] > CAPACITY or data["cleanliness"] > 100 or data["condition"] > 100 or data["progress"] >= AUTO_BATCH_TIME:
		return false
	if data["solar_built"] and not data["blueprint"]:
		return false
	if data["extractor_built"] and not data["solar_built"]:
		return false
	if not data["solar_built"] and (data["time"] != 0 or data["energy"] != 0):
		return false
	if not data["extractor_built"] and data["progress"] != 0:
		return false
	for key in FLAGS + VALUES:
		set(key, data[key])
	extractor_status = "等待供电" if extractor_enabled else "已手动暂停"
	return true
