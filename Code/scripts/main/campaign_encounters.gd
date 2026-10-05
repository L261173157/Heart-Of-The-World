## 有限野外遭遇资格与实例。调用方提供现场探针；本类不刷怪、不消费物品、不发奖。
## candidate 只是预览；accept 每次重新探针，必须与 CampaignQuestData.accept 同一事务。
class_name CampaignEncounters
extends RefCounted

signal changed

const Facts := preload("res://scripts/main/campaign_world_facts.gd")
const VERSION := 1
const MAX_PER_TEMPLATE := 3
const MAX_INSTANCES := 30
const FAMILY_COOLDOWN := 300
const GLOBAL_COOLDOWN := 45
const LOCAL_RADIUS := 6000.0
const NEST_ROUTE_RADIUS := 900.0
const TEMPLATES := ["random_wounded","random_parcel","random_sign","random_rocks","random_medicine",
	"random_message","random_nest","random_migration","random_camp","random_runes"]
const REQUIRED_ROLES := {
	"random_wounded":["giver","parts","target"],"random_parcel":["giver","target","return"],
	"random_sign":["giver","parts","target"],"random_rocks":["giver","target","return"],
	"random_medicine":["giver","parts","target"],"random_message":["giver","target","return"],
	"random_nest":["giver","target","return"],"random_migration":["giver","target","return"],
	"random_camp":["giver","target","return"],
	"random_runes":["giver","record","rune_a","rune_b","rune_c","target"]}

var _sim: EcologySim
var _facts: CampaignWorldFacts
var _seed := 0
var _state: Dictionary = {}
var _notifying := false

static func _empty(seed_value: int) -> Dictionary:
	return {"version":VERSION,"seed":seed_value,"instances":{},"counts":{},"active":"",
		"last_issue_tick":-GLOBAL_COOLDOWN,"last_closed":{}}

static func instance_id(template: String, seed_value: int, ordinal: int) -> String:
	return "%s:%d:%d" % [template,seed_value,ordinal]

static func _ids(value: Variant) -> Array:
	var out: Array = []
	if not value is Array: return out
	for item: Variant in value:
		var id := Facts._integer(item)
		if id > 0 and not id in out: out.append(id)
		if out.size() >= 16: break
	return out

static func _proof(raw: Variant, seed_value: int) -> Dictionary:
	var out := {}
	if not raw is Dictionary: return out
	for key: String in ["species","region_id","nest_key","state","outcome","source","cost_item"]:
		if raw.get(key) is String: out[key] = Facts._text(raw[key])
	for key: String in ["global_alive","local_alive","quota","cost_count","tick","last_checked_tick"]:
		if raw.has(key): out[key] = Facts._integer(raw[key])
	if raw.get("origin") is Array and raw.origin.size() == 2:
		if typeof(raw.origin[0]) in [TYPE_INT,TYPE_FLOAT] and typeof(raw.origin[1]) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(raw.origin[0])) and is_finite(float(raw.origin[1])): out["origin"] = [float(raw.origin[0]),float(raw.origin[1])]
	out["target_ids"] = _ids(raw.get("target_ids",[]))
	out["credited_ids"] = []
	out["deaths"] = Facts._events(raw.get("deaths",[]),seed_value,16)
	for death: Dictionary in out.deaths:
		if death.kind == "death" and death.cause == EcologySim.DEATH_KILLED and int(death.instance_id) in out.target_ids and death.from_region == str(out.get("region_id","")) and _death_local(out,death) and not int(death.instance_id) in out.credited_ids:
			out.credited_ids.append(int(death.instance_id))
	var migration := Facts._event(raw.get("migration"),seed_value)
	if not migration.is_empty() and migration.kind == "migration": out["migration"] = migration
	return out

static func _death_local(proof: Dictionary, death: Dictionary) -> bool:
	if proof.get("origin") is Array and death.get("position") is Array:
		return Vector2(float(proof.origin[0]),float(proof.origin[1])).distance_to(Vector2(float(death.position[0]),float(death.position[1]))) <= LOCAL_RADIUS
	return true

