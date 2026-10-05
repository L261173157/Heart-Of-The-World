## 正式 CampaignQuest 路由与真实奖励事务的补充测试；仅覆盖批次闸门使用显式夹具。
extends Node
const Data := preload("res://scripts/main/campaign_quest_data.gd")
class EnabledHost extends CampaignQuest:
	func _chapter_enabled(chapter: Dictionary) -> bool: return not chapter.is_empty()
	func visual_state() -> Dictionary:
		var value := super.visual_state()
		value.enabled_batch=4
		return value
var host: EnabledHost
var world: CampaignWorld
var player: CharacterBody2D
var checks:=0
var failures:=0
func _ready() -> void:
	GameState.save_enabled=false
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("DYNAMIC HOST FAIL: "+message)
func frame() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
func go(id: String) -> void:
	world.refresh_state(host.visual_state())
	var node:=world.object_node(id)
	player.position=node.position+Vector2(0,40)
	GameState.fog_reveal_position(player.position)
	await frame()
	host._dynamic._discover()
	check(node.can_interact(),"actual object can interact "+id)
func _run() -> void:
	BiomeMap.configure(GameState.world_seed)
	GameState.campaign_quest=Data.create(GameState.world_seed)
	GameState.gold=0
	var evidence: Dictionary={}
	for id: String in Data.Outpost.EVIDENCE: evidence[id]=true
	Data.authorize_chapter1(GameState.campaign_quest,{"id":"lost_outpost_v1","evidence":evidence,"outcome":"survey","survey_confirmed":true})
	var region:=SimRegion.new()
	region.id=BiomeMap.region_id_at(CampaignLayout.object_position("random_wounded:"+str(GameState.world_seed)+":0:giver"))
	region.center=WorldConfig.spawn_pos()
	region.size=Vector2(100000,100000)
	region.capacity=100
	var species:=SpeciesData.new()
	species.species_name="host_fixture"
	species.breeding_rate=0
	species.migrate_count=0
	var sim:=EcologySim.new()
	var list: Array[SpeciesData]=[species]
	sim.setup([region],list,{region.id:{"host_fixture":8}})
	WorldSim.sim=sim
	world=CampaignWorld.new()
	add_child(world)
	player=CharacterBody2D.new()
	player.add_to_group("player")
	add_child(player)
	host=EnabledHost.new()
	add_child(host)
	await frame()
	host._dynamic.set_physics_process(false)
	check(host._dynamic.facts.snapshot().events.is_empty(),"formal host configures facts after actual sim setup")
	var id:="random_wounded:"+str(GameState.world_seed)+":0"
	host._dynamic._exposed[id]=true
	for role: String in ["giver","parts","target"]: await go(id+":"+role)
	await go(id+":giver")
	host.perform_action(id+":request")
	check(GameState.campaign_quest.quests.is_empty(),"generic action cannot bypass random acceptance")
	var offer:=host.object_payload(id+":giver")
	check(offer.get("kind","")=="camp_action","formal host routes random object to on-site preview")
	host.action(str(offer.get("action","")))
	check(GameState.campaign_quest.active_random==id and host._dynamic.encounters.active().id==id,"formal host accepts one canonical contract through action dispatcher")
	host.abandon(id)
	host.perform_action(id+":request")
	check(not GameState.campaign_quest.quests[id].evidence.has(id+":request"),"abandon pauses generic direct-action route without removing instance")
	host.action("campaign|dynamic|resume|random_wounded|"+id+":giver")
	for role: String in ["giver","parts","target"]:
		await go(id+":"+role)
		var payload:=host.object_payload(id+":"+role)
		check(payload.get("kind","")=="camp_action","formal host offers authored role "+role)
		host.action(str(payload.get("action","")))
	check(Data.ready(GameState.campaign_quest,id) and Data.paid(GameState.campaign_quest,id),"formal host pays real finite random receipt")
	var gold:=GameState.gold
	check(gold>0 and int(GameState.campaign_quest.quests[id].receipt.gold)==gold,"receipt records the real gold transaction")
	check(host._dynamic.encounters.active().is_empty(),"formal settlement closes engine instance")
	host.perform_action(id+":rescue")
	host.claim(id)
	check(GameState.gold==gold,"direct action and repeated claim cannot duplicate payment")
	var q:=Data.sanitize(JSON.parse_string(JSON.stringify(GameState.campaign_quest)),GameState.world_seed)
	check(Data.ready(q,id) and Data.paid(q,id) and int(q.quests[id].receipt.gold)==gold,"cold ledger preserves exact real payment")
	await actual_patrol_gate()
	print("CAMPAIGN_DYNAMIC_HOST_TEST %s checks=%d failures=%d"%["PASS" if failures==0 else "FAIL",checks,failures])
	get_tree().quit(0 if failures==0 else 1)


func actual_patrol_gate() -> void:
	player.remove_from_group("player")
	var live:=preload("res://scenes/player/player.tscn").instantiate() as Player
	add_child(live)
	live.set_physics_process(false)
	live.set_process(false)
	(live.get_node("Camera2D") as Camera2D).enabled=false
	var patrol:=preload("res://scripts/main/game_world.gd").LandmarkNPC.new()
	patrol.kind="石环"
	patrol.giver="营地巡守"
	patrol.landmark_id="camp_ecology"
	patrol.quest_kind="outpost"
	var old_anchor:=WorldConfig.spawn_pos()+Vector2(-100,75)
	patrol.position=old_anchor+Vector2(256,0)
	add_child(patrol)
	patrol.set_process(false)
	live.position=patrol.position+Vector2(80,0)
	await frame()
	check(host._dynamic._at_departure("home:patrol"),"dynamic home gate follows the actual moved patrol, not the static spawn anchor")
	live.position=old_anchor
	await frame()
	check(not host._dynamic._at_departure("home:patrol"),"stale static-anchor proximity cannot authorize a home expedition")
	live.position=patrol.position+Vector2(80,0)
	var wall:=StaticBody2D.new()
	wall.position=patrol.position+Vector2(40,0)
	wall.collision_layer=1
	var collision:=CollisionShape2D.new()
	var shape:=RectangleShape2D.new()
	shape.size=Vector2(12,80)
	collision.shape=shape
	wall.add_child(collision)
	add_child(wall)
	await frame()
	check(not host._dynamic._at_departure("home:patrol"),"real physical wall blocks patrol authorization despite close distance")
	wall.queue_free()
	await frame()
	live._is_dead=true
	check(not host._dynamic._at_departure("home:patrol"),"dead player cannot authorize home departure")
	live._is_dead=false
	patrol.visible=false
	check(not host._dynamic._at_departure("home:patrol"),"hidden patrol cannot authorize a home expedition")
	patrol.visible=true
	check(host._dynamic._at_departure("home:patrol"),"actual visible patrol is available again after the verified blocker clears")

	var target:="random_wounded:"+str(GameState.world_seed)+":0:target"
	live.position=world.object_node(target).position+Vector2(0,40)
	await frame()
	check(host._dynamic._at(target),"living actual Player can still interact with the registered campaign object")
	live._is_dead=true
	check(not host._dynamic._at(target),"old campaign-object dialogues cannot act through a dead Player")
	live._is_dead=false
