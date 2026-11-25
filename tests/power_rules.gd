extends SceneTree

const Grid := preload("res://scripts/power_grid.gd")
const State := preload("res://scripts/mission_state.gd")
const Save := preload("res://scripts/campaign_save.gd")
var failures := 0


func _initialize() -> void:
	var grid := _grid()
	grid.time = 80.0
	_expect(grid.tick(10, 0, false, false, false) == 0 and grid.progress == 0, "No power at night means no free ice")
	grid.energy = 10
	grid.tick(5, 0, false, false, false)
	_expect(is_equal_approx(grid.energy, 5) and is_equal_approx(grid.progress, 5), "Night work uses battery energy per second")
	grid.extractor_enabled = false
	grid.tick(5, 0, false, false, false)
	_expect(is_equal_approx(grid.energy, 5) and is_equal_approx(grid.progress, 5), "Pause preserves both battery and partial batch")
	grid.extractor_enabled = true
	grid.tick(10, 0, false, false, false)
	_expect(is_zero_approx(grid.energy) and is_equal_approx(grid.progress, 10), "Empty battery stops progress exactly when energy runs out")
	grid.time = 0
	_expect(grid.tick(10, 0, false, false, false) == 2 and is_zero_approx(grid.progress), "Daylight resumes the existing partial batch once")
	_expect(grid.condition == 95 and grid.energy > 9.8, "Completed batch wears the machine and surplus generation enters storage: " + str(grid.energy))

	grid = _grid()
	grid.time = 80
	grid.energy = 0.1
	grid.tick(0.1, 0, true, false, false)
	_expect(is_equal_approx(grid.bench_fraction, 1) and is_zero_approx(grid.progress) and is_zero_approx(grid.energy), "Manufacturing gets priority when only one load can be powered")
	grid.energy = 1
	grid.tick(2, 0, true, false, false)
	_expect(is_equal_approx(grid.bench_fraction, 0.25) and is_equal_approx(grid.progress, 0.5) and is_zero_approx(grid.energy), "Shared battery powers both loads for half a second, then both power draws stop")
	grid = _grid()
	_expect(grid.tick(50, 6, false, false, false) == 0 and grid.condition == 100 and grid.energy == 40, "Stock target prevents overproduction and battery respects its capacity")
	grid.energy = 0
	grid.tick(5, 6, false, true, false)
	_expect(grid.energy == 0, "Cleaning stops solar generation until maintenance ends")

	grid = _grid()
	grid.time = 80
	grid.energy = 40
	grid.condition = 5
	grid.progress = 19.9
	_expect(grid.tick(0.2, 0, false, false, false) == 2 and grid.condition == 0, "Final worn batch completes before the machine stops")
	var broken_progress: float = grid.progress
	_expect(grid.tick(10, 0, false, false, false) == 0 and grid.progress == broken_progress, "Broken equipment produces nothing")
	grid.condition = 100
	grid.tick(1, 0, false, false, true)
	_expect(grid.progress == broken_progress, "Servicing prevents machine progress")
	grid.tick(1, 0, false, false, false)
	_expect(grid.progress > broken_progress, "Repaired equipment resumes")

	grid = _grid()
	grid.time = 149.9
	var notices: Array[String] = []
	grid.notice.connect(func(message: String): notices.append(message))
	grid.tick(0.2, 6, false, false, false)
	_expect(grid.weather_stage() == "warning" and notices.size() == 1, "Forecast occurs before the storm")
	var reloaded := Grid.new()
	_expect(reloaded.restore(grid.snapshot()), "Restore weather phase and battery")
	reloaded.notice.connect(func(message: String): notices.append(message))
	reloaded.tick(0.2, 6, false, false, false)
	_expect(notices.size() == 1, "Loading during a warning does not replay it")
	reloaded.tick(30, 6, false, false, false)
	_expect(reloaded.weather_stage() == "storm" and reloaded.cleanliness < 75 and notices.size() == 2, "Storm reduces panel output and announces once")
	_expect(reloaded.generation() < 0.5, "Dust storm lowers daylight production")
	reloaded.tick(31, 6, false, false, false)
	_expect(reloaded.weather_stage() == "clear" and notices.size() == 3, "Storm ends without erasing accumulated dust")
	for field in ["energy", "condition", "progress", "blueprint"]:
		var invalid := reloaded.snapshot()
		match field:
			"energy": invalid[field] = 41
			"condition": invalid[field] = -1
			"progress": invalid[field] = 20
			"blueprint": invalid[field] = false
		_expect(not Grid.new().restore(invalid), "Reject inconsistent power save field " + field)
	_check_campaign_save(reloaded)
	if failures == 0:
		print("PASS: battery conservation, night, partial power, stock cap, wear, service, forecast, weather persistence and power saves")
	quit(1 if failures else 0)


func _check_campaign_save(grid: RefCounted) -> void:
	Save.path = "/private/tmp/starfire-power-save-%d.json" % OS.get_process_id()
	var state := State.new(true)
	state.recovered = {"wreck": true, "ore": true}
	state.recruited = true
	state.greenhouse_built = true
	state.first_harvest = true
	state.pump_blueprint = true
	state.pump_built = true
	state.crew["tech"] = {"pos": Vector2(619, 76), "dest": Vector2(619, 76),
		"job": "", "phase": "", "elapsed": 0.0, "reserved": {}}
	state.power.restore(grid.snapshot())
	state.power.extractor_enabled = false
	state.power.progress = 7.25
	_expect(Save.write_game(state, "camp", "lead"), "Save campaign energy and partial production")
	var saved := Save.read_game()
	_expect(not saved.is_empty(), "Read valid industrial campaign")
	if not saved.is_empty():
		_expect(is_equal_approx(saved["state"].power.progress, 7.25) and not saved["state"].power.extractor_enabled,
			"Save preserves power machine progress and switch")
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Save.path))
	previous["version"] = 2
	previous["state"].erase("power")
	var file := FileAccess.open(Save.path, FileAccess.WRITE)
	file.store_string(JSON.stringify(previous))
	file.close()
	saved = Save.read_game()
	_expect(not saved.is_empty() and saved["state"].pump_built and not saved["state"].power.solar_built, "Version 2 camp loads with unfinished energy development")
	DirAccess.remove_absolute(Save.path)


func _grid() -> RefCounted:
	var grid := Grid.new()
	grid.blueprint = true
	grid.solar_built = true
	grid.extractor_built = true
	return grid


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
