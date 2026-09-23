class_name CharacterFrames
extends RefCounted
## 生成主角的占位动画帧（SpriteFrames）。
## 正式美术就绪后，直接给 AnimatedSprite2D 换一份编辑器制作的 SpriteFrames 即可。
##
## 动画一览（均按「向右移动」绘制，向左由 flip_h 镜像）：
## - fire_idle / fire_move：火焰；移动时火苗向行进反方向拖曳（迎风变形）并略微收窄
## - water_idle / water_move：有张力的圆形水滴；静止时轻微张力呼吸，移动时横向拉伸

const FRAME_SIZE := 64

const FIRE_IDLE := "fire_idle"
const FIRE_MOVE := "fire_move"
const WATER_IDLE := "water_idle"
const WATER_MOVE := "water_move"


static func build() -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	_add_anim(frames, FIRE_IDLE, 6, 10.0)
	_add_anim(frames, FIRE_MOVE, 6, 14.0)
	_add_anim(frames, WATER_IDLE, 4, 6.0)
	_add_anim(frames, WATER_MOVE, 4, 10.0)
	return frames


static func _add_anim(frames: SpriteFrames, anim: String, count: int, fps: float) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, true)
	for i in count:
		var phase := float(i) / float(count)
		var tex: Texture2D = null
		match anim:
			FIRE_IDLE:
				tex = _texture(func(x: int, y: int) -> Color: return _fire_pixel(x, y, phase, 0.0))
			FIRE_MOVE:
				tex = _texture(func(x: int, y: int) -> Color: return _fire_pixel(x, y, phase, -0.42))
			WATER_IDLE:
				tex = _texture(func(x: int, y: int) -> Color: return _water_pixel(x, y, phase, 1.0, 0.92))
			WATER_MOVE:
				tex = _texture(func(x: int, y: int) -> Color: return _water_pixel(x, y, phase, 1.3, 0.8))
		frames.add_frame(anim, tex)


static func _texture(draw: Callable) -> Texture2D:
	var image := Image.create_empty(FRAME_SIZE, FRAME_SIZE, false, Image.FORMAT_RGBA8)
	for y in FRAME_SIZE:
		for x in FRAME_SIZE:
			image.set_pixel(x, y, draw.call(x, y))
	return ImageTexture.create_from_image(image)


## 火焰像素：底部宽、顶部收尖；中轴随高度摆动（帧相位制造跳动）。
## lean 为移动时的迎风拖曳量（负值 = 火苗向左拖曳，配 flip_h 使用）。
static func _fire_pixel(x: int, y: int, phase: float, lean: float) -> Color:
	var nx := (float(x) + 0.5 - 32.0) / 28.0
	var t := 1.0 - (float(y) + 0.5) / 56.0
	if t < 0.0 or t > 1.0:
		return Color(0, 0, 0, 0)
	var axis := sin(t * 5.5 + phase * TAU) * 0.14 * t + lean * pow(t, 1.5)
	var half_width := 0.62 * sqrt(maxf(0.0, 1.0 - t * t)) + 0.05
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
static func _water_pixel(x: int, y: int, phase: float, stretch_x: float, stretch_y: float) -> Color:
	var nx := (float(x) + 0.5 - 32.0) / 22.0
	var ny := (float(y) + 0.5 - 32.0) / 22.0
	var angle := atan2(ny, nx)
	var d := sqrt(pow(nx / stretch_x, 2.0) + pow(ny / stretch_y, 2.0))
	var tension := 1.0 + 0.05 * sin(3.0 * angle + phase * TAU)
	if d >= tension:
		return Color(0, 0, 0, 0)
	var depth := clampf((tension - d) * 1.6, 0.0, 1.0)
	var light := clampf(0.6 - (nx + ny) * 0.6, 0.0, 1.0) * depth
	var color := Color(0.16, 0.42, 0.95, 1.0).lerp(Color(0.80, 0.95, 1.0, 1.0), light)
	color.a = clampf((tension - d) * 7.0, 0.0, 1.0) * 0.92
	return color
