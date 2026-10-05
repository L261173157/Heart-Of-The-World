## 每档战役的生态事实账本。只观察原始 EcologySim 信号，不消费限流新闻。
## configure 必须在 setup/restore 完成后调用；初始/恢复快照是基线，不是新事件。
class_name CampaignWorldFacts
extends Node

signal changed

const VERSION := 1
const MAX_EVENTS := 512
const MAX_SPECIES := 64
const MAX_CLUES := 256
const MIGRATION_WINDOW := 120
const DECLINE_TICKS := 3
const ENDANGERED := 6

var _sim: EcologySim
var _seed := 0
var _state: Dictionary = {}
var _regions_by_id: Dictionary = {}
var _positions_by_id: Dictionary = {}
var _flushing := false
var _position_poll := 0.0

static func _integer(value: Variant, fallback := 0) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return fallback
	return clampi(int(value), 0, 2147483647)

static func _flag(value: Variant) -> bool:
	return value if typeof(value) == TYPE_BOOL else false

static func _same_seed(value: Variant, seed_value: int) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value) == float(seed_value)

static func _text(value: Variant, limit := 160) -> String:
	return value.left(limit) if value is String else ""

static func _point(value: Variant) -> Array:
	if not value is Array or value.size()!=2: return []
	for coordinate: Variant in value:
		if typeof(coordinate) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(coordinate)): return []
	return [float(value[0]),float(value[1])]

static func _empty(seed_value: int) -> Dictionary:
	return {"version":VERSION,"seed":seed_value,"sequence":0,"last_tick":-1,
		"events":[],"migration_windows":{},"decline_runs":{},"population":{},
		"clues":{},"extinct_baseline":{},"last_deaths":{},"triggers":{}}

static func _event(raw: Variant, seed_value: int) -> Dictionary:
	if not raw is Dictionary or not _same_seed(raw.get("seed"),seed_value): return {}
	var kind := _text(raw.get("kind"))
	if kind not in ["migration","death","nest","extinction"]: return {}
	var species := _text(raw.get("species"),64)
	var source := _text(raw.get("source"))
	var from_region := _text(raw.get("from_region"))
	var to_region := _text(raw.get("to_region"))
	var instance_id := _integer(raw.get("instance_id"))
	if species.is_empty() or source.is_empty(): return {}
	if kind in ["migration","death","extinction"] and instance_id <= 0: return {}
	if kind == "migration" and (from_region.is_empty() or to_region.is_empty() or from_region == to_region): return {}
	if kind == "nest" and from_region.is_empty(): return {}
	var out := {"kind":kind,"seed":seed_value,"sequence":_integer(raw.get("sequence")),
		"tick":_integer(raw.get("tick")),"instance_id":instance_id,"species":species,
		"from_region":from_region,"to_region":to_region,"cause":_text(raw.get("cause")),
		"source":source,"is_boss":_flag(raw.get("is_boss"))}
	if kind == "nest":
		out["active"] = _flag(raw.get("active"))
		out["ransacked"] = _flag(raw.get("ransacked"))
		out["nest_key"] = from_region+"|"+species
	for position_key: String in ["position","from_position"]:
		var pos: Variant = raw.get(position_key)
		if pos is Array and pos.size() == 2 and typeof(pos[0]) in [TYPE_INT,TYPE_FLOAT] and typeof(pos[1]) in [TYPE_INT,TYPE_FLOAT]:
			if is_finite(float(pos[0])) and is_finite(float(pos[1])): out[position_key] = [float(pos[0]),float(pos[1])]
	return out

static func _events(raw: Variant, seed_value: int, maximum: int) -> Array:
	var out: Array = []
	if not raw is Array: return out
	for index in range(maxi(0,raw.size()-maximum),raw.size()):
		var event := _event(raw[index],seed_value)
		if not event.is_empty(): out.append(event)
	return out

