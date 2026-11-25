extends RefCounted


static func current(state: RefCounted) -> Dictionary:
	var goal: Dictionary
	if not state.survey_complete():
		var first: bool = not state.recovered.has("wreck")
		goal = _goal("勘察迫降点", [
			_row(state.recovered.has("wreck"), "选择着陆舱的打捞物资"),
			_row(state.recovered.has("ore"), "采集附近矿物样本")],
			"wreck" if first else "ore", "salvage" if first else "mine", "查看采集点")
	elif not state.recruited:
		goal = _goal("回应求救信号", ["●  完成迫降点勘察", "○  携带 1 份口粮救助勘探员"], "casualty", "rescue", "定位求救信号")
	elif not state.first_harvest:
		var recipe := "build" if not state.greenhouse_built else ("extract" if state.inventory["ice"] == 0 else "grow")
		goal = _goal("建立营地补给", [_row(state.greenhouse_built, "搭建密封温室"), "○  用水冰培育首批口粮"],
			state.RECIPES[recipe]["site"], recipe, "查看首批补给任务")
	elif not state.won:
		var recipe := "research"
		if state.blueprint:
			recipe = "fabricate" if state.inventory["plate"] < 1 else ("trade_food" if state.inventory["circuit"] < 1 else "repair")
		var repairer: String = state.active_at("beacon")
		if not repairer.is_empty() and state.crew[repairer]["job"] == "repair":
			recipe = "repair"
		goal = _goal("恢复轨道通信", [_row(state.blueprint, "研究信标维修蓝图"),
			_row(state.inventory["plate"] >= 1 and state.inventory["circuit"] >= 1 or state.crew.values().any(func(unit: Dictionary): return unit["job"] == "repair"), "备齐结构件和电路"),
			"○  修复通信信标"], state.RECIPES[recipe]["site"], recipe, "查看归航准备任务")
	elif not state.first_record_uploaded():
		var recipe := "deliver"
		if state.outpost_supplied and not state.outpost_built:
			recipe = "establish_outpost"
		elif state.outpost_built and not state.navigation_record:
			recipe = "survey_archive"
		goal = _goal("寻找归航航标", [_row(state.highlands_visited, "派队员前往北缘高地"),
			_row(state.navigation_record, "回收旧测绘站航标"), _row(state.outpost_built, "运送物资并架设前哨")],
			state.RECIPES[recipe]["site"], recipe, "定位航标任务")
	elif not state.array_calibrated:
		var recipe := "exchange_calibration" if not state.calibration_blueprint else ("calibrate_array" if state.array_supplied else "deliver_array")
		goal = _goal("恢复第二份航标", [_row(state.calibration_blueprint, "交换或研究校准蓝图"),
			_row(state.array_supplied, "从信标运送阵列设备"), "○  在高地修复测向阵列"],
			state.RECIPES[recipe]["site"], recipe, "定位航标任务")
	else:
		return _homeward_goal(state)
	# Alerts guide the next click; they never assign work or replace the main goal.
	if state.recruited and state.greenhouse_built and state.camp_diners() > 0:
		var farmer: String = state.active_at("greenhouse")
		var waiting_for_ice: bool = not farmer.is_empty() and state.crew[farmer]["job"] == "grow" and state.crew[farmer]["phase"] == "waiting" and state.inventory["ice"] == 0
		if waiting_for_ice:
			goal.merge({"site": "ice", "recipe": "extract", "cta": "温室缺水 · 查看采冰任务", "alert": true}, true)
		elif state.inventory["food"] < state.camp_diners() and (farmer.is_empty() or state.crew[farmer]["job"] != "grow"):
			var recipe := "extract" if state.inventory["ice"] == 0 else "grow"
			goal.merge({"site": state.RECIPES[recipe]["site"], "recipe": recipe, "cta": "口粮不足 · 查看补给任务", "alert": true}, true)
	return goal


static func _homeward_goal(state: RefCounted) -> Dictionary:
	if state.homeward_launched:
		return _goal("归航成功", ["●  三份航标已同步", "●  领队已踏上归途"], "beacon", "launch_homeward", "归航记录")
	if state.third_record_source.is_empty():
		var survey: bool = state.crew.values().any(func(unit: Dictionary): return unit.get("region") == state.HIGHLANDS)
		return _goal("寻找最后一份航标", ["●  已同步 2 / 3 份航标", "○  到高地阵列追踪远端信号", "或  到曙光站交换测绘记录"],
			"array" if survey else "relay", "survey_last_record" if survey else "exchange_last_record", "定位高地阵列" if survey else "查看邻站报价")
	if not state.return_craft_ready:
		return _goal("组装归航舱", ["●  三份航标已拼成航线", "○  备齐 3 结构件、2 电路", "○  到着陆舱残骸完成组装"], "wreck", "assemble_return_craft", "查看归航舱工位")
	if state.crew_region("lead") == state.HIGHLANDS:
		return _goal("接领队返营", ["●  归航舱已就绪", "○  领队从高地接驳点返营"], "trail", "return", "定位领队返程点")
	return _goal("点火归航", ["●  归航舱已就绪", "○  领队携 3 口粮、2 水冰", "○  在通信信标发出起航指令"], "beacon", "launch_homeward", "定位起航点")


static func _goal(title: String, lines: Array, site: String, recipe: String, cta: String) -> Dictionary:
	return {"title": title, "text": "\n".join(lines), "site": site, "recipe": recipe, "cta": cta, "alert": false}


static func _row(done: bool, text: String) -> String:
	return ("●  " if done else "○  ") + text
