extends "res://tests/frontier_play.gd"


func _play() -> void:
	Save.path = "/private/tmp/starfire-tool-play-%d.json" % OS.get_process_id()
	change_scene_to_file("res://scenes/title.tscn")
	await scene_changed
	_click(_center(current_scene.start_button))
	await scene_changed
	var game := current_scene
	game.set_process(false)
	game.feedback.sound_enabled = false
	_expect(game.state.tool_holder.is_empty(), "A fresh camp may choose its tool holder")
	_click(_center(game.sites["wreck"]), MOUSE_BUTTON_RIGHT)
	_until_working(game, "lead")
	var elapsed: float = game.state.crew["lead"]["elapsed"]
	_advance(game, 0.5)
	var baseline: float = game.state.crew["lead"]["elapsed"] - elapsed
	var supplies: Dictionary = game.state.inventory.duplicate()
	await _drag(_center(game.items["tool"]), _center(game.crew_cards["lead"]))
	_expect(game.state.tool_holder == "lead" and game.crew_cards["lead"].tool_equipped and "领队" in game.items["tool"].caption,
		"Dragging the one tool onto the worker records and displays the recipient")
	_expect(game.state.inventory == supplies and game.state.crew["lead"]["job"] == "salvage",
		"Equipment transfer neither spends materials nor interrupts the current batch")
	elapsed = game.state.crew["lead"]["elapsed"]
	_advance(game, 0.5)
	_expect(is_equal_approx(game.state.crew["lead"]["elapsed"] - elapsed, baseline * 1.25),
		"The same salvage batch immediately runs 25 percent faster")
	await _capture("equipped_worker")
	_advance(game, 12)
	_run_job(game, "ore", "mine")
	_run_job(game, "casualty", "rescue")
	_click(_center(game.crew_buttons["tech"]))
	_click(_center(game.items["tool"]))
	_expect(game.action_button.visible and not game.action_button.disabled and "勘探员" in game.action_button.text,
		"A click-only transfer is available for the selected crew")
	_click(_center(game.action_button))
	_expect(game.state.tool_holder == "tech" and not game.crew_cards["lead"].tool_equipped and game.crew_cards["tech"].tool_equipped and game.action_button.disabled,
		"Transfer changes exactly one owner and repeated transfer is unavailable")
	_run_job(game, "greenhouse", "build")
	_run_job(game, "ice", "extract")
	_run_job(game, "greenhouse", "grow")
	_click(_center(game.crew_buttons["lead"]))
	_run_job(game, "ore", "mine")
	_click(_center(game.crew_buttons["tech"]))
	_click(_center(game.scout_button))
	_click(_center(game.expedition_buttons["scout_scrap"]))
	_expect(game.state.crew["tech"]["job"] == "scout_scrap", "Dispatch the equipped explorer: " + game.log_line.text + ", selected " + game.selected_crew)
	_click(_center(game.crew_buttons["lead"]))
	_click(_center(game.items["tool"]))
	_expect(game.action_button.disabled and game.state.tool_holder == "tech", "A crew walking to departure cannot pass the tool")
	_until_working(game, "tech")
	await _drag(_center(game.items["tool"]), _center(game.crew_cards["lead"]))
	_expect(game.state.tool_holder == "tech" and not game.state.equip_tool("lead"), "Tool carried in the field cannot be dragged or assigned back to camp")
	game = await _save_reload(game)
	_expect(game.state.crew_away("tech") and game.state.tool_holder == "tech" and not game.state.equip_tool("lead"), "Continuing a trip keeps its equipment on the travelling crew")
	var saved: Dictionary = Save._encode(game.state)
	saved["tool_holder"] = "botanist"
	_expect(Save._decode(saved) == null, "Reject ownership assigned to an absent crew member")
	_advance(game, 35)
	await _drag(_center(game.items["tool"]), _center(game.crew_cards["lead"]))
	_expect(game.state.tool_holder == "lead" and game.state.inventory["tool"] == 1, "After return, the same single tool can be transferred again")
	_click(_center(game.crew_buttons["tech"]))
	_run_job(game, "lab", "research")
	_run_job(game, "wreck", "salvage")
	_click(_center(game.sites["bench"]), MOUSE_BUTTON_RIGHT)
	_until_working(game, "tech")
	elapsed = game.state.crew["tech"]["elapsed"]
	_advance(game, 0.5)
	baseline = game.state.crew["tech"]["elapsed"] - elapsed
	await _drag(_center(game.items["tool"]), _center(game.crew_cards["tech"]))
	elapsed = game.state.crew["tech"]["elapsed"]
	_advance(game, 0.5)
	_expect(is_equal_approx(game.state.crew["tech"]["elapsed"] - elapsed, baseline * 1.25),
		"Giving the tool to a fabricator also combines with their specialty")
	_advance(game, 15)
	await _drag(_center(game.items["tool"]), _center(game.crew_cards["lead"]))
	_click(_center(game.crew_buttons["tech"]))
	_run_job(game, "relay", "trade_food")
	_run_job(game, "beacon", "repair")
	_run_job(game, "beacon", "depart")
	_expect(game.state.crew_region("tech") == "highlands" and not game.state.equip_tool("tech") and game.state.tool_holder == "lead", "A worker already at the highlands cannot remotely receive the camp tool")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: equipment drag, click transfer, immediate work rate, single holder, transit protection, remote region and saved ownership")
	quit(1 if failures else 0)


func _until_working(game: Control, id: String) -> void:
	for step in range(300):
		if game.state.crew[id]["phase"] == "working":
			return
		_advance(game, 0.05)
	_expect(false, "Reach active work for " + id)
