extends Node2D
## 主场景：搭建关卡与 HUD，处理消散重开、通关提示。

## 相机活动范围（关卡世界坐标）。
const CAMERA_BOUNDS := Rect2(0, 0, 2560, 720)

@onready var player: Player = $Player
@onready var exit_gate: ExitGate = $Level/ExitGate

var _form_label: Label
var _message_label: Label
var _amount_bar: ProgressBar
var _fill_style: StyleBoxFlat
var _finished: bool = false
var _reloading: bool = false


func _ready() -> void:
	var camera: Camera2D = $Player/Camera2D
	camera.limit_left = int(CAMERA_BOUNDS.position.x)
	camera.limit_top = int(CAMERA_BOUNDS.position.y)
	camera.limit_right = int(CAMERA_BOUNDS.end.x)
	camera.limit_bottom = int(CAMERA_BOUNDS.end.y)

	player.form_changed.connect(_on_player_form_changed)
	player.depleted.connect(_on_player_depleted)
	player.extinguished.connect(_on_player_extinguished)
	exit_gate.reached.connect(_on_exit_reached)
	_build_ui()


func _process(_delta: float) -> void:
	_amount_bar.value = player.amount


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset"):
		_restart()


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

	_amount_bar = ProgressBar.new()
	_amount_bar.custom_minimum_size = Vector2(240, 14)
	_amount_bar.min_value = 0.0
	_amount_bar.max_value = 1.0
	_amount_bar.show_percentage = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.1, 0.16, 0.85)
	bg_style.set_corner_radius_all(7)
	_amount_bar.add_theme_stylebox_override("background", bg_style)
	_fill_style = StyleBoxFlat.new()
	_fill_style.set_corner_radius_all(7)
	_amount_bar.add_theme_stylebox_override("fill", _fill_style)
	box.add_child(_amount_bar)

	var hint := Label.new()
	hint.text = "移动 A/D 或 ←/→    切换形态 Q    重置 R\n小心：火怕水滴 · 水怕煤块"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.72, 0.75, 0.82))
	box.add_child(hint)

	_message_label = Label.new()
	_message_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 42)
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	_message_label.visible = false
	layer.add_child(_message_label)

	_refresh_form_label()


func _on_player_form_changed(_form: int) -> void:
	_refresh_form_label()


func _refresh_form_label() -> void:
	if player.form == Player.Form.FIRE:
		_form_label.text = "当前形态：火（吃煤块）"
		_form_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
		_fill_style.bg_color = Color(1.0, 0.45, 0.22)
	else:
		_form_label.text = "当前形态：水（吸水滴）"
		_form_label.add_theme_color_override("font_color", Color(0.45, 0.75, 1.0))
		_fill_style.bg_color = Color(0.30, 0.62, 1.0)


func _on_player_depleted() -> void:
	if _finished or _reloading:
		return
	_show_message("元素耗尽……")
	await get_tree().create_timer(1.0).timeout
	_restart()


func _on_player_extinguished() -> void:
	if _finished or _reloading:
		return
	_show_message("被水熄灭了……")
	await get_tree().create_timer(1.2).timeout
	_restart()


func _on_exit_reached(_body: Node2D) -> void:
	if _finished or _reloading:
		return
	_finished = true
	player.input_enabled = false
	_show_message("到达终点！按 R 重新开始")


func _show_message(text: String) -> void:
	_message_label.text = text
	_message_label.visible = true
	_message_label.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(_message_label, "modulate:a", 1.0, 0.3)


func _restart() -> void:
	if _reloading:
		return
	_reloading = true
	get_tree().reload_current_scene()
