class_name CharacterFrames
extends RefCounted
## 生成主角的动画帧（SpriteFrames）。
## 没有正式美术的动画用程序生成的占位帧；有正式美术的用 _use_art_frames 替换。
##
## 动画一览（均按「向右移动」绘制，向左由 flip_h 镜像）：
## - fire_idle / fire_move：火焰（占位）；移动时火苗向行进反方向拖曳（迎风变形）并略微收窄
## - water_idle：水滴待机 —— 正式美术 8 帧（assets/water/idle/）
## - water_move：有张力的圆形水滴（占位）；移动时横向拉伸

const FRAME_SIZE := 128
const FIRE_TO_WATER := "fire_to_water"
const WATER_TO_FIRE := "water_to_fire"
static var _cached: SpriteFrames

const FIRE_IDLE := "fire_idle"
const FIRE_MOVE := "fire_move"
const WATER_IDLE := "water_idle"
const WATER_MOVE := "water_move"

## 水待机正式美术：assets/water/idle/1.png ~ 8.png（300×280，透明底）
const WATER_IDLE_DIR := "res://assets/water/idle/"
const WATER_IDLE_COUNT := 8
const WATER_IDLE_FPS := 8.0


static func build() -> SpriteFrames:
	if _cached != null:
		return _cached
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	_add_anim(frames, FIRE_IDLE, 12, 12.0)
	_add_anim(frames, FIRE_MOVE, 12, 18.0)
	_add_anim(frames, WATER_IDLE, 16, 12.0)
	_add_anim(frames, WATER_MOVE, 16, 18.0)
	# 原始水美术保留在 assets/water/idle，可随时调用 _use_art_frames 切回。
	_build_transition(frames, FIRE_TO_WATER, FIRE_IDLE, WATER_IDLE)
	_build_transition(frames, WATER_TO_FIRE, WATER_IDLE, FIRE_IDLE)
	_cached = frames
	return frames


## 用正式美术帧替换占位动画：图片构建时缩放进 64px 帧格，沿用既有标定
## （贴地高度、sprite_scale、百分比位置都不用动）。任一帧缺失就保留占位帧并告警，
## 方便美术资源按目录逐步补齐。
static func _use_art_frames(frames: SpriteFrames, anim: String, dir_path: String, count: int, fps: float) -> void:
	for i in count:
		if not ResourceLoader.exists(dir_path + str(i + 1) + ".png"):
			push_warning("正式美术帧缺失：" + dir_path + str(i + 1) + ".png，沿用占位帧")
			return
	frames.remove_animation(anim)
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, true)
	for i in count:
		var image := (load(dir_path + str(i + 1) + ".png") as Texture2D).get_image()
		image.resize(FRAME_SIZE, int(round(float(image.get_height()) * FRAME_SIZE / image.get_width())), Image.INTERPOLATE_LANCZOS)
		var canvas := Image.create_empty(FRAME_SIZE, FRAME_SIZE, false, Image.FORMAT_RGBA8)
		canvas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(0, FRAME_SIZE - image.get_height()))
		image = canvas
		frames.add_frame(anim, ImageTexture.create_from_image(image))


static func _add_anim(frames: SpriteFrames, anim: String, count: int, fps: float) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, true)
	for i in count:
		var phase := float(i) / float(count)
		var tex: Texture2D = null
		match anim:
			FIRE_IDLE:
				tex = _texture(func(x: float, y: float) -> Color: return _fire_pixel(x, y, phase, 0.0))
			FIRE_MOVE:
				tex = _texture(func(x: float, y: float) -> Color: return _fire_pixel(x, y, phase, -0.42 - 0.08 * sin(phase * TAU)))
			WATER_IDLE:
				tex = _texture(func(x: float, y: float) -> Color: return _water_pixel(x, y, phase, 1.0 + 0.018 * sin(phase * TAU), 0.96 - 0.018 * sin(phase * TAU)))
			WATER_MOVE:
				tex = _texture(func(x: float, y: float) -> Color: return _water_pixel(x, y, phase, 1.14 + 0.045 * sin(phase * TAU), 0.86 - 0.025 * sin(phase * TAU)))
		frames.add_frame(anim, tex)


static func _texture(draw: Callable) -> Texture2D:
	var image := Image.create_empty(FRAME_SIZE, FRAME_SIZE, false, Image.FORMAT_RGBA8)
	for y in FRAME_SIZE:
		for x in FRAME_SIZE:
			image.set_pixel(x, y, draw.call(float(x) * 64.0 / FRAME_SIZE, float(y) * 64.0 / FRAME_SIZE))
	return ImageTexture.create_from_image(image)


