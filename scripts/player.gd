class_name Player
extends CharacterBody2D
## 元素主角：可在「火 / 水」两种基础形态间切换。
## 当前版本切换只影响外观与内部状态；后续再把形态接入关卡机制
## （例如火形态点燃机关、水形态熄灭火焰、双元素相遇产生蒸汽等）。

signal form_changed(form)

enum Form { FIRE, WATER }

const SPEED: float = 300.0
const JUMP_VELOCITY: float = -520.0
const GRAVITY: float = 980.0

const FORM_COLORS: Dictionary = {
	Form.FIRE: Color(1.0, 0.45, 0.22),
	Form.WATER: Color(0.30, 0.62, 1.0),
}

var form: Form = Form.FIRE

var _facing: int = 1
var _body: Polygon2D
var _aura: CPUParticles2D
var _face: Node2D

@onready var visual: Node2D = $Visual


func _ready() -> void:
	_build_visual()
	_apply_form(false)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = direction * SPEED
		_facing = 1 if direction > 0.0 else -1
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	move_and_slide()
	_face.position.x = _facing * 3.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_form"):
		switch_form()


## 切换到另一种形态，并广播 form_changed 信号。
func switch_form() -> void:
	form = Form.WATER if form == Form.FIRE else Form.FIRE
	_apply_form(true)
	form_changed.emit(form)


## 占位外观全部由代码生成，之后可直接替换为 Sprite2D / 动画。
func _build_visual() -> void:
	_body = Polygon2D.new()
	_body.polygon = PackedVector2Array([
		Vector2(-14, -22), Vector2(14, -22),
		Vector2(14, 22), Vector2(-14, 22),
	])
	visual.add_child(_body)

	_face = Node2D.new()
	visual.add_child(_face)
	for offset in [Vector2(-7, -10), Vector2(5, -10)]:
		var eye := Polygon2D.new()
		eye.polygon = PackedVector2Array([
			Vector2(-2, -4), Vector2(2, -4), Vector2(2, 4), Vector2(-2, 4),
		])
		eye.color = Color(0.12, 0.13, 0.2)
		eye.position = offset
		_face.add_child(eye)

	_aura = CPUParticles2D.new()
	_aura.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_aura.emission_sphere_radius = 16.0
	_aura.amount = 24
	_aura.lifetime = 0.7
	_aura.spread = 35.0
	_aura.local_coords = true
	_aura.scale_amount_min = 3.0
	_aura.scale_amount_max = 6.0
	_aura.texture = _make_particle_texture()
	visual.add_child(_aura)


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
		visual.scale = Vector2.ONE
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual, "scale:x", 1.3, 0.08)
		tween.tween_property(visual, "scale:y", 0.75, 0.08)
		tween.chain().tween_property(visual, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 生成一张柔和的圆形渐变贴图供粒子使用，避免依赖美术资源。
func _make_particle_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 16
	texture.height = 16
	texture.gradient = gradient
	return texture
