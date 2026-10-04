class_name ElementMorph
extends Node2D
## 身体采样成光点：爆散、旋转、聚拢；跟随主角，兼容移动中转换。
var progress := 0.0
var _pieces: Array[Dictionary] = []

func configure(before: Texture2D, after: Texture2D, display_scale: float) -> void:
	var a := before.get_image()
	var b := after.get_image()
	var starts := _samples(a, display_scale)
	var ends := _samples(b, display_scale)
	var count := maxi(starts.size(), ends.size())
	for i in count:
		var first: Dictionary = starts[i % starts.size()]
		var last: Dictionary = ends[i % ends.size()]
		var angle := float(i) * 2.399963
		_pieces.append({"from": first.position, "to": last.position, "a": first.color, "b": last.color,
			"orbit": Vector2(cos(angle), sin(angle)) * (38.0 + float(i % 7) * 5.0), "size": 1.4 + float(i % 3) * 0.45})
	var material := CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	self.material = material

func _samples(image: Image, display_scale: float) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	for y in range(4, image.get_height(), 8):
		for x in range(4, image.get_width(), 8):
			var color := image.get_pixel(x, y)
			if color.a > 0.3:
				samples.append({"position": (Vector2(x, y) - Vector2(image.get_size()) * 0.5) * display_scale, "color": color})
	if samples.is_empty():
		samples.append({"position": Vector2.ZERO, "color": Color.WHITE})
	return samples

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var spread := sin(progress * PI)
	var turn := progress * TAU * 0.65
	var blend := smoothstep(0.15, 0.85, progress)
	for piece in _pieces:
		var position: Vector2 = piece.from.lerp(piece.to, blend) + piece.orbit.rotated(turn) * spread
		var color: Color = piece.a.lerp(piece.b, blend)
		color.a = minf(progress * 12.0, 1.0) * minf((1.0 - progress) * 12.0, 1.0)
		var radius: float = piece.size
		draw_circle(position, radius * 3.5, Color(color, color.a * 0.10))
		draw_circle(position, radius * 1.8, Color(color, color.a * 0.25))
		draw_circle(position, radius, color)
		draw_circle(position - Vector2(0.4, 0.4), radius * 0.4, Color(1, 1, 1, color.a * 0.85))
