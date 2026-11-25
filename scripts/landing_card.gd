extends "res://scripts/card_view.gd"

const ATLAS := preload("res://assets/art/opening_atlas.png")
const TOOL := preload("res://assets/icons/wrench.svg")
const REGIONS := {
	"lead": Rect2(116, 10, 289, 489),
	"wreck": Rect2(520, 10, 473, 483),
	"ore": Rect2(1070, 64, 438, 393),
	"food": Rect2(44, 558, 422, 432),
	"scrap": Rect2(526, 566, 464, 392),
	"sample": Rect2(1064, 575, 432, 375),
}

var finished := false
var accepted_items: PackedStringArray = []
signal drag_started(payload: Dictionary)
var drop_check: Callable
var drop_active := false
var drop_valid := false
var drop_waiting := false
var worker_name := ""
var worker_tint := Color.WHITE
var work_recipe := ""
var material_flow := ""
var reduced_motion := false
var relocatable := false
var tool_equipped := false:
	set(value):
		if tool_equipped != value:
			tool_equipped = value
			queue_redraw()
var _pulse: Tween
var _receipt_amount := 0
var _receipt_left := 0.0


func _ready() -> void:
	set_process(false)


func mark_received(count: int) -> void:
	if count <= 0:
		return
	_receipt_amount = count
	_receipt_left = 3.5
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_receipt_left = maxf(0, _receipt_left - delta)
	if _receipt_left == 0:
		_receipt_amount = 0
		set_process(false)
	queue_redraw()


