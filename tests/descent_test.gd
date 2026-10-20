extends SceneTree
var game: Node2D
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, description: String) -> void:
	print(("PASS " if ok else "FAIL ") + description)
	if not ok: failures += 1
func ticks(count: int) -> void:
	for i in count:
		game._physics_process(1.0/60)
func run() -> void:
	game = (load("res://scenes/mobile/descent.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	ticks(30)
	check(game.grounded and absf(game.position_world.y-224)<1, "起点可安全停留")
	game.position_world = Vector2(80, 224)
	ticks(90)
	check(game.grounded and game.water and absf(game.position_world.y-410)<1, "水落在木板上停住")
	game.switch_form()
	ticks(75)
	check(not game.alive, "火烧穿木板后遇水失败")
	game.restart()
	check(game.alive and game.water and game.cleared==0, "一键重新开始")
	game.position_world = Vector2(210,410)
	game.switch_form()
	ticks(35)
	check(game.alive and game.position_world.y>450, "火能够烧穿木板")
	game.switch_form()
	ticks(55)
	check(game.alive and game.combo>=2, "及时变水可以安全通过水池")
	game.paused = true
	var before: Vector2 = game.position_world
	ticks(30)
	check(game.position_world == before, "暂停时重力与机关都停止")
	game.paused = false
	game.restart()
	var index := -1
	for i in game.objects.size():
		if game.objects[i].kind == "rope": index=i; break
	game.water=false
	game.position_world=game.objects[index].a
	game.velocity=Vector2.ZERO
	ticks(1)
	check(game.rider>=0, "火能够接住斜绳")
	var rope_start: Vector2 = game.position_world
	ticks(20)
	check(game.rider>=0 and game.position_world.distance_to(rope_start)>50, "绳子接管移动并推进")
	game.switch_form()
	check(game.rider==-1 and game.water, "变水立即脱绳")
	game.restart()
	game.best=100000
	game.position_world.x=80
	for frame in 6000:
		if game.position_world.y>300: game.position_world.x=210
		for o in game.objects:
			if o.used or o.kind == "rope": continue
			var distance: float = o.rect.position.y - game.position_world.y - 20
			if o.kind == "wood" and distance >= -1 and distance < 25 and game.water:
				game.switch_form()
			if o.kind == "pool" and distance >= 0 and distance < 110 and not game.water:
				game.switch_form()
		ticks(1)
		if not game.alive or game.cleared>=10: break
	check(game.alive and game.cleared>=10, "从起点按规则连续实跑10关，无需传送")
	game.restart()
	game.best=100000 # 不覆盖本机最佳成绩
	for stage in 40:
		game.position_world=Vector2(210, 330+stage*1120+1070)
		game.camera_y=game.position_world.y-285
		game.velocity=Vector2(0,310)
		ticks(15)
	check(game.cleared==40 and game.next_stage>40, "可以连续生成并通过40关")
	check(game.objects.size()<45, "回收旧片段，内存中的机关数量有界")
	game.restart()
	game._begin_pointer(0,Vector2(200,300))
	game._end_pointer(Vector2(201,301))
	check(not game.water, "触屏轻点切换")
	game._begin_pointer(0,Vector2(200,300))
	game._move_pointer(Vector2(250,300))
	game._end_pointer(Vector2(250,300))
	check(not game.water and game.position_world.x>210, "触屏拖动移动，不误切换")
	game.queue_free()
	await process_frame
	quit(failures)
