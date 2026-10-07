## 有限野外遭遇与世界调查。原始事实、实例占位、物资去向与付款分开保存。
## configure_after_restore 只能在模拟 setup/restore 返回后调用；不重放恢复信号。
class_name CampaignDynamic
extends Node

const Presentation := preload("res://scripts/ui/quest_presentation.gd")
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
const Layout := preload("res://scripts/ecology/campaign_layout.gd")
const Facts := preload("res://scripts/main/campaign_world_facts.gd")
const Encounters := preload("res://scripts/main/campaign_encounters.gd")
const Inventory := preload("res://scripts/main/camp_quest_inventory.gd")
var _host: Node
var _sim: EcologySim
var facts: CampaignWorldFacts
var encounters := Encounters.new()
var _actions: Dictionary = {}
var _objects: Dictionary = {}
var _nodes: Dictionary = {}
var _previews: Dictionary = {}
var _exposed: Dictionary = {}
var _mutating := false
var _syncing := false
var _publish_pending := false
var _background_queue_ms := -6000
var _paired_tick := -1
var _paired_facts: Dictionary = {}
var _paired_encounters: Dictionary = {}
var _paired_context: Dictionary = {}
var _poll := 0.0
var _last_position := Vector2.INF
var _route_cache: Dictionary = {}
var _route_reentry: Dictionary = {}

func setup(host: Node) -> void:
	_host = host
	name = "CampaignDynamic"
	_actions = Catalog.actions(GameState.world_seed)
	for item: Dictionary in Layout.objects(): _objects[str(item.id)] = item
	for a: Dictionary in _actions.values():
		if a.kind == "route" and str(a.stage).begins_with("random_"):
			var visits: Array = _q().get("optional_routes",{}).get(a.id,[])
			if not visits.is_empty() and visits.size()<a.get("route_waypoints",[]).size(): _route_reentry[a.id] = true

func _ready() -> void:
	add_to_group("campaign_dynamic")
	# Deferred binding runs after the game world's synchronous setup/restore, never inside it.
	configure_after_restore.call_deferred()

func _enabled() -> bool:
	return is_instance_valid(_host) and bool(_host.call("_chapter_enabled", {"batch":4,"family":"world"}))

func _q() -> Dictionary:
	return _host.call("ledger") if is_instance_valid(_host) else {}

func _runtime() -> Dictionary:
	if not _q().has("dynamic_runtime"): _q()["dynamic_runtime"] = {}
	var runtime: Dictionary = _q().dynamic_runtime
	for key: String in ["known_objects","relief_needs","bindings","route_steps"]:
		if not runtime.has(key): runtime[key] = {}
	return runtime

func configure_after_restore() -> void:
	if not _enabled() or WorldSim.sim == null: return
	if _sim == WorldSim.sim and facts != null: return
	_sim = WorldSim.sim
	if facts == null: facts = Facts.new()
	if facts.get_parent()==null: add_child(facts)
	if not facts.changed.is_connected(_on_facts_changed): facts.changed.connect(_on_facts_changed)
	_paired_tick=-1
	_paired_facts={}
	_paired_encounters={}
	_paired_context={}
	facts.configure(_sim, GameState.world_seed, _q().get("world_facts", {}))
	encounters.configure(_sim, GameState.world_seed, _q().get("encounters", {}), facts)
	if not encounters.changed.is_connected(_on_changed): encounters.changed.connect(_on_changed)
	_sync()

func _queue_background_save() -> void:
	# Preserve the existing ecological autosave cadence. Player actions/rewards keep their immediate invalidation path.
	if _mutating: return
	var now:=Time.get_ticks_msec()
	if now-_background_queue_ms<int(GameState.ECOLOGY_SAVE_INTERVAL*1000.0): return
	_background_queue_ms=now
	GameState._queue_save()

func _on_facts_changed() -> void:
	_sync()
	_queue_background_save()

func _on_changed() -> void:
	_sync()
	# Bound contributions and instance transitions deserve the ordinary prompt save, but no eager whole-world cloning.
	if not _mutating: GameState._queue_save()
	if not _mutating and not _publish_pending and is_instance_valid(_host):
		_publish_pending=true
		_publish_changed.call_deferred()

func _publish_changed() -> void:
	_publish_pending=false
	# Relevant encounter changes may update the scene; publication alone is not a save-cache invalidation.
	if not _mutating and is_instance_valid(_host) and _host.has_method("_publish"): _host.call("_publish")

func _sync() -> void:
	if _syncing or facts == null or _q().is_empty(): return
	_syncing = true
	_q().world_facts = facts.persistence_state()
	_q().encounters = encounters.persistence_state()
	_route_cache.clear()
	_syncing = false

func _persistence_active() -> bool:
	return _enabled() and facts!=null and _sim!=null and _sim==WorldSim.sim and int(_q().get("seed",-1))==GameState.world_seed

func flush_for_save() -> void:
	if not _persistence_active(): return
	var was_mutating:=_mutating
	_mutating=true
	facts.flush_for_save()
	encounters.flush_for_save()
	_sync()
	_finish_encounter()
	_mutating=was_mutating

func can_reuse_ecology_cache(cached_tick: int) -> bool:
	if not _persistence_active(): return true
	# A reentrant mid-tick snapshot is valid at that instant, but cannot stand in for the completed tick on retry.
	if _paired_tick!=cached_tick or _paired_facts.is_empty() or int(_paired_facts.get("last_tick",-1))!=cached_tick: return false
	if _q().get("encounters",{})!=_paired_encounters: return false
	if _q().size()-2!=_paired_context.size(): return false
	for key: String in _paired_context:
		if _q().get(key)!=_paired_context[key]: return false
	return true

func campaign_for_save(copy: Dictionary, ecology_tick: int, refreshed: bool) -> Dictionary:
	if not _persistence_active(): return copy
	if refreshed:
		# GameState already made this single deep copy at the save boundary. Cache only its two observer-owned subtrees.
		_paired_tick=ecology_tick
		_paired_facts=copy.get("world_facts",{})
		_paired_encounters=copy.get("encounters",{})
		_paired_context={}
		for key: String in copy:
			if key not in ["world_facts","encounters"]: _paired_context[key]=copy[key]
	elif can_reuse_ecology_cache(ecology_tick):
		# Background autosaves retain the matching fact history for the chosen cached ecology, never future evidence.
		# The authoritative live ledger remains current and unchanged; explicit actions/rewards force a fresh world snapshot.
		copy["world_facts"]=_paired_facts
		copy["encounters"]=_paired_encounters
	return copy

func _physics_process(delta: float) -> void:
	if not _enabled(): return
	configure_after_restore()
	if _sim == null: return
	_poll += delta
	if _poll < 0.15: return
	_poll = 0.0
	_discover()
	_track_route()
	_finish_encounter()

func handles_object(id: String) -> bool:
	return id.begins_with("random_") or id.begins_with("world_")

func handles_action(id: String) -> bool:
	return handles_object(id)

func _node(id: String) -> Node2D:
	if _nodes.has(id) and is_instance_valid(_nodes[id]): return _nodes[id]
	if not is_inside_tree(): return null
	for node: Node in get_tree().get_nodes_in_group("campaign_objects"):
		if node is Node2D and str(node.get("campaign_id")) == id:
			_nodes[id] = node
			return node as Node2D
	return null

func _player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D if is_inside_tree() else null

func _at(id: String) -> bool:
	var player := _player()
	if player == null or (player is Player and player._is_dead): return false
	var node := _node(id)
	return node != null and node.has_method("can_interact") and bool(node.call("can_interact"))

func _position(id: String) -> Vector2:
	var node := _node(id)
	if node != null: return node.global_position
	var binding: Dictionary = _runtime().bindings.get(id,{})
	if binding.has("position"): return Vector2(float(binding.position[0]),float(binding.position[1]))
	return Layout.object_position(id)

func _title(id: String) -> String:
	var node := _node(id)
	return str(node.get("title")) if node != null else str(_objects.get(id,{}).get("title","守望记录"))

func _info(body: String, id: String) -> Dictionary:
	return {"kind":"info","giver":_title(id),"text":body}

func _payload(body: String, verb: String, command: String, id: String) -> Dictionary:
	return {"kind":"camp_action","giver":_title(id),"origin":_position(id),"text":body,"confirm_text":verb,"action":"campaign|dynamic|"+command}

func _known(id: String) -> bool:
	return _runtime().known_objects.has(id)

