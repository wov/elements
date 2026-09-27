class_name UiFont
extends RefCounted
## 中文 HUD 字体：Godot 内置默认字体没有 CJK 字形，中文会显示成方块（乱码）。
## 主方案：打包的缝合像素字体（fusion-pixel 12px，OFL 开源，见 assets/fonts/），
## 各平台、导出版表现一致，像素风格也贴合游戏美术。
## 兜底：字体文件缺失时回退各系统自带 CJK 字体（macOS / Windows / Linux）。

const PIXEL_FONT_PATH := "res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf"

static var _cache: Font = null


static func cjk() -> Font:
	if _cache == null:
		_cache = _load_pixel_font()
		if _cache == null:
			_cache = _load_system_font()
	return _cache


## 给 Label 套上中文字体。
static func apply(label: Label) -> void:
	label.add_theme_font_override("font", cjk())


static func _load_pixel_font() -> Font:
	if not ResourceLoader.exists(PIXEL_FONT_PATH):
		push_warning("缺少打包字体 " + PIXEL_FONT_PATH + "，回退系统字体")
		return null
	return load(PIXEL_FONT_PATH) as Font


## 各平台常见的中文无衬线字体，按顺序回退。
static func _load_system_font() -> Font:
	var system := SystemFont.new()
	system.font_names = PackedStringArray([
		"PingFang SC", "Hiragino Sans GB",  # macOS
		"Microsoft YaHei", "SimHei",  # Windows
		"Noto Sans CJK SC", "WenQuanYi Micro Hei",  # Linux
	])
	return system
