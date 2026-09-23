class_name VisualFx
extends RefCounted
## 代码占位美术的共享小工具。


static var _soft_circle: Texture2D


## 柔和的圆形渐变贴图（白色，向边缘透明），供各类粒子使用。
static func soft_circle() -> Texture2D:
	if _soft_circle == null:
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
		var texture := GradientTexture2D.new()
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 16
		texture.height = 16
		texture.gradient = gradient
		_soft_circle = texture
	return _soft_circle