func _chapter_local(id: String) -> bool:
	var terrain := str(_objects.get(id,{}).get("terrain",""))
	return terrain in _q().get("travel",{}).get("unlocked",[])

func _bind(id: String, point: Vector2, region: String) -> void:
	if _runtime().bindings.has(id) or not point.is_finite() or not _objects.has(id): return
	_runtime().bindings[id] = {"position":[point.x,point.y],"region_id":region,"tick":_sim.tick_count}

func _bind_ecology() -> void:
	# The historical source determines the investigation anchor once; later migration cannot reroll it.
	var trigger := facts.migration_trigger()
	if not trigger.is_empty():
		var events: Array = trigger.get("events",[])
		if events.size() >= 3:
			var first: Dictionary = events[0]
			var last: Dictionary = events[-1]
			var origin_event:=first.duplicate(true)
			origin_event.position=first.get("from_position",[])
			_bind_world_site("world_migration:route_a",str(first.from_region),origin_event)
			_bind_world_site("world_migration:route_b",str(last.to_region),last)
			_bind_world_site("world_migration:observer",str(last.to_region),last,Vector2(128,0))
	trigger = facts.decline_trigger()
	if not trigger.is_empty():
		var region := str(trigger.get("region_id",""))
		var event: Dictionary = {"position":trigger.get("position",[])}
		for i in 3: _bind_world_site(["world_decline:last_site","world_decline:evidence_post","world_decline:warning_sign"][i],region,event,Vector2(i*128,0))

func _site_walkable(point: Vector2, region: String) -> bool:
	return point.is_finite() and Rect2(Vector2.ZERO,BiomeMap.WORLD_SIZE).has_point(point) and BiomeMap.region_id_at(point)==region and not ObstacleField.nav_blocked_at(point) and ObstacleField.liquid_kind_at(point).is_empty()

func _site_has_approach(point: Vector2, region: String) -> bool:
	for direction: Vector2 in [Vector2.DOWN,Vector2.UP,Vector2.LEFT,Vector2.RIGHT]:
		var approach:=point+direction*96
		if _site_walkable(approach,region) and _clear(point,approach): return true
	return false

func _bind_world_site(id: String, region_id: String, event: Dictionary, offset := Vector2.ZERO) -> void:
	if _runtime().bindings.has(id) or not _sim.regions.has(region_id): return
	var raw: Variant=event.get("position")
	if not raw is Array or raw.size()!=2: return
	var historical:=Vector2(float(raw[0]),float(raw[1]))
	if not historical.is_finite() or BiomeMap.region_id_at(historical)!=region_id: return
	for radius in range(0,13):
		for direction: Vector2 in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP,Vector2(1,1).normalized(),Vector2(-1,1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,-1).normalized()]:
			var candidate:=historical+offset+direction*radius*32.0
			if candidate.distance_to(historical)>384 or not _site_walkable(candidate,region_id) or not _site_has_approach(candidate,region_id): continue
			_bind(id,candidate,region_id)
			return

func _historical_sources(chain: String) -> Dictionary:
	var sources: Dictionary={}
	if facts==null: return sources
	if chain=="world_migration":
		var trigger:=facts.migration_trigger()
		var events: Array=trigger.get("events",[])
		if events.size()<3: return sources
		sources["world_migration:route_a"]={"region_id":events[0].from_region,"position":events[0].get("from_position",[])}
		sources["world_migration:route_b"]={"region_id":events[-1].to_region,"position":events[-1].get("position",[])}
		sources["world_migration:observer"]=sources["world_migration:route_b"].duplicate(true)
	elif chain=="world_decline":
		var trigger:=facts.decline_trigger()
		if trigger.is_empty(): return sources
		for id: String in ["world_decline:last_site","world_decline:evidence_post","world_decline:warning_sign"]:
			sources[id]={"region_id":trigger.get("region_id",""),"position":trigger.get("position",[])}
	return sources

func _world_sites_ready(chain: String) -> bool:
	if chain not in ["world_migration","world_decline"]: return true
	var sources:=_historical_sources(chain)
	if sources.size()!=3: return false
	for id: String in sources:
		var raw: Array=sources[id].get("position",[])
		var binding: Dictionary=_runtime().bindings.get(id,{})
		if raw.size()!=2 or binding.is_empty() or binding.get("region_id","")!=sources[id].region_id: return false
		var historical:=Vector2(float(raw[0]),float(raw[1]))
		var point:=Vector2(float(binding.position[0]),float(binding.position[1]))
		if point.distance_to(historical)>384 or not _site_walkable(point,str(sources[id].region_id)) or not _site_has_approach(point,str(sources[id].region_id)): return false
		var node:=_node(id)
		if node==null or node.global_position.distance_to(point)>1: return false
	return true

func _prepare_nest(id: String) -> void:
	if _runtime().bindings.has(id+":target"): return
	var giver := Layout.object_position(id+":giver")
	var region_id := BiomeMap.region_id_at(giver)
	if not _sim.regions.has(region_id): return
	for key: String in _sim.nests:
		if key.get_slice("|",0) != region_id or not _sim.nests[key].get("active",false): continue
		var species := _sim.find_species(key.get_slice("|",1))
		if species == null or species.is_boss: continue
		var position := _sim.camp_pos(_sim.regions[region_id],species)
		if giver.distance_to(position) > 5000 or not GameState.fog_knows_position(position): continue
		var candidate := position+Vector2(192,192)
		if ObstacleField.nav_blocked_at(candidate) or not _route_exists(giver,candidate): continue
		_bind(id+":target",candidate,region_id)
		return

func _migration_site(historical: Vector2, origin: Vector2, region_id: String) -> Vector2:
	if BiomeMap.region_id_at(historical)!=region_id or not _known_position(historical): return Vector2.INF
	for radius in range(0,13):
		for direction: Vector2 in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP,Vector2(1,1).normalized(),Vector2(-1,1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,-1).normalized()]:
			var point := historical+direction*radius*32.0
			if origin.distance_to(point)>Encounters.LOCAL_RADIUS or not _known_position(point): continue
			if not _site_walkable(point,region_id) or not _site_has_approach(point,region_id) or not _route_exists(origin,point): continue
			return point
	return Vector2.INF

func _prepare_migration(id: String) -> bool:
	# Accepted sites belong to the saved contract. Neither a later event nor a reload may substitute a new site.
	if _q().get("quests",{}).get(id,{}).get("accepted",false): return _runtime().bindings.has(id+":target")
	var origin := _position(id+":giver")
	var region := BiomeMap.region_id_at(origin)
	if facts.known_clue(region).is_empty(): return false
	var selected := facts.local_migration_site(region,origin,_migration_site.bind(origin,region))
	if selected.is_empty(): return false
	var target := id+":target"
	var old: Dictionary = _runtime().bindings.get(target,{})
	var point: Vector2 = selected.position
	if old.get("position",[]) != [point.x,point.y]:
		_runtime().bindings[target] = {"position":[point.x,point.y],"region_id":region,"tick":_sim.tick_count}
		# Seeing the former pad does not grant knowledge of the newly bound historical location.
		_runtime().known_objects.erase(target)
		_host.call("_save")
	return true

func _discovery_eligible(template: String, id: String) -> bool:
	if not _chapter_local(id+":giver"): return false
	var state := encounters.persistence_state()
	if not str(state.active).is_empty() or int(state.counts.get(template,0)) >= 3: return false
	if _sim.tick_count-int(state.last_issue_tick) < Encounters.GLOBAL_COOLDOWN: return false
	if state.last_closed.has(template) and _sim.tick_count-int(state.last_closed[template]) < Encounters.FAMILY_COOLDOWN: return false
	if template == "random_migration":
		return _prepare_migration(id)
	if template == "random_nest":
		_prepare_nest(id)
		return _runtime().bindings.has(id+":target")
	if template == "random_rocks": return not _broken(id+":barrier")
	if template == "random_camp":
		return not encounters._camp_target(_context(id)).is_empty()
	return true

