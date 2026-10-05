## 《断开的守望》作者内容目录。ID 是存档合同，不随显示名或接单次数重写。
## 第一章继续由 OutpostQuestData 持有；这里不复制它的证据或39/44旧预算。
class_name CampaignCatalog
extends RefCounted

const ID := "campaign_watch_v1"
const VERSION := 1
const RANDOM_LIMIT := 30
const RANDOM_PER_TEMPLATE := 3
static var _groups: Dictionary = {}
static var _stages: Dictionary = {}
static var _stage_maps: Dictionary = {}
static var _action_maps: Dictionary = {}

static func main_chapters() -> Array:
	if not _groups.has("main_chapters"): _groups["main_chapters"] = _seal(_main_chapters())
	return _groups["main_chapters"]

static func _main_chapters() -> Array:
	return [
		_chapter("watch_c2_forest", "林间旧约", "forest", 2, [
			_step("古树下的旧约", "询问林地药师，再亲自读完古树下的旧约。", [
				_action("herbalist", "c2:herbalist", "林地药师", "talk", "询问旧哨所", "药师把一页叶脉拓本交给你：林下三枚符标仍沿用旧约的次序，先去古树寻找原文。"),
				_action("old_pact", "c2:old_pact", "古树下的旧约", "read", "读旧约", "旧约记着人类曾为巡林者保留过林下通路。文字没有许诺安全，只留下三枚符标与失散联络员的名字。", ["herbalist"])]),
			_step("林下通道", "读出北、东、西的符标次序，开启栅门后步行取回残页。", [
				_action("route_marks", "c2:route_marks", "旧路标刻痕", "read", "辨读刻痕", "刻痕由晨露、日影与归鸟串起：先北，再东，最后西。按错只会熄灭已亮的符标，可以重新尝试。"),
				_action("runes", "c2:forest_gate", "三枚林下符标", "puzzle", "核对符标", "三枚符标依次亮起，旧栅门的锁舌松开。残页仍在门后，需要你亲自走过去。", ["route_marks"], {"puzzle_order": ["north", "east", "west"], "puzzle_objects": ["c2:rune_north", "c2:rune_east", "c2:rune_west"], "opens": "c2:forest_gate"}),
				_action("torn_record", "c2:torn_record", "被撕开的守望记录", "recover", "拾起残页", "残页上的信号图并不完整。末行写着：联络员仍守着东侧歇脚处，补给没有送到。", ["runes"])]),
			_step("留在林地的人", "找到失联联络员，取回专用急救包，再回到他身边救治。", [
				_action("liaison", "c2:liaison", "负伤联络员", "talk", "查看伤势", "联络员无法继续行走。他指出树根后的封存急救箱，并请你把信号重新送上山脊。"),
				_action("aid_cache", "c2:aid_cache", "联络站急救箱", "recover", "取专用急救包", "你取出联络站封存的急救包。它只用于这次救援，不占背包，也不会被快捷补给消耗。", ["liaison"], {"quest_item": "c2:aid"}),
				_action("rescue", "c2:liaison", "负伤联络员", "rescue", "为联络员包扎", "你在联络员身旁完成包扎。他能留守联络站了，但仍不能代替你去修复烽灯。", ["aid_cache"])]),
			_step("第一束信号", "回收信号零件，在烽灯处亲手恢复第一束信号。", [
				_action("signal_parts", "c2:signal_parts", "封存的信号零件", "recover", "回收零件", "木匣内保留着遮光片与旧灯芯。零件齐了，灯塔还需要现场装配。", [], {"quest_item": "c2:signal_parts"}),
				_action("beacon", "c2:beacon", "林地烽灯", "repair", "修复烽灯", "林地烽灯重新亮起。联络员留下值守，证实远征队曾分赴沼泽与丘陵，并交给你沼泽接应点的旧坐标；灯亮不代表林路已经安全。", ["signal_parts"], {"service": "forest_station", "next_chapter": "watch_c3_swamp"})])]),
		_chapter("watch_c3_swamp", "沼泽双途", "swamp", 3, [
			_step("漂来的行囊", "对照沉睡图腾与枯木灵龛上的记号，寻找漂来的远征行囊。", [
				_action("totem", "c3:totem_record", "沉睡图腾旁的绳结", "read", "辨认绳结", "绳结被水浸过，打结法却与前哨记录一致。它指向枯木灵龛旁搁浅的旧行囊。"),
				_action("shrine", "c3:shrine_record", "灵龛上的留字", "read", "读留字", "木片写着：近路曾经可走，外缘曾有接应。两句话都没有日期，不能代替眼前的调查。", ["totem"]),
				_action("satchel", "c3:satchel", "远征队行囊", "recover", "回收行囊", "你取出防水封套。里面是两份互相矛盾的路书与一封没有寄出的回信。", ["shrine"], {"quest_item": "c3:satchel_record"})]),
			_step("两份路书", "读旧路书，分别到近路与外缘核对眼前通路和族群。", [
				_action("old_route", "c3:old_route", "浸水路书", "read", "读两份路书", "一份路书沿浅滩直切，另一份绕过枯木外缘。记录只代表那次远征，今天的障碍与怪物仍要分别查看。"),
				_action("route_near", "c3:route_near", "浅滩近路勘察点", "observe", "勘察近路", "你记下浅滩近路现在的通行条件和可见活动，保留眼前事实，没有把旧猎数当成现在的存量。", ["old_route"]),
				_action("route_outer", "c3:route_outer", "枯木外缘勘察点", "observe", "勘察外缘", "外缘距离更长，转折也更多。你把当前观察与近路记录并列，接下来由你选择接近方式。", ["old_route"])]),
			_step("接应点", "明确选择一条已勘察路线，亲自走到幸存者身边并完成接应。", [
				_action("route_choice", "c3:route_choice", "接应路线图", "choice", "选择路线", "近路较短，外缘绕行较长。两条路线都只能依据已勘察的现状选择，不保证永久安全。", [], {"choices": [{"id": "near", "title": "走浅滩近路"}, {"id": "outer", "title": "绕枯木外缘"}]}),
				_action("reach", "c3:survivor", "沼泽幸存者", "route", "确认已到接应点", "你沿选定线路到达接应点。幸存者认出行囊封套，请你取来留在一旁的急救物资。", ["route_choice"], {"routes": ["near", "outer"], "route_by_choice": {"near": ["c3:route_near", "c3:survivor"], "outer": ["c3:route_outer", "c3:survivor"]}}),
				_action("aid", "c3:aid_cache", "接应点急救物资", "recover", "取接应物资", "接应物资仍封在油布里，足够完成这次救助。它不进入交易背包。", ["reach"], {"quest_item": "c3:aid"}),
				_action("rescue", "c3:survivor", "沼泽幸存者", "rescue", "完成现场接应", "你把物资交到幸存者手中并处理伤处。接应点恢复了留驻人员，先前穿过的道路并未自动整修。", ["aid"])]),
			_step("未完成的回信", "核实行囊来历，取得回信中的丘陵线索，恢复沼泽联络。", [
				_action("account", "c3:survivor", "沼泽幸存者", "talk", "核实行囊来历", "幸存者承认两份路书来自两次不同撤离。远征队没有全员失踪，有人转往丘陵档案接近区。"),
				_action("reply", "c3:reply_record", "未完成的回信", "recover", "收起回信", "回信留下丘陵学者的名字与绞盘构造草图。你带走的是原件，没人替远征队补写结局。", ["account"], {"quest_item": "c3:reply"}),
				_action("beacon", "c3:beacon", "沼泽联络灯", "repair", "接通联络灯", "接应点的联络灯亮起。幸存者愿意留守，你获得前往丘陵接近点的路线资格。", ["reply"], {"service": "swamp_station", "next_chapter": "watch_c4_hill"})])]),
		_chapter("watch_c4_hill", "丘陵封关", "hill", 4, [
			_step("封门者的名册", "找到遗迹学者，核对旧名册里真正负责封存档案的人。", [
				_action("scholar", "c4:scholar", "丘陵遗迹学者", "talk", "询问封门者", "学者说城塞南门一直存在通路；被封起来的是后来加设的档案接近区。封门者留下了名册。"),
				_action("roster", "c4:roster", "封存名册", "read", "核对名册", "名册上有沼泽回信的署名，也有一位地图保管员。档案不是战利品，银钥匙开不了这道新栅门。", ["scholar"])]),
			_step("断开的绞盘", "回收绞盘零件，在原位装好绞盘，打开档案区局部门。", [
				_action("parts", "c4:winch_parts", "散落的绞盘零件", "recover", "回收绞盘零件", "齿轮与轴销被分开收存，部件齐全后才能重新拉起档案区栅门。", [], {"quest_item": "c4:winch_parts"}),
				_action("winch", "c4:winch", "断开的绞盘", "repair", "安装并拉动绞盘", "绞盘咬合，新增档案栅门被拉起。原有城塞南门和循环宝箱仍按原来的规则使用。", ["parts"], {"opens": "c4:archive_gate"})]),
			_step("牛头王的城塞", "实地核对牛头王，战斗、局部绕行或空城调查后亲取档案。", [
				_action("fortress", "c4:fortress_record", "城塞值守记录", "read", "核对城塞现状", "档案位于旧城塞附近。先核对牛头王当前是否在场：战胜它、完成环境绕行，或在确无目标时据实调查，都不能互相冒认。"),
				_action("passage", "c4:bypass_control", "档案区接近机关", "encounter", "确认接近方式", "你将接近档案区的实际经过写入记录。绕行不记讨伐，空城不记击杀；存在的Boss仍按自己的生态规则活动。", ["fortress"], {"boss_species": "牛头王", "choices": ["defeated", "bypass", "absent"], "opens": "c4:archive_gate"}),
				_action("archive", "c4:archive", "丘陵远征档案", "recover", "取出远征档案", "档案记载了第二次分队：有人留下维护通路，有人带着总图进入雪原。你从档案台取走原件。", ["passage"], {"quest_item": "c4:archive"})]),
			_step("第二次分队", "帮助地图保管员，取雪原坐标并恢复丘陵信标。", [
				_action("keeper", "c4:map_keeper", "地图保管员", "talk", "扶起地图保管员", "你扶起困在散页间的保管员，替他收拢身旁地图。他没有受伤用药的要求，只请你把下一程坐标带出去。"),
				_action("coordinates", "c4:snow_coordinates", "雪原坐标页", "recover", "取雪原坐标", "地图标出冰封祭坛旁的接近点，队长最后一次回信来自那里。旧坐标不证明他现在仍在那里。", ["keeper"], {"quest_item": "c4:snow_coordinates"}),
				_action("beacon", "c4:beacon", "丘陵信标", "repair", "恢复丘陵信标", "信标恢复联络。地图保管员守住新增接应点，雪原远征线路已可明确选择。", ["coordinates"], {"service": "hill_station", "next_chapter": "watch_c5_snow"})])]),
		_chapter("watch_c5_snow", "雪原回声", "snow", 5, [
			_step("冰封祭坛", "读祭坛留字，真正打碎登记冰障，再取出冰后的铭片。", [
				_action("altar", "c5:altar_record", "祭坛留字", "read", "读祭坛留字", "留字说明铭片被藏在薄冰后，而不是冻在不可破坏的祭坛墙里。先找到登记的薄冰障碍。"),
				_action("ice", "c5:ice_barrier", "铭片前的薄冰障", "obstacle", "核验冰障已破", "你打碎真实冰障，通向铭片的接近路径出现了缺口。记录只属于这块登记冰障。", ["altar"]),
				_action("tablet", "c5:tablet", "雪下守望铭片", "recover", "拾取铭片", "铭片背面刻着队长的接应标记，指向避风处。雪原没有等待你讨伐的故事Boss。", ["ice"], {"quest_item": "c5:tablet"})]),
			_step("雪下的守望", "找到队长，回收专用急救箱，回到身旁明确救助。", [
				_action("leader", "c5:leader", "远征队长", "talk", "检查队长状况", "队长把自己留在最后一个接应点。他指向隔着冰脊保存的急救箱，暂时无力解释两本日志的矛盾。"),
				_action("aid", "c5:aid_cache", "远征急救箱", "recover", "取远征药包", "你从封存箱取出专用药包。它只属于队长的救援，不会扣掉背包里设为快捷补给的药。", ["leader"], {"quest_item": "c5:aid"}),
				_action("rescue", "c5:leader", "远征队长", "rescue", "救助队长", "完成包扎后，队长能继续留在站点。他承认撤守是一次有意的选择，却并没有预料之后的失联。", ["aid"])]),
			_step("相互矛盾的日志", "实读撤守日志与路线日志，将分队、撤守、失联按因果排列。", [
				_action("withdrawal", "c5:withdrawal_log", "撤守日志", "read", "读撤守日志", "撤守日志：分队以后，各处仍尝试维持旧节点；直到无法兼顾，队长才签下撤守令。"),
				_action("route_log", "c5:route_log", "路线日志", "read", "读路线日志", "路线日志：撤守令之后，联络设备逐一失效。正确顺序是先分队，再撤守，最后失联，不是失联迫使所有人同时逃离。"),
				_action("causality", "c5:evidence_board", "远征证据板", "puzzle", "排列因果记录", "你把两本日志与丘陵档案排在一起：分队、撤守、失联。矛盾来自记录时间不同，没有被你改写为某人的背叛。", ["withdrawal", "route_log"], {"puzzle_order": ["split", "withdrawal", "lost"]})]),
			_step("最后的坐标", "听队长说明两种派驻方案，亲取熔岩坐标并恢复雪原信标。", [
				_action("plans", "c5:leader", "远征队长", "talk", "听取派驻方案", "队长提出两条路：把新增巡守分散到已修复节点，或把新增幸存者集中安置。世界之心是联络装置，不能使怪物复活，也不能替人维持所有据点。\n出发建议：Lv6或等效构筑，先回营强化并备足补给。只赶主线可能仍为Lv3；活体龟王必须真正战胜。"),
				_action("coordinates", "c5:lava_coordinates", "最后的坐标页", "recover", "收好熔岩坐标", "坐标页给出熔岩城塞外的安全接近点。核心的旧操作口诀写着：西侧撤守，东侧接应，中央信号。", ["plans"], {"quest_item": "c5:lava_coordinates"}),
				_action("beacon", "c5:beacon", "雪原回声信标", "repair", "接通雪原信标", "雪原信标回应了来路。队长留守新增休整点，你获得熔岩接近点的远征资格。", ["coordinates"], {"service": "snow_station", "next_chapter": "watch_c6_lava"})])]),
		_chapter("watch_c6_lava", "熔火之心", "lava", 6, [
			_step("熔河之间", "阅读灼热边界记录，亲自沿接近路线抵达城塞外围。", [
				_action("hazard", "c6:hazard_record", "熔河边界记录", "read", "了解灼热边界", "熔岩可踏入，但会持续灼烧。竹水壶只能补蓝，不能让人免疫熔岩。接近线沿石脊绕过可见熔流。"),
				_action("approach", "c6:route_approach", "城塞接近石脊", "observe", "确认抵达石脊", "你亲自到达城塞外的石脊，把眼前可走的边缘写入记录。坐标没有把你直接送到龟王身边。", ["hazard"])]),
			_step("龟王盘踞之地", "核对熔岩龟王的真实状态，战胜在场龟王或核实空场后取得核心记录。", [
				_action("fortress", "c6:fortress_record", "中枢外围记录", "read", "核对龟王现状", "熔岩龟王仍属于原城塞。核心记录另存于新增接近区，不要求金钥匙，也不要求等待Boss复生。"),
				_action("passage", "c6:bypass_control", "中枢安全锁", "encounter", "确认中枢通路", "你记录了真实战斗或核实后的空场调查。只有亲自造成的Boss死亡才计为讨伐；通路的完成不会消灭未来的复生。", ["fortress"], {"boss_species": "熔岩龟王", "choices": ["defeated", "absent"], "opens": "c6:core_gate"}),
				_action("core_record", "c6:core_record", "世界之心操作记录", "recover", "取核心记录", "操作图重申：先西侧撤守，再东侧接应，最后中央信号。沿途实物记录已经解释了这个次序。", ["passage"], {"quest_item": "c6:core_record"})]),
			_step("世界之心", "按西、东、中顺序操作中枢，再亲自启动联络装置。", [
				_action("core_order", "c6:heart", "世界之心中枢", "puzzle", "核对中枢次序", "西侧的撤守铭牌亮起，东侧接应纹路接通，最后是中央信号。中枢获得了启动条件，还需要你明确启动。", [], {"puzzle_order": ["west", "east", "center"], "puzzle_objects": ["c6:core_west", "c6:core_east", "c6:core_center"]}),
				_action("activate", "c6:heart", "世界之心", "repair", "启动世界之心", "古老中枢重新连通已经修复的节点。它恢复的是联络能力，野外种群、巢穴和迁徙仍然按真实世界运行。", ["core_order"], {"service": "heart_station"})]),
			_step("此后的道路", "明确决定新增人员的派驻方式，在中枢旁落实这份安排。", [
				_action("ending", "c6:ending_council", "派驻议事台", "choice", "决定此后的道路", "分散派驻让新增巡守留在已修复节点；集中安置让新增幸存者聚在一个避难据点。既有检查点、回城和前哨巡守都继续保留。", [], {"choices": [{"id": "distributed", "title": "分散派驻"}, {"id": "centralized", "title": "集中安置"}]}),
				_action("settle", "c6:beacon", "最终派驻名册", "repair", "落实派驻安排", "你把选定方案记入最终名册。后记只列出真正完成的救援、修复和支线；未走过的路仍留白。", ["ending"], {"service": "ending_station", "ending": true})])]),

	]

