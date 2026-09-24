class_name Player
extends CharacterBody2D
## 元素主角：只能左右移动（没有跳跃）。
## 元素量（amount）只在移动时衰竭（停留不消耗，给玩家思考时间），归零即消散。
## 火形态吃「煤块」补充元素量，水形态吸收「水滴」补充；
## 火碰到水滴会被熄灭，水碰到煤块会被整个吸进去（见 ElementPickup）。
##
## 外观：AnimatedSprite2D 动画帧（占位帧由 CharacterFrames 程序生成，可整体替换）。
## - 火：微微浮空 + 缓慢起伏；移动时火苗向行进反方向拖曳（迎风变形）
## - 水：贴地的圆形张力水滴；移动时横向拉伸，并在地面留下水渍
## - 体内显示元素量百分比，制造紧迫感
## 火形态自带 PointLight2D 光照，能照亮周围环境（配合场景里的 CanvasModulate 压暗）。
## 反馈动画全部用多边形 + 补间完成，没有粒子效果。

signal form_changed(form)
signal depleted
signal extinguished
signal absorbed

enum Form { FIRE, WATER }

@export_group("移动")
@export var move_speed: float = 300.0
@export var gravity: float = 980.0
## 元素量越低移动越无力：speed = move_speed * lerp(min_speed_ratio, 1, amount)
@export var min_speed_ratio: float = 0.5

@export_group("衰竭")
@export var start_amount: float = 1.0
## 停留不消耗（0 = 静止完全不衰竭；想加全局压力可调大）
@export var idle_drain: float = 0.0
## 移动时的衰竭速度（每秒）
@export var move_drain: float = 0.13

@export_group("外观")
## 火焰悬空高度（像素）
@export var fire_hover: float = 6.0
## 火焰光照强度（PointLight2D energy）
@export var fire_light_energy: float = 1.15
## 火焰光照范围（256px 光照纹理 × 该缩放）
@export var fire_light_scale: float = 1.7
## 水渍生成间隔（秒）
@export var stain_interval: float = 0.12
## 占位帧的显示缩放
@export var sprite_scale: float = 0.6

var form: Form = Form.FIRE
## 当前元素量（0~1）。归零即消散并发出 depleted 信号。
var amount: float = 1.0
## 通关等场合可冻结玩家输入。
var input_enabled: bool = true

var _facing: int = 1
var _dead: bool = false
var _time: float = 0.0
var _trail_timer: float = 0.0
var _last_percent: int = -1
var _fx_tween: Tween
var _sprite: AnimatedSprite2D
var _percent_label: Label
var _light: PointLight2D
var _float: Node2D
var _fx: Node2D

@onready var visual: Node2D = $Visual


func _ready() -> void:
	add_to_group("player")
	amount = start_amount
	_build_visual()
	_apply_form(false)
	_update_size()


func _physics_process(delta: float) -> void:
	_time += delta
	if _dead:
		# 死亡后的表现完全交给补间动画（缩小 / 被吸走 / 淡出）
		return
	if not is_on_floor():
		velocity.y += gravity * delta

	var direction := 0.0
	if input_enabled:
		direction = Input.get_axis("move_left", "move_right")
	var moving := direction != 0.0

	var speed := move_speed * lerpf(min_speed_ratio, 1.0, amount)
	if moving:
		velocity.x = direction * speed
		_facing = 1 if direction > 0.0 else -1
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)

	move_and_slide()

	# 衰竭：只有移动才消耗；归零即消散
	var drain := idle_drain + (move_drain if moving else 0.0)
	amount = maxf(amount - drain * delta, 0.0)
	_update_size()

	if amount <= 0.0:
		_die()
		return

	_update_animation(moving)
	_update_hover(delta)
	_update_light()
	_update_percent()

	# 水渍：水形态移动时在地面留下痕迹
	if form == Form.WATER and moving and is_on_floor():
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = stain_interval
			_spawn_stain()
	else:
		_trail_timer = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_form"):
		switch_form()


## 切换到另一种形态，并广播 form_changed 信号。
func switch_form() -> void:
	if _dead:
		return
	form = Form.WATER if form == Form.FIRE else Form.FIRE
	_apply_form(true)
	form_changed.emit(form)


