extends "res://tests/work_rules.gd"


func _initialize() -> void:
	Save.path = "/private/tmp/starfire-aid-rules-%d.json" % OS.get_process_id()
	for test in ["_routes", "_expiry_and_save", "_care", "_migration"]:
		_expect(call(test) == true, test + " reaches its end")
	DirAccess.remove_absolute(Save.path)
	if "--force-fail" in OS.get_cmdline_user_args():
		_expect(false, "Intentional test-runner failure")
	if failures == 0:
		print("PASS: six aid routes, exclusive rewards, deadline refunds, resumed duties, saved timers, nursing, v4 migration and invalid saves")
	quit(1 if failures else 0)


func _prepared() -> RefCounted:
	var state := _camp()
	state.tick(0.05)
	for item in State.ITEMS:
		state.inventory[item] = 20
	return state


func _offer(state: RefCounted, offer: String) -> void:
	state.requests.next_offer = State.Requests.OFFERS.keys().find(offer)
	state.requests.cooldown = 0.05
	state.tick(0.05)
	_expect(state.requests.active == offer, "Timed announcement opens " + offer)


func _work_started(state: RefCounted, id: String) -> void:
	for step in range(300):
		state.tick(0.05)
		if state.crew[id]["phase"] == "working":
			return
	_expect(false, "Worker could not start")


func _routes() -> bool:
	var initial := State.new(true)
	_advance(initial, 200)
	_expect(initial.requests.active.is_empty() and initial.requests.cooldown == 45, "No aid pressure before first harvest")
	for recipe in State.Requests.RECIPES:
		var state := _prepared()
		var spec: Dictionary = State.RECIPES[recipe]
		_offer(state, spec["request"])
		var before: Dictionary = state.inventory.duplicate()
		_expect(state.assign("lead", recipe), "Accept " + recipe)
		_expect(not state.assign("tech", state.requests.choices()[1]), "Only one neighbor delivery occupies the relay")
		_work_started(state, "lead")
		_expect(state.requests.completed == 0, "Walking and reserving cannot grant rewards")
		for step in range(600):
			state.tick(0.05)
			if state.requests.completed > 0:
				break
		for item in State.ITEMS:
			_expect(state.inventory[item] == before[item] - spec["cost"].get(item, 0) + spec["out"].get(item, 0), "Exact settlement: " + recipe + "/" + item)
		_expect(state.requests.completed == 1 and state.requests.active.is_empty() and state.requests.care_health() == 45, "One delivery resolves the request and shares nursing knowledge")
		var stock: Dictionary = state.inventory.duplicate()
		for alternative in State.Requests.OFFERS[spec["request"]]["choices"]:
			_expect(not state.assign("lead", alternative), "Both alternatives close after completion")
		_expect(stock == state.inventory, "Rejected duplicate claims never change inventory")
		_advance(state, 90.1)
		var next: int = (State.Requests.OFFERS.keys().find(spec["request"]) + 1) % 3
		_expect(state.requests.active == State.Requests.OFFERS.keys()[next], "Another type arrives after cooldown")
	return true


func _expiry_and_save() -> bool:
	var state := _prepared()
	_offer(state, "water")
	_expect(state.set_order("lead", "mine", "stock", 22), "Set a home duty")
	_expect(state.assign("lead", "aid_water"), "Temporary aid preserves the home duty")
	_work_started(state, "lead")
	state.requests.remaining = 1.0
	var ice: int = state.inventory["ice"]
	var circuits: int = state.inventory["circuit"]
	_expect(Save.write_game(state, "camp", "lead"), "Save active timed aid")
	var saved := Save.read_game()
	_expect(not saved.is_empty(), "Read active timed aid")
	if saved.is_empty():
		return false
	state = saved["state"]
	_expect(state.requests.remaining == 1 and state.crew["lead"]["reserved"] == {"ice": 4}, "Timer and reservation restored without offline progression")
	_advance(state, 1.05)
	_expect(state.requests.expired == 1 and state.requests.completed == 0 and state.inventory["ice"] == ice + 4 and state.inventory["circuit"] == circuits, "Deadline refunds an unfinished delivery without reward")
	_expect(state.crew["lead"]["job"] == "mine", "Expiry resumes the saved duty")
	_advance(state, 20)
	_expect(state.inventory["ore"] == 22 and state.inventory["ice"] == ice + 4, "Duty produces again, refund happens only once")
	state = _prepared()
	_offer(state, "water")
	state.assign("lead", "aid_water")
	state.requests.remaining = 0.05
	state.tick(0.05)
	_expect(state.inventory["ice"] == 20 and state.requests.expired == 1, "Expiry while walking refunds nothing and grants nothing")
	state = _prepared()
	_offer(state, "water")
	state.assign("lead", "aid_water")
	_work_started(state, "lead")
	state.stop_crew("lead")
	_expect(state.inventory["ice"] == 20 and state.requests.active == "water", "Manual cancellation refunds and leaves the choice open")
	_expect(state.assign("lead", "aid_repair"), "Can choose the alternate route after cancellation")
	_work_started(state, "lead")
	state.crew["lead"]["elapsed"] = state._duration("aid_repair") - 0.01
	state.requests.remaining = 0.05
	state.tick(0.05)
	_expect(state.requests.completed == 0 and state.inventory["plate"] == 20 and state.inventory["circuit"] == 20, "Deadline wins when delivery would finish in the same tick")
	return true