static func side_chains() -> Array:
	if not _groups.has("side_chains"): _groups["side_chains"] = _seal(_side_chains())
	return _groups["side_chains"]

static func _side_chains() -> Array:
	return [

		_chain("side_patrol", "旧巡逻队", "plains", "side", 1, [
			_step("旧巡逻队的徽记", "询问接替者，读巡逻名册，在旧歇脚处回收身份徽记。", [
				_action("request", "side_patrol:giver", "新巡守", "talk", "听巡守的请求", "新巡守想知道前任的姓名，而不是继承一个空缺。旧队的徽记留在歇脚处，请先核对名册。"),
				_action("record", "side_patrol:record", "旧巡逻名册", "read", "核对姓名", "名册注明徽记属于主动留下接应的一组人。名单不是死亡证明。", ["request"]),
				_action("badge", "side_patrol:target", "遗留的身份徽记", "recover", "回收徽记", "徽记背面的刻字与名册一致。你把原件交给了接替者，旧巡逻不再只是一个编号。", ["record"], {"quest_item": "side_patrol:badge"})]),
			_step("新巡守的归处", "选择新增巡守驻地，亲自在选定站点安放徽记。", [
				_action("station", "side_patrol:resolution", "巡守驻地名册", "choice", "选择巡守驻地", "可以让新增巡守驻在营地接应新来者，或驻在林地协助联络。第一章的巡守仍守着原前哨。", [], {"choices": [{"id": "camp", "title": "营地接应"}, {"id": "forest", "title": "林地联络"}]}),
				_action("settle", "side_patrol:station_camp", "营地驻守点", "repair", "安放徽记并驻守", "徽记被挂在选定的新增驻守点。新的巡守与一次补给在这里提供服务。", ["station"], {"destination_by_choice": {"camp": "side_patrol:station_camp", "forest": "side_patrol:station_forest"}, "service": "patrol_station"})])]),
		_chain("side_herbalist", "一份两用的药", "forest", "side", 2, [
			_step("学徒留下的记录", "听草药师说明失散学徒的去向，取回实际药物用途记录。", [
				_action("request", "side_herbalist:giver", "草药师", "talk", "询问学徒", "草药师没有请你漫无目的采药。他只想找回学徒留下的用途记录，确认封存药物该送到哪里。"),
				_action("record", "side_herbalist:record", "学徒用途记录", "read", "辨读用途记录", "学徒把一份专用药列给伤者，也写下站点缺少储备。这是一份物资的两种用途，不能同时兑现。", ["request"]),
				_action("medicine", "side_herbalist:medicine", "学徒封存药包", "recover", "收好封存药包", "封条完整，药包有独立编号。选择用途后，这一份不能再交第二次。", ["record"], {"quest_item": "side_herbalist:medicine"})]),
			_step("一份两用的药", "决定药包用于当前伤者还是站点储备，亲自完成唯一交付。", [
				_action("purpose", "side_herbalist:resolution", "药包用途牌", "choice", "决定药包用途", "交给眼前伤者会完成一次具体救助；送往储备处会启用新增站点补给。没有一份药能同时做两件事。", [], {"choices": [{"id": "patient", "title": "救助伤者"}, {"id": "reserve", "title": "留作站点储备"}]}),
				_action("deliver", "side_herbalist:patient", "等待药包的伤者", "deliver", "交付这一份药", "你将带编号的药包交到选定地点。另一项需求仍留在记录里，没有被悄悄写成完成。", ["purpose"], {"destination_by_choice": {"patient": "side_herbalist:patient", "reserve": "side_herbalist:station_reserve"}, "consumes": "side_herbalist:medicine", "service": "herbalist_reserve", "service_choices": ["reserve"]})])]),
		_chain("side_hunter", "收起的悬赏", "plains", "side", 3, [
			_step("昨日的猎数", "对照猎人旧账、现场足迹和真实生态记录，分清死亡来源。", [
				_action("request", "side_hunter:giver", "营地猎人", "talk", "听猎人质疑", "猎人发现旧猎数与眼前踪迹不符，请你核对。账上的减少可能来自猎杀、自然死亡或迁出。"),
				_action("book", "side_hunter:record", "昨日猎数账", "read", "读旧猎数", "旧账记的是过去的数量。它没有权力把后来发生的捕食或自然死亡记到你名下。", ["request"]),
				_action("survey", "side_hunter:target", "猎场足迹核对点", "observe", "核对真实足迹", "你将实际玩家贡献、现场活动与未知去向分栏记录。没有目击到活体就据实写没有目击。", ["book"], {"ecology_mode": "hunter_counts"})]),
			_step("收起的悬赏", "根据现在的族群状态，作有限本地处理或亲自立下路线警示。", [
				_action("choice", "side_hunter:resolution", "猎人的新决定", "choice", "决定如何收尾", "若真实当地目标与余量允许，可以有限处理；也可以撤下不再可靠的悬赏，去路线旁立警示。", [], {"choices": [{"id": "local", "title": "核实后有限处理"}, {"id": "warning", "title": "收起悬赏并警示"}]}),
				_action("result", "side_hunter:warning_sign", "旧猎场警示牌", "ecology", "提交现场结果", "猎人收下实际结果。警示记录的是当前风险，有限处理也不许诺这里从此没有怪物。", ["choice"], {"destination_by_choice": {"local": "side_hunter:target", "warning": "side_hunter:warning_sign"}, "ecology_mode": "hunter_resolution"})])]),
		_chain("side_scholar", "缺失的拓印", "hill", "side", 4, [
			_step("缺失的拓印", "听学者说明缺口，在遗迹原处核对并回收遗失拓印。", [
				_action("request", "side_scholar:giver", "拓印学者", "talk", "询问拓印缺口", "学者缺了一页证明旧通路用途的拓印。只有拿到原件，才能决定铭文与机关件如何处理。"),
				_action("inscription", "side_scholar:record", "旧道铭文", "read", "核对原铭文", "铭文既是历史记录，也盖住一枚仍可使用的机关件。拆取会留下可见缺口。", ["request"]),
				_action("rubbing", "side_scholar:target", "遗失的拓印", "recover", "收回拓印", "纸上的断笔与原铭文吻合。你保留了一份实物证据，可以再作处置。", ["inscription"], {"quest_item": "side_scholar:rubbing"})]),
			_step("原样还是拆取", "选择保留铭文或拆取机关件，并在现场落实相应结果。", [
				_action("choice", "side_scholar:resolution", "铭文处置案", "choice", "决定铭文去留", "保留原状会补齐学者的记录；拆取会启用新增近道，但铭文会留下真实缺损。", [], {"choices": [{"id": "preserve", "title": "原样保留并补记"}, {"id": "component", "title": "拆取部件开近道"}]}),
				_action("resolve", "side_scholar:record", "旧道铭文", "repair", "落实现场处置", "你在原处完成所选处置。保留的铭文或打开的近道会各自留下可见结果。", ["choice"], {"destination_by_choice": {"preserve": "side_scholar:record", "component": "side_scholar:shortcut_gate"}, "opens_choice": {"component": "side_scholar:shortcut_gate"}})])]),
		_chain("side_merchant", "落下的货箱", "swamp", "side", 5, [
			_step("落下的货箱", "问清货箱编号，核对运单，再到真实落箱处回收。", [
				_action("request", "side_merchant:giver", "赶路的行商", "talk", "询问失落货物", "行商承认自己没能同时照顾两条路。他只托付这一只箱子，不是一批可以反复领取的货。"),
				_action("waybill", "side_merchant:record", "湿透的运单", "read", "核对货箱编号", "运单分别列着近路站点与外缘站点的需求，箱号只有一个。", ["request"]),
				_action("crate", "side_merchant:crate", "落下的封存货箱", "recover", "回收货箱", "你在泥岸边找到编号吻合的封箱。箱内是任务专用物资，不进入通用背包。", ["waybill"], {"quest_item": "side_merchant:crate"})]),
			_step("这一箱送往哪里", "选定一个补给站，将唯一的封箱送到其真实站点。", [
				_action("destination", "side_merchant:resolution", "补给去向板", "choice", "选择收货站", "近路更容易来往，外缘距离更远。选定一处后，这一箱物资只会启用那里的新增服务。", [], {"choices": [{"id": "near", "title": "近路补给站"}, {"id": "outer", "title": "外缘补给站"}]}),
				_action("deliver", "side_merchant:station_near", "近路收货台", "deliver", "交付封存货箱", "收货人在箱号旁签字。选定站点获得一次补给，另一处没有收到这只箱子。", ["destination"], {"destination_by_choice": {"near": "side_merchant:station_near", "outer": "side_merchant:station_outer"}, "consumes": "side_merchant:crate", "service": "merchant_station"})])]),
		_chain("side_watchman", "看不见的旗", "hill", "side", 6, [
			_step("看不见的旗", "读瞭望者值守记录，亲自调查被山脊遮住的视线路径。", [
				_action("request", "side_watchman:giver", "瞭望者", "talk", "询问失去的信号", "瞭望者看不到低处旧旗，但不知道是倒了还是被山脊遮住。请去实地核对，不要先写成又一场袭击。"),
				_action("record", "side_watchman:record", "值守视线草图", "read", "读视线草图", "旧旗与望台之间有一段岩脊。新旗可放在近处便于维护，也可放在高处提供另一方向的线索。", ["request"]),
				_action("sight", "side_watchman:target", "旧旗视线核对点", "observe", "调查视线路径", "你从旧旗一侧检查地形与可见范围。没有因看不见就宣称巡守死亡。", ["record"], {"ecology_mode": "watch_sight"})]),
			_step("换岗之前", "选择近处或高处旗位，亲自立起新旗并完成换岗记录。", [
				_action("choice", "side_watchman:resolution", "新旗位置图", "choice", "选择新旗位", "近处旗易维护，高处旗提供不同方向的粗线索。两者都不揭示未知远方活体。", [], {"choices": [{"id": "near", "title": "近处守望位"}, {"id": "high", "title": "高处守望位"}]}),
				_action("flag", "side_watchman:watch_near", "近处新旗位", "repair", "竖起新信号旗", "新旗在选定位置立起。瞭望者按这个实际位置留下粗略方向说明，不再沿用旧旗的目击缓存。", ["choice"], {"destination_by_choice": {"near": "side_watchman:watch_near", "high": "side_watchman:watch_high"}, "service": "watchman_station"})])]),
		_chain("side_letter", "冻结的信筒", "snow", "side", 7, [
			_step("冻结的信筒", "从留下的收信记录辨认信筒，亲自取出仍封存的信件。", [
				_action("request", "side_letter:giver", "守信人", "talk", "询问无人取走的信", "守信人一直没敢拆开信筒。寄信者离开后，真正需要找到的是收信的人。"),
				_action("record", "side_letter:record", "收信登记", "read", "核对信筒署名", "登记只说明信应交给谁，没有授权旁人替他作答。", ["request"]),
				_action("case", "side_letter:letter_case", "冻结的信筒", "recover", "取出密封信件", "你拂去筒口积雪，取出带收件人署名的信。它是独立任务物件，不会被出售。", ["record"], {"quest_item": "side_letter:letter"})]),
			_step("收信的人", "找到真正的收件人，在他身旁交信，再听完他的回答。", [
				_action("recipient", "side_letter:recipient", "等信的旧队员", "talk", "确认收信身份", "旧队员说出了登记里才有的地点和名字。他确实是信上的收件人。"),
				_action("deliver", "side_letter:recipient", "等信的旧队员", "deliver", "把信交到手中", "他读完信，没有请你替已离开的人作保证，只说：我知道那时有人还记得我。", ["recipient"], {"consumes": "side_letter:letter"}),
				_action("reply", "side_letter:resolution", "收信后的回执", "read", "收好回执", "回执上只有已经收到四字。这段关系得到一次明确收尾，不会因为读档再次寄出同一封信。", ["deliver"])])]),
		_chain("side_troll", "巨魔旧旗", "forest", "side", 8, [
			_step("巨魔旧旗", "核对旧人类旗记，调查真实巨魔王盘踞处附近的遗迹。", [
				_action("request", "side_troll:giver", "旧营地知情者", "talk", "听旧旗来历", "知情者记得那面人类旧旗先于巨魔王存在。王是否仍在，需要现场核对；故事不要求等待它出现。"),
				_action("flag", "side_troll:record", "褪色的人类旗记", "read", "辨认旧旗", "旗背记着房间符记顺序：叶、石、灯。它不是巨魔王掉落物的线索。", ["request"]),
				_action("site", "side_troll:target", "巨魔盘踞处旧遗迹", "observe", "调查当前遗迹", "你调查真实盘踞处旁的旧人类遗迹，把巨魔王当前状态与房间来历分开记录。挑战由你自行决定。", ["flag"], {"ecology_mode": "troll_state"}),
				_action("challenge", "side_troll:target", "当前巨魔王", "boss", "记录自选挑战结果", "你选择挑战并记录了真实玩家讨伐。此项可选，不阻塞房间故事，也不另付一份任务奖励。", ["site"], {"optional": true, "boss_species": "巨魔王"})]),
			_step("遗留的房间", "在房间外按叶、石、灯操作符记，开门后亲自取回记录。", [
				_action("runes", "side_troll:room_runes", "旧房间符记", "puzzle", "排列旧房间符记", "叶、石、灯依次亮起，新增房门打开。无论巨魔王现在是否存在，房间记录都不需要它的掉落。", [], {"puzzle_order": ["leaf", "stone", "lamp"], "puzzle_objects": ["side_troll:rune_leaf", "side_troll:rune_stone", "side_troll:rune_lamp"], "opens": "side_troll:room_gate"}),
				_action("record", "side_troll:room_record", "旧房间居住记录", "recover", "取回房间记录", "记录列出曾暂住此处的人和离开的日期。你收回的是一段人类历史，没有宣称夺回整片森林。", ["runes"], {"quest_item": "side_troll:room_record"})])]),
	]