func _discover() -> void:
	var player := _player()
	if player == null or not player.is_visible_in_tree(): return
	var dirty := false
	var terrain := BiomeMap.terrain_at(player.global_position)
	if terrain in _q().get("travel",{}).get("unlocked",[]) and not terrain in _q().travel.visited:
		_q().travel.visited.append(terrain)
		dirty = true
	var binding_count: int = _runtime().bindings.size()
	_earn_record_clues()
	_bind_ecology()
	if binding_count != _runtime().bindings.size(): dirty = true
	var state := encounters.persistence_state()
	for template: String in Encounters.TEMPLATES:
		var id := Encounters.instance_id(template,GameState.world_seed,int(state.counts.get(template,0)))
		if not _exposed.has(id) and not _known(id+":giver") and _objects.has(id+":giver") and player.global_position.distance_to(_position(id+":giver")) <= 900 and _discovery_eligible(template,id):
			if not _exposed.has(id):
				_exposed[id] = true
				dirty = true
	# Visibility alone is not knowledge: every object must pass its real viewport + occlusion check.
	for id: String in _objects:
		if _known(id): continue
		var node := _node(id)
		if node == null or not node.has_method("is_observed") or not bool(node.call("is_observed",player.global_position)): continue
		_runtime().known_objects[id] = {"tick":_sim.tick_count,"position":[node.global_position.x,node.global_position.y]}
		dirty = true
	# A read nearby authored record is a clue; passively registered objects never earn it.
	_ensure_relief_needs()
	if dirty: _host.call("_save")


func _earn_record_clues() -> void:
	for a: Dictionary in _actions.values():
		if a.kind not in ["read","talk","observe"] or not _done(a): continue
		var proof: Dictionary = _q().quests[a.stage].evidence[a.id]
		var raw: Array = proof.get("position",[])
		if raw.size()!=2: continue
		facts.obtain_clue(BiomeMap.region_id_at(Vector2(float(raw[0]),float(raw[1]))),str(a.object))

func _ensure_relief_needs() -> void:
	for pair: Array in [["world_relief:need_a","forest_station"],["world_relief:need_b","swamp_station"]]:
		if _runtime().relief_needs.has(pair[0]) or _node(pair[0]) == null: continue
		if not _q().get("services",{}).get(pair[1],{}).get("enabled",false): continue
		_runtime().relief_needs[pair[0]] = {"seed":GameState.world_seed,"tick":_sim.tick_count,"station":pair[1],"need":"supply","resolved":false}

func _probe(id: String) -> Dictionary:
	var node := _node(id)
	if node == null or not _objects.has(id): return {}
	var stage_id := str(_objects[id].get("instance_id",""))
	var stage := Catalog.stage(stage_id)
	var evidence: Dictionary = _q().get("quests",{}).get(stage_id,{}).get("evidence",{})
	var role := id.get_slice(":",3)
	var acted := false
	for a: Dictionary in stage.get("actions",[]):
		if str(a.object) == id and evidence.has(a.id): acted = true
	var origin := _position(stage_id+":giver")
	return {"id":id,"exists":not node.is_queued_for_deletion(),"registered":true,"known":_known(id),
		"reachable":_route_exists(origin,node.global_position),"region_id":BiomeMap.region_id_at(node.global_position),
		"position":node.global_position,"at_player":_at(id),"needs_aid":role=="target" and not acted,
		"unclaimed":not acted,"recipient":str(node.get("kind")) in ["npc","injured"],"pending_repair":not acted,
		"breakable":not Layout.barrier_cells(stage_id+":barrier").is_empty(),"broken":_broken(stage_id+":barrier"),
		"route_endpoint":role in ["giver","return"],"pending_need":not acted,"unsettled":not Data.ready(_q(),stage_id),"readable":role=="record"}

func _context(id: String) -> Dictionary:
	var origin := _position(id+":giver")
	return {"origin":origin,"region_id":BiomeMap.region_id_at(origin),"probe_object":_probe,
		"known_position":_known_position,"route_exists":_route_exists,"position_of":_actor_position,
		"migration_site":_migration_site.bind(origin,BiomeMap.region_id_at(origin)),
		"stats":GameState.stats,"cost_item":"dedicated_medicine","cost_count":1,"can_pay_cost":false}

func _known_position(position: Vector2) -> bool:
	return GameState.fog_knows_position(position)

func _actor_position(inst: MonsterInstance) -> Vector2:
	if is_inside_tree():
		for actor: Node in get_tree().get_nodes_in_group("monsters"):
			if actor is Node2D and actor.get("inst") == inst and not actor.is_queued_for_deletion(): return actor.global_position
	return inst.spawn_pos

func _clear(from: Vector2, to: Vector2) -> bool:
	if not from.is_finite() or not to.is_finite(): return false
	var count := maxi(1,ceili(from.distance_to(to)/16.0))
	for index in count+1:
		if ObstacleField.nav_blocked_at(from.lerp(to,float(index)/count)): return false
	return true

func _route_exists(from: Vector2, to: Vector2) -> bool:
	if not from.is_finite() or not to.is_finite() or from.distance_to(to) > 6000: return false
	var key := str(Vector2i(from/32))+":"+str(Vector2i(to/32))
	if _route_cache.has(key): return _route_cache[key]
	var possible := _clear(from,to)
	if not possible:
		for corner: Vector2 in [Vector2(from.x,to.y),Vector2(to.x,from.y)]:
			if _clear(from,corner) and _clear(corner,to): possible = true
	if not possible: possible = _grid_route(from,to)
	_route_cache[key] = possible
	return possible

func _broken(id: String) -> bool:
	var cells := Layout.barrier_cells(id)
	if cells.is_empty(): return false
	for cell: Vector2i in cells:
		if not ObstacleField._destroyed.has(cell): return false
	return true

func _done(a: Dictionary) -> bool:
	return _q().get("quests",{}).get(a.get("stage",""),{}).get("evidence",{}).has(a.get("id",""))

func _can(a: Dictionary) -> bool:
	# 大多数目录行动尚未接取；先按保存状态排除，再检查真实现场的可达性。
	var stage: Dictionary = _q().get("quests", {}).get(a.get("stage", ""), {})
	if not stage.get("accepted", false) or stage.get("evidence", {}).has(a.get("id", "")): return false
	return _enabled() and not str(a.get("chain","")) in _q().get("paused_chains",[]) and Data.can_record(_q(),str(a.stage),str(a.id)) and _world_sites_ready(str(a.get("chain","")))

func _stage_object(stage: Dictionary) -> String:
	if stage.get("family","") == "random": return str(stage.id)+":giver"
	return str(stage.get("actions",[{}])[0].get("object",""))

const INVESTIGATION_OUTCOMES := {
	"continuing":"迁徙仍在继续","stopped":"近期迁徙已经停止","lost":"已失去踪迹",
	"endangered":"仍处于濒危","recovered":"种群已经回升","naturally_absent":"自然消失（非玩家永久灭绝）",
	"player_extinct":"玩家造成永久灭绝","present":"登记现场仍有活动","migrated":"目标已离开登记现场"}

## Read-only view of a verified, completed saved record. Never creates knowledge, kill credit or receipts.
static func recorded_investigation(q: Dictionary, chain: String) -> Dictionary:
	if chain not in ["world_migration","world_decline"] or not Data.ready(q,chain+":s3"): return {}
	var seed_value := int(q.get("seed",-1))
	var trigger := Facts._trigger(q.get("world_facts",{}).get("triggers",{}).get(chain),seed_value,chain)
	if trigger.is_empty(): return {}
	var action_id := chain+":s3:archive"
	var proof := Data._proof(q.get("quests",{}).get(chain+":s3",{}).get("evidence",{}).get(action_id),Catalog.action(chain+":s3",action_id),seed_value)
	var outcomes: Array = ["continuing","stopped","lost"] if chain=="world_migration" else ["endangered","recovered","naturally_absent","player_extinct"]
	if proof.is_empty() or proof.get("species","")!=trigger.species or proof.get("reason","")!=trigger.cause or proof.get("outcome","") not in outcomes: return {}
	if proof.get("events",[])!=trigger.events or int(proof.tick)<int(trigger.tick) or not proof.get("counts",{}).has(trigger.species): return {}
	return {"chain":chain,"proof":proof,"trigger":trigger}

static func investigation_text(record: Dictionary) -> String:
	if record.is_empty(): return ""
	var proof: Dictionary = record.proof
	var trigger: Dictionary = record.trigger
	var lines: Array[String] = ["调查附注 · "+str(trigger.species),
		"结案采样：第%d刻，%s，全球存量%d" % [int(proof.tick),INVESTIGATION_OUTCOMES.get(proof.outcome,proof.outcome),int(proof.counts[trigger.species])]]
	var cause := "已发生的跨区迁徙" if record.chain=="world_migration" else ("持续低于濒危阈值" if trigger.cause=="sustained_decline" else "玩家永久灭绝事件")
	lines.append("历史触发：第%d刻，%s；来源 %s" % [int(trigger.tick),cause,str(trigger.source)])
	for event: Dictionary in trigger.events:
		if event.kind=="migration":
			lines.append("迁徙证据 #%d：个体%d，%s → %s，第%d刻（%s）" % [int(event.sequence),int(event.instance_id),event.from_region,event.to_region,int(event.tick),event.source])
		else:
			var cause_text: String = {"killed":"玩家猎杀","aging":"衰老","predated":"捕食","player_permanent_extinction":"玩家永久灭绝"}.get(event.cause,event.cause)
			lines.append("历史事件 #%d：个体%d，%s，第%d刻（%s）；此为当时事件，不单独证明后续状态的原因" % [int(event.sequence),int(event.instance_id),cause_text,int(event.tick),event.source])
	lines.append("结案状态取自当时的模拟核对；历史记录不会随之后的世界变化改写")
	return "\n".join(lines)

