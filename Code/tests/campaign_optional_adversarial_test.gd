extends "res://tests/campaign_optional_outcomes_test.gd"
var review_checks := 0
func _run() -> void:
	OS.set_environment("HOTW_OUTCOME_SEED", "99")
	await super._run()
	_check(review_checks == 13, "thirteen independent negative controls actually executed")
	if _fails == 0: print("=== CAMPAIGN OPTIONAL ADVERSARIAL PASS (%d checks) ===" % _checks)
	get_tree().quit(0 if _fails == 0 else 1)
func _negative(ok: bool, label: String) -> void:
	review_checks += 1
	_check(ok, "INDEPENDENT NEGATIVE " + label)
func _capture_snapshot(stage_id: String, branch_set: int, suffix := "stage") -> void:
	if stage_id == "region_forest:s1" and suffix=="stage": _forest_negatives()
	if stage_id == "region_plains:s3" and branch_set==1 and suffix=="stage": _shared_service_negatives()
	if suffix=="service" and stage_id=="region_plains:s3": print("INDEPENDENT OPTIONAL NEGATIVES checks=",review_checks)
func _forest_negatives() -> void:
	var q := GameState.campaign_quest.duplicate(true)
	var before_pos := _player.position
	var last_pos := _optional._last_player_position
	var binding: Dictionary=q.optional_bindings.region_forest
	var key: String=binding.target_key
	var sight := _optional._position("region_forest:survey_a")
	_negative(not _optional._choose_local_target("region_forest:survey_a",true).is_empty(),"baseline actual existing local target selectable")
	var nest: NestNode=nests[0]
	nest.visible=false
	_negative(_optional._choose_local_target("region_forest:survey_a",true).is_empty(),"hidden real nest cannot authorize near branch")
	_negative(_optional._nearby_nests(sight).is_empty(),"hidden real nest cannot become an observation")
	nest.visible=true
	var pos:=nest.position
	nest.position+=Vector2(4000,0)
	_negative(_optional._choose_local_target("region_forest:survey_a",true).is_empty(),"current nest position overrides historical camp coordinates")
	nest.position=pos
	for actor: MonsterBase in actors: actor.visible=false
	_negative(_optional._choose_local_target("region_forest:survey_a",true).is_empty(),"hidden living actors cannot authorize hunt or ransack branch")
	for actor: MonsterBase in actors: actor.visible=true
	var bound_before:=binding.duplicate(true)
	_optional._bind_forest_markers()
	_negative(GameState.campaign_quest.optional_bindings.region_forest==bound_before,"repeated clue binding cannot reroll object or route positions")
	_player.position=_optional._position("region_forest:choice")
	_optional.accept_stage("region_forest:s2","region_forest:choice")
	_optional.perform_action("region_forest:s2:choice","near")
	_negative(_optional._saved_target("region_forest").get("target_key","")==key,"physical current choice pins original target identity")
	var accepted:=JSON.stringify(GameState.campaign_quest)
	_player.position=CampaignLayout.object_position("region_forest:choice")
	_optional.perform_action("region_forest:s2:work")
	_negative(JSON.stringify(GameState.campaign_quest)==accepted,"unbound old object location cannot complete newly bound work")
	_player.position=_optional._position("region_forest:work_near")
	EventBus.nest_ransacked_at.emit(key.get_slice("|",1),key.get_slice("|",0),nest.position)
	_optional.perform_action("region_forest:s2:work")
	_negative(not Data.ready(GameState.campaign_quest,"region_forest:s2"),"forged event at real active nest does not complete work")
	_negative(not GameState.campaign_quest.get("optional_targets",{}).get("region_forest",{}).get("ransack",false),"forged event does not create persistent credit")
	GameState.campaign_quest=q
	_player.position=before_pos
	_optional._last_player_position=last_pos
	_refresh()
func _shared_service_negatives() -> void:
	var q:=GameState.campaign_quest.duplicate(true)
	var inv:=GameState.inventory.duplicate(true)
	var pos:=_player.position
	var saved_pending := GameState.pending_items.duplicate(true)
	var pending_before := _pending_total("onigiri")
	var endpoints: Array[String]=["region_plains:work_outer","region_plains:station"]
	GameState.inventory["onigiri"]=99
	for id: String in endpoints:
		_player.position=_optional._position(id)
		_optional.claim_service(id)
	_negative(GameState.inventory.onigiri==99 and Data.service_claimed(GameState.campaign_quest,"region_plains_station") and _pending_total("onigiri")==pending_before+1 and _pending_sources_unique(),"both full99 endpoints settle exactly one shared stock into a unique pending receipt")
	GameState.inventory["onigiri"]=98
	_check(_claim_one_pending("onigiri") and _pending_total("onigiri")==pending_before,"claim one owned overflow item without reopening either service")
	for id: String in endpoints:
		_player.position=_optional._position(id)
		_optional.claim_service(id)
	_negative(GameState.inventory.onigiri==99 and Data.service_claimed(GameState.campaign_quest,"region_plains_station"),"two different reachable endpoints cannot dispense twice")
	GameState.campaign_quest=Data.sanitize(GameState.campaign_quest,GameState.world_seed)
	for id: String in endpoints:
		_player.position=_optional._position(id)
		_optional.claim_service(id)
	_negative(GameState.inventory.onigiri==99,"cold ledger restore cannot reopen either shared endpoint")
	GameState.campaign_quest=q
	GameState.inventory=inv
	GameState.pending_items=saved_pending
	_player.position=pos
	_refresh()