static func regional_arcs() -> Array:
	if not _groups.has("regional_arcs"): _groups["regional_arcs"] = _seal(_regional_arcs())
	return _groups["regional_arcs"]

static func _regional_arcs() -> Array:
	return [

		_chain("region_plains", "补给三角", "plains", "regional", 1, [
			_step("核对旧补给点", "分别核对旧近路仓与外缘接应处，确认两处实际用途。", [
				_action("near", "region_plains:survey_a", "旧近路仓", "read", "核对近路仓记录", "近路仓曾面向新巡守，货架上的旧签没有证明今天还有物资。你记录了空架与原来用途。"),
				_action("outer", "region_plains:survey_b", "外缘接应处", "observe", "调查外缘接应处", "外缘接应处距离更远，却能覆盖另一条来路。你已亲自核对两处位置，没有把地图上的点当成已到访。")]),
			_step("集中或分散配置", "决定补给配置，带专用部件到选定工作点实际安装。", [
				_action("choice", "region_plains:choice", "补给配置图", "choice", "选择补给配置", "集中配置便于维护，分散配置覆盖较远来路。本工程只新增对应服务，不改写世界资源经济。", [], {"choices": [{"id": "near", "title": "集中近路"}, {"id": "outer", "title": "分散外缘"}]}),
				_action("work", "region_plains:work_near", "近路补给支架", "repair", "安装补给标识", "你把本工程专用标识装在选定工作点，旧地图上的补给三角终于有一条实际可用的线路。", ["choice"], {"destination_by_choice": {"near": "region_plains:work_near", "outer": "region_plains:work_outer"}})]),
			_step("三角中的一条路", "走完所选补给线，在接应站确认真实可用的服务。", [
				_action("walk", "region_plains:station", "补给三角接应站", "route", "验收补给线", "你沿修好的标识抵达接应站，确认补给并非只写在图上。野外风险仍按实际情况变化。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_plains:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_plains:work_near", "region_plains:station"], "outer": ["region_plains:work_outer", "region_plains:station"]}}),
				_action("station", "region_plains:station", "补给三角接应站", "repair", "启用接应服务", "集中配置只开放接应站；分散配置同时开放接应站和外缘补给台。两处共享同一份专用饭团库存，领取一处后另一处也不再补发。", ["walk"], {"service": "region_plains_station", "choice_stage": "region_plains:s2", "service_endpoints_by_choice": {"near": ["region_plains:station"], "outer": ["region_plains:station", "region_plains:work_outer"]}})])]),
		_chain("region_forest", "树下边界", "forest", "regional", 2, [
			_step("巢区与来路", "分别调查真实巢区和行人来路，记录当前存在的冲突位置。", [
				_action("clue", "region_forest:guide", "林缘巡线员", "talk", "询问巢区旧路", "巡线员把旧图上的一处真实巢址标给你。坐标只说明历史来路，那里今天是否有活体、巢穴是否活跃，都必须亲自抵达核实。", [], {"ecology_mode": "nest_clue"}),
				_action("nest", "region_forest:survey_a", "林下巢区调查点", "observe", "核对真实巢区", "你区分现在仍活跃的巢穴与历史巢址。旧的捣毁记录不能证明今天仍受抑制。", ["clue"], {"ecology_mode": "nest_survey"}),
				_action("trail", "region_forest:survey_b", "林间来路调查点", "observe", "核对来路", "来路与巢区并不完全重合，绕行可以留下空间。你只记录眼前路径，没有扩大怪物密度。")]),
			_step("暂时处理或绕行", "决定暂时处理真实巢穴，或在外缘建立可走的绕行标识。", [
				_action("choice", "region_forest:choice", "林下边界图", "choice", "选择处理方式", "捣巢只会暂时抑制当地繁衍；绕行不以杀死怪物为条件。巢穴状态变化时需重新核实。", [], {"choices": [{"id": "near", "title": "核实后暂时捣巢"}, {"id": "outer", "title": "标出林缘绕行"}]}),
				_action("work", "region_forest:work_near", "巢区接近点", "ecology", "确认实际处理", "你留下临时捣巢或实地绕行的准确记录。不能把绕行写成清剿，也不能把旧捣毁冒充当前行动。", ["choice"], {"ecology_mode": "nest_resolution", "destination_by_choice": {"near": "region_forest:work_near", "outer": "region_forest:work_outer"}})]),
			_step("树下的新标识", "亲自走完选定线路，在林下站点修复对应方向的标识。", [
				_action("walk", "region_forest:station", "树下守望点", "route", "验收林下路径", "你走过选定路径，核对标识与真实来路一致。即便巢穴以后重建，已经完成的工程也会保留。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_forest:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_forest:work_near", "region_forest:station"], "outer": ["region_forest:work_outer", "region_forest:station"]}}),
				_action("sign", "region_forest:station", "树下守望点", "repair", "修复方向标识", "新标识指向实际验收的路径，新增守望服务开放。它没有宣称森林从此安全。", ["walk"], {"service": "region_forest_station"})])]),
		_chain("region_swamp", "两条归路", "swamp", "regional", 3, [
			_step("工程前的两条路", "再次实勘近路与外缘，这次记录需要施工的实际位置。", [
				_action("near", "region_swamp:survey_a", "泥岸近路工程点", "observe", "测近路障碍", "你查看的是工程专用的近路障碍，主线曾经经过沼泽不等于完成这次整修。"),
				_action("outer", "region_swamp:survey_b", "枯木外缘工程点", "observe", "测外缘接应处", "外缘有可设置补给的位置，但现在仍没有这次工程的支架与标识。")]),
			_step("开路或设站", "选破除登记路障，或在外缘实际建起绕行补给点。", [
				_action("choice", "region_swamp:choice", "归路工程图", "choice", "选择归路工程", "近路需要真实破障；外缘需要亲手安装补给支架。两种工程都不会改变全世界水面规则。", [], {"choices": [{"id": "near", "title": "破除近路岩障"}, {"id": "outer", "title": "建外缘补给点"}]}),
				_action("work", "region_swamp:work_near", "近路登记岩障", "repair", "确认施工结果", "你在选定施工点完成实际工程。记录的是破开的登记岩障或建成的外缘支架。", ["choice"], {"destination_by_choice": {"near": "region_swamp:work_near", "outer": "region_swamp:work_outer"}, "obstacle_by_choice": {"near": "region_swamp:near_barrier"}})]),
			_step("脚下的归路", "沿新施工路线实走验收，启用归路接应点。", [
				_action("walk", "region_swamp:station", "归路接应站", "route", "实走验收归路", "你穿过本次工程开通或标出的路段，抵达归路站点。这个验收没有挪用主线的旧穿行证据。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_swamp:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_swamp:work_near", "region_swamp:station"], "outer": ["region_swamp:work_outer", "region_swamp:station"]}}),
				_action("station", "region_swamp:station", "归路接应站", "repair", "启用归路补给", "新的接应站留下持续可见的工程结果。将来迁入的怪物不会抹去修路历史。", ["walk"], {"service": "region_swamp_station"})])]),
		_chain("region_hill", "岩脊旧道", "hill", "regional", 4, [
			_step("旧道两端", "找到岩脊旧道的两端，查清哪里被碎岩封住、哪里仍有机关。", [
				_action("south", "region_hill:survey_a", "岩脊旧道南端", "read", "核对南端标记", "南端的旧道标记指向一段可破碎岩，不是不可破坏的整座山脊。"),
				_action("north", "region_hill:survey_b", "岩脊旧道北端", "observe", "调查北端机关", "北端保留另一处局部机关，可以不从碎岩缺口接近。两端都已由你亲自确认。")]),
			_step("碎岩与旧机关", "选择破除登记碎岩或操作北端机关，真正形成通路。", [
				_action("choice", "region_hill:choice", "岩脊工程板", "choice", "选择开路方法", "破碎岩与修旧机关是两种不同的现场工作。它们都不要求移动城塞或牛头王。", [], {"choices": [{"id": "near", "title": "破除南端碎岩"}, {"id": "outer", "title": "操作北端机关"}]}),
				_action("work", "region_hill:work_near", "南端登记碎岩", "repair", "确认旧道开通", "你在选定地点完成开路，局部物理通路随之改变，旧地图不再是唯一证据。", ["choice"], {"destination_by_choice": {"near": "region_hill:work_near", "outer": "region_hill:work_outer"}, "obstacle_by_choice": {"near": "region_hill:near_barrier"}, "opens_choice": {"outer": "region_hill:shortcut_gate"}})]),
			_step("岩脊接应点", "走通修复的旧道，到山脊接应点安装最后标识。", [
				_action("walk", "region_hill:station", "岩脊接应点", "route", "验收旧道通路", "你从选定工作点走到接应处，确认新增路线确实可以使用。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_hill:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_hill:work_near", "region_hill:station"], "outer": ["region_hill:work_outer", "region_hill:station"]}}),
				_action("station", "region_hill:station", "岩脊接应点", "repair", "启用岩脊接应", "新接应点亮起标识，提供有限补给。附近城塞的真实生态活动继续存在。", ["walk"], {"service": "region_hill_station"})])]),
		_chain("region_snow", "白地归途", "snow", "regional", 5, [
			_step("看得见的路标", "在白地两侧分别找到真实可见路标，辨认开阔线和掩护线。", [
				_action("open", "region_snow:survey_a", "开阔地旧路标", "read", "辨认开阔线路标", "路标清楚标出较短的开阔线。这里没有凭空新增的冻伤或饥饿倒计时。"),
				_action("cover", "region_snow:survey_b", "冰脊后旧路标", "observe", "核对掩护线", "冰脊后可以沿更长的掩护线行走。路线差异来自实际地形与长度。")]),
			_step("短路与掩护", "选择短开阔线或长掩护线，在对应位置装好休整设施。", [
				_action("choice", "region_snow:choice", "白地归途图", "choice", "选择休整线", "较短开阔线便于直行，较长掩护线转折更多。你决定把新增休整点服务于哪一条路。", [], {"choices": [{"id": "near", "title": "短开阔线"}, {"id": "outer", "title": "长掩护线"}]}),
				_action("work", "region_snow:work_near", "开阔线休整台", "repair", "安装休整设施", "你在选定路线边架好休整设施与标识。工程没有改动雪原生存规则。", ["choice"], {"destination_by_choice": {"near": "region_snow:work_near", "outer": "region_snow:work_outer"}})]),
			_step("归途有人留灯", "沿实际路线走到休整点，确认归途标识与服务。", [
				_action("walk", "region_snow:station", "白地休整点", "route", "验收白地归途", "你沿所选路标走到休整点。它是一处实际建成的新增站点，不是一行白地安全的宣告。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_snow:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_snow:work_near", "region_snow:station"], "outer": ["region_snow:work_outer", "region_snow:station"]}}),
				_action("station", "region_snow:station", "白地休整点", "repair", "点亮休整标识", "休整标识亮起，有限补给可用。你留住的是归途的方向，而不是永远不变的野外状态。", ["walk"], {"service": "region_snow_station"})])]),
		_chain("region_lava", "灼热的边界", "lava", "regional", 6, [
			_step("熔流的两侧", "实地核对两侧熔岩伤害边界，记下可用石脊。", [
				_action("near", "region_lava:survey_a", "近侧熔流边界", "observe", "调查近侧边界", "你按真实熔岩地形记录近侧边界。可踩入不代表没有灼伤，补蓝物品不能提供免疫。"),
				_action("outer", "region_lava:survey_b", "远侧石脊", "observe", "调查远侧石脊", "远侧石脊绕得更远，但能避开可见熔流。记录只描述这条实际接近线。")]),
			_step("留在石脊上", "在两条已调查绕行线中选一条，修复对应方向的标识。", [
				_action("choice", "region_lava:choice", "熔河绕行图", "choice", "选择石脊绕行线", "选择近侧石脊或远侧外缘。两条线路都避开已核对的熔流，不会替玩家关闭全区熔岩伤害。", [], {"choices": [{"id": "near", "title": "近侧石脊"}, {"id": "outer", "title": "远侧外缘"}]}),
				_action("work", "region_lava:work_near", "近侧绕行标识", "repair", "修复绕行标识", "你把耐热标识装在实际石脊上。路标指出可走的位置，没有许诺脚下的熔岩变凉。", ["choice"], {"destination_by_choice": {"near": "region_lava:work_near", "outer": "region_lava:work_outer"}})]),
			_step("边界上的补给点", "亲自走完所选接近线，在石脊尽头启用补给点。", [
				_action("walk", "region_lava:station", "石脊补给点", "route", "验收熔河绕行线", "你沿已修复标识抵达补给点，现场验收这条绕行线。工程的存在与怪物是否迁入是两回事。", [], {"route_corner_count_by_choice": {"near": 4, "outer": 4}, "choice_stage": "region_lava:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_lava:work_near", "region_lava:station"], "outer": ["region_lava:work_outer", "region_lava:station"]}}),
				_action("station", "region_lava:station", "石脊补给点", "repair", "启用石脊补给", "边界补给点完成，有限物资可领取。世界之心仍不能替这片土地停止灼烧或生态变化。", ["walk"], {"service": "region_lava_station"})])]),
	]

