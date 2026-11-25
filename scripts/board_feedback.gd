extends Control

const NAMES := {"food": "口粮", "scrap": "残件", "ore": "矿样", "ice": "水冰", "plate": "结构件", "circuit": "电路"}
const GOLD := Color("#f0ba80")
const TEAL := Color("#a6e0d5")
var face: Font
var reduced_motion := false
var sound_enabled := true
var effects: Array[Dictionary] = []
var _voices: Array[AudioStreamPlayer] = []
var _tones: Dictionary = {}
var _last_sound := -1.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_process(false)
	for pitch in [420, 640, 920]:
		_tones[pitch] = _tone(float(pitch))
	for index in range(4):
		var player := AudioStreamPlayer.new()
		player.volume_db = -20
		add_child(player)
		_voices.append(player)


func _tone(frequency: float) -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var data := PackedByteArray()
	var samples := 2205
	data.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / sound.mix_rate
		var envelope := minf(t / 0.008, 1.0) * pow(1.0 - float(i) / samples, 2)
		var wave := sin(TAU * frequency * t) * 0.65 + sin(TAU * frequency * 1.5 * t) * 0.12
		data.encode_s16(i * 2, roundi(wave * envelope * 16000))
	sound.data = data
	return sound


func _exit_tree() -> void:
	for player in _voices:
		player.stop()
		player.stream = null
	_tones.clear()


func cue(pitch: int = 640) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not sound_enabled or DisplayServer.get_name() == "headless" or now - _last_sound < 0.09:
		return
	for player in _voices:
		if not player.playing:
			player.stream = _tones[pitch]
			player.play()
			_last_sound = now
			return


func transfer(item: String, count: int, from: Vector2, to: Vector2, incoming: bool) -> void:
	if effects.size() >= 32:
		effects.pop_front()
	# Multi-material deliveries use separate rows where their paths meet.
	var shared_end := from if incoming else to
	var occupied: Array[int] = []
	for prior in effects:
		if prior["transfer"] and prior["shared_end"] == shared_end:
			occupied.append(prior["row"])
	var row := 0
	while row in occupied:
		row += 1
	effects.append({"from": from, "to": to, "age": 0.0, "duration": 1.15,
		"text": ("+" if incoming else "−") + str(count) + " " + NAMES.get(item, item),
		"tone": TEAL if incoming else GOLD, "transfer": true,
		"shared_end": shared_end, "row": row, "incoming": incoming})
	set_process(true)
	queue_redraw()


func toast(message: String, at: Vector2, success: bool = true) -> void:
	if effects.size() >= 32:
		effects.pop_front()
	effects.append({"from": at, "to": at - Vector2(0, 32), "age": 0.0, "duration": 1.35,
		"text": message, "tone": TEAL if success else GOLD, "transfer": false})
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	for index in range(effects.size() - 1, -1, -1):
		effects[index]["age"] += delta
		if effects[index]["age"] >= effects[index]["duration"]:
			effects.remove_at(index)
	queue_redraw()
	if effects.is_empty():
		set_process(false)


func _draw() -> void:
	if face == null:
		return
	for effect in effects:
		var t: float = effect["age"] / effect["duration"]
		var from: Vector2 = effect["from"]
		var to: Vector2 = effect["to"]
		# Hold at the source so the gain is readable, then fly to its inventory slot.
		var travel := clampf((t - 0.3) / 0.7, 0, 1)
		travel = travel * travel * (3 - 2 * travel)
		var pos := from if reduced_motion else from.lerp(to, travel)
		if not reduced_motion and effect["transfer"]:
			pos.y -= sin(travel * PI) * 42
		if effect["transfer"]:
			var near_site := (1.0 - travel) if effect["incoming"] else travel
			if reduced_motion:
				near_site = 1.0 if effect["incoming"] else 0.0
			var row: int = effect["row"]
			# Alternate above and below the worksite; avoid a tower of labels.
			var stagger := ceilf(row / 2.0) * (-38 if row % 2 == 1 else 38)
			pos.y += near_site * stagger
		var alpha := clampf((1.0 - t) / 0.22, 0, 1)
		var tone: Color = effect["tone"]
		tone.a = alpha
		var width := maxf(88, face.get_string_size(effect["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 24)
		pos.x = clampf(pos.x, width / 2 + 6, size.x - width / 2 - 6)
		pos.y = clampf(pos.y, 24, size.y - 24)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.09, 0.12, 0.13, 0.96 * alpha)
		box.border_color = tone
		box.set_border_width_all(1)
		box.set_corner_radius_all(6)
		draw_style_box(box, Rect2(pos - Vector2(width / 2, 18), Vector2(width, 36)))
		draw_string(face, pos + Vector2(-width / 2, 6), effect["text"], HORIZONTAL_ALIGNMENT_CENTER, width, 17, tone)