static func _clue(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {}
	var region_id := _text(raw.get("region_id"))
	var source_id := _text(raw.get("source_id"))
	if region_id.is_empty() or source_id.is_empty(): return {}
	return {"region_id":region_id,"source_id":source_id,"tick":_integer(raw.get("tick"))}

static func _trigger(raw: Variant, seed_value: int, kind: String) -> Dictionary:
	if not raw is Dictionary or not _same_seed(raw.get("seed"),seed_value): return {}
	var species := _text(raw.get("species"),64)
	if species.is_empty(): return {}
	var events := _events(raw.get("events"),seed_value,8)
	var out := {"seed":seed_value,"species":species,"tick":_integer(raw.get("tick")),
		"kind":kind,"events":events,"source":_text(raw.get("source")),"cause":_text(raw.get("cause"))}
	if kind == "world_migration":
		var boundaries := {}
		var identities := {}
		for event: Dictionary in events:
			if event.kind != "migration" or event.species != species or event.is_boss: return {}
			if int(event.sequence) <= 0 or identities.has(int(event.sequence)): return {}
			identities[int(event.sequence)] = true
			if int(event.tick) > int(out.tick) or int(out.tick)-int(event.tick) >= MIGRATION_WINDOW: return {}
			boundaries[_boundary(event)] = true
		var clue := _clue(raw.get("clue"))
		if events.size() < 3 or boundaries.size() < 2 or clue.is_empty(): return {}
		var covered := false
		for event: Dictionary in events:
			if clue.region_id in [event.from_region,event.to_region]: covered = true
		if not covered: return {}
		out["clue"] = clue
	else:
		var point: Variant = raw.get("position")
		if point is Array and point.size()==2 and typeof(point[0]) in [TYPE_INT,TYPE_FLOAT] and typeof(point[1]) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(point[0])) and is_finite(float(point[1])): out["position"]=[float(point[0]),float(point[1])]
		out["witness_instance_id"]=_integer(raw.get("witness_instance_id"))
		out["baseline"] = _integer(raw.get("baseline"))
		out["start_tick"] = _integer(raw.get("start_tick"))
		out["region_id"] = _text(raw.get("region_id"))
		if out.cause == "permanent_extinction":
			if events.is_empty() or events[-1].kind != "extinction" or events[-1].species != species or events[-1].is_boss: return {}
		elif out.cause == "sustained_decline":
			if int(out.baseline) < 1 or int(out.baseline) >= ENDANGERED: return {}
			if int(out.tick)-int(out.start_tick) < DECLINE_TICKS-1: return {}
		else: return {}
	return out

static func sanitize(value: Variant, seed_value: int) -> Dictionary:
	var out := _empty(seed_value)
	if not value is Dictionary or not _same_seed(value.get("seed"),seed_value): return out
	out["sequence"] = _integer(value.get("sequence"))
	out["last_tick"] = _integer(value.get("last_tick"),-1)
	out["events"] = _events(value.get("events"),seed_value,MAX_EVENTS)
	for event: Dictionary in out.events: out.sequence = maxi(int(out.sequence),int(event.sequence))
	for key: String in ["migration_windows","last_deaths","population","decline_runs","extinct_baseline"]:
		var entries: Variant = value.get(key,{})
		if not entries is Dictionary: continue
		for raw_name: Variant in entries:
			var species := _text(raw_name,64)
			if species.is_empty() or out[key].size() >= MAX_SPECIES: continue
			var item: Variant = entries[raw_name]
			match key:
				"migration_windows":
					var window := _events(item,seed_value,4)
					var valid: Array = []
					for event: Dictionary in window:
						if event.kind == "migration" and event.species == species and not event.is_boss: valid.append(event)
					out[key][species] = valid
				"last_deaths":
					var event := _event(item,seed_value)
					if not event.is_empty() and event.kind == "death" and event.species == species: out[key][species] = event
				"population": out[key][species] = _integer(item)
				"extinct_baseline":
					if _flag(item): out[key][species] = true
				"decline_runs":
					if item is Dictionary:
						out[key][species] = {"count":mini(DECLINE_TICKS,_integer(item.get("count"))),
							"start_tick":_integer(item.get("start_tick")),"last_tick":_integer(item.get("last_tick")),
							"baseline":_integer(item.get("baseline")),"region_id":_text(item.get("region_id"))}
						var point:=_point(item.get("position"))
						if not point.is_empty() and _integer(item.get("witness_instance_id"))>0:
							out[key][species]["position"]=point
							out[key][species]["witness_instance_id"]=_integer(item.get("witness_instance_id"))
	var clues: Variant = value.get("clues",{})
	if clues is Dictionary:
		for key: Variant in clues:
			if out.clues.size() >= MAX_CLUES: break
			var clue := _clue(clues[key])
			if not clue.is_empty(): out.clues[clue.region_id] = clue
	var triggers: Variant = value.get("triggers",{})
	if triggers is Dictionary:
		for kind: String in ["world_migration","world_decline"]:
			var trigger := _trigger(triggers.get(kind),seed_value,kind)
			if not trigger.is_empty(): out.triggers[kind] = trigger
	return out