static func random_templates() -> Array:
	if not _groups.has("random_templates"): _groups["random_templates"] = _seal(_random_templates())
	return _groups["random_templates"]

static func _random_templates() -> Array:
	return [

		_chain("random_wounded", "野外伤者", "local", "random", 1, [
			_step("野外伤者", "确认登记伤者的需求，取专用急救物资后返回身旁救助。", [
				_action("request", "random_wounded:giver", "伤者留下的呼救记号", "read", "辨读呼救记号", "记号指向附近登记的伤者与封存急救物资。确认两者仍在且可达，才接下这次救助。"),
				_action("aid", "random_wounded:parts", "封存急救物资", "recover", "取急救物资", "你取出只供这名伤者使用的专用急救包。它不会进入可出售的背包。", ["request"], {"quest_item": "random_wounded:aid"}),
				_action("rescue", "random_wounded:target", "野外伤者", "rescue", "完成现场救助", "你在伤者身旁完成救助。这名有限剧情人物留下获救记录，不会因重载再受一次同样的伤。", ["aid"])])]),
		_chain("random_parcel", "散落包裹", "local", "random", 2, [
			_step("散落包裹", "核对包裹封签，实地回收，再亲手还给登记收件人。", [
				_action("request", "random_parcel:giver", "包裹认领告示", "read", "读认领告示", "告示给出包裹封签与当地收件人。包裹必须尚未回收，收件人也必须真实可达。"),
				_action("parcel", "random_parcel:target", "散落的封签包裹", "recover", "回收包裹", "封签与告示一致，你收起这份独立编号的包裹。", ["request"], {"quest_item": "random_parcel:parcel"}),
				_action("return", "random_parcel:return", "包裹收件人", "deliver", "亲手交还包裹", "收件人核对封签后签收。包裹到此结案，离线时间不会再生一只同编号包裹。", ["parcel"], {"consumes": "random_parcel:parcel"})])]),
		_chain("random_sign", "断裂路标", "local", "random", 3, [
			_step("断裂路标", "读断裂说明，取本路标的专用部件，到原处修复。", [
				_action("request", "random_sign:giver", "路标维修留言", "read", "读维修留言", "留言登记了这根已经断裂的路标与一包备件。没有待修实体就不会发布这次遭遇。"),
				_action("parts", "random_sign:parts", "路标专用备件", "recover", "取路标备件", "你找到刻着同一编号的支脚与横梁。它们不能拿去反复交给另一根路标。", ["request"], {"quest_item": "random_sign:parts"}),
				_action("repair", "random_sign:target", "断裂的路标", "repair", "立起路标", "支脚固定、横梁归位，路标重新指向真实来路。修的是路标，不是周围所有危险。", ["parts"])])]),
		_chain("random_rocks", "岩缝近道", "local", "random", 4, [
			_step("岩缝近道", "核对近道两端，打碎登记碎岩，再亲自穿过缺口。", [
				_action("request", "random_rocks:giver", "岩缝近道草图", "read", "核对近道草图", "草图指向可破坏碎岩与真实可达的两端。不可破坏的山体不会被当成这次任务目标。"),
				_action("break", "random_rocks:target", "登记的近道碎岩", "obstacle", "核验碎岩已破", "登记碎岩被实际击碎，缺口记录与这次有限遭遇绑定。", ["request"], {"barrier_id": "random_rocks:barrier"}),
				_action("cross", "random_rocks:return", "近道另一端", "route", "穿过新开缺口", "你走到近道另一端，确认通路真实可用。只打碎远处别的石头不能完成这段验收。", ["break"], {"routes": ["passage"], "route_waypoints": ["random_rocks:target", "random_rocks:return"]})])]),
		_chain("random_medicine", "紧缺药包", "local", "random", 5, [
			_step("紧缺药包", "当面核实药包需求，取已知专用物资并确认唯一交付。", [
				_action("request", "random_medicine:giver", "药包求助人", "talk", "核实药包需求", "求助人指出一处已知可达的专用物资。此次使用那份物资，不会偷偷扣除你的恢复快捷预设。"),
				_action("medicine", "random_medicine:parts", "登记药包物资", "recover", "取登记药包", "你取走带编号的任务药包，封签与这次求助相符。", ["request"], {"quest_item": "random_medicine:medicine"}),
				_action("deliver", "random_medicine:target", "等待药包的巡守", "deliver", "确认交付药包", "巡守在你面前收下药包，登记需求已经解除。这份药包不能再交给别人。", ["medicine"], {"consumes": "random_medicine:medicine"})])]),
		_chain("random_message", "留守讯息", "local", "random", 6, [
			_step("留守讯息", "接受当地已知留守人的讯息，核对封签并送到另一名接收者。", [
				_action("request", "random_message:giver", "留守传信人", "talk", "听留守讯息", "传信人只请你把当前当地情况带给另一位已知接应人，不要求跨越未探索的半个世界。"),
				_action("message", "random_message:target", "留守讯息封套", "recover", "取讯息封套", "封套有这次交接的独立编号，文字说明的是过去目击，没有把它伪装成现在的活体位置。", ["request"], {"quest_item": "random_message:message"}),
				_action("deliver", "random_message:return", "当地接应人", "deliver", "交付留守讯息", "接应人当面确认收到讯息。记录的时间与来源一并保留，未来变化不会重开同一张收据。", ["message"], {"consumes": "random_message:message"})])]),
		_chain("random_nest", "巢区临道", "local", "random", 7, [
			_step("巢区临道", "核对真实临路巢穴，暂时捣巢或现场确认绕行，再提交结果。", [
				_action("request", "random_nest:giver", "临道巢区告示", "read", "核对巢区线索", "告示只在真实活动巢穴靠近当前路线时成立。接取与行动都必须重新核对巢穴。"),
				_action("result", "random_nest:target", "实际临路巢区", "ecology", "确认巢区处置", "你留下实际暂时捣巢或到场核对绕行的结果。历史捣毁不代表今天仍没有巢穴。", ["request"], {"ecology_mode": "nest_resolution"}),
				_action("report", "random_nest:return", "临道记录牌", "deliver", "写下当前路线说明", "路线牌记录这次处理的时间与方式。捣巢的抑制会结束，已经支付的调查奖励不会因此再发。", ["result"])])]),
		_chain("random_migration", "迁徙目击", "local", "random", 8, [
			_step("迁徙目击", "读取有真实来源的迁移线索，到场核对，再记录当前结果。", [
				_action("request", "random_migration:giver", "迁移目击记录", "read", "读真实迁移线索", "记录绑定已经发生的迁移个体、区域与时间。读档重新生成场景不算又一次迁移。"),
				_action("site", "random_migration:target", "迁移线索现场", "observe", "核对迁移现场", "你到已获知的现场核对留痕与现在的活动。目标若已离开，就记录离开，不强迫等待下一次迁移。", ["request"], {"ecology_mode": "migration_state"}),
				_action("report", "random_migration:return", "目击回执点", "deliver", "提交目击核对", "回执保留事件来源与本次现场观察。两者的时间不同，不会混成一个一直跟踪隐藏目标的位置。", ["site"])])]),
		_chain("random_camp", "据点余患", "local", "random", 9, [
			_step("据点余患", "核对健康当地族群与能力范围，有限处理或在目标变化后勘察结案。", [
				_action("request", "random_camp:giver", "当地据点委托牌", "read", "核对当地委托", "只有实际可达、能力相符且有余量的健康族群才会发布这项委托。全球不足六只时不发布狩猎单。"),
				_action("result", "random_camp:target", "登记的当地据点", "ecology", "提交真实处理证据", "有限处理只计真实玩家贡献并留下当地余量。若目标迁出或自然消失，保留贡献并亲自勘察事实。", ["request"], {"ecology_mode": "camp_resolution"}),
				_action("report", "random_camp:return", "当地委托回执点", "deliver", "确认据点结案", "你按实际处理或目标变化提交结案，没有补刷怪物凑数，也没有把自然死亡当成猎杀。", ["result"])])]),
		_chain("random_runes", "废墟符记", "local", "random", 10, [
			_step("废墟符记", "读取独立遗迹线索，按灯、路、人操作三枚现场符记。", [
				_action("request", "random_runes:giver", "废墟外的留字", "read", "读遗迹留字", "这处机关有自己的有限编号。它没有结算过，才会成为新的遭遇线索。"),
				_action("record", "random_runes:record", "三行符记说明", "read", "读机关顺序", "第一行点灯，第二行辨路，第三行等人。正确次序是灯、路、人。按错只会重置当前输入。", ["request"]),
				_action("runes", "random_runes:target", "废墟符记机关", "puzzle", "完成符记次序", "灯、路、人依次回应，机关留下本次完成记录。这处遗迹不会在读档或新的一天再次发满额奖励。", ["record"], {"puzzle_order": ["lamp", "road", "person"], "puzzle_objects": ["random_runes:rune_a", "random_runes:rune_b", "random_runes:rune_c"]})])]),
	]