func show_work_stack(state: RefCounted, worker: String) -> void:
	var name_text := ""
	var job_text := ""
	var flow := ""
	var tint := MARS
	if not worker.is_empty():
		var unit: Dictionary = state.crew[worker]
		name_text = state.CREW_NAMES[worker]
		tint = {"lead": MARS, "tech": ICE, "botanist": Color("#b4d58c")}.get(worker, MARS)
		if unit["phase"] == "working":
			var job: String = unit["job"]
			job_text = state.RECIPES[job]["label"]
			var paid: Dictionary = unit["reserved"]
			var output: Dictionary = state.production_output(job)
			flow = _flow_text(state.ITEMS, paid, output)
			if font_face.get_string_size(flow, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x > size.x - 18:
				var brief := {"food": "粮", "scrap": "残", "ore": "矿", "ice": "冰", "plate": "件", "circuit": "电"}
				flow = _flow_text(brief, paid, output)
	if worker_name != name_text or work_recipe != job_text or material_flow != flow:
		worker_name = name_text
		worker_tint = tint
		work_recipe = job_text
		material_flow = flow
		queue_redraw()


func _flow_text(names: Dictionary, inputs: Dictionary, outputs: Dictionary) -> String:
	var left := PackedStringArray()
	var right := PackedStringArray()
	for item in inputs:
		left.append("%s%d" % [names.get(item, item), inputs[item]])
	for item in outputs:
		right.append("%s%d" % [names.get(item, item), outputs[item]])
	if left.is_empty():
		return "" if right.is_empty() else "产出 " + " ".join(right)
	if right.is_empty():
		return "投入 " + " ".join(left)
	return " ".join(left) + " → " + " ".join(right)


func _get_drag_data(_at: Vector2) -> Variant:
	if kind == "site" and relocatable:
		var preview := Control.new()
		var card: Control = get_script().new()
		card.configure(key, kind, heading, font_face, title_face)
		card.size = size
		card.position = -size / 2
		card.modulate.a = 0.7
		card.caption = "移动设施 · 空地松手"
		card.mouse_filter = MOUSE_FILTER_IGNORE
		preview.add_child(card)
		set_drag_preview(preview)
		var payload := {"kind": "facility", "id": key}
		drag_started.emit(payload)
		return payload
	if kind == "item":
		var data: Variant = super._get_drag_data(_at)
		if data is Dictionary:
			drag_started.emit(data)
		return data
	if kind != "crew":
		return null
	var preview := Control.new()
	var sprite := TextureRect.new()
	var region := AtlasTexture.new()
	region.atlas = ATLAS
	region.region = REGIONS["lead"]
	sprite.texture = region
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.size = Vector2(58, 75)
	sprite.position = -sprite.size / 2
	sprite.modulate = Color(0.79, 1.0, 1.0, 0.9) if key == "tech" else Color(1, 1, 1, 0.9)
	sprite.mouse_filter = MOUSE_FILTER_IGNORE
	preview.add_child(sprite)
	set_drag_preview(preview)
	var payload := {"kind": "crew", "id": key}
	drag_started.emit(payload)
	return payload


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if kind == "crew" and data is Dictionary and data.get("kind") == "item" and data.get("id") == "tool":
		return drop_check.is_valid() and drop_check.call(data, true).get("allowed", false)
	if kind != "site" or not data is Dictionary:
		return false
	if drop_check.is_valid():
		return drop_check.call(data, true).get("allowed", false)
	return data.get("kind") == "crew" or (data.get("kind") == "item" and data.get("id") in accepted_items)


func pop() -> void:
	if _pulse:
		_pulse.kill()
	scale = Vector2.ONE
	if reduced_motion:
		return
	pivot_offset = size / 2
	scale = Vector2(1.035, 0.97)
	_pulse = create_tween()
	_pulse.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if font_face == null:
		return
	match kind:
		"item":
			_draw_inventory()
		"crew", "site":
			_draw_map_card()


func _draw_map_card() -> void:
	var tone := MARS
	if finished or key in ["tech", "botanist", "ice", "greenhouse", "outpost", "shelter", "radar_lens"]:
		tone = ICE
	elif key == "casualty":
		tone = RED
	var is_actor := kind == "crew"
	var image_height := size.y - 54.0
	var border := Color("#785747")
	if selected or hovered:
		border = tone
	if drop_active:
		border = (ORE if drop_waiting else ICE) if drop_valid else Color("#624d45")
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.12, 0.085, 0.075, 0.62)
	box.border_color = border
	box.set_border_width_all(3 if drop_active and drop_valid else (2 if selected else 1))
	box.set_corner_radius_all(8)
	box.shadow_color = Color(0.09, 0.05, 0.05, 0.38)
	box.shadow_size = 8
	box.shadow_offset = Vector2(1, 4)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	if key in ["tech", "botanist"]:
		_draw_art("lead", Rect2(8, 6, size.x - 16, image_height - 11), Color("#c9ffff") if key == "tech" else Color("#c9ef99"))
	elif REGIONS.has(key):
		_draw_art(key, Rect2(8, 6, size.x - 16, image_height - 11))
	else:
		_draw_badge(Vector2(size.x / 2, image_height / 2), tone)
	draw_line(Vector2(8, image_height), Vector2(size.x - 8, image_height), border)
	var title_size := 16 if is_actor else 18
	draw_string(title_face, Vector2(0, image_height + 22), heading,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, title_size, INK)
	var detail := caption
	if not work_recipe.is_empty():
		detail = work_recipe.trim_prefix("互助 · ").trim_suffix(" · 完成后归岗")
	draw_string(font_face, Vector2(0, image_height + 41), detail,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, tone)
	if not worker_name.is_empty():
		_draw_worker_tab(image_height)
	if is_actor and tool_equipped:
		draw_rect(Rect2(5, 5, 22, 22), Color("#29232a"))
		draw_texture_rect(TOOL, Rect2(7, 7, 18, 18), false, ORE)
	if ratio >= 0.0:
		var bar_color := worker_tint if not worker_name.is_empty() else tone
		draw_rect(Rect2(5, size.y - 7, size.x - 10, 4), Color(bar_color, 0.22))
		draw_rect(Rect2(5, size.y - 7, (size.x - 10) * clampf(ratio, 0, 1), 4), bar_color)
	if drop_active and drop_valid:
		draw_circle(Vector2(size.x - 13, 13), 7, ORE if drop_waiting else ICE)

	if not material_flow.is_empty():
		var rect := Rect2(5, image_height - 19, size.x - 10, 19)
		draw_rect(rect, Color(0.08, 0.12, 0.13, 0.92))
		draw_string(font_face, Vector2(7, image_height - 5), material_flow, HORIZONTAL_ALIGNMENT_CENTER, size.x - 14, 13, ICE)