static func completed_investigation_notes(q: Dictionary) -> Dictionary:
	var notes := {}
	for chain: String in ["world_migration","world_decline"]:
		var record := recorded_investigation(q,chain)
		if record.is_empty(): continue
		var species := str(record.trigger.species)
		if not notes.has(species): notes[species] = []
		notes[species].append(investigation_text(record))
	return notes

static func investigation_pages(record: Dictionary) -> Array[String]:
	var pages: Array[String] = []
	if record.is_empty(): return pages
	# Existing dialogue paper is finite; every source line stays available via the existing context menu.
	for line: String in investigation_text(record).split("\n"):
		while line.length()>96:
			pages.append(line.left(96))
			line=line.substr(96)
		if not line.is_empty(): pages.append(line)
	return pages

func _investigation_payload(chain: String, id: String) -> Dictionary:
	var record := recorded_investigation(_q(),chain)
	if record.is_empty(): return {}
	var proof: Dictionary = record.proof
	var text := "%s的这次调查已经记下：%s。" % [record.trigger.species,INVESTIGATION_OUTCOMES.get(proof.outcome,proof.outcome)]
	# Live state is separately labelled and never overwrites the archived sample or awards anything.
	var current := facts.migration_status(record.trigger) if chain=="world_migration" else facts.decline_status(record.trigger)
	if not current.is_empty():
		text += "\n现在再核对，%s。" % INVESTIGATION_OUTCOMES.get(current.state,current.state)
	text += "\n想查当时的来路与依据，可以翻翻这些调查档案。"
	var options: Array = []
	var pages := investigation_pages(record)
	for index in pages.size():
		options.append({"label":"调查档案 %d/%d · %s" % [index+1,pages.size(),pages[index].left(16)],"action":"campaign|dynamic|archive|"+id+"|"+str(index),"enabled":true,"utility":true})
	options.append_array(expedition_options(id))
	return {"kind":"camp_choice","giver":_title(id),"origin":_position(id),"text":text,"options":options}

func _read_archive(id: String, page: int) -> String:
	if not _at(id): return "请在调查现场查看保存的档案"
	var record := recorded_investigation(_q(),id.get_slice(":",0))
	var pages := investigation_pages(record)
	if page<0 or page>=pages.size(): return "没有这页已结案的调查记录"
	EventBus.npc_dialogue.emit({"kind":"info","giver":"调查档案 · %d/%d" % [page+1,pages.size()],"origin":_position(id),"text":pages[page],"back_action":"campaign|dynamic|archive_menu|"+id})
	return ""

func object_payload(id: String) -> Dictionary:
	if not handles_object(id): return {}
	if not _enabled(): return _info("这条调查线索还没有消息",id)
	if not _at(id): return _info("请先走近，再查看或交付",id)
	configure_after_restore()
	if _sim == null: return _info("世界记录尚未就绪",id)
	var chain := id.get_slice(":",0)
	if chain == "world_decline" and id in ["world_decline:last_site","world_decline:observer"] and not facts.decline_trigger().is_empty() and facts.known_clue(str(facts.decline_trigger().get("region_id",""))).is_empty():
		return _payload("观察记录标着最后见到足迹的地点和时间。先读清这页，再沿线索去看看。","辨读足迹线索","clue|"+id,id)
	if chain in _q().get("paused_chains",[]): return _payload("上次查到的线索还在。要接着往下看看吗？","继续调查","resume|"+chain+"|"+id,id)
	if id.begins_with("random_"):
		var instance_id := str(_objects.get(id,{}).get("instance_id",""))
		if instance_id.is_empty(): return _info("这个对象没有登记实例",id)
		if Data.paid(_q(),instance_id): return _info("这里的事情已经办妥，先前的记录也已收好",id)
		if not _q().get("quests",{}).get(instance_id,{}).get("accepted",false):
			if id != instance_id+":giver": return _info("先去看看附近的求助或留言，弄清需要帮什么忙",id)
			if chain=="random_migration": _prepare_migration(instance_id)
			var candidate := encounters.candidate(chain,_context(instance_id))
			if candidate.is_empty(): return _info("这条线索眼下接不上。先看看附近的人和物资是否还在，不用停下来等。",id)
			_previews[instance_id] = candidate
			var stage := Catalog.stage(instance_id)
			return Presentation.with_narrative(_payload(Presentation.action_prompt(stage.get("actions", [{}])[0]),"看看能帮什么忙","accept_random|"+instance_id,id), stage.get("actions", [{}])[0])
	else:
		for stage: Dictionary in Catalog.chain(chain).get("steps",[]):
			if Data.ready(_q(),str(stage.id)): continue
			if not _q().get("quests",{}).get(stage.id,{}).get("accepted",false) and id == _stage_object(stage):
				if not _world_eligible(chain): return _info("还缺一条可以追查的线索。等有了确切消息，再来看看",id)
				return Presentation.with_narrative(_payload(Presentation.action_prompt(stage.get("actions", [{}])[0]),"顺着线索调查","accept_world|"+str(stage.id)+"|"+id,id), stage.get("actions", [{}])[0])
			break
	for a: Dictionary in _actions.values():
		if not handles_action(str(a.id)) or not _can(a): continue
		if id in a.get("puzzle_objects",[]): return Presentation.with_narrative(_payload("三行刻字就在一旁。想好点灯、辨路、等人的次序，再触碰这枚符记。","触碰符记","rune|"+str(a.id)+"|"+id,id), a)
		if str(a.object) != id: continue
		if a.kind == "puzzle": return Presentation.with_narrative(_info("先读清三行刻字，再去逐一触碰灯、路、人三枚符记",id), a)
		if a.kind == "configure": return _network_payload(a,id)
		if a.get("ecology_mode","") == "nest_resolution":
			return Presentation.with_narrative({"kind":"camp_choice","giver":_title(id),"origin":_position(id),"text":Presentation.action_prompt(a),"options":[{"label":"查看并确认绕行","action":"campaign|dynamic|act|"+str(a.id)+"|survey","enabled":true,"consequence":"记录当前巢区，提醒来人绕行","risk":"无需战斗；巢穴仍可能继续繁衍"},{"label":"记录这次捣巢","action":"campaign|dynamic|act|"+str(a.id)+"|ransack","enabled":true,"consequence":"记下本次接取后亲手捣巢的结果","risk":"只暂时抑制巢穴，之后仍可能重建"}]}, a)
		return Presentation.with_narrative(_payload(Presentation.action_prompt(a),str(a.verb),"act|"+str(a.id),id), a)
	var services: Dictionary = visual_state().services
	if services.has(id): return _service_payload(id,str(services[id]))
	var investigation := _investigation_payload(chain,id)
	if not investigation.is_empty(): return investigation
	if chain in ["world_migration","world_decline"] and not _historical_sources(chain).is_empty() and not _world_sites_ready(chain): return _info("线索还在，只是暂时没找到能安全靠近的观察点。先收好记录，这趟不必冒险硬闯。",id)
	var expeditions := expedition_options(id)
	if not expeditions.is_empty(): return {"kind":"camp_choice","giver":_title(id),"origin":_position(id),"text":"路书标着先前留下线索的地方。选一处去看看，或回记录点；路书写下以后，那里也许已有变化。","options":expeditions}
	return _info("这里暂时没有新发现。沿手头的线索继续看看",id)