static func world_arcs() -> Array:
	if not _groups.has("world_arcs"): _groups["world_arcs"] = _seal(_world_arcs())
	return _groups["world_arcs"]

static func _world_arcs() -> Array:
	return [

		_chain("world_migration", "迁徙的长路", "world", "world", 1, [
			_step("沿线的两个地点", "依据已获知的真实迁移线索，分别到两处沿线地点调查。", [
				_action("route_a", "world_migration:route_a", "迁徙来路观察点", "observe", "调查迁徙来路", "你核对已获知的迁入迁出记录。个体、起止区域和发生时间属于同一条真实事实链。", [], {"ecology_mode": "world_migration_origin"}),
				_action("route_b", "world_migration:route_b", "迁徙去路观察点", "observe", "调查迁徙去路", "你抵达第二处沿线地点。曾经迁过这条边界不代表今天仍在此处。", [], {"ecology_mode": "world_migration_destination"})]),
			_step("现在走到哪里", "向观察员核对当前状态，区分仍继续、已停止与失去踪迹。", [
				_action("status", "world_migration:observer", "沿线观察员", "observe", "核对当前迁徙状态", "观察员只接受有来源的当前状态：仍在继续、已经停止或失去踪迹。结案不要求世界再发生一次迁移。", [], {"ecology_mode": "world_migration_status"})]),
			_step("把长路留下", "在记录板提交两地调查与当前状态，完成这一次世界调查。", [
				_action("archive", "world_migration:record_board", "迁徙路线记录板", "deliver", "提交迁徙路线记录", "这次迁徙调查被收入世界档案。后来出现的新变化可以补记事实，不会重开这张调查收据。")])]),
		_chain("world_decline", "最后的足迹", "world", "world", 2, [
			_step("已经获知的足迹", "依有来源的濒危或永久灭绝线索，亲自调查已知地点。", [
				_action("site", "world_decline:last_site", "最后已知活动地", "observe", "调查已知足迹", "这项调查由真实持续濒危或有来源的永久灭绝事件触发。奖励调查，不奖励把物种杀到最后一只。", [], {"ecology_mode": "world_decline_site"})]),
			_step("减少的原因", "在证据柱核对仍存、迁出、自然死亡与玩家造成的永久灭绝。", [
				_action("cause", "world_decline:evidence_post", "衰退证据柱", "observe", "核对真实原因", "你把仍濒危、已经回升、自然消失或玩家永久灭绝分别记明。没有证据就不把空场改写成讨伐。", [], {"ecology_mode": "world_decline_status"})]),
			_step("留给来者的警示", "亲自立下警示，再把这次有限调查交给观察员。", [
				_action("warning", "world_decline:warning_sign", "足迹警示牌", "repair", "立下真实状态警示", "警示牌标明调查时间与真实原因，不向后来的巡守保证物种一定会恢复。"),
				_action("archive", "world_decline:observer", "物种记录观察员", "deliver", "提交足迹调查", "观察员收下调查并补入图鉴附注。今后的自然复苏可留下新事实，这次结案不会反复支付。", ["warning"])])]),
		_chain("world_relief", "彼此的接应", "world", "world", 3, [
			_step("两地正在等什么", "在已到访三种地形后，分别确认两处新增接应点的实际待办。", [
				_action("need_a", "world_relief:need_a", "第一处接应需求", "talk", "确认第一处需求", "这里需要的是新增剧情站点已经登记的救援或补给事项，并非凭空模拟出的市场短缺。"),
				_action("need_b", "world_relief:need_b", "第二处接应需求", "talk", "确认第二处需求", "另一处也明确说明所缺物资。你亲自核实两地需求后，才能分配各自编号的任务供应。")]),
			_step("各有去向的物资", "将两份不同编号的专用物资交到各自接应处。", [
				_action("supply_a", "world_relief:supply_a", "第一份接应物资", "deliver", "交付第一份物资", "第一份专用物资交到登记接应处。它的唯一去向写入账本，不能再给第二处。", [], {"supply_id": "world_relief:parcel_a"}),
				_action("supply_b", "world_relief:supply_b", "第二份接应物资", "deliver", "交付第二份物资", "第二份物资有自己的编号与目的地。两处收到的是两份实际独立的供应。", [], {"supply_id": "world_relief:parcel_b"})]),
			_step("接应之后", "回访两处接应点，在协调台确认新增居民与服务的实际变化。", [
				_action("return_a", "world_relief:need_a", "第一处接应居民", "talk", "回访第一处接应", "居民当面确认收到的物资和已经改变的服务，不需要你长距离护送一个不存在的队伍。"),
				_action("return_b", "world_relief:need_b", "第二处接应居民", "talk", "回访第二处接应", "第二处也给出自己的接收回执。两张回执对应两份不同物资。"),
				_action("settle", "world_relief:coordination_post", "接应协调台", "repair", "确认两地接应", "协调台保存两地真实去向与回访结果，新增联合补给服务生效，这条世界事项有限完结。", ["return_a", "return_b"], {"service": "world_relief_station"})])]),
		_chain("world_watchnet", "灯火相望", "world", "world", 4, [
			_step("选择三处灯火", "主线完成且至少三条区域工程完工后，选择三个真实可用节点。", [
				_action("plan", "world_watchnet:planning_board", "守望网络配置板", "configure", "选择三个守望节点", "选中的必须是已经实际完成的区域站点。最终配置不会替你补做未完成的工程。", [], {"node_count": 3})]),
			_step("让节点彼此识别", "亲自安装三套各有编号的守望标识。", [
				_action("node_1", "world_watchnet:node_1", "第一套守望装置", "repair", "安装第一套标识", "第一套专用装置落在选定的真实节点上，没有复制另一处已经用过的部件。", [], {"node_index": 0}),
				_action("node_2", "world_watchnet:node_2", "第二套守望装置", "repair", "安装第二套标识", "第二套装置记下自己的节点身份，让这处灯火在新网络中可辨认。", [], {"node_index": 1}),
				_action("node_3", "world_watchnet:node_3", "第三套守望装置", "repair", "安装第三套标识", "第三套装置安装完成，三个节点都已留下现场证据。", [], {"node_index": 2})]),
			_step("灯火相望", "确认三个节点真正可用，提交最终线路配置与世界档案。", [
				_action("archive", "world_watchnet:record_board", "最终守望档案", "deliver", "提交整体配置", "三处实际可用的节点收入最终档案。以后种群迁移、Boss复生或道路风险改变，都不会抹去这项已完成的工程。", [], {"service": "world_watchnet_station"})])]),
	]

