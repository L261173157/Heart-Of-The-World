## 新增驻守人的固定偏移也必须落在真实干燥可行走格；不只检查站点的铭牌。
extends SceneTree
const SITES := ["side_patrol:station_camp", "side_patrol:station_forest", "side_merchant:station_near", "side_merchant:station_outer", "side_watchman:watch_near", "side_watchman:watch_high"]
var checks := 0
var failures := 0
func _initialize() -> void:
	for seed_value: int in [BiomeMap.DEFAULT_SEED, 1, 42, 99, 20261004, 982451653, 2147483647]:
		BiomeMap.configure(seed_value)
		ObstacleField.restore_destroyed([])
		for id: String in SITES:
			var station := CampaignLayout.object_position(id)
			var resident := station + Vector2(64,0)
			_check(resident.is_finite() and not ObstacleField.blocks(resident, 12), "%d %s新增驻守人站位不撞墙" % [seed_value,id])
			_check(ObstacleField.liquid_kind_at(resident) == "", "%d %s新增驻守人站位无深水/熔岩" % [seed_value,id])
			var connected := true
			for i in range(9):
				if ObstacleField.nav_blocked_at(station.lerp(resident, float(i)/8.0)): connected = false
			_check(connected, "%d %s铭牌与服务人之间真实可达" % [seed_value,id])
	if failures == 0: print("=== CAMPAIGN OPTIONAL PLACEMENTS PASS (%d checks, 7 seeds) ===" % checks)
	quit(0 if failures == 0 else 1)
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("OPTIONAL PLACEMENT FAIL " + label)
