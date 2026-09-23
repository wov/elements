class_name ElementPickup
extends Area2D
## 场景补给：燃料（火形态可吸收）或水滴（水形态可吸收）。
## 与当前形态不符时无效果，元素可以直接穿过。

enum Kind { FUEL, WATER }

@export var kind: Kind = Kind.FUEL
@export var restore_amount: float = 0.4

const KIND_COLORS: Dictionary = {
	Kind.FUEL: Color(1.0, 0.6, 0.2),
	Kind.WATER: Color(0.35, 0.7, 1.0),
}

var _visual: Node2D
var _consumed: bool = false
var _bob_tween: Tween


func _ready() -> void:
	_build_visual()
	_start_bob()
	body_entered.connect(_on_body_entered)


## 占位外观：菱形主体 + 少量环绕粒子，颜色区分种类。
func _build_visual() -> void:
	_visual = Node2D.new()
	add_child(_visual)

	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([
		Vector2(0, -14), Vector2(12, 0), Vector2(0, 14), Vector2(-12, 0),
	])
	diamond.color = KIND_COLORS[kind]
	_visual.add_child(diamond)

	var sparkles := CPUParticles2D.new()
	sparkles.texture = VisualFx.soft_circle()
	sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	sparkles.emission_sphere_radius = 10.0
	sparkles.amount = 8
	sparkles.lifetime = 0.6
	sparkles.local_coords = true
	sparkles.scale_amount_min = 2.0
	sparkles.scale_amount_max = 4.0
	sparkles.initial_velocity_min = 8.0
	sparkles.initial_velocity_max = 24.0
	if kind == Kind.FUEL:
		sparkles.direction = Vector2(0, -1)
		sparkles.gravity = Vector2(0, -60)
		sparkles.color = Color(1.0, 0.75, 0.3, 0.8)
	else:
		sparkles.direction = Vector2(0, 1)
		sparkles.gravity = Vector2(0, 120)
		sparkles.color = Color(0.6, 0.9, 1.0, 0.8)
	_visual.add_child(sparkles)


func _start_bob() -> void:
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(_visual, "position:y", -6.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(_visual, "position:y", 6.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_body_entered(body: Node2D) -> void:
	if _consumed or not body is Player:
		return
	var player := body as Player
	var matches_form: bool = (
		kind == Kind.FUEL and player.form == Player.Form.FIRE
	) or (
		kind == Kind.WATER and player.form == Player.Form.WATER
	)
	if not matches_form:
		return

	_consumed = true
	if _bob_tween and _bob_tween.is_valid():
		_bob_tween.kill()
	player.add_amount(restore_amount)

	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector2(1.8, 1.8), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_visual, "modulate:a", 0.0, 0.2)
	tween.tween_callback(queue_free)