static func chapter(id: String) -> Dictionary:
	for entry: Dictionary in main_chapters():
		if entry["id"] == id: return entry
	return {}

static func all_stages(seed: int = 0) -> Array:
	if _stages.has(seed): return _stages[seed]
	if _stages.size() >= 16:
		_stages.clear()
		_stage_maps.clear()
		_action_maps.clear()
	var result: Array = []
	for group: Array in [main_chapters(), side_chains(), regional_arcs(), world_arcs()]:
		for entry: Dictionary in group: result.append_array(entry["steps"])
	for template: Dictionary in random_templates():
		for serial: int in range(RANDOM_PER_TEMPLATE):
			var source: Dictionary = template["steps"][0]
			var instance_id := str(template["id"]) + ":" + str(seed) + ":" + str(serial)
			var entry: Dictionary = _remap(source, str(template["id"]), instance_id)
			entry["id"] = instance_id
			entry["chain"] = str(template["id"])
			entry["template"] = template["id"]
			entry["serial"] = serial
			entry["seed"] = seed
			entry["previous"] = ""
			entry["required"] = []
			for action_entry: Dictionary in entry["actions"]:
				action_entry["id"] = str(action_entry["id"]).replace(instance_id + ":s1:", instance_id + ":")
				action_entry["stage"] = instance_id
				action_entry["chain"] = str(template["id"])
				for i: int in range(action_entry["requires"].size()):
					action_entry["requires"][i] = str(action_entry["requires"][i]).replace(instance_id + ":s1:", instance_id + ":")
				if not action_entry.get("optional", false): entry["required"].append(action_entry["id"])
			result.append(entry)
	var stage_map: Dictionary = {}
	var action_map: Dictionary = {}
	for entry: Dictionary in result:
		stage_map[entry["id"]] = entry
		for a: Dictionary in entry["actions"]: action_map[a["id"]] = a
	_stages[seed] = _seal(result)
	_stage_maps[seed] = _seal(stage_map)
	_action_maps[seed] = _seal(action_map)
	return _stages[seed]

