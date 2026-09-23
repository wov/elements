class_name ExitGate
extends Area2D
## 关卡终点门：任意形态抵达即通关（由 main.gd 监听 reached 信号）。

signal reached(body: Node2D)

var _visual: Node2D


func _ready() -> void:
	_build_visual()
	body_entered.connect(_on_body_entered)


## 占位外观：两根柱子加一根横梁，带轻微呼吸感。
func _build_visual() -> void:
	_visual = Node2D.new()
	add_child(_visual)

	var gold := Color(1.0, 0.82, 0.35)
	var dark := Color(0.55, 0.45, 0.25)
	for x in [-34.0, 34.0]:
		var pillar := Polygon2D.new()
		pillar.polygon = PackedVector2Array([
			Vector2(x - 6.0, -46.0), Vector2(x + 6.0, -46.0),
			Vector2(x + 6.0, 46.0), Vector2(x - 6.0, 46.0),
		])
		pillar.color = dark
		_visual.add_child(pillar)
	var top := Polygon2D.new()
	top.polygon = PackedVector2Array([
		Vector2(-44, -50), Vector2(44, -50),
		Vector2(44, -38), Vector2(-44, -38),
	])
	top.color = gold
	_visual.add_child(top)

	var tween := create_tween().set_loops()
	tween.tween_property(_visual, "modulate:a", 0.75, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_visual, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		reached.emit(body)
