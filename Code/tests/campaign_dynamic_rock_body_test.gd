## Actual ObstacleTileLayer collision and CharacterBody2D sweeps; no simulated collision replacement.
extends Node
var checks:=0
var failures:=0
var terrain: ObstacleTileLayer
var body: CharacterBody2D
func _ready() -> void:
	GameState.save_enabled=false
	_run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("ROCK BODY FAIL: "+label)
func frames(n:=2) -> void:
	for i in n: await get_tree().physics_frame
func clear_line(from: Vector2,to: Vector2) -> bool:
	var count:=maxi(1,ceili(from.distance_to(to)/8.0))
	for i in count+1:
		if ObstacleField.nav_blocked_at(from.lerp(to,float(i)/count)): return false
	return true
func _run() -> void:
	for seed_value: int in [20260908,1,2,42,734,12345,987654]:
		GameState.world_seed=seed_value
		BiomeMap.configure(seed_value)
		ObstacleField.restore_destroyed([])
		terrain=ObstacleTileLayer.new()
		add_child(terrain)
		body=CharacterBody2D.new()
		body.motion_mode=CharacterBody2D.MOTION_MODE_FLOATING
		body.collision_layer=2
		body.collision_mask=1
		body.safe_margin=0.5
		var collision:=CollisionShape2D.new()
		var shape:=RectangleShape2D.new()
		shape.size=Vector2(20,20)
		collision.shape=shape
		body.add_child(collision)
		add_child(body)
		var used: Dictionary={}
		for ordinal in 3:
			var id:="random_rocks:%d:%d"%[seed_value,ordinal]
			var from:=CampaignLayout.object_position(id+":target")
			var to:=CampaignLayout.object_position(id+":return")
			var center:=(from+to)/2
			var cells:=CampaignLayout.barrier_cells(id+":barrier")
			for cell: Vector2i in cells:
				check(not used.has(cell),"seed%d ordinal%d owns distinct rock cells"%[seed_value,ordinal])
				used[cell]=true
			var chunk:=Vector2i(floori(center.x/512),floori(center.y/512))*512
			for y in range(-1,2):
				for x in range(-1,2): terrain._on_chunk_ready(chunk+Vector2i(x,y)*512)
			while not terrain._lay_queue.is_empty(): terrain._process(0)
			await frames()
			check(not clear_line(from,to),"own unbroken rocks block direct route seed%d ordinal%d"%[seed_value,ordinal])
			body.position=from
			var hit:=body.move_and_collide(to-from)
			check(hit!=null and body.position.distance_to(to)>128,"actual player-sized body collides with unbroken gap seed%d ordinal%d"%[seed_value,ordinal])
			body.position=from
			var detour: Array[Vector2]=[from+Vector2(0,-288),to+Vector2(0,-288),to]
			var open:=true
			for point: Vector2 in detour:
				if body.move_and_collide(point-body.position)!=null: open=false
			check(open and body.position.distance_to(to)<1,"actual longer outer route reaches both ends before break seed%d ordinal%d"%[seed_value,ordinal])
			for cell: Vector2i in cells:
				for hit_index in 4:
					var kind:=ObstacleField.damage_cell(cell)
					if not kind.is_empty(): EventBus.obstacle_destroyed.emit(cell,(Vector2(cell)+Vector2(0.5,0.5))*32,kind)
			await frames()
			check(clear_line(from,to),"only this instance's real destruction opens direct navigation seed%d ordinal%d"%[seed_value,ordinal])
			body.position=from
			hit=body.move_and_collide(to-from)
			check(hit==null and body.position.distance_to(to)<1,"actual body passes through destroyed registered gap seed%d ordinal%d"%[seed_value,ordinal])
			for other in range(ordinal+1,3):
				var other_id:="random_rocks:%d:%d"%[seed_value,other]
				check(not clear_line(CampaignLayout.object_position(other_id+":target"),CampaignLayout.object_position(other_id+":return")),"breaking one instance never opens a neighboring ordinal")
			print("ROCK_BODY seed=",seed_value," ordinal=",ordinal," direct=",from.distance_to(to)," detour=",from.distance_to(to)+576," before=blocked after=traversed")
		body.free()
		terrain.free()
		await frames()
	print("CAMPAIGN_DYNAMIC_ROCK_BODY_TEST %s checks=%d failures=%d"%["PASS" if failures==0 else "FAIL",checks,failures])
	get_tree().quit(0 if failures==0 else 1)
