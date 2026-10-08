## 真实导航准备/提交预算、逐位旧规则对照和在途地形变化回归。
extends Node2D

## 固定原规则在36块上的字节摘要，防止新旧两个实现同时漂移而自证通过。
const BASELINE_MASK_SHA256 := {
	20260908: "c85d8a9f41691349123d103b6a43bfef53c833473868b537eabcf092a28f4cc0",
	20261002: "c7781f7f3ee9c4917b735580bb4d6cc53243110347a9b78263e183e81013e3bd",
	20261003: "cc89638f5f5a04aab90f4d1ac38250b3a9c2f70b12a7ed5c834321bbb1db50cd",
}

var _checks := 0
var _fails := 0
var _legacy_usec := 0
var _sliced_usec := 0
var _corpus_sliced_usec := 0
var _slice_max_usec := 0
var _slice_count := 0
var _seen_kinds := {}
var _deadends := 0

## 只给真实瓦片提交增加可测成本，不替换采样、结果或生产调度器。
class CostlySubmission extends NavTileLayer:
	func _write_nav_cell(cell: Vector2i, blocked: bool) -> void:
		super._write_nav_cell(cell, blocked)
		var until := Time.get_ticks_usec() + 250
		while Time.get_ticks_usec() < until:
			pass


func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.stop()
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("FAIL " + label)


## 保留改动前的直接规则作为独立基线，不使用新halo或新分块入口。
func _legacy_mask(chunk: Vector2i) -> PackedByteArray:
	# 完整保留旧版18×18首轮采样 + 自由格重复四邻采样算法，计时可直接对照。
	var obstacles := PackedByteArray()
	obstacles.resize(324)
	for index in 324:
		var sample := ObstacleField.sample_cell(chunk * 16 + Vector2i(index % 18 - 1,index / 18 - 1))
		obstacles[index] = int(not sample.is_empty())
		if not sample.is_empty(): _seen_kinds[sample.kind] = true
	var out := PackedByteArray()
	out.resize(256)
	for index in 256:
		var cell := chunk * 16 + Vector2i(index % 16, index / 16)
		var middle := (index / 16 + 1) * 18 + index % 16 + 1
		var blocked := obstacles[middle] == 1
		if not blocked:
			var walls := obstacles[middle+1]+obstacles[middle-1]+obstacles[middle+18]+obstacles[middle-18]
			blocked = walls >= 3
			if blocked: _deadends += 1
		if not blocked:
			for offset: Vector2i in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.DOWN,Vector2i.UP]:
				var sample := ObstacleField.sample_cell(cell+offset)
				if not sample.is_empty() and sample.kind != "castle" and float(sample.r) > 11.0:
					blocked = true
					break
		out[index] = int(blocked)
	return out


func _mask_cells_match(nav: NavTileLayer, chunk: Vector2i, expected: PackedByteArray) -> bool:
	for index in 256:
		var cell := chunk * 16 + Vector2i(index % 16, index / 16)
		if (nav.get_cell_source_id(cell) == -1) != (expected[index] != 0):
			return false
	return true


func _complete_job(job: ObstacleField.NavChunkJob) -> void:
	for attempt in 20000:
		var started := Time.get_ticks_usec()
		var ready := ObstacleField.advance_nav_chunk(job, started + 200)
		var elapsed := Time.get_ticks_usec() - started
		_sliced_usec += elapsed
		_slice_max_usec = maxi(_slice_max_usec, elapsed)
		_slice_count += 1
		if ready:
			return
	_check(false, "实际采样任务能在有限工作内完成")


func _prepare_layer(nav: NavTileLayer, chunk: Vector2i) -> void:
	add_child(nav)
	nav.set_process(false)
	nav._center_chunk = chunk
	nav._pending.assign([chunk])


func _drain(nav: NavTileLayer) -> void:
	for attempt in 20000:
		if nav._pending.is_empty() and nav._fill_job == null and nav._clearing.is_empty():
			return
		nav._advance_work()
	_check(false, "真实流式任务最终收敛")


