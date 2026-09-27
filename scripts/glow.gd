class_name Glow
extends RefCounted
## 径向渐变光照纹理：中心亮、向边缘平滑衰减到全透明。逐像素生成，
## 保证内切圆以外（包括正方形四角）alpha 恒为 0，不会露出方形光斑。
## 带缓存，Player 火焰与绳子燃烧前沿共用。


static var _cache: Dictionary = {}


static func radial(size: int, falloff_power: float = 1.8) -> ImageTexture:
	var key := "%d|%f" % [size, falloff_power]
	if _cache.has(key):
		return _cache[key]
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var nx := (float(x) + 0.5) / float(size) * 2.0 - 1.0
			var ny := (float(y) + 0.5) / float(size) * 2.0 - 1.0
			var d := sqrt(nx * nx + ny * ny)
			var falloff := clampf(1.0 - d, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, pow(falloff, falloff_power)))
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture
