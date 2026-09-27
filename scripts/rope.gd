class_name Rope
extends Node2D
## 可燃绳：火形态的主角碰到即点燃，火苗从触点向两端蔓延；
## 蔓延期间玩家元素量锁定不衰竭（Player.drain_holds，即「期间保持元素状态不变」），
## 烧过的绳段化作灰烬碎屑掉落，整根烧完后绳节点自行移除，仅两端系绳环留在锚点处。
## 水形态不触发。可任意角度布置（水平拉索 / 垂挂皆可）。

signal burn_started
signal burn_finished

@export_group("布置")
## 绳两端（本节点局部坐标），可任意角度。
@export var point_a := Vector2(-120, 0)
@export var point_b := Vector2(120, 0)
## 绳中点自然下垂量（像素）。
@export var sag := 10.0

@export_group("燃烧")
## 触发检测的粗细（沿绳方向胶囊体的直径）。
@export var touch_thickness := 24.0
## 火苗蔓延速度（像素/秒）。
@export var burn_speed := 240.0
## 灰烬碎屑生成密度（个/秒，每条蔓延前沿）。
@export var ash_rate := 14.0

@export_group("外观")
@export var rope_color := Color(0.72, 0.55, 0.32)
@export var rope_width := 5.0
## 前沿火苗的光照强度（PointLight2D energy）。
@export var front_light_energy := 0.6

const _SEGMENTS := 24
const _ASH_GROUP := "rope_ash"

var _points: PackedVector2Array = []
var _knots: Array[Line2D] = []
var _knot_indices: Array[int] = []
var _front_a := 0.5  # 前沿 A 的参数位置（0~1，向 point_a 推进，递减）
var _front_b := 0.5  # 前沿 B 的参数位置（向 point_b 推进，递增）
var _burning := false
var _time := 0.0
var _ash_accum := 0.0
var _player: Player = null
var _line: Line2D
var _area: Area2D
var _flame_a: Node2D
var _flame_b: Node2D
var _light: PointLight2D
var _anchor_a: Node2D
var _anchor_b: Node2D


func _ready() -> void:
	_build_points()
	_build_visual()
	_build_area()


func _physics_process(delta: float) -> void:
	_time += delta
	if not _burning:
		return
	var step := burn_speed * delta / _length()
	_front_a = maxf(_front_a - step, 0.0)
	_front_b = minf(_front_b + step, 1.0)
	_update_line()
	_update_flames(delta)
	_update_light()
	if _front_a <= 0.0 and _front_b >= 1.0:
		_finish()


## 火形态玩家触碰点燃；也可由其他机关直接调用。
func ignite(player: Player) -> void:
	if _burning or player == null:
		return
	_burning = true
	_player = player
	player.drain_holds += 1
	var t := _nearest_t(to_local(player.global_position))
	_front_a = t
	_front_b = t
	_area.set_deferred("monitoring", false)
	burn_started.emit()


func _build_points() -> void:
	for i in _SEGMENTS + 1:
		_points.append(_point_at(float(i) / float(_SEGMENTS)))


## 两端点 + 下垂控制点的二次贝塞尔绳形。
func _point_at(t: float) -> Vector2:
	var control := (point_a + point_b) * 0.5 + Vector2(0, sag * 1.4)
	var u := 1.0 - t
	return point_a * (u * u) + control * (2.0 * u * t) + point_b * (t * t)


