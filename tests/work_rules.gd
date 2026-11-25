extends SceneTree

const State := preload("res://scripts/mission_state.gd")
const Save := preload("res://scripts/campaign_save.gd")
var failures := 0


func _initialize() -> void:
	Save.path = "/private/tmp/starfire-work-rules-%d.json" % OS.get_process_id()
	var state := _camp()
	state.inventory["scrap"] = 6
	_expect(state.set_order("tech", "fabricate", "batch", 3), "Assign finite manufacturing order")
	for step in range(1000):
		state.tick(0.05)
		if state.inventory["plate"] == 1 and state.crew["tech"]["phase"] == "working":
			break
	_expect(state.crew["tech"]["duty"]["remaining"] == 2, "Only completed batches reduce the outstanding order")
	_expect(Save.write_game(state, "camp", "tech"), "Save partially completed order")
	var saved := Save.read_game()
	_expect(not saved.is_empty(), "Load order with reserved next batch")
	if not saved.is_empty():
		var restored: RefCounted = saved["state"]
		restored.stop_crew("tech")
		_expect(restored.inventory["plate"] == 1 and restored.inventory["scrap"] == 4 and restored.crew["tech"]["duty"].is_empty(), "Cancel after reload refunds only the unfinished batch")

	state = _camp()
	state.crew["lead"]["stamina"] = 10.0
	_expect(state.assign("lead", "salvage"), "Tired crew can accept a task")
	_advance(state, 5)
	_expect(state.crew["lead"]["phase"] == "resting" and state.inventory["scrap"] == 0, "Tired crew rests before starting the batch")
	_expect(Save.write_game(state, "camp", "lead"), "Save automatic rest")
	saved = Save.read_game()
	_expect(not saved.is_empty(), "Read automatic rest with a pending task")
	if not saved.is_empty():
		_advance(saved["state"], 50)
		_expect(saved["state"].inventory["scrap"] == 3 and saved["state"].crew["lead"]["job"].is_empty(), "Rested crew completes the pending task once")

	state = _camp()
	_expect(state.set_order("lead", "extract", "stock", 6), "Assign home duty before departure")
	_expect(state.assign("lead", "depart"), "Temporary expedition interrupts duty")
	_advance(state, 25)
	_expect(state.crew_region("lead") == "highlands" and state.crew["lead"]["job"].is_empty() and state.inventory["ice"] == 0, "Field worker does not produce remotely")
	_expect(state.assign("lead", "return"), "Return to home region")
	_advance(state, 55)
	_expect(state.crew_region("lead") == "camp" and state.crew["lead"]["job"] == "extract" and state.inventory["ice"] == 6, "Returned crew resumes their stock policy")

	var generalist := _camp()
	var specialist := _camp()
	generalist.inventory["ice"] = 1
	specialist.inventory["ice"] = 1
	specialist.crew["botanist"] = specialist.crew["tech"].duplicate(true)
	specialist.crew.erase("tech")
	generalist.assign("lead", "grow")
	specialist.assign("botanist", "grow")
	while generalist.crew["lead"]["phase"] == "travel":
		generalist.tick(0.05)
	while specialist.crew["botanist"]["phase"] == "travel":
		specialist.tick(0.05)
	_advance(generalist, 6.5)
	_advance(specialist, 6.5)
	_expect(generalist.crew["lead"]["phase"] == "working" and specialist.crew["botanist"]["job"].is_empty(), "Agronomy specialty changes actual work completion time")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: partial batch refund, automatic rest, expedition duty suspension/return and specialty work speed")
	quit(1 if failures else 0)


func _camp() -> RefCounted:
	var state := State.new(true)
	state.recovered = {"wreck": true, "ore": true}
	state.recruited = true
	state.greenhouse_built = true
	state.first_harvest = true
	state.blueprint = true
	state.won = true
	state.inventory["food"] = 30
	state.crew["tech"] = {"pos": Vector2(619, 76), "dest": Vector2(619, 76),
		"job": "", "phase": "", "elapsed": 0.0, "reserved": {}}
	return state


func _advance(state: RefCounted, seconds: float) -> void:
	for step in range(roundi(seconds * 20)):
		state.tick(0.05)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
