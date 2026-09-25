class_name Backdrop
extends RefCounted
## 程序生成的三层视差布景（占位美术，正式资源就绪后可整体替换）：
## - 远景（scroll 0.12）：竖向渐变夜空 + 两重远山剪影 + 发光晶簇 + 微光尘点
## - 中景（scroll 0.45）：岩柱、残破石拱、顶部钟乳石
## - 前景（scroll 1.3，画在玩家前面）：地面草叶丛、垂下的藤蔓
## 随机数使用固定种子，每次生成的布景一致。
## 全部是默认画布里的 CanvasItem：会被 CanvasModulate 压暗，也会被火焰光照亮。

## 布景横向覆盖范围（关卡 0~2560，窗口 1280，留足视差滚动余量）
const LEFT := -500.0
const RIGHT := 3100.0


static func build_far(host: Node2D) -> void:
	var rng := _rng(20260925)

	var sky := Sprite2D.new()
	sky.texture = _sky_texture()
	sky.centered = false
	sky.position = Vector2(LEFT, -40.0)
	sky.scale = Vector2(RIGHT - LEFT, 820.0) / Vector2(16.0, 256.0)
	host.add_child(sky)

	_ridge(host, rng, 560.0, 150.0, Color(0.24, 0.20, 0.36))
	_crystals(host, rng)
	_motes(host, rng)
	_ridge(host, rng, 645.0, 85.0, Color(0.19, 0.16, 0.29))


static func build_mid(host: Node2D) -> void:
	var rng := _rng(4711)
	var x := LEFT + 220.0
	while x < RIGHT - 120.0:
		if rng.randf() < 0.25:
			_arch(host, rng, x)
			x += rng.randf_range(430.0, 640.0)
		else:
			_pillar(host, rng, x)
			x += rng.randf_range(230.0, 420.0)
	_stalactites(host, rng)


static func build_fore(host: Node2D) -> void:
	var rng := _rng(998)
	var x := LEFT + 100.0
	while x < RIGHT:
		_grass_tuft(host, rng, x, rng.randf_range(0.8, 1.3))
		x += rng.randf_range(75.0, 190.0)
	_vines(host, rng)


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## 竖向渐变夜空纹理（上暖紫、下近黑）。
static func _sky_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.30, 0.24, 0.46),
		Color(0.16, 0.14, 0.28),
		Color(0.07, 0.08, 0.15),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 16
	tex.height = 256
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	return tex


## 一重山脊剪影：随机锯齿多边形，向下填充到画面外。
static func _ridge(host: Node2D, rng: RandomNumberGenerator, base_y: float, amp: float, color: Color) -> void:
	var points := PackedVector2Array()
	points.append(Vector2(LEFT, 1000.0))
	var x := LEFT
	while x < RIGHT:
		points.append(Vector2(x, base_y - rng.randf_range(amp * 0.2, amp)))
		x += rng.randf_range(130.0, 260.0)
	points.append(Vector2(RIGHT, base_y - rng.randf_range(amp * 0.2, amp)))
	points.append(Vector2(RIGHT, 1000.0))
	var ridge := Polygon2D.new()
	ridge.polygon = points
	ridge.color = color
	host.add_child(ridge)


## 远山上零星的发光晶簇。
static func _crystals(host: Node2D, rng: RandomNumberGenerator) -> void:
	for i in 9:
		var shard := Polygon2D.new()
		var w := rng.randf_range(10.0, 22.0)
		shard.polygon = PackedVector2Array([
			Vector2(0, -rng.randf_range(70.0, 170.0)), Vector2(w, 0), Vector2(-w, 0),
		])
		shard.position = Vector2(rng.randf_range(LEFT + 100.0, RIGHT - 100.0), 560.0 - rng.randf_range(0.0, 60.0))
		shard.rotation = rng.randf_range(-0.15, 0.15)
		shard.color = Color(0.55, 0.45, 0.85, rng.randf_range(0.25, 0.45))
		host.add_child(shard)


## 空中漂浮的微光尘点。
static func _motes(host: Node2D, rng: RandomNumberGenerator) -> void:
	for i in 26:
		var dot := Polygon2D.new()
		dot.polygon = _circle(1.2 + rng.randf() * 1.6)
		dot.position = Vector2(rng.randf_range(LEFT, RIGHT), rng.randf_range(40.0, 420.0))
		dot.color = Color(0.8, 0.8, 1.0, rng.randf_range(0.12, 0.3))
		host.add_child(dot)