func action(parts: Variant) -> String:
	var args: Array = []
	if not parts is Array and not parts is PackedStringArray: return "未识别的世界行动"
	for value: Variant in parts: args.append(str(value))
	if args.size() >= 2 and args[0] == "campaign" and args[1] == "dynamic": args = args.slice(2)
	if args.is_empty() or not _enabled(): return "这条调查线索还没有消息"
	match str(args[0]):
		"archive": return _read_archive(str(args[1]),int(args[2])) if args.size()>2 else "缺少档案页"
		"archive_menu":
			if args.size()<2 or not _at(str(args[1])): return "请在调查现场查看保存的档案"
			var payload := _investigation_payload(str(args[1]).get_slice(":",0),str(args[1]))
			if not payload.is_empty(): EventBus.npc_dialogue.emit(payload)
			return ""
		"clue":
			if args.size()<2 or not _at(str(args[1])) or str(args[1]) not in ["world_decline:last_site","world_decline:observer"] or facts.decline_trigger().is_empty(): return "请在真实足迹现场或观察员身旁辨读"
			facts.obtain_clue(str(facts.decline_trigger().get("region_id","")),str(args[1]))
			_host.call("_save")
			return "足迹的地点与记录时间已记下"
		"accept_random": return accept_random(str(args[1])) if args.size()>1 else "缺少实例"
		"accept_world": return accept_world(str(args[1]),str(args[2])) if args.size()>2 else "缺少接取地点"
		"act": return perform_action(str(args[1]),str(args[2]) if args.size()>2 else "") if args.size()>1 else "缺少行动"
		"rune": return touch_rune(str(args[1]),str(args[2])) if args.size()>2 else "缺少符记"
		"resume":
			if args.size()<3 or not _at(str(args[2])) or str(args[2]).get_slice(":",0)!=str(args[1]): return "请在本线现场继续"
			_q().paused_chains.erase(str(args[1]))
			_host.call("_save")
			return "已继续，上次的调查进度保留"
		"supply": return claim_service(str(args[1])) if args.size()>1 else "缺少站点"
		"expedition": return request_expedition(str(args[1]),str(args[2])) if args.size()>2 else "缺少历史调查目的地"
		"travel": return travel_node(str(args[1]),str(args[2])) if args.size()>2 else "缺少目的节点"
	return "未识别的世界行动"

func accept_random(id: String) -> String:
	_route_cache.clear()
	if not _enabled() or _sim == null or not _at(id+":giver") or not _previews.has(id): return "请在当地发起人身旁重新打开接取说明"
	if id.begins_with("random_migration:"): _prepare_migration(id)
	var trial := _q().duplicate(true)
	if not Data.accept(trial,id,GameState.stats.level): return "已有活动遭遇，或本实例名额已使用"
	_mutating = true
	if not encounters.accept(_previews[id],_context(id)):
		_mutating = false
		_previews.erase(id)
		return "现场条件已经变化，请重新核对；没有消耗实例名额"
	# Both sides were validated without yielding. Only commit the exact accepted contract.
	_q().quests = trial.quests
	_q().random_used = trial.random_used
	_q().active_random = trial.active_random
	_sync()
	_previews.clear()
	GameState.tracked_quest_id = id
	_host.call("_save")
	_mutating = false
	return "已接下这件事，先从眼前的线索查起"

func _world_eligible(chain: String) -> bool:
	_ensure_relief_needs()
	if not _world_sites_ready(chain): return false
	if chain in ["world_migration","world_decline"]:
		for id: String in _historical_sources(chain):
			if expedition_candidates(id).is_empty(): return false
	if chain == "world_decline":
		var trigger := facts.decline_trigger()
		if trigger.is_empty(): return false
		# No hidden population locator: first earn a clue by reading a real local authored object.
		if facts.known_clue(str(trigger.get("region_id",""))).is_empty(): return false
	return Data._world_unlocked(_q(),chain)

func accept_world(stage_id: String, id: String) -> String:
	var stage := Catalog.stage(stage_id)
	if not _enabled() or stage.get("family","") != "world" or id != _stage_object(stage) or not _at(id): return "请到这段调查的实际发布地点"
	if not _world_eligible(str(stage.chain)) or not Data.accept(_q(),stage_id,GameState.stats.level): return "当前真实前提未满足，或此段已经接取"
	GameState.tracked_quest_id = stage_id
	_host.call("_save")
	return "已接取："+str(stage.title)

func perform_action(id: String, choice := "") -> String:
	_route_cache.clear()
	var a: Dictionary = _actions.get(id,{})
	if _mutating or a.is_empty() or not handles_action(id) or not _can(a): return "先接取此段，并完成现场前置"
	if not _at(str(a.object)): return "请走到线索或收件人身旁，再查看或交付"
	if a.kind == "puzzle": return "请操作实际符记，不能直接完成机关"
	var proof := {"position":_position(str(a.object)),"tick":_sim.tick_count,"destination":str(a.object)}
	var error := _verify(a,proof,choice)
	if not error.is_empty(): return error
	return _commit(a,proof)

func _verify(a: Dictionary, proof: Dictionary, choice: String) -> String:
	if a.has("quest_item"): proof.item = str(a.quest_item)
	if a.has("consumes"):
		if not Data._has_quest_item(_q(),str(a.chain),str(a.consumes)): return "需要的物资还没取到，或已经交付"
		proof.item = str(a.consumes)
	if a.kind == "obstacle":
		var barrier := str(a.get("barrier_id",""))
		if not _broken(barrier): return "这处近道仍有碎岩挡着，请先打通眼前的缺口"
		proof.obstacle_key = barrier
		proof.destroyed = true
	if a.kind == "route":
		var visits: Array = _q().get("optional_routes",{}).get(a.id,[])
		if visits != a.get("route_waypoints",[]) or int(_runtime().route_steps.get(a.id,0))<1: return "请实际穿过这次破开的岩缝；只绕到两个端点不能验收新近道"
		proof.obstacle_key=str(a.stage)+":barrier"
		proof.destroyed=true
		proof.reason="crossed_registered_gap"
		var crossing:=_rock_gap(a)
		proof.target_position=[crossing.x,crossing.y]
		proof.route = "passage"
		proof.traversed = true
		proof.visit_ids = visits.duplicate()
	if str(a.stage).begins_with("random_"):
		var row := encounters.active()
		if row.get("id","") != a.stage: return "当前活动实例与此对象不一致"
		var current := encounters.refresh_active(_context(str(a.stage)))
		if current.get("state","") == "site_unavailable": return "登记对象或道路已经不可用，请先核对真实现场"
		var mode := str(a.get("ecology_mode",""))
		if mode == "nest_resolution":
			proof.outcome = "survey"
			proof.verified = true
			proof.region_id = row.proof.region_id
			proof.species = row.proof.species
			proof.target_key = row.proof.nest_key
			proof.reason = str(current.state)
			if choice == "ransack":
				var events: Array = []
				for event: Dictionary in facts.snapshot().events:
					if event.kind == "nest" and event.get("nest_key","") == row.proof.nest_key and int(event.tick)>=int(row.issued_tick) and event.get("ransacked",false): events.append(event)
				if events.is_empty(): return "这次还没有亲手捣毁巢穴，也可以查看现场后确认绕行"
				proof.outcome = "ransack"
				proof.events = events
		if mode == "migration_state":
			proof.outcome = str(current.state)
			proof.events = [row.proof.migration]
			proof.target_position = row.proof.site_position.duplicate()
			proof.region_id = row.proof.region_id
			proof.species = row.proof.species
		if mode == "camp_resolution":
			if current.state != "quota_met" and not current.get("can_survey_close",false): return "目标仍在附近，处理数目还没够；请按本次约定完成，并留下余量"
			proof.outcome = "hunt" if current.state == "quota_met" else "survey"
			proof.verified = true
			proof.reason = str(current.state)
			proof.unit_ids = current.credited_ids
			proof.events = []
			for event: Dictionary in current.proof.get("deaths",[]):
				if event.cause == EcologySim.DEATH_KILLED and int(event.instance_id) in proof.unit_ids: proof.events.append(event)
			proof.region_id = row.proof.region_id
			proof.species = row.proof.species
	if a.chain in ["world_migration","world_decline"]:
		var trigger := facts.migration_trigger() if a.chain == "world_migration" else facts.decline_trigger()
		if trigger.is_empty(): return "缺少真实世界触发证据"
		proof.species = str(trigger.species)
		proof.events = trigger.get("events",[])
		proof.region_id = BiomeMap.region_id_at(_position(str(a.object)))
		var status := facts.migration_status(trigger) if a.chain == "world_migration" else facts.decline_status(trigger)
		proof.outcome = str(status.state)
		proof.counts = {str(trigger.species):int(status.global_alive)}
		proof.reason = str(trigger.get("cause","migration"))
	if a.chain == "world_relief" and str(a.id) in ["world_relief:s1:need_a","world_relief:s1:need_b"]:
		proof.item = "world_relief:parcel_a" if str(a.id).ends_with("_a") else "world_relief:parcel_b"
		proof.reason = "dedicated_allocation_reserved"
		proof.witness = str(a.object)
	if a.has("supply_id"):
		var need := "world_relief:need_a" if str(a.supply_id).ends_with("_a") else "world_relief:need_b"
		if not _done(_actions.get("world_relief:s1:"+need.get_slice(":",1),{})): return "先亲自确认对应居民的明确需求"
		proof.item = str(a.supply_id)
		proof.witness = need
	if a.chain == "world_relief" and str(a.id).contains(":return_"):
		var supply := "world_relief:s2:supply_a" if str(a.id).ends_with("_a") else "world_relief:s2:supply_b"
		if not _done(_actions.get(supply,{})): return "对应编号的物资尚未交到此处"
		proof.item = str(_actions.get(supply,{}).get("supply_id",""))
		proof.witness = str(a.object)
	if a.kind == "configure":
		var selected: Array = []
		for node: String in choice.split(",",false): selected.append(node)
		if selected.size()!=3: return "请选择三个不同的已完成区域节点"
		for node: String in selected:
			if selected.count(node)!=1 or not node in _completed_nodes(): return "选定节点必须真实完成且互不重复"
		proof.nodes = selected
	if a.has("node_index"):
		var nodes := selected_nodes()
		var index := int(a.node_index)
		if nodes.size()!=3 or not nodes[index] in _completed_nodes(): return "规划的节点尚未实际可用"
		proof.nodes = nodes
		proof.item = "world_watchnet:device_"+str(index+1)
		proof.witness = str(nodes[index])
	if a.chain == "world_watchnet" and a.get("service","") == "world_watchnet_station":
		for node: String in selected_nodes():
			if not node in _completed_nodes(): return "三处已选服务必须真实可用"
	return ""

