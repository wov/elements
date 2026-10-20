extends "res://scripts/mobile/descent.gd"
## 一关有终点的逃生原型。继承输入/UI，另加实体管道运输、追赶压力和分支奖励。
const FINISH_Y := 9850.0
var collapse_y := -650.0
var started := false
var elapsed := 0.0
var gems := 0
var pipe: Dictionary = {}
var pipe_distance := 0.0
var won := false
var pipe_count := 0
var rope_count := 0
var last_rider := -1
var treasures: Array[Dictionary] = []

func restart() -> void:
	super.restart()
	rail_speed = 780.0
	objects.clear()
	next_stage = 100000 # 固定手工关卡，不调用无限生成。
	objects.append(_platform(120,244,180))
	collapse_y = -650
	elapsed = 0
	started = false
	won = false
	gems = 0
	pipe_count = 0
	rope_count = 0
	last_rider = -1
	pipe = {}
	treasures.clear()
	# 开场：向左找到蓝色管口，水穿越实体岩层；火不能进入。
	_add_pipe(PackedVector2Array([Vector2(95,540),Vector2(95,650),Vector2(325,760),Vector2(325,970)]), "水 → 钻管穿岩")
	objects.append(_platform(22,540,376))
	_add_rope(Vector2(325,1130),Vector2(85,1500))
	objects.append(_pool(1690))
	objects.append(_platform(100,1940,220))
	# 路线选择：左管穿岩层是安全捷径，右侧洞口为绕行收集路线。
	_add_branch(2220, true)
	_add_combo(3550, false)
	objects.append(_platform(100,4650,220))
	_add_branch(4950, false)
	_add_combo(6320, true)
	objects.append(_platform(100,7450,220))
	_add_branch(7750, true)
	objects.append({"kind":"wood","rect":Rect2(22,9040,376,18),"used":false})
	objects.append(_pool(9430))
	hint = "逃离坍塌！先向左滑出平台，变水进入蓝色管口"
	failure.hide()
	_update_hud()

func _platform(x: float, y: float, width: float) -> Dictionary:
	return {"kind":"safe","rect":Rect2(x,y,width,16),"used":false}

func _pool(y: float) -> Dictionary:
	return {"kind":"pool","rect":Rect2(22,y,376,30),"used":false}

func _add_pipe(points: PackedVector2Array, label: String) -> void:
	var length := 0.0
	for i in range(1,points.size()): length += points[i-1].distance_to(points[i])
	objects.append({"kind":"pipe","rect":Rect2(points[0]-Vector2(42,0),Vector2(84,20)),"points":points,"length":length,"used":false,"label":label})

func _add_rope(a: Vector2, b: Vector2) -> void:
	objects.append({"kind":"rope","a":a,"b":b,"used":false,"burn":0.0})

func _add_branch(y: float, left: bool) -> void:
	var entry := 85.0 if left else 335.0
	var exit_x := 115.0 if left else 305.0
	_add_pipe(PackedVector2Array([Vector2(entry,y),Vector2(entry,y+170),Vector2(exit_x,y+300),Vector2(exit_x,y+680)]), "安全捷径 / 水管")
	objects[-1]["risk_x"] = 345.0 if left else 75.0
	# 对侧留约110px宽的绕行口；选择前能看到金币与出口。
	objects.append(_platform(22 if left else 132,y+200,266))
	var risk_x := 345.0 if left else 75.0
	for i in 5:
		treasures.append({"p":Vector2(risk_x,y+160+i*82),"used":false})
	_add_rope(Vector2(risk_x,y+740),Vector2(210,y+920))
	objects.append(_pool(y+1020))

func _add_combo(y: float, left: bool) -> void:
	objects.append({"kind":"wood","rect":Rect2(22,y,376,18),"used":false})
	objects.append(_pool(y+380))
	var x := 80.0 if left else 340.0
	_add_rope(Vector2(x,y+580),Vector2(420-x,y+850))
	for i in 3:
		treasures.append({"p":Vector2(210,y+450+i*65),"used":false})

func _generate_stage() -> void:
	next_stage += 1 # 父类 restart 的临时生成钩子，随后由固定关卡替换。