static func sanitize(value: Variant, seed_value: int) -> Dictionary:
	var out := _empty(seed_value)
	if not value is Dictionary or not Facts._same_seed(value.get("seed"),seed_value): return out
	out.last_issue_tick = Facts._integer(value.get("last_issue_tick"),-GLOBAL_COOLDOWN)
	if typeof(value.get("last_issue_tick")) in [TYPE_INT,TYPE_FLOAT] and float(value.last_issue_tick) < 0:
		out.last_issue_tick = -GLOBAL_COOLDOWN
	var counts: Variant = value.get("counts",{})
	var closed: Variant = value.get("last_closed",{})
	for template: String in TEMPLATES:
		if counts is Dictionary: out.counts[template] = mini(MAX_PER_TEMPLATE,Facts._integer(counts.get(template)))
		if closed is Dictionary and closed.has(template): out.last_closed[template] = Facts._integer(closed[template])
	var entries: Variant = value.get("instances",{})
	if entries is Dictionary:
		# Whitelisted deterministic keys bound work even for a malicious oversized dictionary.
		for template: String in TEMPLATES:
			for ordinal in MAX_PER_TEMPLATE:
				var id := instance_id(template,seed_value,ordinal)
				if not entries.has(id): continue
				out.counts[template] = maxi(int(out.counts.get(template,0)),ordinal+1)
				var raw: Variant = entries[id]
				# A corrupt spent instance becomes a closed tombstone, never a rerollable slot.
				var row := {"id":id,"template_id":template,"seed":seed_value,"ordinal":ordinal,
					"version":VERSION,"status":"closed","issued_tick":0,"closed_tick":0,
					"object_ids":{},"proof":{},"outcome":"damaged_record","evidence":{}}
				if raw is Dictionary:
					row.status = "active" if Facts._text(raw.get("status")) == "active" else "closed"
					row.issued_tick = Facts._integer(raw.get("issued_tick"))
					row.closed_tick = Facts._integer(raw.get("closed_tick"))
					row.outcome = Facts._text(raw.get("outcome"))
					row.proof = _proof(raw.get("proof"),seed_value)
					for role: String in REQUIRED_ROLES[template]: row.object_ids[role] = id+":"+role
					var evidence: Variant = raw.get("evidence",{})
					if evidence is Dictionary:
						for role: String in REQUIRED_ROLES[template]:
							if evidence.get(role) is Dictionary:
								row.evidence[role] = {"object_id":id+":"+role,"tick":Facts._integer(evidence[role].get("tick")),
									"action":Facts._text(evidence[role].get("action")),"choice":Facts._text(evidence[role].get("choice"))}
				out.instances[id] = row
	var active_id := Facts._text(value.get("active"))
	if out.instances.has(active_id) and out.instances[active_id].status == "active": out.active = active_id
	for id: String in out.instances:
		if id != out.active and out.instances[id].status == "active":
			out.instances[id].status = "closed"
			out.instances[id].outcome = "inactive_record"
	# Per-instance timestamps are independent witnesses. Losing an index cannot bypass either cooldown.
	for row: Dictionary in out.instances.values():
		out.last_issue_tick=maxi(int(out.last_issue_tick),int(row.issued_tick))
		if row.status=="closed":
			row.closed_tick=maxi(int(row.closed_tick),int(row.issued_tick))
			out.last_closed[row.template_id]=maxi(int(out.last_closed.get(row.template_id,0)),int(row.closed_tick))
	return out

func configure(sim: EcologySim, seed_value: int, saved: Dictionary = {}, facts: CampaignWorldFacts = null) -> void:
	if _facts != null and is_instance_valid(_facts) and _facts.changed.is_connected(_on_fact_changed): _facts.changed.disconnect(_on_fact_changed)
	_sim = sim
	_seed = seed_value
	_state = sanitize(saved,_seed)
	_facts = facts
	if _facts != null: _facts.changed.connect(_on_fact_changed)
	_capture_credit()

func snapshot() -> Dictionary:
	_capture_credit()
	return _state.duplicate(true)

func active() -> Dictionary:
	return (_state.get("instances",{}).get(str(_state.get("active","")),{}) as Dictionary).duplicate(true)

func total_issued() -> int:
	var total := 0
	for count: int in _state.get("counts",{}).values(): total += count
	return total

func _available(template: String) -> bool:
	if _sim == null or not template in TEMPLATES or not str(_state.get("active","")).is_empty(): return false
	if int(_state.counts.get(template,0)) >= MAX_PER_TEMPLATE or total_issued() >= MAX_INSTANCES: return false
	if _sim.tick_count-int(_state.last_issue_tick) < GLOBAL_COOLDOWN: return false
	if _state.last_closed.has(template) and _sim.tick_count-int(_state.last_closed[template]) < FAMILY_COOLDOWN: return false
	return true

func candidate(template: String, context: Dictionary) -> Dictionary:
	if not _available(template): return {}
	var ordinal := int(_state.counts.get(template,0))
	var id := instance_id(template,_seed,ordinal)
	var result := _eligibility(template,id,context)
	if result.is_empty(): return {}
	result.merge({"id":id,"template_id":template,"seed":_seed,"ordinal":ordinal,"version":VERSION,
		"issued_tick":_sim.tick_count,"status":"preview"})
	return result