## 是否已经消散/熄灭（供补给判断）。
func is_dead() -> bool:
	return _dead


## 吸收对应资源时补充元素量；strong = 吃煤块这类「大口进补」，反馈更猛。
func add_amount(value: float, strong := false) -> void:
	if _dead:
		return
	amount = clampf(amount + value, 0.0, 1.0)
	var tween := _new_fx_tween()
	if strong:
		tween.set_parallel(true)
		tween.tween_property(_fx, "scale:x", 1.55, 0.07)
		tween.tween_property(_fx, "scale:y", 0.7, 0.07)
		tween.chain().tween_property(_fx, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_flash(Color(2.0, 1.7, 1.1))
	else:
		tween.tween_property(_fx, "scale", Vector2(1.35, 1.35), 0.08)
		tween.chain().tween_property(_fx, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 火形态碰到水滴：熄灭。冒几缕蒸汽后广播 extinguished。
func extinguish() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	_sprite.stop()
	_sprite.modulate = Color(0.75, 0.85, 1.05)
	_spawn_steam()
	var light_fade := create_tween()
	light_fade.tween_property(_light, "energy", 0.0, 0.35)
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector2.ZERO, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: extinguished.emit())


## 水形态碰到煤块：整颗水滴被拽进煤里（缩小的同时移向煤块），然后广播 absorbed。
func absorb_into(into: Vector2) -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	_sprite.stop()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", into, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(visual, "scale", Vector2.ZERO, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void: absorbed.emit())


func _die() -> void:
	_dead = true
	velocity.x = 0.0
	var light_fade := create_tween()
	light_fade.tween_property(_light, "energy", 0.0, 0.35)
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector2.ZERO, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: depleted.emit())


## 视觉层级：visual(随元素量缩放) > _fx(拾取/受吸收的弹跳) > _float(形态悬停/起伏) > 精灵+百分比
func _build_visual() -> void:
	_fx = Node2D.new()
	visual.add_child(_fx)

	_float = Node2D.new()
	_fx.add_child(_float)

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = CharacterFrames.build()
	_sprite.scale = Vector2(sprite_scale, sprite_scale)
	_sprite.play(CharacterFrames.FIRE_IDLE)
	_float.add_child(_sprite)

	_percent_label = Label.new()
	_percent_label.position = Vector2(-24, -12)
	_percent_label.custom_minimum_size = Vector2(48, 24)
	_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_percent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_percent_label.add_theme_font_size_override("font_size", 18)
	_percent_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_percent_label.add_theme_color_override("font_outline_color", Color(0.08, 0.09, 0.14, 0.9))
	_percent_label.add_theme_constant_override("outline_size", 6)
	_float.add_child(_percent_label)

	_light = PointLight2D.new()
	_light.texture = _light_texture()
	_light.color = Color(1.0, 0.72, 0.42)
	_light.energy = fire_light_energy
	_light.texture_scale = fire_light_scale
	_float.add_child(_light)


