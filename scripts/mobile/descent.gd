extends Node2D
## 独立竖屏原型：固定物理步长、扫掠落地、有限窗口生成；不依赖旧关卡玩家。
const W := 420.0
const R := 20.0
const STAGE_HEIGHT := 1120.0
const FIRE := Color("ff9851")
const WATER := Color("57dfea")
var position_world := Vector2(210, 224)
var velocity := Vector2.ZERO
var water := true
var alive := true
var paused := false
var grounded := false
var camera_y := 0.0
var chapter := 1
var cleared := 0
var best := 0
var combo := 0
var clock := 0.0
var morph := 0.0
var hint := "滑出平台开始 · 点按切换水火"
var objects: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var next_stage := 0
var rider := -1
var rope_t := 0.0
@export var rail_speed := 330.0
var pointer := -1
var press_at := Vector2.ZERO
var last_at := Vector2.ZERO
var press_time := 0.0
var dragging := false
var score_label: Label
var form_label: Label
var hint_label: Label
var switch_button: Button
var pause_button: Button
var failure: PanelContainer
var end_label: Label
var font: Font
var frames: SpriteFrames

func _ready() -> void:
	font = UiFont.cjk()
	frames = CharacterFrames.build()
	var save := ConfigFile.new()
	if save.load("user://descent.cfg") == OK:
		best = int(save.get_value("score", "best", 0))
	_build_ui()
	restart()

func restart() -> void:
	position_world = Vector2(210, 224)
	velocity = Vector2.ZERO
	water = true
	alive = true
	paused = false
	grounded = true
	camera_y = 0.0
	chapter = 1
	cleared = 0
	combo = 0
	rider = -1
	next_stage = 0
	objects.clear()
	sparks.clear()
	objects.append({"kind":"safe", "rect":Rect2(120, 244, 180, 16), "used":false})
	for i in 3:
		_generate_stage()
	failure.hide()
	pause_button.text = "暂停"
	hint = "拖动左右移动 · 轻点切换水火"
	_update_hud()

func _generate_stage() -> void:
	var base := 330.0 + next_stage * STAGE_HEIGHT
	var rng := RandomNumberGenerator.new()
	rng.seed = 7281 + next_stage * 7919
	var left := rng.randf() > 0.5
	# 全宽木板保证先学习“水停、火穿”，水池之间有足够反应距离。
	objects.append({"kind":"wood", "rect":Rect2(22, base + 100, 376, 18), "used":false})
	objects.append({"kind":"pool", "rect":Rect2(22, base + 390, 376, 34), "used":false})
	var a := Vector2(65 if left else 355, base + 570)
	var b := Vector2(340 if left else 80, base + 760)
	objects.append({"kind":"rope", "a":a, "b":b, "used":false, "burn":0.0})
	objects.append({"kind":"safe", "rect":Rect2(35 if left else 245, base + 810, 140, 16), "used":false})
	# 后续模板在相同安全接口中变化，增加一组木板/水池，而非提高下落速度。
	if next_stage % 3 == 2:
		objects.append({"kind":"wood", "rect":Rect2(22, base + 890, 376, 14), "used":false})
		objects.append({"kind":"pool", "rect":Rect2(22, base + 1040, 376, 26), "used":false})
	objects.append({"kind":"gate", "rect":Rect2(22, base + 1100, 376, 6), "used":false})
	next_stage += 1

func switch_form() -> void:
	if not alive or paused:
		return
	water = not water
	morph = 1.0
	_spawn_sparks(position_world, WATER if water else FIRE, 22)
	if rider >= 0 and water:
		rider = -1
		velocity.y = 60
	if OS.has_feature("ios"):
		Input.vibrate_handheld(18)
	_update_hud()