func candidates(context: Dictionary) -> Array:
	var out: Array = []
	for template: String in TEMPLATES:
		var item := candidate(template,context)
		if not item.is_empty(): out.append(item)
	return out

func _probe(id: String, context: Dictionary) -> Dictionary:
	var probe: Variant = context.get("probe_object")
	if not probe is Callable or not probe.is_valid(): return {}
	var raw: Variant = probe.call(id)
	if not raw is Dictionary or raw.get("id") != id: return {}
	if raw.get("exists") != true or raw.get("registered") != true or raw.get("known") != true or raw.get("reachable") != true: return {}
	if str(raw.get("region_id","")) != str(context.get("region_id","")): return {}
	var position: Variant = raw.get("position")
	var origin: Variant = context.get("origin")
	if not position is Vector2 or not origin is Vector2 or not position.is_finite() or not origin.is_finite(): return {}
	if origin.distance_to(position) > LOCAL_RADIUS: return {}
	return raw

func _eligibility(template: String, id: String, context: Dictionary) -> Dictionary:
	var region_id := str(context.get("region_id",""))
	if not _sim.regions.has(region_id): return {}
	var objects := {}
	var object_ids := {}
	for role: String in REQUIRED_ROLES[template]:
		var object_id := id+":"+role
		var object := _probe(object_id,context)
		if object.is_empty(): return {}
		objects[role] = object
		object_ids[role] = object_id
	var origin: Vector2 = context.origin
	var proof := {"region_id":region_id,"tick":_sim.tick_count,"source":"registered_authored_objects","origin":[origin.x,origin.y]}
	match template:
		"random_wounded":
			if objects.target.get("needs_aid") != true or objects.parts.get("unclaimed") != true: return {}
		"random_parcel":
			if objects.target.get("unclaimed") != true or objects["return"].get("recipient") != true: return {}
		"random_sign":
			if objects.target.get("pending_repair") != true or objects.parts.get("unclaimed") != true: return {}
		"random_rocks":
			if objects.target.get("breakable") != true or objects.target.get("broken") == true: return {}
			if objects.giver.get("route_endpoint") != true or objects["return"].get("route_endpoint") != true: return {}
		"random_medicine":
			if objects.target.get("pending_need") != true: return {}
			if objects.parts.get("unclaimed") != true and context.get("can_pay_cost") != true: return {}
			# Only record the advertised cost. Inventory mutation belongs to explicit confirmed action.
			proof.cost_item = str(context.get("cost_item","dedicated_medicine"))
			proof.cost_count = maxi(1,Facts._integer(context.get("cost_count",1)))
		"random_message":
			if objects.giver.get("recipient") != true or objects["return"].get("recipient") != true: return {}
		"random_nest":
			var nest := _nest_target(objects.target.position,context)
			if nest.is_empty(): return {}
			proof.merge(nest,true)
		"random_migration":
			if _facts == null or _facts.known_clue(region_id).is_empty(): return {}
			var migration := _facts.latest_migration(region_id)
			if migration.is_empty(): return {}
			proof["migration"] = migration
			proof["species"] = migration.species
			proof["source"] = "EcologySim.instance_migrated"
		"random_camp":
			var camp := _camp_target(context)
			if camp.is_empty(): return {}
			proof.merge(camp,true)
		"random_runes":
			if objects.target.get("unsettled") != true or objects.record.get("readable") != true: return {}
	return {"object_ids":object_ids,"proof":proof}

func _position_allowed(position: Vector2, context: Dictionary) -> bool:
	var known: Variant = context.get("known_position")
	var route: Variant = context.get("route_exists")
	var origin: Variant = context.get("origin")
	if not origin is Vector2 or not position.is_finite() or origin.distance_to(position) > LOCAL_RADIUS: return false
	if not known is Callable or not known.is_valid() or not route is Callable or not route.is_valid(): return false
	return known.call(position) == true and route.call(origin,position) == true

static func capable(inst: MonsterInstance, stats: CharacterStats) -> bool:
	if stats == null or not inst.is_alive or inst.species.is_boss or inst.species.ambient: return false
	var band: Dictionary = CombatBandMath.TERRAIN_BANDS["plains"]
	for candidate_band: Dictionary in CombatBandMath.TERRAIN_BANDS.values():
		if int(candidate_band.expected) <= stats.level and int(candidate_band.expected) > int(band.expected): band = candidate_band
	var heavy := inst.species.defense_reduction >= CombatBandMath.HEAVY_DEF
	var kill_band: Array = band["kill_heavy" if heavy else "kill"]
	var pressure := CombatBandMath.attackers_of(inst.species)
	var minimum: float = CombatBandMath.HEAVY_DIE_FLOOR if heavy else band["die_pack" if pressure == 3 else "die_solo"]
	return CombatBandMath.hits_to_kill(inst,stats.physical_attack()) <= int(kill_band[1]) \
		and CombatBandMath.hits_to_die(inst,stats.max_hp(),pressure) >= minimum

