extends Node2D
## 主场景：搭建测试关卡与 HUD，处理重置等全局逻辑。

const SPAWN_POSITION: Vector2 = Vector2(200, 560)

@onready var player: Player = $Player

var _form_label: Label


func _ready() -> void:
	player.form_changed.connect(_on_player_form_changed)
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset"):
		player.global_position = SPAWN_POSITION
		player.velocity = Vector2.ZERO


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var box := VBoxContainer.new()
	box.position = Vector2(16, 12)
	box.add_theme_constant_override("separation", 6)
	layer.add_child(box)

	_form_label = Label.new()
	_form_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_form_label)

	var hint := Label.new()
	hint.text = "移动 A/D 或 ←/→    跳跃 空格 / W / ↑    切换形态 Q    重置 R"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.72, 0.75, 0.82))
	box.add_child(hint)

	_refresh_form_label()


func _on_player_form_changed(_form: int) -> void:
	_refresh_form_label()


func _refresh_form_label() -> void:
	if player.form == Player.Form.FIRE:
		_form_label.text = "当前形态：火"
		_form_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
	else:
		_form_label.text = "当前形态：水"
		_form_label.add_theme_color_override("font_color", Color(0.45, 0.75, 1.0))