func _test_masks() -> void:
	for seed_value in [20260908, 20261002, 20261003]:
		BiomeMap.configure(seed_value)
		ObstacleField.restore_destroyed([])
		CampaignLayout.set_open_gates([])
		var chunks: Array[Vector2i] = [Vector2i(-1,-1), Vector2i(-1,0), Vector2i(0,-1)]
		for terrain: String in ["plains", "forest", "snow", "swamp", "hill", "lava"]:
			var pos: Vector2 = BiomeMap.farthest_patch(terrain).center + Vector2(2048,2048)
			chunks.append(Vector2i(floori(pos.x / 512), floori(pos.y / 512)))
		if seed_value == 20260908:
			# 固定实测深水位置，包含跨块上下边界，不能仅靠群系名声称覆盖水。
			chunks.append_array([Vector2i(893,207),Vector2i(893,206),Vector2i(1311,40)])
		for dungeon: Dictionary in ObstacleField.dungeons():
			var pos: Vector2 = dungeon.center + Vector2(0,128)
			chunks.append(Vector2i(floori(pos.x / 512), floori(pos.y / 512)))
		var corpus := PackedByteArray()
		for chunk in chunks:
			var start := Time.get_ticks_usec()
			var expected := _legacy_mask(chunk)
			corpus.append_array(expected)
			_legacy_usec += Time.get_ticks_usec() - start
			var job := ObstacleField.begin_nav_chunk(chunk * 512)
			_check(not job.complete, "冷缓存确实需要准备 %s/%s" % [seed_value, chunk])
			ObstacleField.advance_nav_chunk(job, Time.get_ticks_usec() - 1)
			_check(job.sample_cursor == 0, "已耗尽预算不能继续真实采样")
			_complete_job(job)
			_check(job.sample_cursor == 324, "18×18 halo每格只取样一次")
			_check(job.blocked == expected, "三种子/六群系/负坐标/城门逐位保持旧掩码")
			_check(ObstacleField.nav_blocked_chunk(chunk * 512) == expected, "同步入口和缓存结果逐位相同")
			for index in 256:
				var cell := chunk * 16 + Vector2i(index % 16,index / 16)
				_check(ObstacleField.nav_blocked_cell(cell) == (expected[index] != 0), "单格缓存与旧规则相同")
		_check(corpus.hex_encode().sha256_text() == BASELINE_MASK_SHA256[seed_value],
			"固定三种子基线摘要保持一致 %d" % seed_value)
	_check(_seen_kinds.has("water") and _seen_kinds.has("boulder") and _seen_kinds.has("castle")
		and _seen_kinds.has("tree") and _deadends > 0, "样本确实包含深水、宽石、城墙、窄树干和死点填充")
	_corpus_sliced_usec = _sliced_usec


func _test_preparation_budget() -> void:
	BiomeMap.configure(20260908)
	ObstacleField.restore_destroyed([])
	var chunk := Vector2i(575,36) # 真实森林树簇，不能用假廉价采样证明预算。
	# 世界装配已初始化的作者布局不属于冷导航块；只预热这一步，不创建导航缓存。
	ObstacleField.sample_cell(Vector2i.ZERO)
	var nav := NavTileLayer.new()
	_prepare_layer(nav, chunk)
	var started := Time.get_ticks_usec()
	for attempt in 100:
		nav._advance_work(200)
		if nav._fill_job != null and nav._fill_job.sample_cursor > 0: break
	var first_usec := Time.get_ticks_usec() - started
	_check(nav._fill_job != null and not nav._fill_job.complete,
		"生产铺层在冷块的昂贵准备阶段就能让出帧")
	_check(nav._fill_job != null and nav._fill_job.sample_cursor > 0
		and nav._fill_job.sample_cursor < 324, "微秒预算推进部分真实采样，未偷算整块")
	_check(nav.get_used_cells().is_empty(), "完整掩码准备前不提交不完整样本")
	_drain(nav)
	_check(nav._filled.has(chunk) and _mask_cells_match(nav,chunk,_legacy_mask(chunk)),
		"预算化准备最终铺满同一真实导航块")
	print("NAV_COLD_FIRST_SLICE usec=%d budget=200" % first_usec)
	nav.free()


func _test_submission_budget() -> void:
	var chunk := Vector2i(575,36)
	ObstacleField.nav_blocked_chunk(chunk * 512) # 命中缓存也不能绕过提交时钟。
	var nav := CostlySubmission.new()
	_prepare_layer(nav,chunk)
	var started := Time.get_ticks_usec()
	for attempt in 100:
		nav._advance_work(800)
		if nav._fill_cursor > 0: break
	var elapsed := Time.get_ticks_usec()-started
	_check(nav._fill_job != null and nav._fill_cursor > 0 and nav._fill_cursor < 10,
		"真实瓦片提交用微秒截止，而非整块256格计数")
	# 用真实昂贵单格成本和提交游标证明截止生效；墙钟打印取证，避免CPU抢占误报。
	_check(nav._fill_cursor <= 4, "800微秒不会塞入超过4次各250微秒的真实提交")
	print("NAV_SUBMIT_SLICE usec=%d budget=800 submitted=%d" % [elapsed,nav._fill_cursor])
	_drain(nav)
	_check(_mask_cells_match(nav,chunk,_legacy_mask(chunk)),"分帧提交不改变任何格")
	nav.free()


