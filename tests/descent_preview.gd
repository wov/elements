extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	change_scene_to_file("res://scenes/mobile/descent.tscn")
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/elements_mobile_start.png")
	var game := current_scene
	game.position_world=Vector2(210,410)
	game.camera_y=190
	game.set_physics_process(false)
	game.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/elements_mobile_play.png")
	quit()
