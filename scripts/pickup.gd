class_name ElementPickup
extends Area2D
## 场景补给与相克交互（全部用多边形 + 补间动画，无粒子）：
## - 煤块 × 火：播放「吃煤」动画并补充元素量，煤块消失
## - 煤块 × 水：水量被煤块吸走一部分（煤块不消失，有吸收间隔）
## - 水滴 × 水：靠近会被吸附飞来，融合后补充元素量
## - 水滴 × 火：火焰直接被熄灭（玩家死亡）

enum Kind { COAL, WATER }

@export var kind: Kind = Kind.COAL
@export var restore_amount: float = 0.4
## 煤块每次从水形态身上吸走的水量
@export var absorb_amount: float = 0.2
## 煤块两次吸水之间的间隔（秒）
@export var absorb_cooldown: float = 1.0
## 水滴被水形态吸附的起始距离（像素）
@export var attract_radius: float = 90.0

## 与玩家距离小于该值时水滴完成融合（像素）
const MERGE_DISTANCE := 20.0

var _visual: Node2D
var _consumed := false
var _absorb_timer := 0.0
var _attract_speed := 0.0
var _bob_tween: Tween


func _ready() -> void:
	_build_visual()
	if kind == Kind.WATER:
		_start_bob()
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_absorb_timer = maxf(_absorb_timer - delta, 0.0)
	if _consumed:
		return
	match kind:
		Kind.COAL:
			_update_coal()
		Kind.WATER:
			_update_drop(delta)


## 占位外观：煤块 = 棱角分明的深色石块（带一点余烬）；水滴 = 球形水珠。
func _build_visual() -> void:
	_visual = Node2D.new()
	add_child(_visual)

	if kind == Kind.COAL:
		var lump := Polygon2D.new()
		lump.polygon = PackedVector2Array([
			Vector2(-13, -6), Vector2(-6, -13), Vector2(4, -14), Vector2(13, -7),
			Vector2(15, 2), Vector2(8, 11), Vector2(-3, 13), Vector2(-12, 6),
		])
		lump.color = Color(0.13, 0.14, 0.18)
		_visual.add_child(lump)

		var facet := Polygon2D.new()
		facet.polygon = PackedVector2Array([
			Vector2(-6, -13), Vector2(4, -14), Vector2(2, -5), Vector2(-7, -5),
		])
		facet.color = Color(0.3, 0.32, 0.4)
		_visual.add_child(facet)

		var ember := Polygon2D.new()
		ember.polygon = PackedVector2Array([
			Vector2(-2, 6), Vector2(5, 3), Vector2(7, 9), Vector2(0, 10),
		])
		ember.color = Color(1.0, 0.45, 0.15, 0.9)
		_visual.add_child(ember)
	else:
		var drop := Polygon2D.new()
		drop.polygon = _circle_points(13.0)
		drop.color = Color(0.22, 0.5, 0.98)
		_visual.add_child(drop)

		var shine := Polygon2D.new()
		shine.polygon = _circle_points(4.0)
		shine.color = Color(0.75, 0.9, 1.0, 0.85)
		shine.position = Vector2(-4, -5)
		_visual.add_child(shine)


static func _circle_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 16:
		var angle := TAU * float(i) / 16.0
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return points


func _start_bob() -> void:
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(_visual, "position:y", -5.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(_visual, "position:y", 5.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 飞出的动画节点挂到当前场景（无主场景的测试环境下挂到父节点兜底）。
func _fx_host() -> Node:
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	return get_parent()


## 煤块：吸走正重叠的水形态玩家（带冷却）。
func _update_coal() -> void:
	if _absorb_timer > 0.0:
		return
	for body in get_overlapping_bodies():
		var player := body as Player
		if player and player.form == Player.Form.WATER and not player.is_dead():
			_drink(player)
			break


## 水滴：被附近的水形态玩家吸附，贴近后融合。
func _update_drop(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.form != Player.Form.WATER or player.is_dead():
		_attract_speed = 0.0
		return
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist > attract_radius:
		_attract_speed = 0.0
		return
	_attract_speed = minf(_attract_speed + 700.0 * delta, 430.0)
	global_position += to_player / maxf(dist, 0.001) * _attract_speed * delta
	# 飞行途中朝移动方向轻微拉长
	_visual.scale = _visual.scale.lerp(Vector2(1.25, 0.85), 10.0 * delta)
	if dist <= MERGE_DISTANCE:
		_merge(player)


func _on_body_entered(body: Node2D) -> void:
	if _consumed or not body is Player:
		return
	var player := body as Player
	if player.is_dead():
		return
	match kind:
		Kind.COAL:
			if player.form == Player.Form.FIRE:
				_eat(player)
		Kind.WATER:
			if player.form == Player.Form.FIRE:
				player.extinguish()
				_steam_pop()


## 吃煤：煤块碎成小块飞进火里，火苗满足地一鼓。
func _eat(player: Player) -> void:
	_consumed = true
	player.add_amount(restore_amount, true)
	for i in 3:
		_spawn_chunk(global_position + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0)), player, 0.06 * float(i))
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector2(0.1, 0.1), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_visual, "modulate:a", 0.0, 0.22)
	tween.tween_callback(queue_free)