func _commit(a: Dictionary, proof: Dictionary) -> String:
	_mutating = true
	var trial := _q().duplicate(true)
	if not Data.record(trial,str(a.stage),str(a.id),proof):
		_mutating = false
		return "现场证据不完整，未消耗物资或支付奖励"
	if str(a.stage).begins_with("random_"):
		var role := str(a.object).get_slice(":",3)
		if not encounters.record_action(role,str(a.id),_context(str(a.stage)),str(proof.get("outcome",""))):
			_mutating = false
			return "实例对象核验失败，请在现场重新确认"
	# Replace only data-derived sections, preserving live fact and encounter snapshots.
	for key: String in ["quests","flags","services","ending","history","puzzle_progress","travel"]: _q()[key] = trial[key]
	if a.has("supply_id"):
		var need := "world_relief:need_a" if str(a.supply_id).ends_with("_a") else "world_relief:need_b"
		_runtime().relief_needs[need].resolved = true
	if a.kind in ["read","talk","observe"]: facts.obtain_clue(BiomeMap.region_id_at(_position(str(a.object))),str(a.object))
	GameState.begin_world_reward()
	_host.call("_settle_ready")
	_finish_encounter()
	_sync()
	_host.call("_save")
	GameState.end_world_reward()
	_mutating = false
	return str(a.get("text","现场记录已保存"))

func _finish_encounter() -> void:
	var row := encounters.active()
	if row.is_empty() or not Data.ready(_q(),str(row.id)) or not Data.paid(_q(),str(row.id)): return
	var outcome := "completed"
	for proof: Dictionary in _q().quests[row.id].evidence.values():
		if proof.has("reason"): outcome = str(proof.reason)
	encounters.complete(outcome,{"validated":true})
	_sync()

func touch_rune(action_id: String, id: String) -> String:
	var a: Dictionary = _actions.get(action_id,{})
	if a.is_empty() or not _can(a) or not _at(id) or not id in a.get("puzzle_objects",[]): return "请先阅读线索，再到当前实例的实体符记旁"
	var index: int = a.puzzle_objects.find(id)
	var progress: Array = _q().puzzle_progress.get(action_id,[]).duplicate()
	var symbol := str(a.puzzle_order[index])
	if symbol != str(a.puzzle_order[progress.size()]):
		_q().puzzle_progress.erase(action_id)
		_host.call("_save")
		return "次序不合，符光熄灭了。再看看三行刻字，从头试一次"
	progress.append(symbol)
	if progress.size()<a.puzzle_order.size():
		_q().puzzle_progress[action_id] = progress
		_host.call("_save")
		return "这枚符记已回应"
	# The final rune is a genuine on-site puzzle action; record it at that rune, never fake target proximity.
	var trial := _q().duplicate(true)
	var proof := {"position":_position(id),"tick":_sim.tick_count,"order":progress,"destination":str(a.object)}
	if not Data.record(trial,str(a.stage),action_id,proof): return "机关证据未通过"
	_mutating = true
	if not encounters.record_action(id.get_slice(":",3),action_id,_context(str(a.stage))):
		_mutating = false
		return "符记现场已变化"
	for key: String in ["quests","flags","services","ending","history","puzzle_progress","travel"]: _q()[key] = trial[key]
	GameState.begin_world_reward()
	_host.call("_settle_ready")
	_finish_encounter()
	_host.call("_save")
	GameState.end_world_reward()
	_mutating = false
	return "灯、路、人依次回应，三行刻字旁亮起了光"

func _rock_gap(a: Dictionary) -> Vector2:
	var cells:=Layout.barrier_cells(str(a.get("stage",""))+":barrier")
	if cells.is_empty(): return Vector2.INF
	var center:=Vector2.ZERO
	for cell: Vector2i in cells: center+=(Vector2(cell)+Vector2(0.5,0.5))*32.0
	return center/float(cells.size())

func _route_anchor(a: Dictionary, visits: Array) -> Vector2:
	if int(_runtime().route_steps.get(a.id,0))>=1: return _rock_gap(a)
	return _position(str(visits[-1])) if not visits.is_empty() else Vector2.INF

func _motion_clear(from: Vector2, to: Vector2) -> bool:
	if not from.is_finite() or not to.is_finite(): return false
	var count:=maxi(1,ceili(from.distance_to(to)/8.0))
	for index in count+1:
		if ObstacleField.blocks(from.lerp(to,float(index)/count),10.0): return false
	return true

func _crossed_rock_gap(a: Dictionary, previous: Vector2, current: Vector2) -> bool:
	if not previous.is_finite() or not _broken(str(a.stage)+":barrier"): return false
	var center:=_rock_gap(a)
	var points: Array=a.get("route_waypoints",[])
	if not center.is_finite() or points.size()!=2: return false
	var direction:=(_position(str(points[1]))-_position(str(points[0]))).normalized()
	var before: float=(previous-center).dot(direction)
	var after: float=(current-center).dot(direction)
	if before>0 or after<0 or after-before<0.001: return false
	var point:=previous.lerp(current,-before/(after-before))
	# Swept-segment crossing accepts a normal dash while rejecting the already-open outer detour.
	return absf((point-center).cross(direction))<=30.0 and _motion_clear(previous,current)

func _track_route() -> void:
	var player := _player()
	if player == null or (player is Player and player._is_dead): return
	var current := player.global_position
	var previous:=_last_position
	var discontinuous := previous.is_finite() and (previous.distance_to(current)>160 or not _motion_clear(previous,current))
	_last_position = current
	for a: Dictionary in _actions.values():
		if not str(a.stage).begins_with("random_rocks:") or a.kind != "route" or not _can(a): continue
		var visits: Array = _q().optional_routes.get(a.id,[]).duplicate()
		var changed:=false
		if discontinuous and not visits.is_empty() and visits.size()<a.route_waypoints.size(): _route_reentry[a.id] = true
		if _route_reentry.get(a.id,false):
			var anchor:=_route_anchor(a,visits)
			if anchor.is_finite() and current.distance_to(anchor)<=64 and _motion_clear(current,anchor): _route_reentry.erase(a.id)
			else: continue
		if not discontinuous and not visits.is_empty() and int(_runtime().route_steps.get(a.id,0))<1 and _crossed_rock_gap(a,previous,current):
			_runtime().route_steps[a.id]=1
			changed=true
		if visits.size()<a.route_waypoints.size() and _at(str(a.route_waypoints[visits.size()])):
			if visits.is_empty() or int(_runtime().route_steps.get(a.id,0))>=1: visits.append(a.route_waypoints[visits.size()])
		if visits != _q().optional_routes.get(a.id,[]):
			_q().optional_routes[a.id] = visits
			changed=true
		if changed: _host.call("_save")