func _physics_process(delta: float) -> void:
	if not alive or paused:
		return
	clock += delta
	morph = maxf(0.0, morph - delta * 3.5)
	for spark in sparks:
		spark.p += spark.v * delta
		spark.v.y += 120.0 * delta
		spark.life -= delta
	sparks = sparks.filter(func(s: Dictionary) -> bool: return s.life > 0.0)
	var axis := Input.get_axis("move_left", "move_right")
	if rider >= 0:
		var rope: Dictionary = objects[rider]
		rope_t = minf(1.0, rope_t + delta * rail_speed / rope.a.distance_to(rope.b))
		position_world = rope.a.lerp(rope.b, rope_t)
		rope.burn = rope_t
		if rope_t >= 1.0:
			rope.used = true
			rider = -1
			velocity = Vector2(0, 100)
			_reward("引火绳捷径 +1")
	else:
		var previous := position_world
		position_world.x = clampf(position_world.x + axis * 240.0 * delta, 43, 377)
		velocity.y = minf(velocity.y + 780.0 * delta, 310.0)
		position_world.y += velocity.y * delta
		grounded = false
		_resolve(previous)
	camera_y = lerpf(camera_y, maxf(0, position_world.y - 285), minf(1, delta * 7))
	while next_stage * STAGE_HEIGHT < position_world.y + 2200:
		_generate_stage()
	# 删除远离画面的旧片段，内存不会随无限关卡持续增长。
	if rider < 0:
		objects = objects.filter(func(o: Dictionary) -> bool:
			return (o.b.y if o.kind == "rope" else o.rect.end.y) > camera_y - 500)
	if position_world.y > camera_y + 950:
		_die("掉出边界")
	_update_hud()
	queue_redraw()

func _resolve(previous: Vector2) -> void:
	for i in objects.size():
		var o: Dictionary = objects[i]
		if o.used:
			continue
		if o.kind == "rope":
			if water:
				continue
			var near := Geometry2D.get_closest_point_to_segment(position_world, o.a, o.b)
			if near.distance_to(position_world) < R + 8:
				rider = i
				rope_t = clampf((near - o.a).dot(o.b - o.a) / o.a.distance_squared_to(o.b), 0, 1)
				o.burn = rope_t
				position_world = near
				velocity = Vector2.ZERO
				hint = "火沿绳移动 · 变水可提前脱离"
				return
			continue
		var rect: Rect2 = o.rect
		var overlaps := position_world.x + R > rect.position.x and position_world.x - R < rect.end.x
		var crossed := previous.y + R <= rect.position.y + 1 and position_world.y + R >= rect.position.y
		if not overlaps or not crossed or velocity.y < 0:
			continue
		match o.kind:
			"safe":
				position_world.y = rect.position.y - R
				velocity.y = 0
				grounded = true
				hint = "安全落脚点 · 想好路线再滑出去"
				return
			"wood":
				if water:
					position_world.y = rect.position.y - R
					velocity.y = 0
					grounded = true
					hint = "水停在木板上 · 点按变火烧穿"
					return
				o.used = true
				_spawn_sparks(Vector2(position_world.x, rect.position.y), FIRE, 16)
				_reward("烧穿木板 · 下方水池要变水")
			"pool":
				if not water:
					_die("火被水池熄灭了\n下次在入水前切成水")
					return
				o.used = true
				velocity.y = 150
				_spawn_sparks(position_world, WATER, 18)
				_reward("融入水池 · 继续下落")
			"gate":
				o.used = true
				cleared += 1
				chapter += 1
				if cleared > best:
					best = cleared
					var save := ConfigFile.new()
					save.set_value("score", "best", best)
					save.save("user://descent.cfg")
				hint = "第 %d 关开始 · 路线继续变化" % chapter

func _reward(message: String) -> void:
	combo += 1
	hint = message