func _context_stats(context: Dictionary) -> CharacterStats:
	var value: Variant = context.get("stats")
	return value if value is CharacterStats else null

func _nest_target(route_position: Vector2, context: Dictionary) -> Dictionary:
	var region_id := str(context.get("region_id",""))
	var region: SimRegion = _sim.regions.get(region_id)
	for key: String in _sim.nests:
		if key.get_slice("|",0) != region_id or _sim.nests[key].get("active") != true: continue
		var species := _sim.find_species(key.get_slice("|",1))
		if species == null or species.is_boss: continue
		var position := _sim.camp_pos(region,species)
		if position.distance_to(route_position) > NEST_ROUTE_RADIUS or not _position_allowed(position,context): continue
		var feasible := false
		for inst: MonsterInstance in _sim.instances.values():
			if inst.region_id == region_id and inst.species == species and capable(inst,_context_stats(context)): feasible = true
		if not feasible: continue
		return {"nest_key":key,"species":species.species_name,"source":"EcologySim.nests","state":"active"}
	return {}

func _current_position(inst: MonsterInstance, context: Dictionary) -> Vector2:
	var position_of: Variant = context.get("position_of")
	if position_of is Callable and position_of.is_valid():
		var result: Variant = position_of.call(inst)
		return result if result is Vector2 and result.is_finite() else Vector2.INF
	return inst.spawn_pos

func _camp_target(context: Dictionary) -> Dictionary:
	var grouped := {}
	var region_id := str(context.get("region_id",""))
	for inst: MonsterInstance in _sim.instances.values():
		if inst.region_id != region_id or not capable(inst,_context_stats(context)): continue
		if not _position_allowed(_current_position(inst,context),context): continue
		var name := inst.species.species_name
		if not grouped.has(name): grouped[name] = []
		if grouped[name].size() < 16: grouped[name].append(inst.id)
	for name: String in grouped:
		var ids: Array = grouped[name]
		var global_alive := _sim.alive_count_of_species(name)
		var local_alive := _sim.alive_count_in(region_id,_sim.find_species(name))
		var quota := mini(2,mini(local_alive-1,global_alive-EcologySim.ENDANGERED_THRESHOLD))
		quota = mini(quota,ids.size()-1)
		if quota < 1: continue
		return {"species":name,"target_ids":ids.duplicate(),"credited_ids":[],"deaths":[],"quota":quota,
			"global_alive":global_alive,"local_alive":local_alive,"source":"EcologySim.instances"}
	return {}

func accept(preview: Dictionary, context: Dictionary) -> bool:
	var template := str(preview.get("template_id",""))
	if not _available(template): return false
	var ordinal := int(_state.counts.get(template,0))
	var id := instance_id(template,_seed,ordinal)
	if preview.get("id") != id or preview.get("seed") != _seed or int(preview.get("version",0)) != VERSION: return false
	var fresh := _eligibility(template,id,context)
	if fresh.is_empty(): return false
	# A changed ecology target must be shown again, never silently substituted under an old button.
	var old_proof: Dictionary = preview.get("proof",{})
	for key: String in ["species","nest_key","target_ids","cost_item","cost_count","migration","region_id","origin"]:
		if old_proof.get(key) != fresh.proof.get(key): return false
	var row := {"id":id,"template_id":template,"seed":_seed,"ordinal":ordinal,"version":VERSION,
		"status":"active","issued_tick":_sim.tick_count,"closed_tick":0,"object_ids":fresh.object_ids,
		"proof":fresh.proof,"evidence":{},"outcome":""}
	_state.instances[id] = row
	_state.counts[template] = ordinal+1
	_state.active = id
	_state.last_issue_tick = _sim.tick_count
	changed.emit()
	return true

func _on_fact_changed() -> void:
	if _capture_credit(): _emit_changed()

func _emit_changed() -> void:
	if _notifying: return
	_notifying = true
	changed.emit()
	_notifying = false