func configure(sim: EcologySim, seed_value: int, saved: Dictionary = {}) -> void:
	add_to_group("campaign_world_facts")
	_disconnect()
	_sim = sim
	_seed = seed_value
	_state = sanitize(saved,_seed)
	_regions_by_id.clear()
	_positions_by_id.clear()
	if _sim == null: return
	# Restore has already replayed spawn/nest signals. Baseline observation emits no facts.
	for inst: MonsterInstance in _sim.instances.values():
		_regions_by_id[inst.id] = inst.region_id
		_positions_by_id[inst.id] = inst.spawn_pos
	for species: String in _sim.player_extinct: _state.extinct_baseline[species] = true
	if int(_state.last_tick) > _sim.tick_count:
		# A mismatched future fact snapshot is not allowed to invent future history.
		_state = _empty(_seed)
		for species: String in _sim.player_extinct: _state.extinct_baseline[species] = true
	_state.last_tick = _sim.tick_count
	_state.population = _population()
	_sim.instance_spawned.connect(_on_spawned)
	_sim.instance_migrated.connect(_on_migrated)
	_sim.instance_died.connect(_on_died)
	_sim.nest_changed.connect(_on_nest_changed)
	_sim.tick_completed.connect(_on_tick)

func _disconnect() -> void:
	if _sim == null: return
	for pair: Array in [[_sim.instance_spawned,_on_spawned],[_sim.instance_migrated,_on_migrated],
		[_sim.instance_died,_on_died],[_sim.nest_changed,_on_nest_changed],[_sim.tick_completed,_on_tick]]:
		if (pair[0] as Signal).is_connected(pair[1]): (pair[0] as Signal).disconnect(pair[1])

func _physics_process(delta: float) -> void:
	if _sim==null: return
	_position_poll+=delta
	if _position_poll<0.12: return
	_position_poll=0.0
	# Keep the last real loaded position before migration listeners relocate the actor.
	# This is internal provenance, not player knowledge and never a new world event.
	for actor: Node in get_tree().get_nodes_in_group("monsters"):
		if not actor is Node2D or actor.is_queued_for_deletion(): continue
		var inst: Variant=actor.get("inst")
		if inst is MonsterInstance and inst.is_alive and _regions_by_id.get(inst.id,"")==inst.region_id:
			_positions_by_id[inst.id]=actor.global_position

func _exit_tree() -> void:
	_disconnect()

func persistence_state() -> Dictionary:
	# Runtime-owned live reference only. General readers must use snapshot(); nobody else mutates this dictionary.
	return _state

func flush_for_save() -> void:
	# report_killed emits death before permanent-extinction/split bookkeeping finishes.
	_flush_extinctions(false)

func snapshot() -> Dictionary:
	flush_for_save()
	return _state.duplicate(true)

func obtain_clue(region_id: String, source_id: String) -> bool:
	if _sim == null or not _sim.regions.has(region_id) or source_id.is_empty() or source_id.length() > 160: return false
	if _state.clues.has(region_id): return false
	if _state.clues.size() >= MAX_CLUES: return false
	_state.clues[region_id] = {"region_id":region_id,"source_id":source_id,"tick":_sim.tick_count}
	_pin_migration()
	changed.emit()
	return true

func _on_spawned(inst: MonsterInstance) -> void:
	# Tracking identity is required to know the previous region after the migration signal.
	# Deliberately no spawn fact: loaded replay can never masquerade as a fresh birth.
	_regions_by_id[inst.id] = inst.region_id
	_positions_by_id[inst.id] = inst.spawn_pos

func _base(kind: String, inst: MonsterInstance, cause: String) -> Dictionary:
	return {"kind":kind,"seed":_seed,"tick":_sim.tick_count,"instance_id":inst.id,
		"species":inst.species.species_name,"from_region":inst.region_id,"to_region":inst.region_id,
		"cause":cause,"is_boss":inst.species.is_boss,"source":"EcologySim.instance_"+kind,
		"position":[inst.spawn_pos.x,inst.spawn_pos.y] if inst.spawn_pos.is_finite() else []}

func _append(event: Dictionary) -> Dictionary:
	_state.sequence = int(_state.sequence)+1
	event["sequence"] = _state.sequence
	_state.events.append(event)
	while _state.events.size() > MAX_EVENTS: _state.events.pop_front()
	return event