func _die(reason: String) -> void:
	alive = false
	pointer = -1
	end_label.text = "本次通过 %d 关\n最佳 %d 关\n\n%s" % [cleared, best, reason]
	failure.show()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset"):
		restart()
	elif event.is_action_pressed("switch_form") and not event.is_echo():
		switch_form()
	elif event is InputEventScreenTouch:
		if event.pressed and pointer == -1:
			_begin_pointer(event.index, event.position)
		elif not event.pressed and event.index == pointer:
			_end_pointer(event.position)
	elif event is InputEventScreenDrag and event.index == pointer:
		_move_pointer(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(-2, event.position)
		elif pointer == -2:
			_end_pointer(event.position)
	elif event is InputEventMouseMotion and pointer == -2:
		_move_pointer(event.position)

func _begin_pointer(id: int, at: Vector2) -> void:
	pointer = id
	press_at = at
	last_at = at
	press_time = Time.get_ticks_msec() / 1000.0
	dragging = false

func _move_pointer(at: Vector2) -> void:
	if not alive or paused:
		return
	if at.distance_to(press_at) > 12:
		dragging = true
	if dragging and rider < 0:
		position_world.x = clampf(position_world.x + at.x - last_at.x, 43, 377)
	last_at = at

func _end_pointer(at: Vector2) -> void:
	if not dragging and at.distance_to(press_at) < 16 and Time.get_ticks_msec() / 1000.0 - press_time < 0.35:
		switch_form()
	pointer = -1

func _spawn_sparks(at: Vector2, color: Color, count: int) -> void:
	for i in count:
		var angle := TAU * float(i) / count
		sparks.append({"p":at, "v":Vector2(cos(angle), sin(angle)) * randf_range(35,110), "life":0.5, "color":color})

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := _label("ELEMENTS / 水火之间", Vector2(24, 40), 18)
	layer.add_child(title)
	score_label = _label("", Vector2(24, 90), 24)
	layer.add_child(score_label)
	form_label = _label("", Vector2(24, 120), 16)
	layer.add_child(form_label)
	pause_button = _button("暂停", Rect2(322, 44, 74, 42))
	pause_button.pressed.connect(func() -> void:
		if not alive: return
		paused = not paused
		pause_button.text = "继续" if paused else "暂停"
		hint_label.text = "已暂停 · 点击继续" if paused else hint
		pointer = -1)
	layer.add_child(pause_button)
	hint_label = _label("", Vector2(24, 716), 16)
	hint_label.size = Vector2(372, 48)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(hint_label)
	switch_button = _button("", Rect2(24, 775, 372, 58))
	switch_button.pressed.connect(switch_form)
	layer.add_child(switch_button)
	failure = PanelContainer.new()
	failure.position = Vector2(28, 242)
	failure.size = Vector2(364, 320)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("142735")
	panel.set_corner_radius_all(22)
	panel.content_margin_left = 24
	panel.content_margin_top = 24
	panel.content_margin_right = 24
	panel.content_margin_bottom = 24
	failure.add_theme_stylebox_override("panel", panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	failure.add_child(box)
	end_label = _label("", Vector2.ZERO, 20)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(end_label)
	var retry := _button("再来一次", Rect2(0,0,300,56))
	retry.custom_minimum_size.y = 56
	retry.pressed.connect(restart)
	box.add_child(retry)
	layer.add_child(failure)

func _label(text: String, at: Vector2, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("e3eee9"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, rect: Rect2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color("e9f8f4"))
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("255364") if state != "pressed" else Color("397788")
		style.set_corner_radius_all(16)
		button.add_theme_stylebox_override(state, style)
	return button

func _update_hud() -> void:
	score_label.text = "第 %02d 关   /   最佳 %02d" % [chapter, best]
	form_label.text = ("水 · 遇水通过 / 木板停留" if water else "火 · 烧穿木板 / 沿绳移动") + "   连击 %d" % combo
	form_label.modulate = WATER if water else FIRE
	hint_label.text = hint
	switch_button.text = "切换为火   /   烧穿与引燃" if water else "切换为水   /   安全入水"

func _draw() -> void:
	draw_rect(Rect2(0,0,W,860), Color("09171f"))
	# 深井岩壁与刻度，随下落滚动；中部留出干净的玩法区域。
	for side in [0,1]:
		var x := 0.0 if side == 0 else 398.0
		draw_rect(Rect2(x,0,22,860), Color("172c35"))
	for i in 13:
		var y := float(i) * 90 - fmod(camera_y, 90)
		draw_line(Vector2(0,y), Vector2(18,y+18), Color("29434a"), 2)
		draw_line(Vector2(402,y+36), Vector2(420,y+18), Color("29434a"), 2)
	for i in 22:
		var p := Vector2(35 + fmod(i * 71.0,350), fposmod(i * 137.0 - camera_y * 0.2, 860))
		draw_circle(p, 1.0, Color(0.3,0.7,0.7,0.12))
	draw_set_transform(Vector2(0,-camera_y))
	for o in objects:
		if o.kind == "rope":
			if not o.used:
				var start: Vector2 = o.a.lerp(o.b, o.burn)
				draw_line(start, o.b, Color("af8751"), 5, true)
				draw_circle(o.a, 5, Color("516366"))
				draw_circle(o.b, 5, Color("516366"))
			continue
		if o.used:
			continue
		var rect: Rect2 = o.rect
		match o.kind:
			"safe":
				draw_style_box(_platform_style(), rect)
				draw_line(rect.position, Vector2(rect.end.x,rect.position.y), Color("8fd4b2"), 3)
				_world_text("安全平台", rect.position + Vector2(6,-9), Color("8fd4b2"))
			"wood":
				draw_rect(rect, Color("895a3a"))
				for j in 8:
					draw_line(rect.position + Vector2(j * 47,2), rect.position + Vector2(j * 47 + 27,14), Color("d89b57"), 2)
				_world_text("木板  /  火烧穿 · 水停留", rect.position + Vector2(8,-12), Color("edba7e"))
			"pool":
				draw_rect(rect, Color(0.13,0.55,0.68,0.35))
				var wave := PackedVector2Array()
				for j in 49:
					wave.append(rect.position + Vector2(j * rect.size.x / 48, sin(j * 0.6 + clock * 3) * 3))
				draw_polyline(wave, WATER, 3, true)
				_world_text("水池  /  变水才能通过", rect.position + Vector2(8,-16), WATER)
			"gate":
				draw_line(rect.position, Vector2(rect.end.x,rect.position.y), Color("73b698"), 1)
				_world_text("下一关 ↓", rect.position + Vector2(145,-14), Color("99cdb2"))
	for spark in sparks:
		var c: Color = spark.color
		c.a = maxf(0, spark.life * 2)
		draw_circle(spark.p, 2.3, c)
	var color := WATER if water else FIRE
	draw_circle(position_world, 32, Color(color,0.07))
	draw_circle(position_world, 26, Color(color,0.10))
	var anim := CharacterFrames.WATER_MOVE if water else CharacterFrames.FIRE_MOVE
	if grounded:
		anim = CharacterFrames.WATER_IDLE if water else CharacterFrames.FIRE_IDLE
	if frames != null:
		var texture := frames.get_frame_texture(anim, int(clock * 14) % frames.get_frame_count(anim))
		draw_texture_rect(texture, Rect2(position_world - Vector2(32,36), Vector2(64,64)), false, Color(1,1,1,1-morph*0.7))
	if grounded:
		draw_arc(position_world + Vector2(0,23), 15, 0, PI, 16, Color(color,0.5), 2,true)
	draw_set_transform(Vector2.ZERO)
	# 固定顶底面板遮挡远处玩法内容，触控区始终清楚。
	draw_rect(Rect2(22,0,376,165), Color(0.035,0.09,0.12,0.96))
	draw_rect(Rect2(22,700,376,160), Color(0.035,0.09,0.12,0.97))

func _world_text(text: String, at: Vector2, color: Color) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)

func _platform_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("304f53")
	style.set_corner_radius_all(5)
	return style
