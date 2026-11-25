extends "res://tests/frontier_play.gd"


func _play() -> void:
	Save.path = "/private/tmp/starfire-gear-patrol-%d.json" % OS.get_process_id()
	change_scene_to_file("res://scenes/title.tscn")
	await scene_changed
	if "--compact" in OS.get_cmdline_user_args():
		root.size = Vector2i(960, 640)
		await process_frame
	_click(_center(current_scene.start_button))
	await scene_changed
	var game := current_scene
	game.set_process(false)
	game.feedback.sound_enabled = false
	_run_job(game, "wreck", "salvage")
	_run_job(game, "ore", "mine")
	_run_job(game, "casualty", "rescue")
	_click(_center(game.crew_buttons["lead"]))
	_run_job(game, "greenhouse", "build")
	for i in range(4):
		_run_job(game, "ice", "extract")
	for i in range(2):
		_run_job(game, "greenhouse", "grow")
	await create_timer(1.3).timeout
	_click(_center(game.scout_button))
	_expect(game.patrol_buttons["patrol_ice"].disabled, "One real discovery is required to start patrolling")
	_click(_center(game.gear_button))
	var board: Control = game.gear_board
	var original: Dictionary = game.state.inventory.duplicate()
	await _drag(_center(board.material_cards["scrap"]), _center(board.tray_target))
	_click(_center(board.material_cards["ore"]))
	_click(_center(board.tray_cards[1]))
	_expect(game.state.field_gear.tray == ["scrap"] and game.state.inventory["ore"] == original["ore"] and board.assemble_button.disabled, "Dragging stages one card and removing another refunds it")
	_click(_center(board.close_button))
	_key(KEY_ESCAPE)
	game = await _save_reload(game)
	_click(_center(game.scout_button))
	_click(_center(game.gear_button))
	board = game.gear_board
	_expect(game.state.field_gear.tray == ["scrap"] and game.state.inventory["scrap"] == original["scrap"] - 1, "Continue keeps the staged card out of storage exactly once")
	_click(_center(board.material_cards["ice"]))
	_click(_center(board.material_cards["scrap"]))
	_expect(not board.assemble_button.disabled, "Reordered ingredient cards unlock the cooler recipe")
	await _capture("gear_tray")
	_click(_center(board.assemble_button))
	_expect(game.state.field_gear.built.has("cooler") and game.state.field_gear.equipped.is_empty(), "Assembly leaves the backpack slot available")
	_click(_center(board.equip_buttons["cooler"]))
	_click(_center(board.close_button))
	_expect("口粮×1" in game.route_details["scout_blueprint"].text and "残件×1" in game.route_details["scout_blueprint"].text, "Expedition cards show the equipped cooler's real multi-item cost")
	var food: int = game.state.inventory["food"]
	_click(_center(game.expedition_buttons["scout_parts"]))
	_click(_center(game.scout_button))
	_click(_center(game.gear_button))
	_expect(game.gear_board.equip_buttons["cooler"].disabled, "The backpack locks on dispatch before walking to the departure site")
	_key(KEY_ESCAPE)
	_click(_center(game.expedition_recall))
	_expect(game.state.crew["lead"]["job"].is_empty() and game.state.inventory["food"] == food, "Cancel before departure leaves all food available")
	_click(_center(game.scout_button))
	_click(_center(game.expedition_buttons["scout_parts"]))
	_advance_until_away(game)
	_expect(game.state.crew["lead"]["reserved"] == {"food": 1}, "Food charged on departure matches the cooler card")
	_finish_trip(game, "scout_parts")
	_click(_center(game.scout_button))
	_expect(not game.patrol_buttons["patrol_ice"].disabled, "Returning from the cargo site unlocks the resupply routes")
	_click(_center(game.gear_button))
	board = game.gear_board
	_click(_center(board.material_cards["plate"]))
	await _drag(_center(board.material_cards["ore"]), _center(board.tray_cards[0]))
	_click(_center(board.material_cards["ore"]))
	_click(_center(board.assemble_button))
	_click(_center(board.equip_buttons["winch"]))
	_click(_center(board.close_button))
	_expect("健康 −2" in game.route_details["patrol_ridge"].text and "29 秒" in game.route_details["patrol_ridge"].text and "健康 −4" in game.route_details["scout_ore"].text, "Winch route cards disclose reduced time and wounds")
	_check_exploration_layout(game)
	await _capture("gear_routes")
	_click(_center(game.patrol_buttons["patrol_ridge"]))
	_advance_until_away(game)
	_advance(game, 2)
	var before: Dictionary = game.state.inventory.duplicate()
	var health: float = game.state.crew["lead"]["health"]
	var elapsed: float = game.state.crew["lead"]["elapsed"]
	game = await _save_reload(game)
	_expect(game.state.field_gear.equipped == "winch" and is_equal_approx(game.state.crew["lead"]["elapsed"], elapsed) and game.state.crew["lead"]["reserved"] == {"food": 2, "ice": 1}, "Save and continue restore the active patrol, pack, payment and timer")
	_finish_patrol(game, 1)
	_expect(game.state.inventory["ore"] == before["ore"] + 3 and game.state.inventory["plate"] == before["plate"] + 1 and is_equal_approx(game.state.crew["lead"]["health"], health - 2), "High ridge rewards and wound settle together once")
	_expect("健康 −2" in game.log_line.text and game.state.expeditions.resolved.size() == 1, "Arrival reports actual injury and leaves finite discoveries unchanged")
	_click(_center(game.scout_button))
	_expect(game.patrol_buttons["patrol_ice"].disabled and game.patrol_buttons["patrol_ridge"].disabled, "The two routes share one resupply window")
	_key(KEY_ESCAPE)
	game = await _save_reload(game)
	_expect(game.state.expeditions.patrol_wait(game.state.clock) == 90, "Loading the camp preserves the next departure time")
	_run_job(game, "greenhouse", "grow")
	_advance(game, 90)
	_click(_center(game.scout_button))
	_click(_center(game.gear_button))
	_click(_center(game.gear_board.equip_buttons["cooler"]))
	_key(KEY_ESCAPE)
	_click(_center(game.patrol_buttons["patrol_ice"]))
	_advance_until_away(game)
	_expect(game.state.crew["lead"]["reserved"] == {"food": 1}, "Next window accepts a different route and module")
	before = game.state.inventory.duplicate()
	_finish_patrol(game, 2)
	_expect(game.state.inventory["ice"] == before["ice"] + 3 and game.state.inventory["scrap"] == before["scrap"] + 2, "A repeat patrol brings a different reward into camp")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: menu-to-patrol, drag and refund, staged save, both modules, dispatch lock, cancellation, displayed and charged supplies, two patrol windows, field save and return rewards")
	quit(1 if failures else 0)


func _finish_patrol(game: Control, goal: int) -> void:
	for step in range(1800):
		game.state.tick(0.05)
		if game.state.expeditions.patrol_count == goal:
			game._refresh()
			return
	_expect(false, "Expected patrol return: " + str(game.state.crew["lead"]) + " / " + game.log_line.text)