func _build_visual() -> void:
	_line = Line2D.new()
	_line.width = rope_width
	_line.default_color = rope_color
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line.points = _points
	add_child(_line)

	# 绞纹：沿绳错开的短划线，像三股麻绳（记录所在段号，烧过即隐藏）
	for i in range(2, _SEGMENTS, 3):
		var knot := Line2D.new()
		var dir := (_points[i + 1] - _points[i - 1]).normalized()
		knot.points = PackedVector2Array([_points[i] - dir * 3.0, _points[i] + dir * 3.0])
		knot.width = rope_width * 0.5
		knot.default_color = rope_color.darkened(0.3)
		add_child(knot)
		_knots.append(knot)
		_knot_indices.append(i)

	# 两端系绳环：绳烧完移除后仍留在锚点处
	_anchor_a = _make_anchor(point_a)
	_anchor_b = _make_anchor(point_b)

	_flame_a = _make_flame()
	_flame_b = _make_flame()
	_flame_a.visible = false
	_flame_b.visible = false

	_light = PointLight2D.new()
	_light.texture = Glow.radial(128, 1.6)
	_light.color = Color(1.0, 0.72, 0.42)
	_light.energy = front_light_energy
	_light.texture_scale = 0.55
	_light.visible = false
	add_child(_light)


## 前沿小火苗：焦黑断面 + 外橙内黄两层三角。
func _make_flame() -> Node2D:
	var flame := Node2D.new()
	var scorch := Polygon2D.new()
	scorch.polygon = PackedVector2Array([Vector2(-3, 3), Vector2(3, 3), Vector2(3, -3), Vector2(-3, -3)])
	scorch.color = Color(0.12, 0.1, 0.1, 0.9)
	flame.add_child(scorch)
	var outer := Polygon2D.new()
	outer.polygon = PackedVector2Array([Vector2(-5, 2), Vector2(0, -13), Vector2(5, 2), Vector2(0, 6)])
	outer.color = Color(0.95, 0.45, 0.15, 0.95)
	flame.add_child(outer)
	var inner := Polygon2D.new()
	inner.polygon = PackedVector2Array([Vector2(-2.5, 1), Vector2(0, -7), Vector2(2.5, 1), Vector2(0, 4)])
	inner.color = Color(1.0, 0.85, 0.4)
	flame.add_child(inner)
	add_child(flame)
	return flame


## 端点系绳环：深色小铁环，标记绳的固定端。
func _make_anchor(at: Vector2) -> Node2D:
	var anchor := Node2D.new()
	var ring := Polygon2D.new()
	ring.polygon = _ring_points(5.5, 3.2, 12)
	ring.color = Color(0.2, 0.22, 0.28)
	anchor.add_child(ring)
	anchor.position = at
	add_child(anchor)
	return anchor


## 圆环多边形（outer/inner 半径交替的星形顶点）。
func _ring_points(outer: float, inner: float, count: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in count * 2:
		var radius := outer if i % 2 == 0 else inner
		var ang := TAU * float(i) / float(count * 2)
		pts.append(Vector2(cos(ang), sin(ang)) * radius)
	return pts


## 沿绳的胶囊检测区（下垂不大时直线近似足够）。
func _build_area() -> void:
	_area = Area2D.new()
	_area.position = (point_a + point_b) * 0.5
	_area.rotation = (point_b - point_a).angle()
	var shape := CapsuleShape2D.new()
	shape.height = _length() + touch_thickness
	shape.radius = touch_thickness * 0.5
	var collision := CollisionShape2D.new()
	collision.shape = shape
	_area.add_child(collision)
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)


func _on_body_entered(body: Node2D) -> void:
	if _burning or not (body is Player):
		return
	var player := body as Player
	if player.form != Player.Form.FIRE or player.is_dead():
		return
	ignite(player)


func _length() -> float:
	return point_a.distance_to(point_b)


## 玩家触点 → 最近的绳参数位置（0~1）。
func _nearest_t(local_pos: Vector2) -> float:
	var best_t := 0.0
	var best_d := INF
	for i in _SEGMENTS + 1:
		var d := _points[i].distance_squared_to(local_pos)
		if d < best_d:
			best_d = d
			best_t = float(i) / float(_SEGMENTS)
	return best_t