func _resolve(previous: Vector2) -> void:
	for o in objects:
		if o.kind != "pipe" or o.used: continue
		var mouth: Rect2 = o.rect
		if previous.y+R <= mouth.position.y+2 and position_world.y+R >= mouth.position.y and absf(position_world.x-mouth.get_center().x)<48:
			if not water:
				position_world.y=mouth.position.y-R
				velocity.y=0
				grounded=true
				hint="管口只能进水 · 点按变水"
				return
			pipe=o
			pipe.used=true
			pipe_distance=0
			velocity=Vector2.ZERO
			pipe_count+=1
			_tone(480,0.20,430)
			_spawn_sparks(position_world,WATER,16)
			hint="水流穿岩！出口后找金色引火绳"
			return
	super._resolve(previous)
	if grounded and position_world.y>300:
		hint="坍塌不会停！找蓝色管口，或滑出平台继续逃生"

func switch_form() -> void:
	if not pipe.is_empty():
		hint="正在管道中流动 · 出口后可切换"
		return
	var before:=water
	super.switch_form()
	if before!=water: _tone(540 if water else 220,0.10,160)

func _physics_process(delta: float) -> void:
	if not alive or paused: return
	if not started and (position_world.y>250 or absf(position_world.x-210)>85): started=true
	if started:
		elapsed+=delta
		var gap := position_world.y-collapse_y
		collapse_y+=(175.0+clampf((gap-700.0)*0.9,0,420))*delta
	if pipe.is_empty():
		super._physics_process(delta)
	else:
		clock+=delta
		pipe_distance=minf(pipe.length,pipe_distance+620*delta)
		position_world=_pipe_point(pipe,pipe_distance)
		camera_y=lerpf(camera_y,maxf(0,position_world.y-285),minf(1,delta*9))
		if pipe_distance>=pipe.length:
			_spawn_sparks(position_world,WATER,18)
			pipe={}
			velocity.y=180
			combo+=1
	if rider>=0 and last_rider<0:
		rope_count+=1
		_tone(180,0.22,650)
	last_rider=rider
	for jewel in treasures:
		if not jewel.used and position_world.distance_to(jewel.p)<34:
			jewel.used=true
			gems+=1
			_tone(880,0.09,320)
			_spawn_sparks(jewel.p,Color("ffdf83"),12)
			hint="收集记忆碎片 +1 · 冒险路线奖励"
	if alive and started and position_world.y-collapse_y<24:
		_die("被坍塌追上了\n利用水管和引线拉开距离")
	if alive and position_world.y>FINISH_Y:
		won=true
		_tone(520,0.45,520)
		alive=false
		end_label.text="逃出生天！\n用时 %.1f 秒 · 碎片 %d / %d\n钻管 %d 次 · 接绳 %d 次\n\n再试试另一条路线？" % [elapsed,gems,treasures.size(),pipe_count,rope_count]
		failure.show()
	_update_hud()
	queue_redraw()

func _pipe_point(o: Dictionary, distance: float) -> Vector2:
	var points: PackedVector2Array=o.points
	var remaining:=distance
	for i in range(1,points.size()):
		var length:=points[i-1].distance_to(points[i])
		if remaining<=length: return points[i-1].lerp(points[i],remaining/length)
		remaining-=length
	return points[-1]

func _die(reason: String) -> void:
	_tone(190,0.35,-120)
	super._die(reason)
	end_label.text="还差 %d%% 就逃出去了\n用时 %.1f 秒 · 碎片 %d\n\n%s" % [int(clampf(1.0-position_world.y/FINISH_Y,0,1)*100),elapsed,gems,reason]

func _update_hud() -> void:
	if score_label==null: return
	score_label.text="逃生 %02d%%   碎片 %02d" % [int(clampf(position_world.y/FINISH_Y,0,1)*100),gems]
	form_label.text=("水 / 钻管穿岩" if water else "火 / 引线冲刺") + "   %.1f 秒" % elapsed
	form_label.modulate=WATER if water else FIRE
	var gap:=position_world.y-collapse_y
	hint_label.text=hint if gap>400 or not started else "坍塌逼近！"+hint
	switch_button.text="变火 · 接引线 / 烧穿" if water else "变水 · 钻管 / 入水"

func _build_ui() -> void:
	super._build_ui()
	for child in get_children():
		if child is CanvasLayer:
			for control in child.get_children():
				if control is Label and control.text=="ELEMENTS / 水火之间": control.text="水火逃生 / 一次逃离，一次选择"

