extends SceneTree
var game: Node2D
var failures:=0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, title: String) -> void:
	print(("PASS " if ok else "FAIL ")+title)
	if not ok: failures+=1
func tick(n: int) -> void:
	for i in n: game._physics_process(1.0/60)
func run_route(risky: bool) -> void:
	game.restart()
	game.set_physics_process(false)
	var target_x:=95.0
	for frame in 7200:
		if not game.alive: break
		if game.pipe.is_empty() and game.rider<0:
			var nearest: Dictionary={}
			var nearest_distance:=99999.0
			for o in game.objects:
				if o.used: continue
				var oy: float=o.a.y if o.kind=="rope" else o.rect.position.y
				var distance: float=oy-game.position_world.y-20
				if distance < -3: continue
				if distance<nearest_distance:
					nearest=o
					nearest_distance=distance
			if not nearest.is_empty():
				match nearest.kind:
					"pipe":
						if risky and nearest.rect.position.y>2000:
							target_x=345 if nearest.points[0].x<210 else 75
						else:
							target_x=nearest.points[0].x
							if not game.water: game.switch_form()
					"rope":
						target_x=nearest.a.x
						if game.water: game.switch_form()
					"pool":
						if nearest_distance<140 and not game.water: game.switch_form()
					"wood":
						if nearest_distance<100 and game.water: game.switch_form()
					"safe":
						target_x=70 if nearest.rect.position.x>80 else 350
			game.position_world.x=move_toward(game.position_world.x,target_x,4.0)
		game._physics_process(1.0/60)
	print("ROUTE ",risky," won=",game.won," y=",game.position_world.y," time=",game.elapsed," pipes=",game.pipe_count," ropes=",game.rope_count," gems=",game.gems," hint=",game.hint)
	check(game.won,"完整路线可逃出生天（冒险=%s）" % risky)
	check(game.pipe_count>=1 and game.rope_count>=1,"完成钻管与接绳连锁")
func run() -> void:
	game=(load("res://scenes/mobile/escape.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	tick(600)
	check(not game.started and game.alive,"起点观察不触发坍塌倒计时")
	game.water=false
	game.position_world=Vector2(95,518)
	game.velocity=Vector2(0,100)
	tick(3)
	check(game.grounded and game.pipe.is_empty(),"火无法进入水管，停在管口")
	game.switch_form()
	tick(3)
	check(not game.pipe.is_empty(),"在管口变水后开始运输")
	var before: Vector2=game.position_world
	game.paused=true
	tick(30)
	check(game.position_world==before,"管道中暂停不会继续运输")
	game.paused=false
	game.switch_form()
	check(game.water,"管道内不允许切火卡进岩层")
	run_route(false)
	run_route(true)
	check(game.gems>0,"冒险路线可收集碎片")
	game.restart()
	game.started=true
	tick(420)
	check(not game.alive and not game.won,"停滞被坍塌追上时明确失败")
	game.restart()
	check(game.alive and game.gems==0 and game.pipe.is_empty(),"重来清空上一局状态")
	game.queue_free()
	await process_frame
	quit(failures)
