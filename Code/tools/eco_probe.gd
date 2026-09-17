## 生态长程探针（诊断工具）：2000 tick 逐物种 存活占比/平均存活/灭绝次数/死因。
## 用途：实证"捕食压力 vs 繁衍速率"是否导致猎物物种陷入 灭绝→重引入 脉冲循环
## （sim_test 长程用例只断言总量 >0，测不出逐物种坍缩）。
## 运行："$GODOT" --headless --path Code -s tools/eco_probe.gd
extends SceneTree

const TICKS := 2000


func _init() -> void:
	randomize()
	var regions: Array = []
	for def: Dictionary in WorldConfig.region_defs():
		var region := SimRegion.new()
		region.id = def["id"]
		region.display_name = def["name"]
		region.terrain = def["terrain"]
		region.threat = def["threat"]
		region.center = def["center"]
		region.size = def["size"]
		region.capacity = def["capacity"]
		for neighbor: String in def["neighbors"]:
			region.neighbor_ids.append(neighbor)
		regions.append(region)
	# 资源缓存隔离（与 sim_test._fresh_species 同法）
	var species_list: Array[SpeciesData] = []
	for s: SpeciesData in SpeciesCatalog.build_all():
		species_list.append(s.duplicate())
	var sim := EcologySim.new()
	sim.setup(regions, species_list, WorldConfig.initial_population().duplicate(true))

	var names: Array[String] = []
	for s: SpeciesData in species_list:
		names.append(s.species_name)
	var alive_ticks := {}
	var alive_sum := {}
	var extinctions := {}
	var causes := {}
	var was_alive := {}
	for n: String in names:
		alive_ticks[n] = 0
		alive_sum[n] = 0
		extinctions[n] = 0
		causes[n] = {}
		was_alive[n] = false
	sim.instance_died.connect(func(inst: MonsterInstance, cause: String) -> void:
		var c: Dictionary = causes[inst.species.species_name]
		c[cause] = c.get(cause, 0) + 1)

	for i in TICKS:
		sim.tick()
		var alive_now := {}
		for inst: MonsterInstance in sim.instances.values():
			if inst.is_alive:
				alive_now[inst.species.species_name] = \
						alive_now.get(inst.species.species_name, 0) + 1
		for n: String in names:
			var a: int = alive_now.get(n, 0)
			if a > 0:
				alive_ticks[n] += 1
				alive_sum[n] += a
			if a == 0 and was_alive[n]:
				extinctions[n] += 1
			was_alive[n] = a > 0

	print("\n物种 | 存活占比 | 平均存活 | 灭绝次数 | 死因统计")
	var total_alive := 0
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive:
			total_alive += 1
	for n: String in names:
		print("%s | %.0f%% | %.1f | %d | %s" % [
			n, 100.0 * alive_ticks[n] / TICKS, float(alive_sum[n]) / TICKS,
			extinctions[n], str(causes[n])])
	print("总存活 %d / tick %d" % [total_alive, sim.tick_count])
	quit(0)