## 中景岩柱：略呈锥形、边缘带随机豁口。
static func _pillar(host: Node2D, rng: RandomNumberGenerator, x: float) -> void:
	var h := rng.randf_range(200.0, 420.0)
	var w := rng.randf_range(34.0, 60.0)
	var steps := 5
	var points := PackedVector2Array()
	for i in range(steps, -1, -1):
		var t := float(i) / float(steps)
		var half_w := w * lerpf(0.55, 1.0, 1.0 - t) + rng.randf_range(-4.0, 4.0)
		points.append(Vector2(-half_w, -h * t))
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var half_w := w * lerpf(0.55, 1.0, 1.0 - t) + rng.randf_range(-4.0, 4.0)
		points.append(Vector2(half_w, -h * t))
	var pillar := Polygon2D.new()
	pillar.polygon = points
	pillar.position = Vector2(x, 660.0)
	pillar.color = Color(0.27, 0.30, 0.40)
	host.add_child(pillar)


## 残破石拱：两根方柱 + 顶梁。
static func _arch(host: Node2D, rng: RandomNumberGenerator, x: float) -> void:
	var h := rng.randf_range(240.0, 340.0)
	var w := rng.randf_range(90.0, 130.0)
	var color := Color(0.24, 0.27, 0.36)
	for side in [-1.0, 1.0]:
		var pillar := Polygon2D.new()
		pillar.polygon = PackedVector2Array([
			Vector2(-14, 0), Vector2(-10, -h), Vector2(10, -h), Vector2(14, 0),
		])
		pillar.position = Vector2(x + side * w, 660.0)
		pillar.color = color
		host.add_child(pillar)
	var beam := Polygon2D.new()
	beam.polygon = PackedVector2Array([
		Vector2(-(w + 26.0), -h), Vector2(-(w + 22.0), -h - 26.0),
		Vector2(w + 22.0, -h - 26.0), Vector2(w + 26.0, -h),
	])
	beam.position = Vector2(x, 660.0)
	beam.color = color
	host.add_child(beam)


## 中景顶部的钟乳石。
static func _stalactites(host: Node2D, rng: RandomNumberGenerator) -> void:
	for i in 7:
		var spike := Polygon2D.new()
		var w := rng.randf_range(16.0, 34.0)
		spike.polygon = PackedVector2Array([
			Vector2(-w, -30.0), Vector2(0, rng.randf_range(90.0, 200.0)), Vector2(w, -30.0),
		])
		spike.position = Vector2(rng.randf_range(LEFT + 200.0, RIGHT - 200.0), 0)
		spike.color = Color(0.22, 0.25, 0.34)
		host.add_child(spike)


## 前景的草叶丛：数片细三角叶片，半透明避免挡住玩法。
static func _grass_tuft(host: Node2D, rng: RandomNumberGenerator, x: float, size: float) -> void:
	var color := Color(0.10, 0.13, 0.17, 0.88)
	for i in int(rng.randf_range(3.0, 6.0)):
		var blade := Polygon2D.new()
		var w := rng.randf_range(3.0, 5.5) * size
		blade.polygon = PackedVector2Array([
			Vector2(-w * 0.5, 0), Vector2(rng.randf_range(-10.0, 10.0), -rng.randf_range(14.0, 36.0) * size), Vector2(w * 0.5, 0),
		])
		blade.position = Vector2(x + rng.randf_range(-14.0, 14.0), 660.0)
		blade.color = color
		host.add_child(blade)


## 前景顶部垂下的藤蔓（末端一片叶）。
static func _vines(host: Node2D, rng: RandomNumberGenerator) -> void:
	for i in 6:
		var x := rng.randf_range(LEFT + 300.0, RIGHT - 300.0)
		var length := rng.randf_range(120.0, 240.0)
		var vine := Line2D.new()
		vine.width = rng.randf_range(3.0, 5.0)
		vine.default_color = Color(0.12, 0.15, 0.18, 0.9)
		var pts := PackedVector2Array()
		var y := -20.0
		var sway := 0.0
		while y < length:
			pts.append(Vector2(x + sin(y * 0.05 + float(i)) * 8.0 + sway, y))
			y += 24.0
			sway += rng.randf_range(-6.0, 6.0)
		vine.points = pts
		host.add_child(vine)
		var leaf := Polygon2D.new()
		leaf.polygon = PackedVector2Array([
			Vector2(0, -10.0), Vector2(9.0, 4.0), Vector2(-9.0, 4.0),
		])
		leaf.position = pts[pts.size() - 1]
		leaf.color = Color(0.13, 0.17, 0.16, 0.9)
		host.add_child(leaf)


static func _circle(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := TAU * float(i) / 6.0
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return points