func _on_migrated(inst: MonsterInstance, to_region_id: String) -> void:
	var from_region := str(_regions_by_id.get(inst.id,""))
	var from_position: Vector2 = _positions_by_id.get(inst.id,Vector2.INF)
	_positions_by_id[inst.id] = inst.spawn_pos
	_regions_by_id[inst.id] = to_region_id
	if from_region.is_empty() or from_region == to_region_id or not _sim.regions.has(from_region) or not _sim.regions.has(to_region_id): return
	var event := _base("migration",inst,"expansion")
	event.from_region = from_region
	event.to_region = to_region_id
	event.source = "EcologySim.instance_migrated"
	if from_position.is_finite(): event.from_position = [from_position.x,from_position.y]
	_append(event)
	if not inst.species.is_boss:
		var window: Array = _state.migration_windows.get(event.species,[]).duplicate(true)
		window.append(event)
		_state.migration_windows[event.species] = _compact_window(window,_sim.tick_count)
		_pin_migration()
	changed.emit()

static func _boundary(event: Dictionary) -> String:
	var ends: Array = [str(event.from_region),str(event.to_region)]
	ends.sort()
	return ends[0]+"|"+ends[1]

static func _compact_window(events: Array, tick: int) -> Array:
	var live: Array = []
	for event: Dictionary in events:
		if int(event.tick) <= tick and tick-int(event.tick) < MIGRATION_WINDOW: live.append(event)
	if live.size() <= 4: return live
	# Last three events plus the newest other-boundary witness suffice for this trigger.
	# This exact small sufficient statistic avoids dropping a boundary in a noisy world.
	var tail: Array = live.slice(live.size()-3)
	var boundary := _boundary(tail[-1])
	for event: Dictionary in tail:
		if _boundary(event) != boundary: return tail
	for i in range(live.size()-4,-1,-1):
		if _boundary(live[i]) != boundary:
			tail.push_front(live[i])
			break
	return tail

func _pin_migration() -> void:
	if _state.triggers.has("world_migration"): return
	for species: String in _state.migration_windows:
		var events := _compact_window(_state.migration_windows[species],_sim.tick_count)
		_state.migration_windows[species] = events
		var boundaries := {}
		var clue: Dictionary = {}
		for event: Dictionary in events:
			boundaries[_boundary(event)] = true
			for region_id: String in [str(event.from_region),str(event.to_region)]:
				if _state.clues.has(region_id): clue = _state.clues[region_id]
		if events.size() >= 3 and boundaries.size() >= 2 and not clue.is_empty():
			_state.triggers.world_migration = {"kind":"world_migration","seed":_seed,"species":species,
				"tick":_sim.tick_count,"events":events.duplicate(true),"clue":clue.duplicate(true),
				"source":"EcologySim.instance_migrated","cause":"observed_migrations"}
			return

func _on_died(inst: MonsterInstance, cause: String) -> void:
	var event := _base("death",inst,cause)
	event.source = "EcologySim.instance_died"
	if inst.death_pos.is_finite(): event.position = [inst.death_pos.x,inst.death_pos.y]
	elif is_inside_tree():
		# Natural deaths have no player-supplied death_pos. A loaded actor may have wandered far from its original spawn.
		for actor: Node in get_tree().get_nodes_in_group("monsters"):
			if actor is Node2D and actor.get("inst") == inst and not actor.is_queued_for_deletion():
				event.position = [actor.global_position.x,actor.global_position.y]
				break
	_append(event)
	_state.last_deaths[inst.species.species_name] = event.duplicate(true)
	_regions_by_id.erase(inst.id)
	_positions_by_id.erase(inst.id)
	# _die emits before splits/permanent-extinction bookkeeping. Never guess permanence here.
	call_deferred("_flush_extinctions")
	changed.emit()

func _on_nest_changed(region_id: String, species: String, active: bool, ransacked: bool) -> void:
	var data := _sim.find_species(species)
	if data == null or not _sim.regions.has(region_id): return
	_append({"kind":"nest","seed":_seed,"tick":_sim.tick_count,"instance_id":0,"species":species,
		"from_region":region_id,"to_region":region_id,"nest_key":region_id+"|"+species,"active":active,"ransacked":ransacked,
		"is_boss":data.is_boss,"source":"EcologySim.nest_changed",
		"cause":"ransacked" if ransacked else ("established" if active else "abandoned")})
	changed.emit()

