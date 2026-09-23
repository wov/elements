class_name Player
extends CharacterBody2D
## 元素主角：只能左右移动（没有跳跃）。
## 元素量（amount）随时间缓慢衰竭，移动时衰竭加快，归零即消散。
## 火形态靠「燃料」补充元素量，水形态靠「水滴」补充（见 ElementPickup）。

signal form_changed(form)
signal depleted

enum Form { FIRE, WATER }

@export_group("移动")
@export var move_speed: float = 300.0
@export var gravity: float = 980.0
## 元素量越低移动越无力：speed = move_speed * lerp(min_speed_ratio, 1, amount)
@export var min_speed_ratio: float = 0.5

@export_group("衰竭")
@export var start_amount: float = 1.0
## 静止时的衰竭速度（每秒）
@export var idle_drain: float = 0.025
## 移动时的额外衰竭速度（每秒）
@export var move_drain: float = 0.13

const FORM_COLORS: Dictionary = {
	Form.FIRE: Color(1.0, 0.45, 0.22),
	Form.WATER: Color(0.30, 0.62, 1.0),
}

var form: Form = Form.FIRE
## 当前元素量（0~1）。归零即消散并发出 depleted 信号。
var amount: float = 1.0
## 通关等场合可冻结玩家输入。
var input_enabled: bool = true

var _facing: int = 1
var _dead: bool = false
var _fx_tween: Tween
var _body: Polygon2D
var _aura: CPUParticles2D
var _face: Node2D
var _fx: Node2D

@onready var visual: Node2D = $Visual


func _ready() -> void:
	amount = start_amount
	_build_visual()
	_apply_form(false)
	_update_size()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

	var direction := 0.0
	if input_enabled and not _dead:
		direction = Input.get_axis("move_left", "move_right")

	var speed := move_speed * lerpf(min_speed_ratio, 1.0, amount)
	if direction != 0.0:
		velocity.x = direction * speed
		_facing = 1 if direction > 0.0 else -1
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)

	move_and_slide()

	if _dead:
		return

	# 衰竭：移动时明显加快；归零即消散
	var drain := idle_drain + (move_drain if direction != 0.0 else 0.0)
	amount = maxf(amount - drain * delta, 0.0)
	_update_size()

	if amount <= 0.0:
		_die()
	else:
		_face.position.x = _facing * 3.0


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


## 吸收对应资源时补充元素量。
func add_amount(value: float) -> void:
	if _dead:
		return
	amount = clampf(amount + value, 0.0, 1.0)
	var tween := _new_fx_tween()
	tween.tween_property(_fx, "scale", Vector2(1.35, 1.35), 0.08)
	tween.chain().tween_property(_fx, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _die() -> void:
	_dead = true
	_aura.emitting = false
	velocity.x = 0.0
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector2.ZERO, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: depleted.emit())


## 占位外观全部由代码生成；visual 节点随元素量缩放，_fx 节点负责弹跳反馈。
func _build_visual() -> void:
	_fx = Node2D.new()
	visual.add_child(_fx)

	_body = Polygon2D.new()
	_body.polygon = PackedVector2Array([
		Vector2(-14, -22), Vector2(14, -22),
		Vector2(14, 22), Vector2(-14, 22),
	])
	_fx.add_child(_body)

	_face = Node2D.new()
	_fx.add_child(_face)
	for offset in [Vector2(-7, -10), Vector2(5, -10)]:
		var eye := Polygon2D.new()
		eye.polygon = PackedVector2Array([
			Vector2(-2, -4), Vector2(2, -4), Vector2(2, 4), Vector2(-2, 4),
		])
		eye.color = Color(0.12, 0.13, 0.2)
		eye.position = offset
		_face.add_child(eye)

	_aura = CPUParticles2D.new()
	_aura.texture = VisualFx.soft_circle()
	_aura.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_aura.emission_sphere_radius = 16.0
	_aura.amount = 24
	_aura.lifetime = 0.7
	_aura.spread = 35.0
	_aura.local_coords = true
	_aura.scale_amount_min = 3.0
	_aura.scale_amount_max = 6.0
	_fx.add_child(_aura)


## 按当前形态刷新外观；play_fx 控制是否播放切换时的挤压反馈。
func _apply_form(play_fx: bool) -> void:
	_body.color = FORM_COLORS[form]
	match form:
		Form.FIRE:
			_aura.direction = Vector2(0, -1)
			_aura.gravity = Vector2(0, -120)
			_aura.initial_velocity_min = 25.0
			_aura.initial_velocity_max = 60.0
			_aura.color = Color(1.0, 0.68, 0.25, 0.75)
		Form.WATER:
			_aura.direction = Vector2(0, 1)
			_aura.gravity = Vector2(0, 260)
			_aura.initial_velocity_min = 15.0
			_aura.initial_velocity_max = 40.0
			_aura.color = Color(0.55, 0.85, 1.0, 0.7)

	if play_fx:
		var tween := _new_fx_tween()
		tween.set_parallel(true)
		tween.tween_property(_fx, "scale:x", 1.3, 0.08)
		tween.tween_property(_fx, "scale:y", 0.75, 0.08)
		tween.chain().tween_property(_fx, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 元素量越低：体形越小、光环粒子越少。
func _update_size() -> void:
	var s := lerpf(0.45, 1.0, amount)
	visual.scale = Vector2(s, s)
	_aura.amount = int(6.0 + 18.0 * amount)


func _new_fx_tween() -> Tween:
	if _fx_tween and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_tween = create_tween()
	return _fx_tween