func _test_geometry_changes() -> void:
	BiomeMap.configure(20260908)
	ObstacleField.restore_destroyed([])
	var changed := CampaignLayout.set_open_gates([])
	ObstacleField.invalidate_authored_cells(changed)
	var gates := CampaignLayout.gate_cells("c2:forest_gate")
	_check(not gates.is_empty(), "使用真实作者石门")
	var gate := gates[0]
	var chunk := Vector2i(gate.x >> 4,gate.y >> 4)
	var job := ObstacleField.begin_nav_chunk(chunk * 512)
	var target := (gate.y - chunk.y * 16 + 1) * 18 + gate.x - chunk.x * 16 + 1
	for attempt in 20000:
		if job.sample_cursor > target: break
		ObstacleField.advance_nav_chunk(job,Time.get_ticks_usec()+50)
	_check(job.sample_cursor > target and not job.complete,"门格已采样但准备尚未结束")
	changed = CampaignLayout.set_open_gates(["c2:forest_gate"])
	ObstacleField.invalidate_authored_cells(changed)
	_complete_job(job)
	_check(job.blocked == _legacy_mask(chunk), "采样中开门会丢弃旧halo，不污染新缓存")
	var nav := CostlySubmission.new()
	_prepare_layer(nav,chunk)
	var gate_index := (gate.y - chunk.y * 16) * 16 + gate.x - chunk.x * 16
	for attempt in 2000:
		nav._advance_work(400)
		if nav._fill_job == null or nav._fill_cursor > gate_index: break
	_check(nav._fill_job != null and nav.get_cell_source_id(gate) != -1,
		"开门格已经提交，整块仍在提交中")
	changed = CampaignLayout.set_open_gates([])
	ObstacleField.invalidate_authored_cells(changed)
	EventBus.campaign_geometry_changed.emit(changed)
	_check(nav.get_cell_source_id(gate) == -1,"提交中关门立即去掉已铺的旧可走格")
	_drain(nav)
	_check(_mask_cells_match(nav,chunk,_legacy_mask(chunk)), "旧提交任务不会重新打开锁门")
	var door := (Vector2(gate)+Vector2.ONE*0.5)*32
	_check(CampaignLayout.separated_by_closed_gate(door+Vector2(0,-64),door+Vector2(0,64)),
		"作者跨锁门寻路守卫保持生效")
	nav.free()
	# 同种子读档也必须废弃在途结果。
	job = ObstacleField.begin_nav_chunk(chunk * 512)
	changed = CampaignLayout.set_open_gates(["c2:forest_gate"])
	ObstacleField.invalidate_authored_cells(changed)
	ObstacleField.restore_destroyed([])
	_complete_job(job)
	_check(job.blocked == _legacy_mask(chunk), "缓存命中任务在同种子恢复后也重新校验")
	BiomeMap.configure(20261003)
	_complete_job(job)
	_check(job.blocked == _legacy_mask(chunk), "换种子后在途旧世界结果不得进入新世界缓存")
	BiomeMap.configure(20260908)
	ObstacleField.restore_destroyed([])