func _flush_extinctions(emit_change := true) -> void:
	if _sim == null or _flushing: return
	_flushing = true
	var did_change := false
	for species: String in _sim.player_extinct:
		if _state.extinct_baseline.has(species): continue
		_state.extinct_baseline[species] = true
		var death: Dictionary = _state.last_deaths.get(species,{})
		if death.is_empty() or death.cause != EcologySim.DEATH_KILLED or death.is_boss: continue
		if _sim.alive_count_of_species(species) != 0: continue
		var event := death.duplicate(true)
		event.kind = "extinction"
		event.cause = "player_permanent_extinction"
		event.source = "EcologySim.player_extinct+instance_died"
		_append(event)
		if not _state.triggers.has("world_decline"):
			_state.triggers.world_decline = {"kind":"world_decline","seed":_seed,"species":species,
				"tick":_sim.tick_count,"start_tick":_sim.tick_count,"baseline":0,"region_id":event.from_region,
				"cause":"permanent_extinction","source":event.source,"events":[event.duplicate(true)],"position":event.get("position",[]),"witness_instance_id":inst_id_from(event)}
		did_change = true
	_flushing = false
	if did_change and emit_change: changed.emit()

static func inst_id_from(event: Dictionary) -> int:
	return int(event.get("instance_id",0))

func _current_known_position(inst: MonsterInstance) -> Vector2:
	if is_inside_tree():
		for actor: Node in get_tree().get_nodes_in_group("monsters"):
			if actor is Node2D and actor.get("inst")==inst and not actor.is_queued_for_deletion(): return actor.global_position
	return inst.spawn_pos

func _population() -> Dictionary:
	var totals := {}
	for inst: MonsterInstance in _sim.instances.values():
		if inst.is_alive: totals[inst.species.species_name] = int(totals.get(inst.species.species_name,0))+1
	return totals

func _decline_witness(species: String, region_id: String, since_tick: int) -> Dictionary:
	for inst: MonsterInstance in _sim.instances.values():
		if not inst.is_alive or inst.species.species_name!=species or (not region_id.is_empty() and inst.region_id!=region_id): continue
		var point:=_current_known_position(inst)
		if point.is_finite(): return {"position":[point.x,point.y],"witness_instance_id":inst.id,"region_id":inst.region_id}
	for index in range(_state.get("events",[]).size()-1,-1,-1):
		var event: Dictionary=_state.events[index]
		if event.kind!="death" or event.species!=species or int(event.tick)<since_tick or (not region_id.is_empty() and event.from_region!=region_id): continue
		var point:=_point(event.get("position"))
		if not point.is_empty(): return {"position":point,"witness_instance_id":int(event.instance_id),"region_id":str(event.from_region)}
	return {}

func _on_tick(summary: Dictionary) -> void:
	var tick := _integer(summary.get("tick"),-1)
	if tick != _sim.tick_count or tick <= int(_state.last_tick): return
	var previous_tick := int(_state.last_tick)
	_state.last_tick = tick
	# The summary is mutable/reused by EcologySim: copy numeric values, never retain its dictionaries.
	var totals := {}
	var first_region := {}
	for region: Dictionary in summary.get("regions",[]):
		for species: String in region.get("species",{}):
			var count := _integer(region.species[species])
			totals[species] = int(totals.get(species,0))+count
			if count > 0 and not first_region.has(species): first_region[species] = str(region.id)
	_state.population = totals
	_flush_extinctions(false)
	for species: SpeciesData in _sim.species_list:
		if species.is_boss: continue
		var name := species.species_name
		var total := int(totals.get(name,0))
		if total < 1 or total >= ENDANGERED:
			_state.decline_runs.erase(name)
			continue
		var run: Dictionary = _state.decline_runs.get(name,{})
		if run.is_empty() or int(run.last_tick) != tick-1 or previous_tick != tick-1:
			run = {"count":0,"start_tick":tick,"last_tick":tick,"baseline":total,"region_id":str(first_region.get(name,""))}
		# Pin the first genuine low-population observation, before its region can empty on ticks 2/3.
		if _point(run.get("position")).is_empty() or int(run.get("witness_instance_id",0))<=0:
			var witness:=_decline_witness(name,str(run.region_id),int(run.start_tick))
			if witness.is_empty(): witness=_decline_witness(name,"",int(run.start_tick))
			if not witness.is_empty(): run.merge(witness,true)
		run.count = mini(DECLINE_TICKS,int(run.count)+1)
		run.last_tick = tick
		_state.decline_runs[name] = run
		if int(run.count) >= DECLINE_TICKS and not _state.triggers.has("world_decline") and not _point(run.get("position")).is_empty():
			var deaths: Array = []
			if _state.last_deaths.has(name): deaths.append(_state.last_deaths[name].duplicate(true))
			_state.triggers.world_decline = {"kind":"world_decline","seed":_seed,"species":name,"tick":tick,
				"start_tick":run.start_tick,"baseline":run.baseline,"region_id":run.region_id,
				"cause":"sustained_decline","source":"EcologySim.tick_completed","events":deaths}
			_state.triggers.world_decline.position=run.position.duplicate()
			_state.triggers.world_decline.witness_instance_id=int(run.witness_instance_id)
	_pin_migration()
	changed.emit()

