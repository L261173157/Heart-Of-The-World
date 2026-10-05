## 既有开门证据的装配顺序回归：真实主场景、菜单按钮、磁盘独立冷启动。
## 最小已验证账本是明确的恢复夹具，不宣称本测试实走了前置任务或讨伐Boss。
extends Node
const Data:=preload("res://scripts/main/campaign_quest_data.gd")
const Catalog:=preload("res://scripts/main/campaign_catalog.gd")
const TIMERS:={"heal":5.0,"heavy":2.0,"empower":7.0,"empower_buff":2.0,"dash":0.7}
var _checks:=0
var _fails:=0
var _world: Node
var _player: Player

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled=false
	_run.call_deferred()

func _check(ok: bool,label: String) -> void:
	_checks+=1
	if not ok: _fails+=1
	print("  %s  %s" % ["PASS" if ok else "FAIL",label])

func _frames(n:=3) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame

func _door() -> Vector2:
	var cells:=CampaignLayout.gate_cells("side_troll:room_gate")
	return (Vector2(cells[cells.size()/2])+Vector2.ONE*0.5)*32.0

func _normalized(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _enter() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await _frames()
	_world=get_tree().current_scene
	_player=_world.get_node("Player") as Player

func _verify(expected: Dictionary,label: String) -> void:
	var inside:=_door()+Vector2(0,-128)
	_check(_player.global_position==inside,label+"开门房内位置逐位保持")
	_check(_player.current_hp==87.0 and _player.current_mp==23.0,label+"血蓝逐位保持")
	var timers: Dictionary=_player.save_snapshot().get("combat_timers",{})
	for key: String in TIMERS:
		_check(is_equal_approx(float(timers.get(key,-1)),TIMERS[key]),label+"保留已付计时 "+key)
	var host:=get_tree().get_first_node_in_group("campaign_quest") as CampaignQuest
	_check("side_troll:room_gate" in host.visual_state().open_gates,label+"运行时仍有真实开门证据")
	_check("side_troll:room_gate" in CampaignQuest.open_gates_from(GameState.campaign_quest),label+"入树前投影与运行时同源")
	if not expected.is_empty():
		_check(_normalized(GameState.campaign_quest)==expected.campaign,label+"不追加任何任务或Boss证据")
		_check(_normalized(WorldSim.sim.to_dict())==expected.ecology and WorldSim.day_time==float(expected.day_time)
			and WorldSim.game_day==int(expected.game_day),label+"整个生态快照与时钟保持")
	# 主场景暂停期间显式完成现有地形队列，检查真正的玩家身体可以出门。
	for child: Node in _world.get_children():
		if not child is ObstacleTileLayer: continue
		var chunk:=Vector2i(floori(inside.x/512),floori(inside.y/512))
		for y in range(-1,2):
			for x in range(-1,2): child._on_chunk_ready((chunk+Vector2i(x,y))*512)
		while not child._lay_queue.is_empty(): child._process(0)
	await _frames()
	_check(not _player.test_move(_player.global_transform,Vector2(0,256)),label+"生产主场景中的开门碰撞允许实际退出")

func _saved_fixture() -> Dictionary:
	var q:=Data.create(42)
	var evidence: Dictionary={}
	for id: String in Data.Outpost.EVIDENCE: evidence[id]=true
	var outpost:={"id":"lost_outpost_v1","evidence":evidence,"outcome":"survey","survey_confirmed":true}
	Data.authorize_chapter1(q,outpost)
	GameState.outpost_quest=outpost
	_check(Data.accept(q,"side_troll:s1",30),"恢复夹具接取旧旗第一阶段")
	for a: Dictionary in Catalog.stage("side_troll:s1").actions:
		if bool(a.get("optional",false)): continue # 不伪造可选Boss讨伐。
		var proof:={"position":[100,200],"tick":1,"destination":a.object,"witness":"not_present","unit_ids":[]}
		_check(Data.record(q,"side_troll:s1",a.id,proof),"生产证据验证器接受最小恢复夹具 "+str(a.id))
	Data.mark_paid(q,"side_troll:s1")
	_check(Data.accept(q,"side_troll:s2",30),"恢复夹具只接取房间阶段")
	var runes:=Catalog.actions(42)["side_troll:s2:runes"] as Dictionary
	_check(Data.record(q,"side_troll:s2",runes.id,{"position":[100,200],"tick":1,"destination":runes.object,"order":runes.puzzle_order}),"保存完成符记但未取房内档案的证据")
	q=Data.sanitize(_normalized(q),42)
	_check(q.get("quests",{}).get("side_troll:s2",{}).get("evidence",{}).has(runes.id),"开门证据通过真实存档清洗")
	_check(q.get("main_kills",{}).is_empty() and not q.get("quests",{}).has("watch_c2_forest:s1"),"夹具没有虚构主线完成或Boss击杀")
	return q

func _projection_controls() -> void:
	var action:=Catalog.actions(42)["side_scholar:s2:resolve"] as Dictionary
	for branch: String in ["preserve","component"]:
		# 只验证目录分支语义的局部输入，不写入玩家账本或声称完成学者任务。
		var q:={"seed":42,"quests":{"side_scholar:s2":{"choice":branch,"evidence":{}}}}
		_check(not "side_scholar:shortcut_gate" in CampaignQuest.open_gates_from(q),"仅选择"+branch+"不冒充落实开门")
		q.quests["side_scholar:s2"].evidence[action.id]={}
		_check(("side_scholar:shortcut_gate" in CampaignQuest.open_gates_from(q))==(branch=="component"),"学者完成分支按目录 opens_choice 投影 "+branch)
		q.quests["side_scholar:s2"].evidence.erase(action.id)
		q.quests["side_scholar:s2"].evidence["side_troll:s2:runes"]={}
		_check(not "side_troll:room_gate" in CampaignQuest.open_gates_from(q),"其它阶段的同名证据不能冒充旧旗开门")

func _run() -> void:
	get_tree().current_scene=null # 控制器留在根，世界/菜单使用真实SceneTree切换。
	get_tree().paused=true
	if "--cold" in OS.get_cmdline_user_args():
		var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH+".open_expected"))
		await _enter()
		await _verify(expected,"独立冷启动")
		_finish()
		return
	GameState.reset_all()
	GameState.world_seed=42
	GameState.stats.strength=20
	GameState.stats.intellect=20
	BiomeMap.configure(42)
	seed(42)
	print("OPEN_ROOM_RESTORE world_seed=42 rng_seed=42")
	GameState.campaign_quest=_saved_fixture()
	_projection_controls()
	var inside:=_door()+Vector2(0,-128)
	GameState.player_snapshot={"position":[inside.x,inside.y],"hp":87.0,"mp":23.0,"combat_timers":TIMERS}
	await _enter()
	WorldSim.resume_clock(0.6,3)
	await _verify({},"首次实际主场景")
	var expected:=_normalized({"campaign":GameState.campaign_quest,"ecology":WorldSim.sim.to_dict(),"day_time":WorldSim.day_time,"game_day":WorldSim.game_day}) as Dictionary
	GameState.save_enabled=true
	_check(GameState.save_now(),"真实原子存档写入开门室内状态")
	GameState.save_enabled=false
	var file:=FileAccess.open(GameState.SAVE_PATH+".open_expected",FileAccess.WRITE)
	file.store_string(JSON.stringify(expected))
	file.close()
	var output: Array=[]
	var exit_code:=OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),
		"res://tests/campaign_open_room_restore_test.tscn","--quit-after","10000","--","--cold"]),output,true)
	var complete:=false
	for line: String in output:
		print(line)
		complete=complete or "=== CAMPAIGN OPEN ROOM RESTORE PASS" in line
	_check(exit_code==0 and complete,"磁盘独立冷启动完整验证成功")
	for repeat in 2:
		_world.get_node("HUD")._back_to_menu()
		get_tree().paused=true
		await _frames()
		get_tree().current_scene.get_node("MenuBox/StartBtn").pressed.emit()
		await _frames()
		_world=get_tree().current_scene
		_player=_world.get_node("Player") as Player
		await _verify(expected,"真实菜单继续%d " % repeat)
	DirAccess.remove_absolute(GameState.SAVE_PATH+".open_expected")
	_finish()

func _finish() -> void:
	GameState.save_enabled=false
	get_tree().paused=false
	print("=== CAMPAIGN OPEN ROOM RESTORE %s (%d checks) ===" % ["PASS" if _fails==0 else "FAIL",_checks])
	get_tree().quit(0 if _fails==0 else 1)