func _test_reversal() -> void:
	var chunk := Vector2i(575,36)
	var nav := NavTileLayer.new()
	_prepare_layer(nav,chunk)
	nav._fill_chunk(chunk)
	var expected := _legacy_mask(chunk)
	nav._replan_window(chunk+Vector2i(13,0))
	for attempt in 100:
		nav._advance_clearing(Time.get_ticks_usec()+8)
		if nav._clear_offsets.get(chunk,0) > 0: break
	_check(nav._clear_offsets.get(chunk,0)>0 and nav._clear_offsets.get(chunk,0)<256,
		"真实erase_cell按时钟暂停在块内，而非整块清理")
	nav._replan_window(chunk)
	_check(not nav._clearing.has(chunk) and not nav._filled.has(chunk),
		"回头撤销旧清理任务，并把部分清空块重新入队")
	nav._pending.assign([chunk])
	_drain(nav)
	_check(_mask_cells_match(nav,chunk,expected),"回头后已清前缀完整恢复，旧队列不再擦新格")
	# 没清过的旧任务也必须在重排时撤销，不能等待新块轮到才撤销。
	nav._replan_window(chunk+Vector2i(13,0))
	nav._replan_window(chunk)
	nav._pending.clear()
	nav._advance_work()
	_check(_mask_cells_match(nav,chunk,expected) and nav._clearing.is_empty(),
		"快速跨界再回头，不会清掉尚未轮到补铺的完整块")
	# 清理期间收到地形信号不能把清过的前缀重新补回，造成永不再清的残格。
	var first_free := -1
	for index in 256:
		if expected[index] == 0:
			first_free = index
			break
	_check(first_free >= 0, "回头夹具包含实际自由格")
	nav._replan_window(chunk+Vector2i(13,0))
	nav._pending.clear()
	for attempt in 10000:
		nav._advance_clearing(Time.get_ticks_usec()+8)
		if nav._clear_offsets.get(chunk,0) > first_free or not nav._resident.has(chunk): break
	var cleared := chunk*16+Vector2i(first_free % 16,first_free / 16)
	EventBus.obstacle_destroyed.emit(cleared,(Vector2(cleared)+Vector2.ONE*0.5)*32,"")
	_check(nav.get_cell_source_id(cleared) == -1, "地形信号不会复活待清块的已清前缀")
	_drain(nav)
	_check(nav.get_used_cells().is_empty(), "清理和地形信号交错后没有遗留格")
	# 半块提交被取消后也必须全部擦除，不能只跟踪完整块。
	var slow := CostlySubmission.new()
	_prepare_layer(slow,chunk)
	slow._advance_work(800)
	_check(slow._fill_job != null and slow._resident.has(chunk),"建立真实部分提交夹具")
	slow._replan_window(chunk+Vector2i(13,0))
	slow._pending.clear()
	_drain(slow)
	_check(slow.get_used_cells().is_empty() and slow._resident.is_empty(), "出窗取消部分提交后不遗留孤立导航格")
	slow.free()
	nav.free()


func _test_boundary_destruction() -> void:
	BiomeMap.configure(20260908)
	ObstacleField.restore_destroyed([])
	var found := false
	var target := Vector2i.ZERO
	var center: Vector2 = BiomeMap.farthest_patch("hill").center + Vector2(2048,2048)
	var base := Vector2i(floori(center.x/32),floori(center.y/32))
	for y in range(-64,65):
		for x in range(-64,65):
			var cell := base+Vector2i(x,y)
			if cell.x % 16 != 0 and cell.y % 16 != 0: continue
			if ObstacleField.sample_cell(cell).get("kind", "") in ObstacleField.DESTRUCTIBLE:
				target=cell
				found=true
				break
		if found: break
	_check(found,"找到真实块边界可破坏岩石")
	if not found: return
	var chunks: Array[Vector2i]=[]
	var jobs: Array[ObstacleField.NavChunkJob]=[]
	for offset: Vector2i in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.UP,Vector2i(-1,-1)]:
		var cell:=target+offset
		var chunk:=Vector2i(cell.x>>4,cell.y>>4)
		if chunks.has(chunk):continue
		chunks.append(chunk)
		var job:=ObstacleField.begin_nav_chunk(chunk*512)
		ObstacleField.advance_nav_chunk(job,Time.get_ticks_usec()+100)
		jobs.append(job)
	ObstacleField.damage_cell(target)
	_check(not ObstacleField.damage_cell(target).is_empty(),"仍需原有两击才能破坏")
	for i in chunks.size():
		_complete_job(jobs[i])
		_check(jobs[i].blocked == _legacy_mask(chunks[i]),"边界破坏让所有在途邻块重采样并释放正确余量")


func _run() -> void:
	_test_masks()
	_test_preparation_budget()
	_test_submission_budget()
	_test_geometry_changes()
	_test_reversal()
	_test_boundary_destruction()
	print("NAV_PREP legacy_total_usec=%d corpus_sliced_total_usec=%d slice_max_usec=%d slices=%d" %
		[_legacy_usec,_corpus_sliced_usec,_slice_max_usec,_slice_count])
	if _fails == 0:
		print("=== NAVIGATION BUDGET PASS (%d checks) ===" % _checks)
	get_tree().quit(0 if _fails == 0 else 1)