func migration_trigger() -> Dictionary:
	return (_state.get("triggers",{}).get("world_migration",{}) as Dictionary).duplicate(true)

func decline_trigger() -> Dictionary:
	_flush_extinctions(false)
	return (_state.get("triggers",{}).get("world_decline",{}) as Dictionary).duplicate(true)

func known_clue(region_id: String) -> Dictionary:
	return (_state.get("clues",{}).get(region_id,{}) as Dictionary).duplicate(true)

func latest_migration(region_id: String = "") -> Dictionary:
	for index in range(_state.get("events",[]).size()-1,-1,-1):
		var event: Dictionary = _state.events[index]
		if event.kind == "migration" and not event.is_boss and (region_id.is_empty() or region_id in [event.from_region,event.to_region]):
			return event.duplicate(true)
	return {}

## Return only the event endpoint belonging to this region, never the actor's hidden live location.
static func migration_position(event: Dictionary, region_id: String) -> Vector2:
	var key := "from_position" if event.get("from_region","")==region_id else "position"
	if region_id not in [event.get("from_region",""),event.get("to_region","")]: return Vector2.INF
	var point := _point(event.get(key))
	return Vector2(float(point[0]),float(point[1])) if point.size()==2 else Vector2.INF

## Bounded raw-ring query. Only the chosen event is copied; no ledger snapshot or invented event.
func local_migration_site(region_id: String, origin: Vector2, locate_site: Callable) -> Dictionary:
	if not origin.is_finite() or not locate_site.is_valid(): return {}
	for index in range(_state.get("events",[]).size()-1,-1,-1):
		var event: Dictionary = _state.events[index]
		if event.kind!="migration" or event.is_boss: continue
		var historical := migration_position(event,region_id)
		if not historical.is_finite() or origin.distance_to(historical)>6000: continue
		var point: Variant = locate_site.call(historical)
		if not point is Vector2 or not point.is_finite() or point.distance_to(historical)>384 or origin.distance_to(point)>6000: continue
		return {"migration":event.duplicate(true),"position":point}
	return {}

func migration_status(proof: Dictionary = {}) -> Dictionary:
	if proof.is_empty(): proof = migration_trigger()
	if _sim == null or proof.is_empty(): return {}
	var name := str(proof.get("species",""))
	var total := _sim.alive_count_of_species(name)
	var recent := _compact_window(_state.migration_windows.get(name,[]),_sim.tick_count)
	return {"state":"lost" if total == 0 else ("continuing" if not recent.is_empty() else "stopped"),
		"species":name,"global_alive":total,"tick":_sim.tick_count,"recent_migrations":recent.duplicate(true)}

func decline_status(proof: Dictionary = {}) -> Dictionary:
	if proof.is_empty(): proof = decline_trigger()
	if _sim == null or proof.is_empty(): return {}
	var name := str(proof.get("species",""))
	var total := _sim.alive_count_of_species(name)
	var status := "endangered"
	if _sim.player_extinct.get(name,false): status = "player_extinct"
	elif total == 0: status = "naturally_absent"
	elif total >= ENDANGERED: status = "recovered"
	return {"state":status,"species":name,"global_alive":total,"tick":_sim.tick_count,
		"last_death":(_state.last_deaths.get(name,{}) as Dictionary).duplicate(true)}

func death_evidence(instance_ids: Array, since_tick: int) -> Array:
	var out: Array = []
	for event: Dictionary in _state.get("events",[]):
		if event.kind == "death" and int(event.tick) >= since_tick and int(event.instance_id) in instance_ids:
			out.append(event.duplicate(true))
	return out