static func stage(id: String) -> Dictionary:
	var seed := 0
	if id.begins_with("random_"):
		var parts := id.split(":")
		if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int(): return {}
		seed = int(parts[1])
	all_stages(seed)
	return _stage_maps[seed].get(id, {})

static func actions(seed: int = 0) -> Dictionary:
	all_stages(seed)
	return _action_maps[seed]

static func action(stage_id: String, action_id: String) -> Dictionary:
	for a: Dictionary in stage(stage_id).get("actions", []):
		if a["id"] == action_id: return a
	return {}

static func chains() -> Array:
	var result: Array = main_chapters().duplicate()
	result.append_array(side_chains())
	result.append_array(regional_arcs())
	result = result.duplicate()
	result.append_array(world_arcs())
	result.append_array(random_templates())
	return result

static func chain(id: String) -> Dictionary:
	for entry: Dictionary in chains():
		if entry["id"] == id: return entry
	return {}

static func _chapter(id: String, title: String, terrain: String, number: int, steps: Array) -> Dictionary:
	return _chain(id, title, terrain, "main", number, steps)

static func _chain(id: String, title: String, terrain: String, family: String, number: int, steps: Array) -> Dictionary:
	var previous := ""
	for i: int in range(steps.size()):
		var s: Dictionary = steps[i]
		s["id"] = id + ":s" + str(i + 1)
		s["chain"] = id
		s["chapter"] = id if family == "main" else ""
		s["family"] = family
		s["index"] = i
		s["terrain"] = terrain
		s["previous"] = previous
		s["required"] = []
		for a: Dictionary in s["actions"]:
			a["id"] = s["id"] + ":" + str(a["id"])
			a["stage"] = s["id"]
			a["chapter"] = s["chapter"]
			a["chain"] = id
			var dependencies: Array = []
			for required: String in a.get("requires", []):
				dependencies.append(s["id"] + ":" + required)
			a["requires"] = dependencies
			if not a.get("optional", false): s["required"].append(a["id"])
		previous = s["id"]
	return {"id": id, "title": title, "terrain": terrain, "family": family, "number": number,
		"steps": steps, "unlock_after": "" if family == "main" else {"plains": "chapter1", "forest": "chapter1", "swamp": "watch_c2_forest", "hill": "watch_c3_swamp", "snow": "watch_c4_hill", "lava": "watch_c5_snow", "local": "chapter1", "world": "chapter1"}.get(terrain, ""), "batch": 1 if family == "main" and number == 2 else (2 if family == "main" else (3 if family in ["side", "regional"] else 4))}

static func _step(title: String, objective: String, action_list: Array) -> Dictionary:
	return {"title": title, "objective": objective, "actions": action_list}

static func _action(id: String, object: String, title: String, kind: String, verb: String, text: String, requires: Array = [], extra: Dictionary = {}) -> Dictionary:
	var out := {"id": id, "object": object, "title": title, "kind": kind, "verb": verb, "text": text, "requires": requires}
	out.merge(extra, true)
	return out


static func _remap(value: Variant, old_prefix: String, new_prefix: String) -> Variant:
	if value is String: return value.replace(old_prefix + ":", new_prefix + ":")
	if value is Array:
		var array: Array = []
		for child: Variant in value: array.append(_remap(child, old_prefix, new_prefix))
		return array
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key: Variant in value: dictionary[key] = _remap(value[key], old_prefix, new_prefix)
		return dictionary
	return value

static func _seal(value: Variant) -> Variant:
	if value is Array:
		for child: Variant in value: _seal(child)
		value.make_read_only()
	elif value is Dictionary:
		for child: Variant in value.values(): _seal(child)
		value.make_read_only()
	return value