func _capture_credit() -> bool:
	if _facts == null or _state.is_empty(): return false
	var row: Dictionary = _state.instances.get(str(_state.active),{})
	if row.is_empty() or row.template_id != "random_camp": return false
	var proof: Dictionary = row.proof
	var ids: Array = proof.get("target_ids",[])
	var changed_value := false
	if not proof.has("credited_ids"): proof.credited_ids = []
	if not proof.has("deaths"): proof.deaths = []
	for death: Dictionary in _facts.death_evidence(ids,int(row.issued_tick)):
		var seen := false
		for old: Dictionary in proof.deaths:
			if int(old.instance_id) == int(death.instance_id): seen = true
		if seen: continue
		proof.deaths.append(death)
		if _death_local(proof,death) and death.cause == EcologySim.DEATH_KILLED and death.from_region == str(proof.get("region_id","")) and not int(death.instance_id) in proof.credited_ids:
			proof.credited_ids.append(int(death.instance_id))
		changed_value = true
	return changed_value

func refresh_active(context: Dictionary) -> Dictionary:
	_capture_credit()
	var row := active()
	if row.is_empty() or _sim == null: return {}
	var result := {"id":row.id,"state":"available","tick":_sim.tick_count,"can_survey_close":false,
		"credited_ids":row.proof.get("credited_ids",[]).duplicate(),"proof":row.proof.duplicate(true)}
	# Author objects remain necessary for on-site actions even when the ecological target disappeared.
	for role: String in row.object_ids:
		if _probe(str(row.object_ids[role]),context).is_empty():
			result.state = "site_unavailable"
			return result
	match str(row.template_id):
		"random_nest":
			var key := str(row.proof.get("nest_key",""))
			if _sim.nests.get(key,{}).get("active") != true:
				result.state = "nest_inactive"
				result.can_survey_close = true
		"random_migration":
			var id := int(row.proof.get("migration",{}).get("instance_id",0))
			var inst: MonsterInstance = _sim.instances.get(id)
			result.state = "lost" if inst == null or not inst.is_alive else ("migrated" if inst.region_id != str(row.proof.region_id) else "present")
			result.can_survey_close = true
		"random_camp":
			var alive := 0
			var moved := 0
			for id: int in row.proof.get("target_ids",[]):
				var inst: MonsterInstance = _sim.instances.get(id)
				if inst == null or not inst.is_alive: continue
				if inst.region_id != str(row.proof.region_id) or not _position_allowed(_current_position(inst,context),context): moved += 1
				else: alive += 1
			var credited: Array = row.proof.get("credited_ids",[])
			var global_alive := _sim.alive_count_of_species(str(row.proof.species))
			var local_alive := _sim.alive_count_in(str(row.proof.region_id),_sim.find_species(str(row.proof.species)))
			if credited.size() >= int(row.proof.quota): result.state = "quota_met"
			elif global_alive <= EcologySim.ENDANGERED_THRESHOLD or local_alive <= 1:
				result.state = "population_protected"
				result.can_survey_close = true
			elif alive < int(row.proof.quota)-credited.size()+1:
				var only_natural := true
				var observed_deaths: Array = row.proof.get("deaths",[])
				if observed_deaths.is_empty(): only_natural = false
				for death: Dictionary in observed_deaths:
					if death.cause == EcologySim.DEATH_KILLED: only_natural = false
				result.state = "migrated" if moved > 0 else ("naturally_depleted" if only_natural else "targets_changed")
				result.can_survey_close = true
			result["global_alive"] = global_alive
			result["local_alive"] = local_alive
	return result

func record_action(role: String, action: String, context: Dictionary, choice := "") -> bool:
	var row: Dictionary = _state.instances.get(str(_state.active),{})
	if row.is_empty() or not row.object_ids.has(role) or action.is_empty(): return false
	var object := _probe(str(row.object_ids[role]),context)
	if object.is_empty() or object.get("at_player") != true: return false
	# Specific action semantics and inventory confirmation remain in CampaignQuest.
	if row.evidence.has(role): return false
	row.evidence[role] = {"object_id":row.object_ids[role],"tick":_sim.tick_count,"action":action,"choice":choice}
	changed.emit()
	return true

func complete(outcome: String, evidence: Dictionary = {}) -> bool:
	_capture_credit()
	var row: Dictionary = _state.instances.get(str(_state.active),{})
	if row.is_empty() or outcome.is_empty(): return false
	# The runtime supplies completed stage evidence; no ecology condition can auto-pay/auto-close.
	if evidence.get("validated") != true: return false
	row.status = "closed"
	row.outcome = outcome.left(160)
	row.closed_tick = _sim.tick_count
	_state.last_closed[str(row.template_id)] = _sim.tick_count
	_state.active = ""
	changed.emit()
	return true
