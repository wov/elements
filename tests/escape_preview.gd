extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	change_scene_to_file("res://scenes/mobile/escape.tscn")
	await create_timer(0.6).timeout
	await shot("/tmp/elements_escape_start.png")
	var game:=current_scene
	game.set_physics_process(false)
	game.position_world=Vector2(210,2220-180)
	game.camera_y=2220-465
	game.collapse_y=game.position_world.y-600
	game.started=true
	game.hint="左侧水管快速穿岩 · 右侧绕行收集碎片"
	game._update_hud()
	game.queue_redraw()
	await shot("/tmp/elements_escape_choice.png")
	quit()
