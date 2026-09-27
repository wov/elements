class_name Rope
extends Node2D
## 引火绳：火形态碰到绳子即「钻进」绳中，火苗载着玩家沿绳快速滑行——
## 没有跳跃的游戏里，这是火专属的移动手段（横跨、爬升、斜上高台）。
## 滑行期间元素量锁定、移动由绳接管（即「期间保持元素状态不变」）；
## 玩家走过的绳段即刻烧断、触点反方向的剩余段被引燃，统统化作灰烬掉落
## （单程路径，走过的绳不复存在）；到达另一端玩家沿切向弹出、恢复控制。
## 途中按 Q 变水会立即脱绳落体。水形态不触发。可任意角度布置。
## 整根烧完后绳节点自行移除，仅两端系绳环留在锚点处。

signal ride_started
signal ride_finished

@export_group("布置")
## 绳两端（本节点局部坐标），可任意角度布置。
@export var point_a := Vector2(-120, 0)
@export var point_b := Vector2(120, 0)
## 绳中点自然下垂量（像素）；斜/垂直绳设 0。
@export var sag := 10.0

@export_group("滑行")
## 触发检测的粗细（沿绳方向胶囊体的直径）。
@export var touch_thickness := 24.0
## 玩家沿绳滑行速度（像素/秒）。
@export var ride_speed := 420.0
## 燃烧前沿（反方向剩余段 / 玩家脱绳后的残段）的烧速（像素/秒）。
@export var trail_burn_speed := 460.0
## 滑到端点后沿切向弹出的初速（像素/秒）。
@export var eject_speed := 240.0
## 灰烬碎屑生成密度（个/秒，每条燃烧前沿）。
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
var _front_a := 0.5  # 向 point_a 推进的前沿（递减到 0）
var _front_b := 0.5  # 向 point_b 推进的前沿（递增到 1）
var _burning := false
var _time := 0.0
var _ash_accum := 0.0
var _player: Player = null  # 滑行中的玩家（脱绳后置 null）
var _rider_dir := 1         # 滑行方向：+1 向 point_b，-1 向 point_a
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
	var inv_len := 1.0 / _length()
	if _player != null:
		# 玩家前沿由滑行驱动；另一侧的引燃前沿把身后的绳烧掉
		var step := ride_speed * delta * inv_len
		var trail := trail_burn_speed * delta * inv_len
		if _rider_dir > 0:
			_front_b = clampf(_front_b + step, 0.0, 1.0)
			_front_a = maxf(_front_a - trail, 0.0)
		else:
			_front_a = clampf(_front_a - step, 0.0, 1.0)
			_front_b = minf(_front_b + trail, 1.0)
		_carry_player()
	else:
		# 玩家脱绳后：双前沿把残段烧完
		var burn := trail_burn_speed * delta * inv_len
		_front_a = maxf(_front_a - burn, 0.0)
		_front_b = minf(_front_b + burn, 1.0)
	_update_line()
	_update_flames(delta)
	_update_light()
	if _front_a <= 0.0 and _front_b >= 1.0:
		_finish()


## 火形态玩家触碰即钻入绳中开始滑行；也可由其他机关直接调用。
func ride(player: Player) -> void:
	if _burning or _player != null or player == null:
		return
	if player.rope != null or player.form != Player.Form.FIRE or player.is_dead():
		return
	_burning = true
	_player = player
	player.drain_holds += 1
	player.rope = self
	var t := _nearest_t(to_local(player.global_position))
	_rider_dir = _pick_direction(player, t)
	_front_a = t
	_front_b = t
	_area.set_deferred("monitoring", false)
	ride_started.emit()


## 滑行方向：优先跟随玩家水平移动方向；静止或垂直绳则去较远的一端。
func _pick_direction(player: Player, t: float) -> int:
	var vx := player.velocity.x
	var span_x := point_b.x - point_a.x
	if absf(vx) > 10.0 and absf(span_x) > 1.0:
		return 1 if signf(vx) == signf(span_x) else -1
	return 1 if t < 0.5 else -1


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
	ride(player)


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


## 玩家贴着前沿沿绳移动；变水/消散立即脱绳，到端沿切向弹出。
func _carry_player() -> void:
	if _player == null:
		return
	if _player.form != Player.Form.FIRE or _player.is_dead():
		_eject(false)
		return
	var t := _front_b if _rider_dir > 0 else _front_a
	_player.global_position = to_global(_point_at(t))
	if (_rider_dir > 0 and _front_b >= 1.0) or (_rider_dir < 0 and _front_a <= 0.0):
		_eject(true)


## 脱绳：arrived = 滑到端点（沿切向弹出）；false = 中途脱离（直接落体）。
func _eject(arrived: bool) -> void:
	var player := _player
	_player = null
	if player == null:
		return
	player.rope = null
	player.drain_holds = maxf(player.drain_holds - 1, 0)
	if arrived:
		var end_t := 1.0 if _rider_dir > 0 else 0.0
		var tangent := _tangent_at(end_t) * float(_rider_dir)
		player.global_position = to_global(_point_at(end_t)) + tangent * 6.0
		player.external_impulse = tangent * eject_speed
	ride_finished.emit()


## t 处沿 +t 方向的单位切向（端点处取向内差分，避免零向量）。
func _tangent_at(t: float) -> Vector2:
	var eps := 1.0 / float(_SEGMENTS)
	var t0 := clampf(t - eps, 0.0, 1.0)
	var t1 := clampf(t + eps, 0.0, 1.0)
	if is_equal_approx(t0, t1):
		return Vector2.RIGHT
	return (_point_at(t1) - _point_at(t0)).normalized()


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
		_spawn_ash(_point_at(_pick_ash_front()) + Vector2(randf_range(-3.0, 3.0), randf_range(-2.0, 3.0)))
	# 滑行中玩家前沿不画火苗——玩家火苗本体就在那里
	var rider_on_a := _player != null and _rider_dir < 0
	var rider_on_b := _player != null and _rider_dir > 0
	_flame_a.visible = _front_a > 0.0 and not rider_on_a
	_flame_b.visible = _front_b < 1.0 and not rider_on_b
	_flame_a.position = _point_at(maxf(_front_a, 0.0))
	_flame_b.position = _point_at(minf(_front_b, 1.0))
	var flicker := 1.0 + 0.18 * sin(_time * 19.0)
	_flame_a.scale = Vector2(flicker, 2.0 - flicker * 0.6)
	_flame_b.scale = Vector2(flicker, 2.0 - flicker * 0.6)


## 灰从仍在燃烧的前沿掉落（两条前沿都活着就随机挑一条）。
func _pick_ash_front() -> float:
	var fronts := []
	if _front_a > 0.0:
		fronts.append(_front_a)
	if _front_b < 1.0:
		fronts.append(_front_b)
	if fronts.is_empty():
		return _front_a
	return fronts[randi() % fronts.size()]


func _update_light() -> void:
	var has_a := _flame_a.visible
	var has_b := _flame_b.visible
	_light.visible = has_a or has_b
	if has_a and has_b:
		_light.position = (_flame_a.position + _flame_b.position) * 0.5
	elif has_a:
		_light.position = _flame_a.position
	elif has_b:
		_light.position = _flame_b.position
	if _light.visible:
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
		_player.rope = null
		_player = null
	_keep_anchors()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_flame_a, "scale", Vector2.ZERO, 0.22)
	tween.tween_property(_flame_b, "scale", Vector2.ZERO, 0.22)
	tween.tween_property(_light, "energy", 0.0, 0.25)
	tween.chain().tween_callback(queue_free)


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