func _completed_nodes() -> Array:
	var nodes: Array = []
	for arc: Dictionary in Catalog.regional_arcs():
		var service := str(arc.id)+"_station"
		if Data.ready(_q(),str(arc.id)+":s3") and _q().get("services",{}).get(service,{}).get("enabled",false): nodes.append(service)
	return nodes

func selected_nodes() -> Array:
	return _q().get("quests",{}).get("world_watchnet:s1",{}).get("evidence",{}).get("world_watchnet:s1:plan",{}).get("nodes",[]).duplicate()

func _network_payload(a: Dictionary,id: String) -> Dictionary:
	var nodes := _completed_nodes()
	var options: Array = []
	for i in nodes.size():
		for j in range(i+1,nodes.size()):
			for k in range(j+1,nodes.size()):
				var selected := [str(nodes[i]),str(nodes[j]),str(nodes[k])]
				var titles: Array[String] = []
				for service: String in selected: titles.append(str(Catalog.chain(service.trim_suffix("_station")).get("title",service)))
				options.append({"label":"、".join(titles),"action":"campaign|dynamic|act|"+str(a.id)+"|"+",".join(selected),"enabled":true,"consequence":"分别安装三套装置，完工后可往返这三处站点","risk":"选定后线路固定，请确认三个去处"})
	return Presentation.with_narrative({"kind":"camp_choice","giver":_title(id),"origin":_position(id),"text":Presentation.action_prompt(a),"options":options}, a)

func _service_payload(id: String, service: String) -> Dictionary:
	var claimed := Data.service_claimed(_q(), service)
	var options: Array = []
	if not claimed:
		options.append({"label":"领取驻站补给","action":"campaign|dynamic|supply|"+id,"enabled":true,"consequence":"饭团×1","risk":"放不下的补给存入背包→待领取"})
	if Data.ready(_q(),"world_watchnet:s3"):
		for node: String in selected_nodes():
			options.append({"label":"前往"+str(Catalog.chain(node.trim_suffix("_station")).get("title",node)),"action":"campaign|dynamic|travel|"+id+"|"+node,"enabled":true,"consequence":"前往已安装且真实可用的区域接应节点","risk":"需要脱离战斗，周围生态风险仍然存在"})
	return {"kind":"camp_choice","giver":_title(id),"origin":_position(id),"text":"给你留的饭团已经领过了，沿途多留心。" if claimed else "补给备好了，给你留了一个饭团。歇歇再走吧。","options":options}

func claim_service(id: String) -> String:
	if _mutating: return "正在提交此项交付"
	if not _enabled() or not _at(id): return "请到驻站身旁"
	var service := str(visual_state().services.get(id,""))
	if service.is_empty() or not _q().get("services",{}).get(service,{}).get("enabled",false): return "此服务尚未恢复"
	if Data.service_claimed(_q(),service): return "这份驻站补给已经领取"
	if not Inventory.can_apply({}, {"onigiri":1}): return "当前无法记录补给，尚未领取；请确认存档可写后重试"
	_mutating = true
	GameState.begin_world_reward()
	_q().services[service].claimed = true
	_q().services[service].status = "claimed"
	if not _q().has("service_receipts"): _q()["service_receipts"] = {}
	_q().service_receipts[service] = {"claimed":true,"status":"claimed"}
	Inventory.apply({}, {"onigiri":1})
	_host.call("_save")
	GameState.end_world_reward()
	_mutating = false
	return "已领取驻站饭团×1"

func is_service_origin(id: String) -> bool:
	return _enabled() and _at(id) and visual_state().services.has(id)

func can_travel_node(origin: String, service: String) -> bool:
	return _enabled() and _at(origin) and visual_state().services.has(origin) and Data.ready(_q(),"world_watchnet:s3") and service in selected_nodes() and service in _completed_nodes()

func node_destination(service: String) -> Vector2:
	if not service in selected_nodes() or not service in _completed_nodes(): return Vector2.INF
	var at := _position(service.trim_suffix("_station")+":station")
	for offset: Vector2 in [Vector2(0,96),Vector2(96,0),Vector2(-96,0),Vector2(0,-96)]:
		if not ObstacleField.blocks(at+offset,16.0) and ObstacleField.liquid_kind_at(at+offset).is_empty(): return at+offset
	return Vector2.INF

func travel_node(origin: String, service: String) -> String:
	if not can_travel_node(origin,service): return "请在实际可用的守望节点身旁选择已经建成的线路"
	if not node_destination(service).is_finite(): return "节点落脚处暂不可用"
	EventBus.campaign_travel_requested.emit("watchnet:"+service,origin)
	return ""

func visual_state() -> Dictionary:
	var state := {"active_encounter":"","placements":{},"services":{},"taken":{},"read":{},"object_states":{},"object_actions":{},"rescued":{},"repaired":{},"active_runes":[]}
	if not _enabled(): return state
	state.active_encounter = str(_q().get("encounters",{}).get("active",""))
	for id: String in _runtime().bindings: state.placements[id] = {"position":_runtime().bindings[id].position}
	for id: String in _objects:
		if not id.begins_with("random_"): continue
		var instance_id := str(_objects[id].get("instance_id",""))
		var known := _known(id)
		var expose := _exposed.has(instance_id) or known or instance_id == str(state.active_encounter)
		if not state.placements.has(id): state.placements[id] = {}
		state.placements[id].hidden = not expose
	for a: Dictionary in _actions.values():
		if not handles_action(str(a.id)) or not _done(a): continue
		var id := str(a.object)
		state.object_states[id] = "taken" if a.kind == "recover" else ("read" if a.kind == "read" else "completed")
		if a.kind == "recover": state.taken[id] = true
		if a.kind == "read": state.read[id] = true
		if a.kind == "rescue": state.rescued[id] = true
		if a.kind in ["repair","deliver","route"]: state.repaired[id] = true
		if a.kind == "puzzle": state.active_runes.append_array(a.get("puzzle_objects",[]))
		if a.has("service"):
			state.services[id] = str(a.service)
			if not state.placements.has(id): state.placements[id] = {}
			state.placements[id].service = "联合补给" if a.chain=="world_relief" else "守望网络"
	for suffix: String in ["a","b"]:
		if _done(_actions.get("world_relief:s2:supply_"+suffix,{})):
			var id := "world_relief:need_"+suffix
			state.repaired[id] = true
			state.placements[id] = {"title":"收到物资的接应居民","service":"接应恢复"}
			if Data.ready(_q(),"world_relief:s3"): state.services[id] = "world_relief_station"
	var nodes := selected_nodes()
	for index in nodes.size():
		var id := "world_watchnet:node_"+str(index+1)
		var point := _position(str(nodes[index]).trim_suffix("_station")+":station")+Vector2(96,0)
		state.placements[id] = {"position":point,"title":"守望装置 · "+str(Catalog.chain(str(nodes[index]).trim_suffix("_station")).get("title","节点"))}
		if Data.ready(_q(),"world_watchnet:s3"):
			state.services[id] = "world_watchnet_station"
			state.placements[id].service = "节点远征"
	for a: Dictionary in _actions.values():
		if not handles_action(str(a.id)) or not _can(a): continue
		var id := str(a.object)
		state.object_states[id] = "available"
		state.object_actions[id] = str(a.get("verb", "调查"))
		for rune: String in a.get("puzzle_objects", []):
			state.object_states[rune] = "available"
			state.object_actions[rune] = "触碰符记"
	for id: String in state.services:
		state.object_states[id] = "claimed" if Data.service_claimed(_q(), str(state.services[id])) else "ready"
		state.object_actions[id] = "驻站服务"
	return state

## 指引只使用已登记现场或眼前真实活体；绝不把隐藏个体当前位置透给地图。
func next_target(a: Dictionary) -> Dictionary:
	var guide := _next_target(a)
	var id := str(guide.get("object_id", ""))
	var title := str(_objects.get(id, {}).get("title", "调查地点"))
	guide["target_title"] = title
	guide["next_action"] = str(guide.get("label", "")) if a.get("kind", "") == "route" or a.has("ecology_mode") or a.get("kind", "") == "puzzle" else str(a.get("verb", "调查")) + " · " + title
	if a.get("kind", "") == "route":
		var visits: Array = _q().get("optional_routes", {}).get(a.get("id", ""), [])
		guide["step_progress"] = "路线 %d/%d" % [visits.size(), a.get("route_waypoints", []).size()]
	return guide