func _spawn_chunk(from: Vector2, player: Player, delay: float) -> void:
	var chunk := Polygon2D.new()
	chunk.polygon = PackedVector2Array([
		Vector2(-3, -2), Vector2(2, -3), Vector2(3, 2), Vector2(-2, 3),
	])
	chunk.color = Color(0.16, 0.17, 0.22)
	chunk.global_position = from
	chunk.z_index = 4
	_fx_host().add_child(chunk)
	var start := chunk.global_position
	var tween := chunk.create_tween()
	tween.tween_interval(delay)
	tween.tween_method(
		func(t: float) -> void: chunk.global_position = start.lerp(player.global_position, t),
		0.0, 1.0, 0.28
	)
	tween.parallel().tween_property(chunk, "scale", Vector2(0.2, 0.2), 0.28)
	tween.tween_callback(chunk.queue_free)


## 煤吸水：几颗小水珠从玩家身上被拽进煤块，煤块鼓一下。
func _drink(player: Player) -> void:
	_absorb_timer = absorb_cooldown
	player.lose_amount(absorb_amount)
	for i in 3:
		_spawn_orb(player, 0.05 * float(i))
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector2(1.2, 1.2), 0.1)
	tween.tween_property(_visual, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _spawn_orb(player: Player, delay: float) -> void:
	var orb := Polygon2D.new()
	orb.polygon = _circle_points(3.5)
	orb.color = Color(0.4, 0.7, 1.0, 0.9)
	orb.global_position = player.global_position + Vector2(randf_range(-8.0, 8.0), randf_range(-10.0, 6.0))
	orb.z_index = 4
	_fx_host().add_child(orb)
	var start := orb.global_position
	var tween := orb.create_tween()
	tween.tween_interval(delay)
	tween.tween_method(
		func(t: float) -> void: orb.global_position = start.lerp(global_position, t),
		0.0, 1.0, 0.3
	)
	tween.parallel().tween_property(orb, "modulate:a", 0.0, 0.3)
	tween.tween_callback(orb.queue_free)


## 融合：水滴一头扎进玩家，泛起一圈涟漪。
func _merge(player: Player) -> void:
	_consumed = true
	if _bob_tween and _bob_tween.is_valid():
		_bob_tween.kill()
	player.add_amount(restore_amount)
	_spawn_ripple(global_position)
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector2(1.45, 1.45), 0.08)
	tween.tween_property(_visual, "scale", Vector2.ZERO, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _spawn_ripple(at: Vector2) -> void:
	var ripple := Polygon2D.new()
	ripple.polygon = _circle_points(8.0)
	ripple.color = Color(0.5, 0.78, 1.0, 0.5)
	ripple.position = at
	ripple.z_index = 3
	_fx_host().add_child(ripple)
	var tween := ripple.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ripple, "scale", Vector2(2.4, 2.4), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ripple, "modulate:a", 0.0, 0.35)
	tween.chain().tween_callback(ripple.queue_free)


## 火碰到水滴：水滴化作一小团蒸汽升走。
func _steam_pop() -> void:
	_consumed = true
	if _bob_tween and _bob_tween.is_valid():
		_bob_tween.kill()
	var steam := Polygon2D.new()
	steam.polygon = _circle_points(6.0)
	steam.color = Color(0.9, 0.94, 1.0, 0.6)
	steam.position = global_position
	steam.z_index = 3
	_fx_host().add_child(steam)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(steam, "position:y", steam.position.y - 26.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(steam, "scale", Vector2(2.0, 2.0), 0.4)
	tween.tween_property(steam, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(steam.queue_free)
	var mine := create_tween()
	mine.tween_property(_visual, "scale", Vector2.ZERO, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	mine.tween_callback(queue_free)