func _draw() -> void:
	super._draw()
	if font==null: return
	# 裁剪新增世界效果，避免管道盖住顶底操作区。
	draw_set_transform(Vector2(0,-camera_y))
	for o in objects:
		if o.kind!="pipe": continue
		var points: PackedVector2Array=o.points
		for i in range(1,points.size()):
			var a: Vector2=points[i-1]
			var b: Vector2=points[i]
			if b.y-camera_y<180 or a.y-camera_y>690: continue
			var low:=maxf(a.y,camera_y+180)
			var high:=minf(b.y,camera_y+690)
			var aa:=a.lerp(b,(low-a.y)/maxf(1,b.y-a.y))
			var bb:=a.lerp(b,(high-a.y)/maxf(1,b.y-a.y))
			draw_line(aa,bb,Color("254f5e"),28,true)
			draw_line(aa,bb,Color("51b4c7"),3,true)
		if points[0].y-camera_y>200 and points[0].y-camera_y<660:
			draw_ellipse_mouth(points[0])
			_world_text(o.label,points[0]+Vector2(-60,-30),WATER)
			if o.has("risk_x"):
				_world_text("碎片绕行 ↓",Vector2(o.risk_x-43,points[0].y-30),Color("ffdf83"))
	if not pipe.is_empty():
		draw_circle(position_world,16,Color(WATER,0.22))
		draw_circle(position_world,9,WATER)
		draw_circle(position_world-Vector2(3,3),3,Color.WHITE)
	for jewel in treasures:
		if jewel.used or jewel.p.y-camera_y<185 or jewel.p.y-camera_y>680: continue
		var p: Vector2=jewel.p
		draw_circle(p,15,Color(1,0.75,0.3,0.08))
		draw_colored_polygon(PackedVector2Array([p+Vector2(0,-9),p+Vector2(6,0),p+Vector2(0,9),p-Vector2(6,0)]),Color("ffdf83"))
	draw_set_transform(Vector2.ZERO)
	var danger:=clampf(collapse_y-camera_y,180,690)
	if started and collapse_y-camera_y>160:
		draw_rect(Rect2(22,170,376,maxf(2,danger-170)),Color(0.65,0.21,0.14,0.28))
		for i in 18:
			var x:=22+i*22.0
			draw_colored_polygon(PackedVector2Array([Vector2(x,danger-8),Vector2(x+22,danger-8),Vector2(x+10,danger+12+sin(clock*4+i)*5)]),Color("c16b4d"))
	var margin := clampf((position_world.y-collapse_y)/1100.0,0,1)
	draw_rect(Rect2(24,174,372,3),Color("573b34"))
	draw_rect(Rect2(24,174,372*margin,3),Color("dba36b"))
	draw_rect(Rect2(24,163,372,4),Color("233d45"))
	draw_rect(Rect2(24,163,372*clampf(position_world.y/FINISH_Y,0,1),4),WATER)
	if grounded and position_world.y<300:
		draw_string(font,Vector2(54,335),"← 水管在左侧 · 滑出平台开始",HORIZONTAL_ALIGNMENT_LEFT,-1,16,WATER)
	if position_world.y>FINISH_Y-550:
		draw_string(font,Vector2(130,250),"洞口就在前方 ↓",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("ffdf83"))

func draw_ellipse_mouth(p: Vector2) -> void:
	draw_line(p-Vector2(40,0),p+Vector2(40,0),Color("57dfea"),10,true)
	draw_line(p-Vector2(32,0),p+Vector2(32,0),Color("102e3e"),4,true)


## 本地合成短音，不依赖外部音频；各反馈音自行清理。
func _tone(frequency: float, duration: float, slide: float) -> void:
	# 自动化回归无需创建音频节点。
	if DisplayServer.get_name()=="headless": return
	var rate:=22050
	var samples:=int(duration*rate)
	var bytes:=PackedByteArray()
	bytes.resize(samples*2)
	var phase:=0.0
	for i in samples:
		var t:=float(i)/samples
		phase+=TAU*(frequency+slide*t)/rate
		var envelope:=sin(t*PI)*0.16
		var value:=int(sin(phase)*envelope*32767)
		bytes[i*2]=value & 255
		bytes[i*2+1]=(value >> 8) & 255
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=rate
	stream.data=bytes
	var audio:=AudioStreamPlayer.new()
	audio.stream=stream
	add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()