func _care() -> bool:
	var state := _prepared()
	var stock: Dictionary = state.inventory.duplicate()
	_expect(not state.assign("tech", "camp_care") and state.inventory == stock, "Healthy crew cannot spend care supplies")
	state.crew["tech"]["health"] = 55.0
	state.crew["tech"]["stamina"] = 10.0
	state.set_order("tech", "mine", "stock", 22)
	_expect(state.assign("tech", "camp_care"), "Exhausted injured crew can request care")
	_work_started(state, "tech")
	_expect(state.crew["tech"]["job"] == "camp_care" and state.crew["tech"]["phase"] == "working", "Care does not wait for automatic full rest")
	_expect(Save.write_game(state, "camp", "tech"), "Save care in progress")
	var saved := Save.read_game()
	_expect(not saved.is_empty(), "Read care in progress")
	if saved.is_empty():
		return false
	state = saved["state"]
	_advance(state, 17)
	_expect(state.crew["tech"]["health"] >= 85 and state.crew["tech"]["health"] < 90 and state.crew["tech"]["stamina"] > 35, "Paid care restores health and stamina before full rest would")
	_expect(state.crew["tech"]["job"] == "mine" and state.inventory["ice"] == 19 and state.inventory["food"] == 19, "Care consumes once and resumes the original duty")
	state.stop_crew("tech")
	state.requests.completed = 1
	state.crew["tech"]["health"] = 70
	state.assign("tech", "camp_care")
	_advance(state, 20)
	_expect(state.crew["tech"]["health"] == 100 and state.crew["tech"]["stamina"] <= 100, "Shared care is stronger and bounded by 100")
	return true


func _migration() -> bool:
	var state := _prepared()
	state.crew["lead"]["pos"] = Vector2(99, 440)
	state.crew["lead"]["dest"] = Vector2(99, 440)
	_expect(state.layout.move_site(state, "greenhouse", Vector2(176, 288)), "Arrange a camp before migration")
	state.expeditions.resolved = {"cargo": "scout_parts"}
	var encoded: Dictionary = Save._encode(state)
	encoded.erase("requests")
	var file := FileAccess.open(Save.path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 4, "state": encoded, "region": "camp", "selected": "lead"}))
	file.close()
	var saved := Save.read_game()
	_expect(not saved.is_empty(), "Version 4 loads with new aid defaults")
	if saved.is_empty():
		return false
	_expect(saved["state"].layout.snapshot() == state.layout.snapshot() and saved["state"].expeditions.snapshot() == state.expeditions.snapshot(), "Version 4 migration preserves moved facilities and exploration choices")
	state = _prepared()
	_offer(state, "water")
	state.assign("lead", "aid_water")
	_work_started(state, "lead")
	encoded = Save._encode(state)
	for bad in [{"active": "unknown"}, {"remaining": 151}, {"remaining": 0}, {"cooldown": 1}, {"next_offer": 0}, {"completed": 0.5}]:
		var invalid: Dictionary = encoded.duplicate(true)
		invalid["requests"].merge(bad, true)
		_expect(Save._decode(invalid) == null, "Reject inconsistent aid state " + str(bad))
	encoded["requests"]["active"] = "supplies"
	encoded["requests"]["next_offer"] = 2
	_expect(Save._decode(encoded) == null, "An active saved job must belong to the active request")
	return true