## 剩余绳段 = [0, 前沿A] + [前沿B, 1]，烧过的部分从线上即时移除。
func _update_line() -> void:
	var ia := int(floor(_front_a * float(_SEGMENTS) + 1e-4))
	var ib := int(ceil(_front_b * float(_SEGMENTS) - 1e-4))
	var remaining := PackedVector2Array()
	for i in ia + 1:
		remaining.append(_points[i])
	for i in range(ib, _SEGMENTS + 1):
		remaining.append(_points[i])
	_line.points = remaining
	# 绞纹随所在绳段一并消失（ia~ib 之间是烧掉的部分）
	for k in _knots.size():
		var i := _knot_indices[k]
		_knots[k].visible = i <= ia or i >= ib


func _update_flames(delta: float) -> void:
	_ash_accum += ash_rate * delta
	while _ash_accum >= 1.0:
		_ash_accum -= 1.0
		# 从仍在燃烧的前沿掉灰（两个前沿都活着就随机挑一个）
		var t := _front_a
		if _front_a <= 0.0 or (_front_b < 1.0 and randf() < 0.5):
			t = _front_b
		_spawn_ash(_point_at(t) + Vector2(randf_range(-3.0, 3.0), randf_range(-2.0, 3.0)))
	_flame_a.visible = _front_a > 0.0
	_flame_b.visible = _front_b < 1.0
	_flame_a.position = _point_at(_front_a)
	_flame_b.position = _point_at(_front_b)
	var flicker := 1.0 + 0.18 * sin(_time * 19.0)
	_flame_a.scale = Vector2(flicker, 2.0 - flicker * 0.6)
	_flame_b.scale = Vector2(flicker, 2.0 - flicker * 0.6)


func _update_light() -> void:
	_light.visible = true
	var mid_t := (_front_a + _front_b) * 0.5
	_light.position = _point_at(mid_t)
	_light.energy = front_light_energy * (1.0 + 0.1 * sin(_time * 17.0))


## 灰烬碎屑：灰白小片（夹带三成余烬色）掉落、旋转、淡出。
func _spawn_ash(at: Vector2) -> void:
	var host := _fx_host()
	var chunk := Polygon2D.new()
	var s := 3.0 + randf() * 3.5
	chunk.polygon = PackedVector2Array([
		Vector2(-s, -s * 0.5), Vector2(s * 0.8, -s * 0.6),
		Vector2(s, s * 0.5), Vector2(-s * 0.7, s * 0.6),
	])
	if randf() < 0.3:
		chunk.color = Color(0.9, 0.4, 0.15, 0.95)
	else:
		chunk.color = Color(0.45, 0.43, 0.46, 0.95)
	chunk.add_to_group(_ASH_GROUP)
	host.add_child(chunk)
	chunk.global_position = to_global(at)
	var fall := 55.0 + randf() * 75.0
	var tween := chunk.create_tween()
	tween.set_parallel(true)
	tween.tween_property(chunk, "position:y", chunk.position.y + fall, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(chunk, "position:x", chunk.position.x + randf_range(-20.0, 20.0), 0.8)
	tween.tween_property(chunk, "rotation", randf_range(-2.5, 2.5), 0.8)
	tween.chain().tween_property(chunk, "modulate:a", 0.0, 0.35)
	tween.chain().tween_callback(chunk.queue_free)


func _finish() -> void:
	set_physics_process(false)
	if _player != null:
		_player.drain_holds = maxf(_player.drain_holds - 1, 0)
	_keep_anchors()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_flame_a, "scale", Vector2.ZERO, 0.22)
	tween.tween_property(_flame_b, "scale", Vector2.ZERO, 0.22)
	tween.tween_property(_light, "energy", 0.0, 0.25)
	tween.chain().tween_callback(queue_free)
	burn_finished.emit()


## 绳整体移除前，把两端系绳环转挂到父节点，留在锚点处。
func _keep_anchors() -> void:
	var host := get_parent()
	if host == null:
		return
	for anchor: Node2D in [_anchor_a, _anchor_b]:
		if anchor == null:
			continue
		var pos := anchor.global_position
		remove_child(anchor)
		host.add_child(anchor)
		anchor.global_position = pos


## 灰烬等临时节点挂到当前场景（无主场景的测试环境下挂到父节点兜底）。
func _fx_host() -> Node:
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	return get_parent()