func _draw_worker_tab(image_height: float) -> void:
	# The miniature crew card sits on the worksite, inside its hit area.
	# Percent follows simulated work, so planning pause freezes the whole stack.
	var width := 24 + font_face.get_string_size(worker_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var tab := Rect2(5, 4, width, 20)
	draw_rect(tab, Color("#212429"))
	draw_rect(Rect2(tab.position, Vector2(2, tab.size.y)), worker_tint)
	_draw_art("lead", Rect2(10, 5, 12, 17), worker_tint)
	draw_string(title_face, Vector2(24, 19), worker_name, HORIZONTAL_ALIGNMENT_LEFT, width - 19, 13, worker_tint)
	if ratio >= 0.0 and not (drop_active and drop_valid):
		var percent := "%d%%" % floori(100 * ratio)
		var area := Rect2(size.x - 42, 4, 37, minf(20, image_height - 23))
		draw_rect(area, Color("#212429"))
		draw_string(title_face, area.position + Vector2(0, 15), percent, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, 13, ICE)


func _draw_inventory() -> void:
	var border := MARS if selected or hovered else Color("#59473c")
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#272023")
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	var compact := size.x < 210
	var plate_width := 39.0 if compact else 58.0
	var plate_center := Vector2(9 + plate_width / 2, size.y / 2)
	var text_x := 9 + plate_width + 12
	draw_rect(Rect2(9, 9, plate_width, size.y - 18), Color("#33282a"))
	if key == "tool":
		draw_texture_rect(TOOL, Rect2(plate_center - Vector2(14, 14), Vector2(28, 28)), false, MARS)
	elif key in ["ice", "plate", "circuit"]:
		_draw_badge(plate_center, TONES.get(key, ICE), 16)
	else:
		var icon := "sample" if key == "ore" else key
		_draw_art(icon, Rect2(16, 13, plate_width - 14, size.y - 26), Color(1, 1, 1, 0.53 if amount == "0" else 1.0))
	draw_string(title_face, Vector2(text_x, 28), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if compact else 17, INK)
	draw_string(font_face, Vector2(text_x, 51), caption, HORIZONTAL_ALIGNMENT_LEFT, 113, 12, MUTED)
	draw_string(title_face, Vector2(size.x - 43, 43), amount, HORIZONTAL_ALIGNMENT_RIGHT, 30, 21 if compact else 25, INK)
	if _receipt_left > 0:
		var gain := "+%d" % _receipt_amount
		var width := title_face.get_string_size(gain, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 10
		var pos := Vector2(size.x - 10 - width, 48)
		var alpha := minf(1.0, _receipt_left / 0.35)
		draw_rect(Rect2(pos, Vector2(width, 17)), Color(0.14, 0.24, 0.23, alpha))
		draw_string(title_face, pos + Vector2(0, 13), gain, HORIZONTAL_ALIGNMENT_CENTER, width, 13, Color(ICE, alpha))


func _draw_badge(center: Vector2, tone: Color, radius: float = 27) -> void:
	if kind == "site" and key in ["bench", "lab", "relay", "greenhouse", "radar_lens", "radar_cache"]:
		_draw_facility(center, tone)
		return
	draw_circle(center, radius, Color(tone, 0.12), true, -1, true)
	draw_circle(center, radius, Color(tone, 0.58), false, 1.0, true)
	_draw_symbol(center, tone)


func _draw_facility(center: Vector2, tone: Color) -> void:
	# Each worksite has its field equipment in profile, legible at compact card size.
	draw_set_transform(center)
	var shadow := Color("#3b3030")
	var steel := Color("#93857a")
	match key:
		"radar_lens":
			var cap := PackedVector2Array([Vector2(-33,3), Vector2(-18,-7), Vector2(8,-13), Vector2(33,-4), Vector2(12,5), Vector2(-10,9)])
			draw_colored_polygon(cap, Color("#997f70"))
			draw_colored_polygon(PackedVector2Array([Vector2(-30,4),Vector2(-9,10),Vector2(13,6),Vector2(31,-2),Vector2(25,6),Vector2(-7,17),Vector2(-24,13)]), Color("#87c5cf"))
			draw_polyline(PackedVector2Array([Vector2(-20,7),Vector2(-8,11),Vector2(10,7),Vector2(23,3)]), Color("#d9eff0"), 2, true)
			draw_polyline(PackedVector2Array([Vector2(-27,13),Vector2(-8,19),Vector2(20,10)]), steel, 2.5, true)
			draw_line(Vector2(18,-9), Vector2(18,-24), ICE, 1.7, true)
			draw_colored_polygon(PackedVector2Array([Vector2(18,-24),Vector2(30,-22),Vector2(18,-17)]), ICE)
		"radar_cache":
			draw_colored_polygon(PackedVector2Array([Vector2(-23,-10),Vector2(11,-17),Vector2(26,-9),Vector2(-7,-1)]), Color("#dbb38c"))
			draw_colored_polygon(PackedVector2Array([Vector2(-23,-10),Vector2(-7,-1),Vector2(-7,18),Vector2(-23,8)]), Color("#805b49"))
			draw_colored_polygon(PackedVector2Array([Vector2(-7,-1),Vector2(26,-9),Vector2(26,10),Vector2(-7,18)]), Color("#a97e5f"))
			for x: int in [0, 18]:
				var y := -2.0 - x * 0.24
				draw_line(Vector2(x,y), Vector2(x,y+17), Color("#454b4e"), 4, true)
				draw_line(Vector2(x,y), Vector2(x-12,y-9), Color("#6d6c65"), 3, true)
			draw_rect(Rect2(6,3,7,4), ICE)
			draw_polyline(PackedVector2Array([Vector2(-28,12),Vector2(-10,20),Vector2(18,17),Vector2(32,12)]), steel, 2, true)
		"bench":
			draw_rect(Rect2(-24, 6, 50, 5), Color("#cb997d"))
			for x in [-21, 18]:
				draw_rect(Rect2(x, 11, 4, 10), steel)
			draw_rect(Rect2(-18, -15, 6, 21), steel)
			draw_rect(Rect2(-18, -19, 23, 6), Color("#d8a37b"))
			draw_rect(Rect2(0, -13, 4, 10), steel)
			draw_colored_polygon(PackedVector2Array([Vector2(-1,-3),Vector2(5,-3),Vector2(2,1)]), tone)
			draw_rect(Rect2(-8, 2, 19, 4), Color("#879897"))
			draw_rect(Rect2(14, -4, 9, 10), shadow)
			draw_line(Vector2(13,-5), Vector2(24,-5), tone, 2, true)
		"lab":
			draw_rect(Rect2(-23, 15, 48, 4), steel)
			draw_line(Vector2(11,14), Vector2(13,-4), steel, 4, true)
			draw_line(Vector2(13,-4), Vector2(4,-13), steel, 4, true)
			draw_colored_polygon(PackedVector2Array([Vector2(-15,-4),Vector2(1,-21),Vector2(8,-15),Vector2(-8,2)]), Color("#7c9b9d"))
			draw_line(Vector2(-17,-4), Vector2(-9,4), ICE, 3, true)
			draw_circle(Vector2(12,-4), 3.5, tone, true, -1, true)
			draw_rect(Rect2(-18, 8, 22, 3), tone)
			draw_rect(Rect2(-10, 5, 9, 3), ICE)
		"relay":
			draw_colored_polygon(PackedVector2Array([Vector2(-22,-9), Vector2(-11,9),Vector2(0,12),Vector2(9,8),Vector2(20,-5)]), Color("#889b9c"))
			draw_line(Vector2(-22,-9), Vector2(20,-5), ICE, 2.5, true)
			draw_line(Vector2(-20,-10), Vector2(0,-19), steel, 1.6, true)
			draw_line(Vector2(0,-19), Vector2(19,-6), steel, 1.6, true)
			draw_circle(Vector2(0,-19), 2.6, tone, true, -1, true)
			draw_line(Vector2(-3,10), Vector2(-7,20), steel, 3, true)
			draw_line(Vector2(3,10), Vector2(7,20), steel, 3, true)
			draw_rect(Rect2(-12, 19, 24, 3), steel)
		"greenhouse":
			var dome := PackedVector2Array()
			for step in range(19):
				dome.append(Vector2(0,4) + Vector2.from_angle(PI + step * PI / 18) * 25)
			draw_colored_polygon(dome, Color("#31534b"))
			draw_arc(Vector2(0,4), 25, PI, TAU, 28, ICE, 2, true)
			for x in [-11, 0, 11]:
				draw_line(Vector2(x * 0.55,-18), Vector2(x,4), Color("#669990"), 1.5, true)
			draw_line(Vector2(-21,-8), Vector2(21,-8), Color("#669990"), 1.5, true)
			draw_rect(Rect2(-26,4,52,6), Color("#948a74"))
			draw_rect(Rect2(-20,10,40,5), Color("#635448"))
			for x in [-13, 2, 14]:
				draw_line(Vector2(x,3), Vector2(x-3,0), Color("#b4d58c"), 2.5, true)
				draw_line(Vector2(x,4), Vector2(x+4,-1), Color("#b4d58c"), 2, true)
	draw_set_transform(Vector2.ZERO)


func _draw_art(id: String, area: Rect2, tint: Color = Color.WHITE) -> void:
	var region: Rect2 = REGIONS[id]
	var factor := minf(area.size.x / region.size.x, area.size.y / region.size.y)
	var fitted := region.size * factor
	draw_texture_rect_region(ATLAS, Rect2(area.get_center() - fitted / 2.0, fitted), region, tint)