## play_fx 控制切换形态时是否播放挤压反馈。
func _apply_form(play_fx: bool) -> void:
	_light.enabled = form == Form.FIRE
	if play_fx:
		var tween := _new_fx_tween()
		tween.set_parallel(true)
		tween.tween_property(_fx, "scale:x", 1.3, 0.08)
		tween.tween_property(_fx, "scale:y", 0.75, 0.08)
		tween.chain().tween_property(_fx, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 元素量越低体形越小。
func _update_size() -> void:
	var s := lerpf(0.45, 1.0, amount)
	visual.scale = Vector2(s, s)


## 形态 + 是否移动 → 动画帧；向左移动用 flip_h 镜像。
func _update_animation(moving: bool) -> void:
	var anim: String
	if form == Form.FIRE:
		anim = CharacterFrames.FIRE_MOVE if moving else CharacterFrames.FIRE_IDLE
	else:
		anim = CharacterFrames.WATER_MOVE if moving else CharacterFrames.WATER_IDLE
	if _sprite.animation != anim or not _sprite.is_playing():
		_sprite.play(anim)
	_sprite.flip_h = _facing < 0


## 火：悬空 + 缓慢起伏；水：贴地 + 轻微张力呼吸。
func _update_hover(delta: float) -> void:
	var target := 0.0
	if form == Form.FIRE:
		target = -fire_hover + sin(_time * 2.5) * 3.0
	else:
		target = 8.0 + sin(_time * 1.8) * 1.2
	_float.position.y = lerpf(_float.position.y, target, 12.0 * delta)


## 火焰光照：忽明忽暗地闪烁；元素量越少，光越弱、照得越近。
func _update_light() -> void:
	if form != Form.FIRE:
		return
	var flicker := 1.0 + 0.08 * sin(_time * 9.0) + 0.05 * sin(_time * 23.0)
	_light.energy = fire_light_energy * flicker * lerpf(0.35, 1.0, amount)
	_light.texture_scale = fire_light_scale * lerpf(0.55, 1.0, amount) * (1.0 + 0.03 * sin(_time * 7.0))


## 径向渐变光照纹理（中心亮、边缘透明），静态缓存。
## 径向光照纹理：中心亮、向边缘平滑衰减到全透明（逐像素生成，
## 保证内切圆以外——包括正方形四角——alpha 恒为 0，不会露出方形光斑）。
static var _light_tex: ImageTexture

static func _light_texture() -> Texture2D:
	if _light_tex == null:
		var size := 256
		var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			for x in size:
				var nx := (float(x) + 0.5) / float(size) * 2.0 - 1.0
				var ny := (float(y) + 0.5) / float(size) * 2.0 - 1.0
				var d := sqrt(nx * nx + ny * ny)
				var falloff := clampf(1.0 - d, 0.0, 1.0)
				image.set_pixel(x, y, Color(1, 1, 1, pow(falloff, 1.8)))
		_light_tex = ImageTexture.create_from_image(image)
	return _light_tex


## 体内百分比数字（只在整数变化时刷新）。
func _update_percent() -> void:
	var percent := int(round(amount * 100.0))
	if percent != _last_percent:
		_last_percent = percent
		_percent_label.text = "%d%%" % percent


## 水形态移动时留在地面的水渍，随时间淡出。
func _spawn_stain() -> void:
	var stain := Polygon2D.new()
	var points := PackedVector2Array()
	var radius := 7.0 + randf() * 4.0
	for i in 10:
		var angle := TAU * float(i) / 10.0
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius * 0.35))
	stain.polygon = points
	stain.position = Vector2(global_position.x + randf_range(-6.0, 6.0), global_position.y + 20.0)
	stain.color = Color(0.3, 0.55, 0.95, 0.4)
	stain.z_index = -1
	_fx_host().add_child(stain)

	var tween := stain.create_tween()
	tween.tween_property(stain, "modulate:a", 0.0, 2.2).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(stain, "scale", Vector2(0.7, 0.7), 2.2)
	tween.tween_callback(stain.queue_free)


func _new_fx_tween() -> Tween:
	if _fx_tween and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_tween = create_tween()
	return _fx_tween


## 水渍/蒸汽等临时节点挂到当前场景（无主场景的测试环境下挂到父节点兜底）。
func _fx_host() -> Node:
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	return get_parent()


## 精灵短暂过曝/变色再淡回白色，做受击与进补的闪光。
func _flash(color: Color) -> void:
	_sprite.modulate = color
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", Color.WHITE, 0.25)


## 熄灭时的蒸汽：几团白色椭圆缓缓上升消散。
func _spawn_steam() -> void:
	for i in 4:
		var wisp := Polygon2D.new()
		var points := PackedVector2Array()
		for j in 8:
			var angle := TAU * float(j) / 8.0
			points.append(Vector2(cos(angle) * (4.0 + i), sin(angle) * (7.0 + i * 2.0)))
		wisp.polygon = points
		wisp.color = Color(0.88, 0.92, 1.0, 0.55)
		wisp.position = global_position + Vector2(randf_range(-12.0, 12.0), randf_range(-10.0, 6.0))
		wisp.z_index = 5
		_fx_host().add_child(wisp)
		var tween := wisp.create_tween()
		tween.tween_interval(0.06 * float(i))
		tween.set_parallel(true)
		tween.tween_property(wisp, "position:y", wisp.position.y - randf_range(26.0, 40.0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(wisp, "modulate:a", 0.0, 0.55)
		tween.chain().tween_callback(wisp.queue_free)