## 火焰像素：底部宽、顶部收尖；中轴随高度摆动（帧相位制造跳动）。
## lean 为移动时的迎风拖曳量（负值 = 火苗向左拖曳，配 flip_h 使用）。
static func _fire_pixel(x: float, y: float, phase: float, lean: float) -> Color:
	var nx := (float(x) + 0.5 - 32.0) / 28.0
	var t := 1.0 - (float(y) + 0.5) / 56.0
	if t < 0.0 or t > 1.0:
		return Color(0, 0, 0, 0)
	var axis := sin(t * 5.5 + phase * TAU) * 0.14 * t + lean * pow(t, 1.5)
	var half_width := (0.62 + 0.035 * sin(phase * TAU)) * sqrt(maxf(0.0, 1.0 - t * t)) + 0.05
	if absf(lean) > 0.0:
		half_width *= 0.88
	var d := absf(nx - axis) / half_width
	if d >= 1.0:
		return Color(0, 0, 0, 0)
	var alpha := clampf((1.0 - d) * 2.2, 0.0, 1.0)
	var heat := clampf((1.0 - d * 0.55) * (1.15 - t * 0.85) + 0.08 * sin(phase * TAU), 0.0, 1.0)
	var color := Color(1.0, 0.25 + 0.6 * heat, 0.08 + 0.35 * heat)
	color.a = alpha
	return color


## 水滴像素：圆形 + 表面张力式的小幅半径波动（帧相位制造抖动）。
## stretch_x / stretch_y 控制移动时的拉伸。
static func _water_pixel(x: float, y: float, phase: float, stretch_x: float, stretch_y: float) -> Color:
	var nx := (float(x) + 0.5 - 32.0) / 22.0
	var ny := (float(y) + 0.5 - 32.0) / 22.0
	var angle := atan2(ny, nx)
	var d := sqrt(pow(nx / stretch_x, 2.0) + pow(ny / stretch_y, 2.0))
	var tension := 1.0 + 0.05 * sin(3.0 * angle + phase * TAU)
	if d >= tension:
		return Color(0, 0, 0, 0)
	var edge := clampf((tension - d) * 18.0, 0.0, 1.0)
	var rim := pow(clampf(d / tension, 0.0, 1.0), 5.0)
	var flow := sin(ny * 15.0 + phase * TAU + sin(nx * 6.0 - phase * TAU)) * 0.5 + 0.5
	var color := Color(0.055, 0.32, 0.72).lerp(Color(0.12, 0.68, 0.9), clampf(0.55 - ny * 0.3 + flow * 0.16, 0.0, 1.0))
	color = color.lerp(Color(0.45, 0.9, 1.0), rim * 0.65)
	var highlight := exp(-((nx + 0.35) * (nx + 0.35) / 0.04 + (ny + 0.42) * (ny + 0.42) / 0.015))
	var small_glint := exp(-((nx + 0.56) * (nx + 0.56) / 0.007 + (ny + 0.14) * (ny + 0.14) / 0.018))
	color = color.lerp(Color(0.94, 1.0, 1.0), clampf(highlight + small_glint * 0.7, 0.0, 1.0))
	color.a = edge * (0.82 + rim * 0.16)
	return color


## 移动沿用水待机美术，以周期拉伸、压缩表现表面张力。
static func _build_water_move(frames: SpriteFrames) -> void:
	frames.remove_animation(WATER_MOVE)
	frames.add_animation(WATER_MOVE)
	frames.set_animation_speed(WATER_MOVE, 12.0)
	for i in WATER_IDLE_COUNT:
		var source := frames.get_frame_texture(WATER_IDLE, i % frames.get_frame_count(WATER_IDLE)).get_image()
		var pulse := sin(float(i) / WATER_IDLE_COUNT * TAU)
		var result := Image.create_empty(FRAME_SIZE, FRAME_SIZE, false, Image.FORMAT_RGBA8)
		var sx := 1.08 + 0.05 * pulse
		var sy := 0.88 - 0.04 * pulse
		for y in FRAME_SIZE:
			for x in FRAME_SIZE:
				var px := int((x - FRAME_SIZE * 0.5) / sx + FRAME_SIZE * 0.5)
				var py := int((y - FRAME_SIZE * 0.78) / sy + FRAME_SIZE * 0.78)
				if px >= 0 and px < FRAME_SIZE and py >= 0 and py < FRAME_SIZE:
					result.set_pixel(x, y, source.get_pixel(px, py))
		frames.add_frame(WATER_MOVE, ImageTexture.create_from_image(result))


## 非循环转换动画：旧形态收束，颜色与轮廓平滑过渡到新形态。
static func _build_transition(frames: SpriteFrames, anim: String, before: String, after: String) -> void:
	frames.add_animation(anim)
	frames.set_animation_loop(anim, false)
	frames.set_animation_speed(anim, 24.0)
	var a := frames.get_frame_texture(before, 0).get_image()
	var b := frames.get_frame_texture(after, 0).get_image()
	for i in 12:
		var t := smoothstep(0.0, 1.0, float(i) / 11.0)
		var image := Image.create_empty(FRAME_SIZE, FRAME_SIZE, false, Image.FORMAT_RGBA8)
		for y in FRAME_SIZE:
			for x in FRAME_SIZE:
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				var alpha := lerpf(ca.a, cb.a, t)
				var rgb := Vector3(ca.r, ca.g, ca.b) * ca.a * (1.0 - t) + Vector3(cb.r, cb.g, cb.b) * cb.a * t
				if alpha > 0.001:
					rgb /= alpha
				image.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, alpha))
		frames.add_frame(anim, ImageTexture.create_from_image(image))
