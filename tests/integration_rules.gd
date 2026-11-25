extends "res://tests/work_rules.gd"


func _initialize() -> void:
	Save.path = "/private/tmp/starfire-integration-rules-%d.json" % OS.get_process_id()
	var state := _camp()
	_expect(state.set_order("lead", "extract", "stock", 6), "Set a home duty before fieldwork")
	_expect(state.assign("lead", "depart"), "Accept a region journey")
	_expect(state.camp_diners() == 2, "Crew still walking to departure eats in camp")
	for step in range(300):
		state.tick(0.05)
		if state.crew_away("lead"):
			break
	_expect(state.crew_away("lead") and state.camp_diners() == 1, "Crew in region transit is absent from camp meals")
	var paid: Dictionary = state.crew["lead"]["reserved"].duplicate()
	var food: int = state.inventory["food"]
	state._ration_clock = 59.9
	state.tick(0.2)
	_expect(state.inventory["food"] == food - 1, "Transport rations are not paid twice")
	var before: Dictionary = state.crew["lead"].duplicate(true)
	_expect(not state.assign("lead", "salvage"), "Transit cannot be silently replaced by a camp task")
	state.rest_crew("lead")
	state.move_crew("lead", Vector2(500, 350))
	_expect(state.crew["lead"] == before, "Rest and move cannot interrupt a departed worker")
	_expect(Save.write_game(state, "camp", "lead"), "Save region journey with home duty")
	var saved := Save.read_game()
	_expect(not saved.is_empty(), "Load active region journey")
	if not saved.is_empty():
		var resumed: RefCounted = saved["state"]
		food = resumed.inventory["food"]
		resumed.recall_crew("lead")
		_expect(resumed.inventory["food"] == food + paid["food"] and resumed.crew["lead"]["job"] == "extract" and resumed.crew["lead"]["duty"]["target"] == 6,
			"Recall after load preserves the original stock policy and refunds only reserved supplies")
		resumed.recall_crew("lead")
		_expect(resumed.inventory["food"] == food + paid["food"], "Repeat recall cannot refund twice")
		_advance(resumed, 45)
		_expect(resumed.inventory["ice"] == 6, "The preserved duty actually resumes production")
		resumed.stop_crew("lead")
		_expect(resumed.crew["lead"]["duty"].is_empty(), "Explicit stop still clears the duty")
	state = _camp()
	state.assign("lead", "depart")
	_advance(state, 25)
	state.assign("lead", "return")
	for step in range(300):
		state.tick(0.05)
		if state.crew_away("lead"):
			break
	food = state.inventory["food"]
	state.recall_crew("lead")
	_expect(state.crew_region("lead") == State.HIGHLANDS and state.inventory["food"] == food,
		"Canceling the return trip stays at its highland origin and grants no refund")
	_expect(state.assign("lead", "return"), "Canceled return can be arranged again")
	_advance(state, 25)
	_expect(state.crew_region("lead") == State.CAMP, "Returning again reaches camp normally")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: consistent transport meals, remote restrictions, saved recall, single refund and restored stock policy")
	quit(1 if failures else 0)