func _next_target(a: Dictionary) -> Dictionary:
	var id := str(a.get("object",""))
	var label := _title(id)
	if a.get("kind","") == "puzzle" and not _done(a):
		var progress: Array = _q().get("puzzle_progress",{}).get(a.get("id",""),[])
		var objects: Array = a.get("puzzle_objects",[])
		if not objects.is_empty():
			var index := mini(progress.size(),objects.size()-1)
			id = str(objects[index])
			label = "依现场说明操作「"+str(a.puzzle_order[index])+"」符记"
	if a.get("kind","") == "route" and not _done(a):
		var visits: Array = _q().get("optional_routes",{}).get(a.get("id",""),[])
		var points: Array = a.get("route_waypoints",[])
		if _route_reentry.get(a.get("id",""),false) and not visits.is_empty():
			return {"object_id":"","position":_route_anchor(a,visits),"label":"返回最后核实的近道位置，接续验收"}
		elif not visits.is_empty() and int(_runtime().route_steps.get(a.get("id",""),0))<1:
			return {"object_id":"","position":_rock_gap(a),"label":"穿过新破开的岩缝"}
		elif visits.size()<points.size():
			id = str(points[visits.size()])
			label = "从登记碎岩沿近道实际走到另一端" if visits.is_empty() else "沿已开缺口走到近道另一端"
	if a.get("ecology_mode","") == "camp_resolution" and not _done(a):
		var row := encounters.active()
		if row.get("id","") == str(a.get("stage","")):
			var status := encounters.refresh_active(_context(str(row.id)))
			var remaining := maxi(0,int(row.proof.get("quota",0))-status.get("credited_ids",[]).size())
			if status.get("state","") == "quota_met": label = "数目已够，返回据点回报情况"
			elif status.get("can_survey_close",false): label = "目标有变化，回到据点查看"
			else:
				label = "前往据点 · 还需处理%d只，找不到时在现场复查" % remaining
				for target_id: int in row.proof.get("target_ids",[]):
					var inst: MonsterInstance = _sim.instances.get(target_id)
					if inst == null or not inst.is_alive or inst.region_id != str(row.proof.get("region_id","")): continue
					if not encounters._position_allowed(_actor_position(inst),_context(str(row.id))): continue
					var actor := _observed_actor(inst)
					if actor != null:
						return {"object_id":"","position":actor.global_position,"label":"附近的"+inst.species.species_name+" · 还需处理%d只"%remaining}
	return {"object_id":id,"position":_position(id),"label":label}

func _observed_actor(inst: MonsterInstance) -> Node2D:
	var player := _player()
	if player == null: return null
	for actor: Node in get_tree().get_nodes_in_group("monsters"):
		if not actor is Node2D or actor.get("inst") != inst or not actor.is_visible_in_tree() or actor.is_queued_for_deletion(): continue
		var point: Vector2 = actor.global_position
		if player.global_position.distance_to(point)>680: continue
		var viewport := get_viewport()
		if viewport.get_camera_2d()!=null and not viewport.get_visible_rect().has_point(viewport.get_canvas_transform()*point): continue
		var steps := maxi(1,ceili(player.global_position.distance_to(point)/12.0))
		var visible := true
		for index in range(1,steps):
			if ObstacleField.blocks(player.global_position.lerp(point,float(index)/steps),0.0):
				visible=false
				break
		if visible: return actor as Node2D
	return null


const WORLD_SITE_IDS := {
	"world_migration":["world_migration:route_a","world_migration:route_b","world_migration:observer","world_migration:record_board"],
	"world_decline":["world_decline:last_site","world_decline:evidence_post","world_decline:warning_sign","world_decline:observer"]}

func _expedition_eligible(chain: String) -> bool:
	if not _enabled() or facts==null or not WORLD_SITE_IDS.has(chain) or not _world_sites_ready(chain): return false
	if chain=="world_migration": return not facts.migration_trigger().is_empty()
	var trigger:=facts.decline_trigger()
	return not trigger.is_empty() and not facts.known_clue(str(trigger.get("region_id",""))).is_empty()

func _at_departure(id: String) -> bool:
	if id!="home:patrol": return _at(id)
	# Host handles home first and validates the actual living player, current patrol position and line of sight.
	return is_instance_valid(_host) and bool(_host.call("_at_origin",id))

func is_expedition_origin(id: String) -> bool:
	if not _at_departure(id): return false
	if id=="home:patrol": return _expedition_eligible("world_migration") or _expedition_eligible("world_decline")
	var chain:=id.get_slice(":",0)
	return _expedition_eligible(chain) and id in WORLD_SITE_IDS.get(chain,[])

func can_travel_site(origin: String, target_id: String) -> bool:
	if not is_expedition_origin(origin): return false
	var chain:=target_id.get_slice(":",0)
	if not _expedition_eligible(chain) or target_id not in WORLD_SITE_IDS.get(chain,[]): return false
	if origin!="home:patrol" and origin.get_slice(":",0)!=chain: return false
	if target_id not in ["world_migration:record_board","world_decline:observer"] and not _runtime().bindings.has(target_id): return false
	return origin!=target_id

func expedition_options(origin: String) -> Array:
	var options: Array=[]
	if not is_expedition_origin(origin): return options
	for chain: String in WORLD_SITE_IDS:
		if not _expedition_eligible(chain) or (origin!="home:patrol" and origin.get_slice(":",0)!=chain): continue
		for target_id: String in WORLD_SITE_IDS[chain]:
			if not can_travel_site(origin,target_id): continue
			options.append({"label":"沿线索前往"+_title(target_id),"action":"campaign|dynamic|expedition|"+origin+"|"+target_id,"enabled":true,
				"consequence":"按旧路书前往这处线索附近，抵达后查看现状",
				"risk":"需要脱离战斗；沿途不回复生命或精力，旧目击不保证目标仍在"})
	return options

func expedition_candidates(target_id: String) -> Array[Vector2]:
	var out: Array[Vector2]=[]
	var chain:=target_id.get_slice(":",0)
	if not _expedition_eligible(chain) or target_id not in WORLD_SITE_IDS.get(chain,[]): return out
	if target_id not in ["world_migration:record_board","world_decline:observer"] and not _runtime().bindings.has(target_id): return out
	var point:=_position(target_id)
	if not point.is_finite(): return out
	# Authored report desks can land close; ecology sites deliberately approach outside the camp itself.
	var radii: Array=[96.0,192.0,384.0] if target_id in ["world_migration:record_board","world_decline:observer"] else [800.0,1024.0,1280.0,1536.0]
	for radius: float in radii:
		for direction: Vector2 in [Vector2.DOWN,Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2(1,1).normalized(),Vector2(-1,1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,-1).normalized()]:
			var candidate:=point+direction*radius
			if ObstacleField.blocks(candidate,16.0) or not ObstacleField.liquid_kind_at(candidate).is_empty(): continue
			if not _route_exists(candidate,point): continue
			out.append(candidate)
	return out

func request_expedition(origin: String, target_id: String) -> String:
	if not can_travel_site(origin,target_id): return "请在联络员或本线现场确认已经取得的调查线索"
	if expedition_candidates(target_id).is_empty(): return "历史现场附近暂未找到安全接近点，线索与进度保留"
	EventBus.campaign_travel_requested.emit("worldsite:"+target_id,origin)
	return ""


func _grid_route(from: Vector2, to: Vector2) -> bool:
	# Bounded 32px navigation probe for a historical site's approach pad, using the same obstacle mask as gameplay.
	var first:=Vector2i(floori(from.x/32.0),floori(from.y/32.0))
	var last:=Vector2i(floori(to.x/32.0),floori(to.y/32.0))
	var corner:=Vector2i(mini(first.x,last.x)-6,mini(first.y,last.y)-6)
	var end:=Vector2i(maxi(first.x,last.x)+7,maxi(first.y,last.y)+7)
	var size:=end-corner
	if size.x*size.y>10000: return false
	var grid:=AStarGrid2D.new()
	grid.region=Rect2i(corner,size)
	grid.cell_size=Vector2(32,32)
	grid.offset=Vector2(16,16)
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for y in range(corner.y,end.y):
		for x in range(corner.x,end.x):
			var cell:=Vector2i(x,y)
			grid.set_point_solid(cell,ObstacleField.nav_blocked_at((Vector2(cell)+Vector2(0.5,0.5))*32.0))
	if grid.is_point_solid(first) or grid.is_point_solid(last): return false
	var reachable:=not grid.get_id_path(first,last).is_empty()
	_route_cache[str(Vector2i(from/32))+":"+str(Vector2i(to/32))]=reachable
	return reachable
