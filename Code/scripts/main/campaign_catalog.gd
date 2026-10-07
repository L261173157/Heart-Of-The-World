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
			_step("古树下的旧约", "与草药师交谈，阅读古树下的旧约抄本。", [
				_action("herbalist", "c2:herbalist", "草药师", "talk", "询问旧哨所", "草药师把叶脉拓本压在你手里。\n「他伤着腿，还惦记那盏灭了的灯。去看看古树下的旧约抄本吧，巡线员留下的路，总该有人接着走。」", [], {"prompt": "草药师停下整理药包的手，先看了看你来时的路。\n「前哨终于有人来了？我正担心林子里的联络员。」", "questions": [{"label": "他为什么没回来？", "answer": "「腿伤拖住了他。他只说还有人会沿旧路回来，我劝不动。」"}, {"label": "旧约和他有关？", "answer": "「那是人类给巡林者留路的约定。他还认这份约，也认上面留下的信号。」"}]}),
				_action("old_pact", "c2:old_pact", "旧约抄本", "read", "阅读旧约抄本", "旧约抄本写着：「为巡林者留一条归路，为后来者留一盏灯。」\n页边画着北、东、西三处信号石。末尾的守望记录被撕去了，旁注指向巡线员的方位刻记。", ["herbalist"], {"prompt": "古树下压着一份旧约抄本。纸角被反复折起，末尾缺了一页。"})]),
			_step("林下通道", "读巡线员的方位刻记，依线索触碰信号石，进门取残页。", [
				_action("route_marks", "c2:route_marks", "巡线员的方位刻记", "read", "辨读方位刻记", "刻记把晨露、日影与归鸟连成一线：北→东→西。\n按这个次序触碰三处信号石，便能打开旧约档案石门。", [], {"prompt": "巡线员的方位刻记还在。三枚刻印分别朝向北、东、西，细小的连线藏在苔痕下。", "rules": "信号石顺序为北→东→西。按错只重置未完成的序列，已取得的记录保留。"}),
				_action("runes", "c2:forest_gate", "旧约档案石门", "puzzle", "核对符标", "北、东、西的信号依次接通。旧约档案石门松开，门后的残页终于露了出来。", ["route_marks"], {"puzzle_order": ["north", "east", "west"], "puzzle_objects": ["c2:rune_north", "c2:rune_east", "c2:rune_west"], "opens": "c2:forest_gate", "prompt": "旧约档案石门上的三道纹路通向信号石。巡线员的刻记写着：北→东→西。"}),
				_action("torn_record", "c2:torn_record", "门后的残页", "recover", "收取门后的残页", "残页最后一行换了笔迹：「补给未到，我留在东侧歇脚处。若有人回来，别让他扑空。」\n落款是远征队联络员。", ["runes"], {"prompt": "门后的残页压在尘土里，边缘与旧约抄本的缺口吻合。"})]),
			_step("留在林地的人", "找到受伤的远征队联络员，取林间急救匣物资并返回包扎。", [
				_action("liaison", "c2:liaison", "受伤的远征队联络员", "talk", "查看伤势", "联络员撑着地想站起来，又停住了。\n「腿不听使唤。林间急救匣还在树根那边，劳你取来。先把这伤扎住，我还有话要带出去。」", [], {"prompt": "联络员抬手挡住眼前的光。\n「谁？……前哨来的？别站在路中间，过来。」", "questions": [{"label": "你一直在等谁？", "answer": "「走散的队员。只要他们还认得旧信号，就会往这儿找。」"}]}),
				_action("aid_cache", "c2:aid_cache", "林间急救匣", "recover", "取出急救物资", "林间急救匣里还有干燥的绷带和封好的药。你收起急救物资，联络员正等着你回去。", ["liaison"], {"quest_item": "c2:aid", "prompt": "林间急救匣的扣环被树根顶住，匣内的药包仍封得严实。", "rules": "急救物资作为任务物件保存，不占普通背包，也不会消耗快捷补给。"}),
				_action("rescue", "c2:liaison", "受伤的远征队联络员", "rescue", "为联络员包扎", "绷带扎紧后，联络员终于松开了捂着伤口的手。\n「这儿我守得住。帮我看看信标备件箱，灯灭着，回来的人就找不到我们。」", ["aid_cache"], {"prompt": "联络员看见你带回的药包，把伤腿慢慢挪到身前。\n「来吧。扎紧些，我还得守这条路。」"})]),
			_step("第一束信号", "取信标备件，修复失火的林间信标。", [
				_action("signal_parts", "c2:signal_parts", "信标备件箱", "recover", "取信标备件", "信标备件箱里留着遮光片和旧灯芯。你把部件收好，可以去修复失火的林间信标了。", [], {"quest_item": "c2:signal_parts", "prompt": "信标备件箱的木盖已经翘起，里面传来零件相碰的轻响。"}),
				_action("beacon", "c2:beacon", "失火的林间信标", "repair", "修复林间信标", "林间信标重新亮起。联络员望着灯，过了片刻才开口。\n「我们分队时，一路去了沼泽，一路去了丘陵。这是沼泽接应点的旧坐标……若见到他们，告诉他们，我还在。」", ["signal_parts"], {"service": "forest_station", "next_chapter": "watch_c3_swamp", "prompt": "失火的林间信标只剩一截焦黑的灯芯。备件已经齐了，联络员还守在林间等这束光。"})])]),
		_chapter("watch_c3_swamp", "沼泽双途", "swamp", 3, [
			_step("漂来的行囊", "查看图腾刻文与灵龛布条，找到漂来的远征行囊。", [
				_action("totem", "c3:totem_record", "沉睡图腾的刻文", "read", "查看图腾刻文", "沉睡图腾的刻文旁留着熟悉的绳结，和前哨的记号一样。绳尾朝向枯木灵龛，那里还挂着一截布条。", [], {"prompt": "水痕爬上了沉睡图腾。刻文旁系着一个绳结，结法有些眼熟。"}),
				_action("shrine", "c3:shrine_record", "枯木灵龛的布条", "read", "读灵龛布条", "布条上写着：「近路能走。若赶不上，到外缘等。」\n两句字的深浅不同，末尾指向搁浅在泥岸的远征行囊。", ["totem"], {"prompt": "枯木灵龛的布条被泥水染暗。你得把它摊开，才能看清叠在一起的字。"}),
				_action("satchel", "c3:satchel", "漂来的远征行囊", "recover", "取回远征行囊", "行囊里有一个防水封套，装着两份路书。一个写「走浅滩」，另一个却把那条路划掉了。\n夹在后面的回信只写了开头，收信人还在等下文。", ["shrine"], {"quest_item": "c3:satchel_record", "prompt": "漂来的远征行囊搁在泥岸上。外皮湿透了，封套却还紧紧系着。"})]),
			_step("两份路书", "读受潮的旧路书，分别勘察近路和外环。", [
				_action("old_route", "c3:old_route", "受潮的旧路书", "read", "读受潮的旧路书", "两份路书都指向同一个接应点，却画着不同的路：一条穿过浅滩，一条沿枯木外缘绕行。日期已经模糊。\n先去近路勘察桩和外环勘察桩看看，纸上的路如今还剩多少。", [], {"prompt": "受潮的旧路书摊在眼前。几处路口被反复涂改，单看其中一张说不通。"}),
				_action("route_near", "c3:route_near", "近路勘察桩", "observe", "勘察浅滩近路", "近路在浅滩间穿过，石障处的缺口通向接应点。你记下眼前能看见的动静；走这条短路，得确保缺口能通行。", ["old_route"], {"prompt": "近路勘察桩朝向浅滩。接应点就在另一头，先看看石障处的缺口能不能通行。"}),
				_action("route_outer", "c3:route_outer", "外环勘察桩", "observe", "勘察枯木外缘", "外缘的路绕向西侧，接连拐过两处弯。你记下这里能看见的动静。\n两边都看过后，就可以去接应路线图前拿主意了。", ["old_route"], {"prompt": "外环勘察桩靠着枯木。路沿西侧伸出去，在视野边缘转了个弯。"})]),
			_step("接应点", "在接应路线图选路，沿路到达幸存者身边，取药并包扎。", [
				_action("route_choice", "c3:route_choice", "接应路线图", "choice", "选择路线", "你在接应路线图上标出了要走的路。接应点在前方，沿所选路线过去吧。", [], {"choices": [{"id": "near", "title": "走浅滩近路"}, {"id": "outer", "title": "绕枯木外缘"}], "prompt": "接应点在沼泽另一侧。浅滩近路短，要先打碎岩障穿过缺口；枯木外缘路长，要走过西侧两个转折。\n你准备从哪边过去？", "rules": "确认后沿所选路线完成接应。近路需打碎岩障并穿过缺口；外缘需走过西侧两个转折。途中离开或倒下可回到最后经过的路标继续。"}),
				_action("reach", "c3:survivor", "沼泽幸存者", "route", "抵达接应点", "幸存者盯着你带来的行囊，手指在封套上停了很久。\n「还在……我以为它沉了。接应急救匣就在旁边，先帮我拿来，手抖得使不上劲。」", ["route_choice"], {"routes": ["near", "outer"], "route_by_choice": {"near": ["c3:route_near", "c3:survivor"], "outer": ["c3:route_outer", "c3:survivor"]}, "prompt": "幸存者听见脚步，抬起头。\n「你从哪条路过来的？把行囊拿近些，让我看看。」"}),
				_action("aid", "c3:aid_cache", "接应急救匣", "recover", "取接应急救物资", "接应急救匣里的油布没有破，药和包扎用品都还干燥。你收好物资，该回到幸存者身旁了。", ["reach"], {"quest_item": "c3:aid", "prompt": "接应急救匣半陷在泥里，外面裹着一层油布。", "rules": "这份急救物资作为任务物件保存，不占普通背包，也不消耗随身药品。"}),
				_action("rescue", "c3:survivor", "沼泽幸存者", "rescue", "为幸存者包扎", "伤处包好后，幸存者终于能稳稳握住行囊。\n「我认得这两份路书。不是谁画错了……给我一点工夫，我把经过说清楚。」", ["aid"], {"prompt": "幸存者伸出受伤的手，目光仍没离开行囊。\n「多谢。包扎好，我就能继续留在这里等人。」"})]),
			_step("未完成的回信", "听幸存者说明来历，取未完成的回信并接通沼泽联络灯。", [
				_action("account", "c3:survivor", "沼泽幸存者", "talk", "听行囊的来历", "「头一回，我们走浅滩。后来路断了，第二次才绕外缘。」幸存者低下头。\n「回信写了一半，就再没送出去。有人去了丘陵，我却一直没告诉那边：接应点还有人。」", [], {"prompt": "幸存者把两份路书并在一起。\n「你一定想问，为什么同一个行囊里，会有两条相反的路。」", "questions": [{"label": "远征队都失踪了吗？", "answer": "「没有。至少分开的时候没有。后来谁到了哪里，我只敢说我亲眼见过的。」"}, {"label": "为什么留下来？", "answer": "「信还没送出去。要是我也走了，再有人回来，就真找不到人了。」"}]}),
				_action("reply", "c3:reply_record", "未完成的回信", "recover", "收起未完成的回信", "回信的收信人是丘陵的遗迹学者，页边附着绞盘草图。\n「若档案还在，请替我们留下分队的去向。」最后半句停在这里。", ["account"], {"quest_item": "c3:reply", "prompt": "未完成的回信搁在接应点。幸存者点点头，示意你带走它。"}),
				_action("beacon", "c3:beacon", "沼泽联络灯", "repair", "接通联络灯", "沼泽联络灯亮起。幸存者把丘陵接近点标在你的路书上。\n「把信带给学者吧。告诉他，这一头终于又有人回话了。」", ["reply"], {"service": "swamp_station", "next_chapter": "watch_c4_hill", "prompt": "沼泽联络灯蒙着水汽，最后一处接头还断着。幸存者守在接应点，等这里重新亮起来。"})])]),
		_chapter("watch_c4_hill", "丘陵封关", "hill", 4, [
			_step("封门者的名册", "与遗迹学者交谈，阅读旧驻守名册。", [
				_action("scholar", "c4:scholar", "遗迹学者", "talk", "询问封门者", "学者认出回信上的笔迹，把纸页抚平。\n「他们还活着。好……先看旧驻守名册。封存档案的人留了名字，我们得知道他想替谁保住这些纸。」", [], {"prompt": "遗迹学者伸手接近那封回信，又停住。\n「这是从沼泽带来的？让我看看署名。」", "questions": [{"label": "城塞的门封了？", "answer": "「南门能走。封住的是档案附室，绞盘断了，里面的东西一直没能取出。」"}, {"label": "你在等这封信？", "answer": "「我等的是他们的下落。纸页晚到一些，总比只剩猜测好。」"}]}),
				_action("roster", "c4:roster", "旧驻守名册", "read", "读旧驻守名册", "旧驻守名册里有回信的署名，也有地图保管员的名字。封存一栏写着：「留下去向，等后来的人。」\n旁边画了绞盘缺失的齿轮和轴销。", ["scholar"], {"prompt": "旧驻守名册摊在石台上。几行姓名旁画着去向箭头，封存一栏另有人签字。", "rules": "剧情档案由绞盘与现场通路解锁，不需要银钥匙；城塞宝箱仍使用原来的钥匙规则。"})]),
			_step("断开的绞盘", "取绞盘零件，装好断开的绞盘，打开档案附室入口。", [
				_action("parts", "c4:winch_parts", "绞盘零件", "recover", "取绞盘零件", "齿轮和轴销还在。你收齐绞盘零件，照名册上的草图便能装回断开的绞盘。", [], {"quest_item": "c4:winch_parts", "prompt": "绞盘零件散放在旧包布里。齿轮上磨亮的缺口，与草图标记正好对得上。"}),
				_action("winch", "c4:winch", "断开的绞盘", "repair", "安装并拉动绞盘", "轴销归位，绞盘重新咬合。你用力拉动，档案附室入口的栅门缓缓升起。\n接下来得去城塞南门观测点，看看能怎样接近档案。", ["parts"], {"opens": "c4:archive_gate", "prompt": "断开的绞盘垂着松弛的绳索。带来的齿轮和轴销正好补上空位。"})]),
			_step("牛头王的城塞", "勘察牛头王城塞，选择讨伐、西侧绕行或空城调查，取封关档案。", [
				_action("fortress", "c4:fortress_record", "城塞南门观测点", "read", "核对城塞现状", "城塞南门旁的旧图标出了封关档案的位置。正面靠近要面对仍在城里的牛头王；西侧绕行绞盘能打开另一条通路。\n若城塞已经空了，就把眼前的情况如实记下。", [], {"prompt": "从城塞南门观测点可以辨认通往档案的方向。先查看现状，别只凭旧图闯进去。", "rules": "可凭本人击败本城塞牛头王的记录、现场西侧绕行，或当前无活体的空城调查接近档案。绕行和空城调查不计作击杀。"}),
				_action("passage", "c4:bypass_control", "西侧绕行绞盘", "encounter", "确认接近方式", "你记下这次接近城塞的经过。通往封关档案的入口就在前方，纸页仍等着被带出来。", ["fortress"], {"boss_species": "牛头王", "choices": ["defeated", "bypass", "absent"], "opens": "c4:archive_gate", "prompt": "封关档案就在城塞另一侧。西侧绕行绞盘可以打开侧路；若走正面，先确认牛头王已经不再挡路。", "rules": "绕行、本人讨伐与空城调查分别记录，不能互相替代击杀功劳。牛头王后续复生不会撤销本次修复或重复发奖。"}),
				_action("archive", "c4:archive", "封关档案", "recover", "取封关档案", "封关档案记着第二次分队：一部分人留下维护通路，另一部分人带总图去了雪原。\n地图保管员在页边留了一句：「若后来者到了，把坐标交给他。」", ["passage"], {"quest_item": "c4:archive", "prompt": "封关档案的封皮落满灰尘。里面夹着与沼泽回信相同格式的路线页。"})]),
			_step("第二次分队", "帮助地图保管员，取第二次分队的坐标，修复丘陵接应信标。", [
				_action("keeper", "c4:map_keeper", "负伤的地图保管员", "talk", "扶起地图保管员", "你扶稳地图保管员，替他收拢脚边的散页。\n「这张别折，坐标就在折痕旁。队长最后从冰封祭坛附近回信……把第二次分队的坐标带上，替我去看看。」", [], {"prompt": "地图保管员一手扶墙，一手护着散落的地图。\n「先帮我把纸收起来。别踩，那是他们走过的路。」", "questions": [{"label": "你不一起去吗？", "answer": "「这些图得有人保管。我能守住这里，你把下一段路带回来就好。」"}]}),
				_action("coordinates", "c4:snow_coordinates", "第二次分队的坐标", "recover", "取第二次分队的坐标", "第二次分队的坐标圈出雪原冰封祭坛旁的接近点。队长的回信到这里为止，再往后的路还没有人补上。", ["keeper"], {"quest_item": "c4:snow_coordinates", "prompt": "坐标页边缘卷起，墨线却还清楚。页边画着一个箭头，指向雪原那一处。"}),
				_action("beacon", "c4:beacon", "丘陵接应信标", "repair", "修复丘陵接应信标", "丘陵接应信标亮起，映着保管员摊开的地图。\n「往雪原去吧。若找到队长，告诉他，留下的路还没全断。」", ["coordinates"], {"service": "hill_station", "next_chapter": "watch_c5_snow", "prompt": "丘陵接应信标的接头已经露出。接通信号后，这里便有人照看返程的路。"})])]),
		_chapter("watch_c5_snow", "雪原回声", "snow", 5, [
			_step("冰封祭坛", "读冰封祭坛刻文，打碎冰障，取祭坛内的石版。", [
				_action("altar", "c5:altar_record", "冰封祭坛刻文", "read", "读冰封祭坛刻文", "冰封祭坛刻文写着：「后来的人，请从薄冰处取石版。若我还在，沿背面的接应记号来找。」\n封住祭坛的冰障有一道裂纹，可以用攻击打出缺口。", [], {"prompt": "祭坛刻文被积雪遮住一半。有人在最后一行刻得很深，像是怕后来的人看漏。"}),
				_action("ice", "c5:ice_barrier", "封住祭坛的冰障", "obstacle", "查看冰障缺口", "碎冰落下，祭坛内的石版露了出来。缺口已经能够通行。", ["altar"], {"prompt": "封住祭坛的冰障横在面前。先打碎这处薄冰，再从缺口进去。"}),
				_action("tablet", "c5:tablet", "祭坛内的石版", "recover", "取祭坛内的石版", "石版背面刻着远征队长的接应记号，箭头朝向避风处。最后一笔没有刻完。", ["ice"], {"quest_item": "c5:tablet", "prompt": "祭坛内的石版覆着一层雪。背面似乎还有一组接应记号。"})]),
			_step("雪下的守望", "找到队长，取雪地急救匣物资，返回他身旁救助。", [
				_action("leader", "c5:leader", "受伤的远征队长", "talk", "查看队长状况", "队长想接过石版，手却抬不起来。\n「是我留的。雪地急救匣在冰脊那边……先劳你取来。那些路书，我会解释。」", [], {"prompt": "远征队长靠在避风处，听见脚步才睁开眼。\n「还有人找到这里。其他站点……先别说，让我缓一缓。」", "questions": [{"label": "你在这里等什么？", "answer": "「等一个能把消息带回去的人。命令是我下的，不能只留下两本说不清的日志。」"}]}),
				_action("aid", "c5:aid_cache", "雪地急救匣", "recover", "取雪地急救物资", "雪地急救匣的封口还完好。你取出药包，里面的绷带没有受潮。队长就在避风处等你。", ["leader"], {"quest_item": "c5:aid", "prompt": "雪地急救匣埋在浅雪里，露出的扣环上结了霜。", "rules": "雪地急救物资作为任务物件保存；救助队长不会扣除普通背包或快捷补给。"}),
				_action("rescue", "c5:leader", "受伤的远征队长", "rescue", "救助队长", "包扎结束，队长终于能坐直。\n「撤守令是我签的。当时只想先把人保住，没想到灯会一盏盏断掉。两份日志都在，别只听我一句话。」", ["aid"], {"prompt": "队长把伤处挪到光里，示意你动手。\n「你都走到这里了，我没理由再瞒着。」"})]),
			_step("相互矛盾的日志", "读撤守日志和分队路书，在核对板按先后排列三份记录。", [
				_action("withdrawal", "c5:withdrawal_log", "撤守日志", "read", "读撤守日志", "撤守日志写着：「分队之后，各处仍尝试维持旧站点。人手再也顾不过来，准予撤守。」\n命令后面，是队长的签名。", [], {"prompt": "撤守日志翻开在签名页。墨迹比前面的巡线记录更重。"}),
				_action("route_log", "c5:route_log", "分队路书", "read", "读分队路书", "分队路书最后补记：「撤守令送到后，联络设备接连失效，此后各站失联。」\n这页补记写下的是撤守之后发生的事。", [], {"prompt": "分队路书上满是路线，最后几行却只剩联络记录。"}),
				_action("causality", "c5:evidence_board", "失联经过核对板", "puzzle", "排列因果记录", "丘陵档案、撤守日志与分队路书终于接上了：先分队，再撤守，最后失联。\n队长看着排好的纸页，没有辩解。「这一次，不能再叫人独自守着一盏会灭的灯。」", ["withdrawal", "route_log"], {"puzzle_order": ["split", "withdrawal", "lost"], "prompt": "把丘陵档案和两份日志按先后放上核对板：分队之后下达撤守令，撤守之后各站才失联。", "rules": "正确顺序：分队→撤守→失联。排错只重置未完成的排列，不消耗日志。"})]),
			_step("最后的坐标", "听队长的打算，取最后的坐标，接通雪原联络灯。", [
				_action("plans", "c5:leader", "受伤的远征队长", "talk", "听队长的打算", "「世界之心能重新连通这些灯。」队长把手按在路书上。\n「可灯还得有人守。留下各站，就让彼此隔着远路接应；把人接到一处，长路上便少几个守候的人。等中枢亮了，这件事交给你决定。」", [], {"prompt": "队长看了很久那些重新接上的路线。\n「还有最后一处，熔岩城塞里的世界之心。我得先告诉你，它能做什么。」", "questions": [{"label": "世界之心能救回所有人吗？", "answer": "「它能让活着的人重新听见彼此。过去失去的，灯带不回来；此后的路，仍要人一步步守。」"}, {"label": "去熔岩前要准备什么？", "answer": "「回营检查装备，把补给带足。龟王若还在，这一趟就得真刀真枪闯过去。别为了赶路把命押上。」"}], "rules": "熔岩出发建议：Lv6或等效构筑，先强化装备并备足补给。只赶主线可能仍为Lv3；在场的熔岩龟王必须击败。"}),
				_action("coordinates", "c5:lava_coordinates", "最后的坐标", "recover", "取最后的坐标", "最后的坐标指向熔岩城塞外的接近点，旁边抄着中枢口诀：「西侧撤守，东侧接应，中央信号。」\n先让人撤出来，再有人接住，最后才让消息传出去。", ["plans"], {"quest_item": "c5:lava_coordinates", "prompt": "最后的坐标压在路书底下。纸背还有三句简短的中枢操作口诀。"}),
				_action("beacon", "c5:beacon", "雪原联络灯", "repair", "接通雪原联络灯", "雪原联络灯亮起，来路终于又有了回应。\n队长望向熔岩的方向。「我留在这里。你回来时，总该先有个人听见。」", ["coordinates"], {"service": "snow_station", "next_chapter": "watch_c6_lava", "prompt": "雪原联络灯还连着旧线。接通信号，留在避风处的队长就能照看这一头。"})])]),
		_chapter("watch_c6_lava", "熔火之心", "lava", 6, [
			_step("熔河之间", "读熔河边界警示，沿石脊抵达避灼通路标记。", [
				_action("hazard", "c6:hazard_record", "熔河边界警示", "read", "读熔河边界警示", "熔河边界警示上写着：「沿石脊走。熔流能踏进去，却会持续烧伤人。」\n旁边的箭头指向避灼通路标记。", [], {"prompt": "灼热的风卷过警示牌，字迹被熏黑了一半。出发的人在牌角补了一行提醒。", "rules": "踏入熔岩会持续受伤。竹水壶只能恢复魔力，不能提供熔岩免疫。"}),
				_action("approach", "c6:route_approach", "避灼通路标记", "observe", "查看避灼通路", "你走到避灼通路标记旁。石脊延向城塞外围，熔流从两边绕过。\n先到龟王城塞观测点看看，队长留下的路还通向哪里。", ["hazard"], {"prompt": "避灼通路标记立在石脊上，城塞的轮廓已经能看清。"})]),
			_step("龟王盘踞之地", "勘察龟王城塞，击败在场龟王或核实空城，取中枢留存记录。", [
				_action("fortress", "c6:fortress_record", "龟王城塞观测点", "read", "核对龟王现状", "城塞外的记录标出了中枢安全锁与中枢留存记录的位置。\n龟王若还盘踞这里，就得先击败它；若城中已无龟王，查清现场便可继续。", [], {"prompt": "龟王城塞观测点留下了一张烧焦的草图。通往中枢的路从城塞穿过，没有另画侧路。", "rules": "活体熔岩龟王在场时必须完成本人讨伐；当前确无活体时可现场调查。不要求等待复生，也不需要金钥匙。"}),
				_action("passage", "c6:bypass_control", "中枢安全锁", "encounter", "确认中枢通路", "你把城塞中的经过记下，中枢通路已经可以继续前行。中枢留存记录就在里面。", ["fortress"], {"boss_species": "熔岩龟王", "choices": ["defeated", "absent"], "opens": "c6:core_gate", "prompt": "中枢安全锁仍扣着通道。先确认熔岩龟王已被你击败，或城塞眼下确实空着，再往里走。", "rules": "只有本人造成的死亡计作讨伐；空城调查单独记录。Boss复生不撤销本次通路、主线进度或支付收据。"}),
				_action("core_record", "c6:core_record", "中枢留存记录", "recover", "取中枢留存记录", "中枢留存记录写着：「先西侧撤守，再东侧接应，最后中央信号。」\n西→东→中。沿途读过的那些离散与接应，成了这座中枢的次序。", ["passage"], {"quest_item": "c6:core_record", "prompt": "中枢留存记录被压在石台上。操作图的三条线，分别通往西、东、中央回路。"})]),
			_step("世界之心", "按西→东→中操作回路，再启动世界之心。", [
				_action("core_order", "c6:heart", "世界之心", "puzzle", "核对中枢次序", "西侧撤守回路亮起，东侧接应回路随之接通，中央信号终于回应。\n世界之心已经就绪，等你启动。", [], {"puzzle_order": ["west", "east", "center"], "puzzle_objects": ["c6:core_west", "c6:core_east", "c6:core_center"], "prompt": "世界之心还没有亮。按中枢留存记录所写，依次操作西、东、中央回路。", "rules": "中枢回路顺序：西→东→中。完成回路后，仍需在世界之心旁确认启动。"}),
				_action("activate", "c6:heart", "世界之心", "repair", "启动世界之心", "世界之心亮起，沿途修复的灯重新连在了一起。\n那些还在站点等候的人，终于有了可以传回消息的路。现在，该决定他们往后在哪里守望了。", ["core_order"], {"service": "heart_station", "prompt": "中央信号已经接通，世界之心发出低沉的回声。启动它，就能把沿途修复的站点连起来。", "rules": "世界之心恢复站点联络，不复活灭绝物种，不改变野外种群、巢穴或迁徙。"})]),
			_step("此后的道路", "选择四人的派驻方式，在熔岩接应信标旁落实安排。", [
				_action("ending", "c6:ending_council", "此后道路的议事桌", "choice", "决定此后的道路", "你在议事桌上留下派驻安排。下一步，把这份安排记在熔岩接应信标的名册里，让等候的人知道该往哪里去。", [], {"choices": [{"id": "distributed", "title": "分散派驻"}, {"id": "centralized", "title": "集中安置"}], "prompt": "联络员、沼泽幸存者、地图保管员和队长，都等着这份安排。\n让四人各守林地、沼泽、丘陵、雪原，远路上就各有接应；让四人回到平原避难所，便能聚在一起照应彼此。", "rules": "分散派驻：四人分别驻留林地、沼泽、丘陵、雪原并提供补给。集中安置：四人迁到平原避难所，补给集中。确认后保留所选安排；旧检查点、回城和第一章前哨巡守不变。"}),
				_action("settle", "c6:beacon", "熔岩接应信标", "repair", "落实派驻安排", "派驻安排写进名册，经熔岩接应信标传向各处。\n从前哨开始，你找到了仍在等候的人，也把他们留下的话带到了下一站。此后的道路，终于不必只靠沉默的旧坐标相连。", ["ending"], {"service": "ending_station", "ending": true, "prompt": "熔岩接应信标旁摊着最后的名册。将选好的派驻安排写下，消息就可以发出去了。"})])]),

	]

static func side_chains() -> Array:
	if not _groups.has("side_chains"): _groups["side_chains"] = _seal(_side_chains())
	return _groups["side_chains"]

static func _side_chains() -> Array:
	return [

		_chain("side_patrol", "旧巡逻队", "plains", "side", 1, [
			_step("旧巡逻队的徽记", "询问接替者，读巡逻名册，在旧歇脚处回收身份徽记。", [
				_action("request", "side_patrol:giver", "新巡守", "talk", "听巡守的请求", "他们把旧队的差事交给我，却没人说起那些人的名字。能帮我看看旧名册吗？歇脚处还留着他们的徽记。", [], {"prompt": "新巡守把一枚空扣翻来覆去地看，见你停下，才提起旧巡逻队。", "questions": [{"label": "为什么在意他们的名字？", "answer": "空缺可以补上，人却不该只剩一个空缺。我想知道自己接的是谁的班。"}]}),
				_action("record", "side_patrol:record", "旧巡逻名册", "read", "核对姓名", "名册末尾写着：留下接应。旁边的徽记纹样与你要找的那枚一致，离开的日期却空着。", ["request"], {"prompt": "名册最后几页磨得发薄。翻到旧队换岗的那一天。"}),
				_action("badge", "side_patrol:target", "遗留的身份徽记", "recover", "回收徽记", "徽记背面的刻字与名册一一相合。你收好它，这回能带给新巡守几个确切的名字。", ["record"], {"quest_item": "side_patrol:badge", "prompt": "旧歇脚处压着一枚徽记。拂去尘土，核对背面的刻字。"})]),
			_step("新巡守的归处", "选择新增巡守驻地，亲自在选定站点安放徽记。", [
				_action("station", "side_patrol:resolution", "巡守驻地名册", "choice", "选择巡守驻地", "新巡守在你选定的驻地旁落了笔：好，就去那里。把徽记挂上，我们便接下这一班。", [], {"choices": [{"id": "camp", "title": "营地接应", "consequence": "新巡守驻在营地，接应初来者并提供驻站补给", "risk": "到营地驻守点安放徽记后生效"}, {"id": "forest", "title": "林地联络", "consequence": "新巡守驻在林地，协助联络并提供驻站补给", "risk": "到林地驻守点安放徽记后生效"}], "rules": "选定后到对应驻地安放徽记。第一章原前哨巡守不迁移。", "prompt": "新巡守合上名册：营地需要接应，林地需要联络。让我接哪一班？"}),
				_action("settle", "side_patrol:station_camp", "营地驻守点", "repair", "安放徽记并驻守", "徽记挂上了站点的木架。新巡守摸了摸刻字：我会在这里接下这一班。歇会儿吧，给你留了一份补给。", ["station"], {"destination_by_choice": {"camp": "side_patrol:station_camp", "forest": "side_patrol:station_forest"}, "service": "patrol_station", "prompt": "把徽记挂在选定驻地，让来往的人认得新的巡守。", "rules": "选定驻地提供商店和一次驻站补给；补给不会重复领取。"})])]),
		_chain("side_herbalist", "一份两用的药", "forest", "side", 2, [
			_step("学徒留下的记录", "听草药师说明失散学徒的去向，取回实际药物用途记录。", [
				_action("request", "side_herbalist:giver", "草药师", "talk", "询问学徒", "学徒把药封好了，偏偏没带回用途记录。我不敢只凭记性让人服下。替我找回那页纸，先弄清这药留给了谁。", [], {"prompt": "草药师按着一张缺页的药单。听听他在担心什么。", "questions": [{"label": "不能再配一包吗？", "answer": "手头只有学徒封好的这一包。先找到用途记录，我才敢把它交出去。"}]}),
				_action("record", "side_herbalist:record", "学徒用途记录", "read", "辨读用途记录", "学徒写道：伤者等着用药，站里的储备也空了。纸上圈了又圈，终究只封好这一包。", ["request"], {"prompt": "用途记录上有两处圈记。展开纸页，看看学徒留下的话。"}),
				_action("medicine", "side_herbalist:medicine", "学徒封存药包", "recover", "收好封存药包", "药包的封条还完整。纸上的两处圈记有了分量：这包药带走后，只能送往一个地方。", ["record"], {"quest_item": "side_herbalist:medicine", "prompt": "药包还放在封存处。核对封条，收好它。", "rules": "专用药包独立保存；交付一次后消耗，不进入可出售库存。"})]),
			_step("一份两用的药", "决定药包用于当前伤者还是站点储备，亲自完成唯一交付。", [
				_action("purpose", "side_herbalist:resolution", "药包用途牌", "choice", "决定药包用途", "用途牌上留下了你的选择。草药师收起笔：带上这一包药，去交给你选的那一边吧。", [], {"choices": [{"id": "patient", "title": "救助伤者", "consequence": "这一包药用于救助眼前伤者", "risk": "消耗唯一药包；储备站本次不开放补给"}, {"id": "reserve", "title": "留作站点储备", "consequence": "这一包药送入站点储备，恢复驻站补给", "risk": "消耗唯一药包；眼前伤者本次未获救助"}], "rules": "伤者分支完成救助；储备分支恢复站点补给。两者只能选一，须到选定地点交付。", "prompt": "用途牌上两处圈记都还在：把药送给眼前伤者，还是留给站点作储备？"}),
				_action("deliver", "side_herbalist:patient", "等待药包的伤者", "deliver", "交付这一份药", "药包交到了你选定的人手里。封条被拆下收好，另一边的圈记仍留在药单上。", ["purpose"], {"destination_by_choice": {"patient": "side_herbalist:patient", "reserve": "side_herbalist:station_reserve"}, "consumes": "side_herbalist:medicine", "service": "herbalist_reserve", "service_choices": ["reserve"], "prompt": "把这一包药亲手交到选定去处。", "rules": "药包只消耗一次。选择伤者不会开放储备站服务。"})])]),
		_chain("side_hunter", "收起的悬赏", "plains", "side", 3, [
			_step("昨日的猎数", "对照猎人旧账、现场足迹和真实生态记录，分清死亡来源。", [
				_action("request", "side_hunter:giver", "营地猎人", "talk", "听猎人质疑", "旧账上还有那么多，眼前却连脚印都稀了。别急着拔刀。帮我对一遍猎数，看看我们究竟漏了什么。", [], {"prompt": "猎人把悬赏压在账本下面，没有递给你。听他说明疑处。", "questions": [{"label": "你怀疑旧账写错了？", "answer": "我怀疑的是拿昨天的数目，去替今天下判断。脚印少了，总得弄清缘由。"}]}),
				_action("book", "side_hunter:record", "昨日猎数账", "read", "读旧猎数", "旧账逐笔记着过去的猎数，后面的空白没有解释那些减少。要知道今日还剩什么，只能到猎场去看。", ["request"], {"prompt": "账页上的数目改过几次。看看哪些有日期，哪些只剩空白。"}),
				_action("survey", "side_hunter:target", "猎场足迹核对点", "observe", "辨认猎场足迹", "脚印、眼前的活物，还有这段时间发生的死亡，都已分开记下。猎人那张旧悬赏，需要重新掂量。", ["book"], {"ecology_mode": "hunter_counts", "prompt": "停在足迹旁，核对眼前活动与这段观察期间的变化。", "rules": "观察只覆盖保存的事件窗口；未知迁出去向不推断为死亡。"})]),
			_step("收起的悬赏", "根据现在的族群状态，作有限本地处理或亲自立下路线警示。", [
				_action("choice", "side_hunter:resolution", "猎人的新决定", "choice", "决定如何收尾", "猎人按你的意思改好了安排：就这么办。去现场做完，再把情况记下来。", [], {"choices": [{"id": "local", "title": "核实后有限处理", "consequence": "只处理一只符合条件的当地目标，并保留族群余量", "risk": "需现场目标仍可行；目标变化时回现场复查"}, {"id": "warning", "title": "收起悬赏并警示", "consequence": "收起悬赏，在旧猎场立下绕行警示", "risk": "无需猎杀；仍须亲自到警示牌处完成"}], "rules": "有限处理须有可达、战力合适且余量足够的现场目标；警示无需猎杀。", "prompt": "猎人把新决定留给你：附近若还有余量，就只处理一只；也可以收起悬赏，立块绕行警示。"}),
				_action("result", "side_hunter:warning_sign", "旧猎场警示牌", "ecology", "回报猎场情况", "猎人看完你带回的结果，把旧悬赏折了起来：往后经过这里的人，至少该知道眼前是什么样。", ["choice"], {"destination_by_choice": {"local": "side_hunter:target", "warning": "side_hunter:warning_sign"}, "ecology_mode": "hunter_resolution", "prompt": "按选定的办法处理猎场，再把看到的变化记在这里。", "rules": "猎杀只认本次真实贡献；目标减少或离开时按当前事实完成调查，不补造怪物。"})])]),
		_chain("side_scholar", "缺失的拓印", "hill", "side", 4, [
			_step("缺失的拓印", "听学者说明缺口，在遗迹原处核对并回收遗失拓印。", [
				_action("request", "side_scholar:giver", "拓印学者", "talk", "询问拓印缺口", "这页拓印少了一角，偏偏是旧道用途的那一行。我不想凭空补字。原碑还在，遗失的拓印也许就在旁边。", [], {"prompt": "学者把缺角朝向光，示意你看那一行断字。", "questions": [{"label": "为什么一定要找原件？", "answer": "猜对一个字不难，错一个字也不难。难的是后来的人会把它当成真的。"}]}),
				_action("inscription", "side_scholar:record", "旧道铭文", "read", "核对原铭文", "铭文压着一枚尚能使用的机关件。想取它开近道，就得让这段字永远缺一角。", ["request"], {"prompt": "贴近原碑，沿拓印缺失的位置查找。"}),
				_action("rubbing", "side_scholar:target", "遗失的拓印", "recover", "收回拓印", "纸上的断笔与原碑吻合。拓印找回了，留下碑文还是取走部件，这回可以想清楚再决定。", ["inscription"], {"quest_item": "side_scholar:rubbing", "prompt": "石边露出卷起的纸角。小心取回，和原碑对照。"})]),
			_step("原样还是拆取", "选择保留铭文或拆取机关件，并在现场落实相应结果。", [
				_action("choice", "side_scholar:resolution", "铭文处置案", "choice", "决定铭文去留", "学者记下你的决定，向旧道望了一眼：想清楚了，就去原处动手吧。", [], {"choices": [{"id": "preserve", "title": "原样保留并补记", "consequence": "保留原铭文，补齐学者记录", "risk": "本次不会用碑下部件打开近道"}, {"id": "component", "title": "拆取部件开近道", "consequence": "拆取机关件，打开旧近道", "risk": "原铭文会留下缺口；须到机关门处安装"}], "rules": "保留分支补记铭文；拆取分支打开局部近道并留下铭文缺口。", "prompt": "学者的手停在碑文缺角旁：保住这些字，还是取下机关件，让旧近道重新开通？"}),
				_action("resolve", "side_scholar:record", "旧道铭文", "repair", "落实现场处置", "你的选择在旧道留下了痕迹。此后经过这里的人，会看见被保留的字，或那条重新打开的近道。", ["choice"], {"destination_by_choice": {"preserve": "side_scholar:record", "component": "side_scholar:shortcut_gate"}, "opens_choice": {"component": "side_scholar:shortcut_gate"}, "prompt": "在选定位置完成处置：补记铭文，或装好取出的机关件。"})])]),
		_chain("side_merchant", "落下的货箱", "swamp", "side", 5, [
			_step("落下的货箱", "问清货箱编号，核对运单，再到真实落箱处回收。", [
				_action("request", "side_merchant:giver", "赶路的行商", "talk", "询问失落货物", "那只箱子陷在泥岸，我拖不动。两处站点都在等货，我却只带了这一箱。先替我找回运单，别连该送去哪儿都弄错。", [], {"prompt": "行商鞋边的泥还没干。他指着湿透的运单，欲言又止。", "questions": [{"label": "两边都在等这一箱？", "answer": "是啊。运单写得满满的，箱子却只有这一只。近处不能不管，远处也不能装作没看见。"}]}),
				_action("waybill", "side_merchant:record", "湿透的运单", "read", "核对货箱编号", "运单上列着近路和外缘两处需求，箱号却始终只有一个。水渍没能替行商划掉任何一边。", ["request"], {"prompt": "摊开湿运单，辨清箱号与两处去向。"}),
				_action("crate", "side_merchant:crate", "落下的封存货箱", "recover", "回收货箱", "泥岸里的封箱与运单吻合。箱盖还牢靠，货物可以送走了。", ["waybill"], {"quest_item": "side_merchant:crate", "prompt": "检查泥岸货箱上的封签，确认后把它带上。", "rules": "封箱是独立任务物资，不进入通用背包，也不会再次生成。"})]),
			_step("这一箱送往哪里", "选定一个补给站，将唯一的封箱送到其真实站点。", [
				_action("destination", "side_merchant:resolution", "补给去向板", "choice", "选择收货站", "行商把你选的站点圈了出来：就送这边。货箱交到收货台，这一趟才算有着落。", [], {"choices": [{"id": "near", "title": "近路补给站", "consequence": "把唯一货箱送往近路，恢复近路补给站", "risk": "外缘站不会收到这箱物资"}, {"id": "outer", "title": "外缘补给站", "consequence": "把唯一货箱送往外缘，恢复外缘补给站", "risk": "近路站不会收到这箱物资"}], "rules": "仅选定站点恢复服务；须到该站亲手交付唯一货箱。", "prompt": "行商望着一箱货、两处去向：送近路，好来往；送外缘，能接住更远的人。你选哪处？"}),
				_action("deliver", "side_merchant:station_near", "近路收货台", "deliver", "交付封存货箱", "收货人在箱号旁签了字，开始把物资摆上补给台。行商终于不用再抱着那张运单踌躇。", ["destination"], {"destination_by_choice": {"near": "side_merchant:station_near", "outer": "side_merchant:station_outer"}, "consumes": "side_merchant:crate", "service": "merchant_station", "prompt": "把封箱送上选定站点的收货台。", "rules": "一次补给由选定站点提供；另一站未收到此箱。"})])]),
		_chain("side_watchman", "看不见的旗", "hill", "side", 6, [
			_step("看不见的旗", "读瞭望者值守记录，亲自调查被山脊遮住的视线路径。", [
				_action("request", "side_watchman:giver", "瞭望者", "talk", "询问失去的信号", "低处的旗看不见了。也许倒了，也许只是岩脊挡住。劳你走近看看，我不想凭这点影子就报一场袭击。", [], {"prompt": "瞭望者眯着眼看向低处，手停在尚未写完的值守记录上。", "questions": [{"label": "看不见旗，意味着什么？", "answer": "只意味着我这儿看不见。旗倒了、路被遮了，都得走过去才能知道。"}]}),
				_action("record", "side_watchman:record", "值守视线草图", "read", "读视线草图", "草图中，旧旗与望台之间横着一段岩脊。近处好维护，高处能望向另一条来路。", ["request"], {"prompt": "顺着草图上的视线，辨认旧旗和岩脊的位置。"}),
				_action("sight", "side_watchman:target", "旧旗视线核对点", "observe", "调查视线路径", "站到旧旗一侧，遮挡与开阔处才看得清楚。换个旗位，比在望台上猜更有用。", ["record"], {"ecology_mode": "watch_sight", "prompt": "从旧旗旁望向岩脊，看看信号会被哪里遮住。"})]),
			_step("换岗之前", "选择近处或高处旗位，亲自立起新旗并完成换岗记录。", [
				_action("choice", "side_watchman:resolution", "新旗位置图", "choice", "选择新旗位", "新旗的位置定下来了。瞭望者把草图交给你：去把旗立起来，我在这里等信号。", [], {"choices": [{"id": "near", "title": "近处守望位", "consequence": "近处新旗指向丘陵接近点，便于维护", "risk": "只有粗略方位；仍需亲自查看沿途情况"}, {"id": "high", "title": "高处守望位", "consequence": "高处新旗指向岩脊旧道另一端", "risk": "只有粗略方位；仍需亲自查看沿途情况"}], "rules": "近处旗指向丘陵接近点；高处旗指向岩脊旧道另一端。仅提供方向线索。", "prompt": "瞭望者摊开新图：近处容易照看，高处朝着另一条来路。这面旗立在哪边？"}),
				_action("flag", "side_watchman:watch_near", "近处新旗位", "repair", "竖起新信号旗", "新旗在选定的位置展开。瞭望者留下了新的方向说明，旧草图终于可以收起来。", ["choice"], {"destination_by_choice": {"near": "side_watchman:watch_near", "high": "side_watchman:watch_high"}, "service": "watchman_station", "prompt": "在选定位置竖好旗杆，重新标出可辨认的方向。", "rules": "方向说明不显示未知远方活体，也不保证沿途安全。"})])]),
		_chain("side_letter", "冻结的信筒", "snow", "side", 7, [
			_step("冻结的信筒", "从留下的收信记录辨认信筒，亲自取出仍封存的信件。", [
				_action("request", "side_letter:giver", "守信人", "talk", "询问无人取走的信", "信筒冻住很久了，我一直没拆。写信的人走了，可等信的人还没收到。替我看看登记，别把它交错了。", [], {"prompt": "守信人拂开信筒上的雪，露出一角署名。", "questions": [{"label": "为什么一直没拆？", "answer": "那上面写的不是我的名字。我能替他守着，不能替他读完。"}]}),
				_action("record", "side_letter:record", "收信登记", "read", "核对信筒署名", "登记上的署名与信筒相同。信该交给那位旧队员，回不回、怎么回，都留给他。", ["request"], {"prompt": "翻开收信登记，核对筒口的署名。"}),
				_action("case", "side_letter:letter_case", "冻结的信筒", "recover", "取出密封信件", "筒口的积雪被拂去，密封的信完整取出。署名仍清楚，接下来该去找收信的人了。", ["record"], {"quest_item": "side_letter:letter", "prompt": "打开冻结的信筒，收好里面尚未拆封的信。", "rules": "信件独立保存，不会出售；亲手交付后消耗。"})]),
			_step("收信的人", "找到真正的收件人，在他身旁交信，再听完他的回答。", [
				_action("recipient", "side_letter:recipient", "等信的旧队员", "talk", "确认收信身份", "旧队员看见封筒，先念出了登记上的署名：是给我的。我还以为……先让我看看吧。", [], {"prompt": "把署名给旧队员看，请他确认这封信是否写给自己。"}),
				_action("deliver", "side_letter:recipient", "等信的旧队员", "deliver", "把信交到手中", "他读了很久，才把信折回去：原来那时候，还有人记得我。谢谢你没有把它留在雪里。", ["recipient"], {"consumes": "side_letter:letter", "prompt": "把密封的信交到旧队员手中。"}),
				_action("reply", "side_letter:resolution", "收信后的回执", "read", "收好回执", "回执上写着：已经收到。笔迹停得很稳，余下的空白没有再添一句话。", ["deliver"], {"prompt": "收信后的回执放在一旁。看看旧队员留下了什么。", "rules": "同一封信与回执仅交付一次，存档继续不会重新寄送。"})])]),
		_chain("side_troll", "巨魔旧旗", "forest", "side", 8, [
			_step("巨魔旧旗", "核对旧人类旗记，调查真实巨魔王盘踞处附近的遗迹。", [
				_action("request", "side_troll:giver", "旧营地知情者", "talk", "听旧旗来历", "那面旗比巨魔王来得早。我们总盯着王，倒把旗下住过谁忘了。去看看旗背吧，那儿或许还认得回房间的路。", [], {"prompt": "知情者认出了褪色的旗，却没有先谈巨魔王。", "questions": [{"label": "一定要挑战巨魔王吗？", "answer": "先找房间吧。王拦不拦路是一回事，旗下的人留下什么，是另一回事。"}]}),
				_action("flag", "side_troll:record", "褪色的人类旗记", "read", "辨认旧旗", "旗背缝着三个小纹样：叶、石、灯。下方的针脚朝着旧房间，像给归来的人留的记号。", ["request"], {"prompt": "翻过褪色旧旗，辨认背面的缝线。"}),
				_action("site", "side_troll:target", "巨魔盘踞处旧遗迹", "observe", "调查当前遗迹", "旧人类遗迹就在盘踞处旁。王的踪迹要看眼前，房间的门却认那些旧符记。", ["flag"], {"ecology_mode": "troll_state", "prompt": "靠近遗迹，分别查看巨魔王的踪迹与旧房间入口。", "rules": "挑战巨魔王可选；没有活体目标也可继续调查房间，不等待或强制复生。"}),
				_action("challenge", "side_troll:target", "巨魔盘踞处旧遗迹", "boss", "记录自选挑战结果", "巨魔王倒下的经过已记下。你转身望向旧房间，那面旗里的问题还在那里。", ["site"], {"optional": true, "boss_species": "巨魔王", "prompt": "确认这次亲自挑战巨魔王的结果。", "rules": "仅认本次选择目标的玩家讨伐；可选挑战不阻塞房间调查，也不另发剧情奖励。"})]),
			_step("遗留的房间", "在房间外按叶、石、灯操作符记，开门后亲自取回记录。", [
				_action("runes", "side_troll:room_runes", "旧房间符记", "puzzle", "排列旧房间符记", "叶、石、灯依次亮起。门后的尘土动了一下，旧房间终于重新开向来路。", [], {"puzzle_order": ["leaf", "stone", "lamp"], "puzzle_objects": ["side_troll:rune_leaf", "side_troll:rune_stone", "side_troll:rune_lamp"], "opens": "side_troll:room_gate", "prompt": "依旧旗上的次序触碰叶、石、灯三枚符记。", "rules": "次序错误仅清除未完成输入；房间不需要巨魔王掉落物。"}),
				_action("record", "side_troll:room_record", "旧房间居住记录", "recover", "取回房间记录", "薄册列着曾在这里暂住的人，以及离开的日期。名字一页接着一页，旧旗终于有了它自己的故事。", ["runes"], {"quest_item": "side_troll:room_record", "prompt": "门内还留着一本居住薄册。进去取回它。"})])]),
	]

static func regional_arcs() -> Array:
	if not _groups.has("regional_arcs"): _groups["regional_arcs"] = _seal(_regional_arcs())
	return _groups["regional_arcs"]

static func _regional_arcs() -> Array:
	return [

		_chain("region_plains", "补给三角", "plains", "regional", 1, [
			_step("核对旧补给点", "分别核对旧近路仓与外缘接应处，确认两处实际用途。", [
				_action("near", "region_plains:survey_a", "旧近路仓", "read", "核对近路仓记录", "旧签上写着给新巡守备粮，货架如今空着。要让这里重新接住来人，得先把补给线找回来。", [], {"prompt": "查看近路仓的旧签和货架。"}),
				_action("outer", "region_plains:survey_b", "外缘接应处", "observe", "调查外缘接应处", "外缘接应处更远，却朝着另一条来路。站在这里，才明白旧图为何没有只画近路。", [], {"prompt": "走到外缘接应处，看看它照顾的是哪一条路。"})]),
			_step("集中或分散配置", "决定补给配置，带专用部件到选定工作点实际安装。", [
				_action("choice", "region_plains:choice", "补给配置图", "choice", "选择补给配置", "选定的补给线已在图上圈明。带上标识，去对应的工作点把这条线落到地上。", [], {"choices": [{"id": "near", "title": "集中近路", "consequence": "补给集中近路，完工后在接应站领取", "risk": "沿近路验收后开放；驻站饭团仅一份"}, {"id": "outer", "title": "分散外缘", "consequence": "补给分到外缘，完工后两处都可领取", "risk": "接应站与外缘台共享一份饭团，领一处即用完"}], "rules": "集中配置仅开放接应站；分散配置另开放外缘补给台，两处共享一份饭团库存。", "prompt": "补给图上，近路便于照料，外缘能多接一条来路。把补给集中一处，还是分开摆设？"}),
				_action("work", "region_plains:work_near", "近路补给支架", "repair", "安装补给标识", "补给标识固定下来，所选来路终于有了清楚的方向。沿着它走一遍，看看能否一直走到接应站。", ["choice"], {"destination_by_choice": {"near": "region_plains:work_near", "outer": "region_plains:work_outer"}, "prompt": "把标识装到选定的补给支架上。"})]),
			_step("三角中的一条路", "走完所选补给线，在接应站确认真实可用的服务。", [
				_action("walk", "region_plains:station", "补给三角接应站", "route", "验收补给线", "标识把你引到了接应站，沿途的转折都已走过。下一批赶路人可以认着这些记号找来。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_plains:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_plains:work_near", "region_plains:station"], "outer": ["region_plains:work_outer", "region_plains:station"]}, "prompt": "从所选工作点沿路标走到接应站，再核对这条路。"}),
				_action("station", "region_plains:station", "补给三角接应站", "repair", "启用接应服务", "接应站的补给台支起来了。来人可以在这里停一停，再看清下一段路。", ["walk"], {"service": "region_plains_station", "choice_stage": "region_plains:s2", "service_endpoints_by_choice": {"near": ["region_plains:station"], "outer": ["region_plains:station", "region_plains:work_outer"]}, "prompt": "安好接应站最后的标识，整理驻站补给。", "rules": "饭团仅一份。分散配置的两处领取点共用库存，领取一处后另一处不再补发。"})])]),
		_chain("region_forest", "树下边界", "forest", "regional", 2, [
			_step("巢区与来路", "分别调查真实巢区和行人来路，记录当前存在的冲突位置。", [
				_action("clue", "region_forest:guide", "林缘巡线员", "talk", "询问巢区旧路", "旧图上这处曾是巢址，我把能认出的路给你标上。今天还有没有住着东西，得请你走近看看。别只照着旧图下刀。", [], {"ecology_mode": "nest_clue", "prompt": "林缘巡线员摊开旧图，手指停在林下的一处记号上。"}),
				_action("nest", "region_forest:survey_a", "林下巢区调查点", "observe", "查看林下巢区", "巢址与眼前活动已核对过。旧图能带你找到这里，接下来怎么让路，还得看今天的情形。", ["clue"], {"ecology_mode": "nest_survey", "prompt": "靠近巢址，查看巢穴和周围是否仍有活动。"}),
				_action("trail", "region_forest:survey_b", "林间来路调查点", "observe", "核对来路", "行人的来路在林缘转开，和巢区并不完全重合。绕远一点，也许就能给两边留下空间。", [], {"prompt": "沿林间来路看看，哪里能绕开巢区。"})]),
			_step("暂时处理或绕行", "决定暂时处理真实巢穴，或在外缘建立可走的绕行标识。", [
				_action("choice", "region_forest:choice", "林下边界图", "choice", "选择处理方式", "处理办法写在了边界图上。去选定的地点动手，再看看这条路怎样接回树下。", [], {"choices": [{"id": "near", "title": "核实后暂时捣巢", "consequence": "暂时捣毁现场巢穴，再沿巢区路线验收", "risk": "巢穴仍可能重建；须先有可行的当地目标"}, {"id": "outer", "title": "标出林缘绕行", "consequence": "标出林缘绕行线，给来路和巢区留出空间", "risk": "无需猎杀；仍须沿外缘路线步行验收"}], "rules": "捣巢仅暂时抑制繁衍，要求可行现场目标；绕行无需猎杀。巢穴变化时须复查。", "prompt": "行人的路贴着巢区。暂时捣巢争取通行的空隙，还是沿林缘标一条绕行路？"}),
				_action("work", "region_forest:work_near", "巢区接近点", "ecology", "记下巢区处置", "这次处理的情况已记下。现在沿选定的路走回守望点，看看标识该朝向哪里。", ["choice"], {"ecology_mode": "nest_resolution", "destination_by_choice": {"near": "region_forest:work_near", "outer": "region_forest:work_outer"}, "prompt": "在选定工作点核对捣巢后的情况，或标出林缘绕行路。", "rules": "只记录本次捣巢或现场调查；巢穴自然变化不算玩家捣巢。"})]),
			_step("树下的新标识", "亲自走完选定线路，在林下站点修复对应方向的标识。", [
				_action("walk", "region_forest:station", "树下守望点", "route", "验收林下路径", "一路走过，标识和来路终于对得上。回到树下，已经知道怎样把下一位行人引过来了。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_forest:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_forest:work_near", "region_forest:station"], "outer": ["region_forest:work_outer", "region_forest:station"]}, "prompt": "沿选定线路逐段走到树下守望点。"}),
				_action("sign", "region_forest:station", "树下守望点", "repair", "修复方向标识", "新标识朝向你刚走过的路，守望点重新备起补给。林下的路有了交代，经过巢区时仍得留心。", ["walk"], {"service": "region_forest_station", "prompt": "固定方向标识，收拾树下守望点。"})])]),
		_chain("region_swamp", "两条归路", "swamp", "regional", 3, [
			_step("工程前的两条路", "再次实勘近路与外缘，这次记录需要施工的实际位置。", [
				_action("near", "region_swamp:survey_a", "泥岸近路工程点", "observe", "测近路障碍", "近路上横着一段碎岩，湿痕一直延到石缝里。要从这里过，得先打出一道能容人通过的口子。", [], {"prompt": "沿泥岸近路查看堵住通路的碎岩。"}),
				_action("outer", "region_swamp:survey_b", "枯木外缘工程点", "observe", "测外缘接应处", "枯木外缘有一处能架补给台的位置。路绕得远，至少能让人停下脚，把下一段看清。", [], {"prompt": "查看外缘的落脚处，量好支架与标识的位置。"})]),
			_step("开路或设站", "选破除登记路障，或在外缘实际建起绕行补给点。", [
				_action("choice", "region_swamp:choice", "归路工程图", "choice", "选择归路工程", "归路工程定下来了。先到选定地点完成施工，再用脚走通图上的那条线。", [], {"choices": [{"id": "near", "title": "破除近路岩障", "consequence": "打碎近路岩障，接通较短归路", "risk": "须穿过本次新开的岩缝并走到接应站"}, {"id": "outer", "title": "建外缘补给点", "consequence": "在外缘搭起绕行补给支架", "risk": "路程更远；须沿外缘逐段验收"}], "rules": "近路须破除指定岩障；外缘须安装支架。地形水面规则保持不变。", "prompt": "归路图标着两项活：打通近路碎岩，或在外缘架补给点。先让哪一条路好走些？"}),
				_action("work", "region_swamp:work_near", "近路登记岩障", "repair", "确认施工结果", "选定工作点的活做完了。还得用脚走一遍，才能把这条归路指给别人。", ["choice"], {"destination_by_choice": {"near": "region_swamp:work_near", "outer": "region_swamp:work_outer"}, "obstacle_by_choice": {"near": "region_swamp:near_barrier"}, "prompt": "破开近路岩障，或在外缘装好补给支架，再检查一遍。"})]),
			_step("脚下的归路", "沿新施工路线实走验收，启用归路接应点。", [
				_action("walk", "region_swamp:station", "归路接应站", "route", "实走验收归路", "你从这次修好的路段走到接应站。脚下这条归路，终于和工程图接上了。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_swamp:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_swamp:work_near", "region_swamp:station"], "outer": ["region_swamp:work_outer", "region_swamp:station"]}, "prompt": "沿新修路段走到接应站；近路要穿过刚打开的缺口。"}),
				_action("station", "region_swamp:station", "归路接应站", "repair", "启用归路补给", "归路站点的标识立稳了，补给也有了去处。下一个走出泥岸的人，能在这里缓一口气。", ["walk"], {"service": "region_swamp_station", "prompt": "整理接应站，启用归路补给。"})])]),
		_chain("region_hill", "岩脊旧道", "hill", "regional", 4, [
			_step("旧道两端", "找到岩脊旧道的两端，查清哪里被碎岩封住、哪里仍有机关。", [
				_action("south", "region_hill:survey_a", "岩脊旧道南端", "read", "核对南端标记", "南端旧标记指着碎岩后的缝隙。堵路的是这段碎石，旧道仍有打开的可能。", [], {"prompt": "擦去南端标记上的灰，看看它指向哪里。"}),
				_action("north", "region_hill:survey_b", "岩脊旧道北端", "observe", "调查北端机关", "北端还留着一处机关。它连着另一道门，能从这一边接回旧路。", [], {"prompt": "检查北端机关和门之间的连接。"})]),
			_step("碎岩与旧机关", "选择破除登记碎岩或操作北端机关，真正形成通路。", [
				_action("choice", "region_hill:choice", "岩脊工程板", "choice", "选择开路方法", "开路的一端选好了。旧道仍等着你动手，碎岩或机关都不会自己让出入口。", [], {"choices": [{"id": "near", "title": "破除南端碎岩", "consequence": "破除南端碎岩，从缺口接回旧道", "risk": "须亲自打碎指定岩障，并穿过新开缺口"}, {"id": "outer", "title": "操作北端机关", "consequence": "修好北端机关，打开另一处旧道入口", "risk": "须在北端操作机关，再穿门验收旧道"}], "rules": "南端需破碎岩并穿过缺口；北端需操作机关并穿过开启的门。", "prompt": "旧道南端堵着碎岩，北端还留有机关。选择一端开路，再去接应点看看。"}),
				_action("work", "region_hill:work_near", "南端登记碎岩", "repair", "确认旧道开通", "旧道在选定的一端打开了。先别急着立好通行的牌子，走到另一头看看。", ["choice"], {"destination_by_choice": {"near": "region_hill:work_near", "outer": "region_hill:work_outer"}, "obstacle_by_choice": {"near": "region_hill:near_barrier"}, "opens_choice": {"outer": "region_hill:shortcut_gate"}, "prompt": "清开南端碎岩，或修好北端机关，检查眼前的入口。"})]),
			_step("岩脊接应点", "走通修复的旧道，到山脊接应点安装最后标识。", [
				_action("walk", "region_hill:station", "岩脊接应点", "route", "验收旧道通路", "从打开的入口一路走来，接应点就在眼前。那些指向旧道的记号重新有了着落。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_hill:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_hill:work_near", "region_hill:station"], "outer": ["region_hill:work_outer", "region_hill:station"]}, "prompt": "穿过所选入口，沿旧道走到岩脊接应点。"}),
				_action("station", "region_hill:station", "岩脊接应点", "repair", "启用岩脊接应", "接应点亮起标识，补给放在伸手可及的地方。山脊那头的来人，如今有个能认出的目的地。", ["walk"], {"service": "region_hill_station", "prompt": "装好最后的标识，启用岩脊接应点。"})])]),
		_chain("region_snow", "白地归途", "snow", "regional", 5, [
			_step("看得见的路标", "在白地两侧分别找到真实可见路标，辨认开阔线和掩护线。", [
				_action("open", "region_snow:survey_a", "开阔地旧路标", "read", "辨认开阔线路标", "旧路标指向开阔地，路短，前方却少有遮挡。远处的方向看得清，自己也同样显眼。", [], {"prompt": "拂开路标上的积雪，辨认开阔线。"}),
				_action("cover", "region_snow:survey_b", "冰脊后旧路标", "observe", "核对掩护线", "冰脊后的路转折更多，走起来也长。沿着地形绕，能借到这一路的遮挡。", [], {"prompt": "沿冰脊观察掩护线的转折。"})]),
			_step("短路与掩护", "选择短开阔线或长掩护线，在对应位置装好休整设施。", [
				_action("choice", "region_snow:choice", "白地归途图", "choice", "选择休整线", "休整线已在图上标明。把设施安到选定路旁，再沿那些路标走一遍。", [], {"choices": [{"id": "near", "title": "短开阔线", "consequence": "把休整设施安在较短的开阔线", "risk": "地形遮挡少；需沿此线验收到休整点"}, {"id": "outer", "title": "长掩护线", "consequence": "把休整设施安在较长的掩护线", "risk": "转折和路程更多；需沿此线验收到休整点"}], "rules": "选择决定休整设施和验收路线；不新增冻伤或饥饿机制。", "prompt": "开阔线较短，冰脊后的掩护线转折更多。把休整设施安在哪条归途旁？"}),
				_action("work", "region_snow:work_near", "开阔线休整台", "repair", "安装休整设施", "休整设施在选定路旁立住了。回头还能看见来时的标识，接下来得把它们连到休整点。", ["choice"], {"destination_by_choice": {"near": "region_snow:work_near", "outer": "region_snow:work_outer"}, "prompt": "架好休整设施，把路标转向所选线路。"})]),
			_step("归途有人留灯", "沿实际路线走到休整点，确认归途标识与服务。", [
				_action("walk", "region_snow:station", "白地休整点", "route", "验收白地归途", "所选路标一路带你走到休整点。白地上那些容易混淆的转折，现在有了可辨认的记号。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_snow:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_snow:work_near", "region_snow:station"], "outer": ["region_snow:work_outer", "region_snow:station"]}, "prompt": "沿所选路线逐段走到白地休整点。"}),
				_action("station", "region_snow:station", "白地休整点", "repair", "点亮休整标识", "标识亮了起来，补给摆上休整台。归来的人即使一时辨不清远处，也有这一点方向可寻。", ["walk"], {"service": "region_snow_station", "prompt": "点亮休整标识，整理白地补给。"})])]),
		_chain("region_lava", "灼热的边界", "lava", "regional", 6, [
			_step("熔流的两侧", "实地核对两侧熔岩伤害边界，记下可用石脊。", [
				_action("near", "region_lava:survey_a", "近侧熔流边界", "observe", "调查近侧边界", "近侧熔流的边界已经辨清。石脊可以落脚，跨进熔流仍会灼伤。记路时得把这条界线看牢。", [], {"prompt": "在石脊上查看近侧熔流，不要为勘察踩进灼热处。"}),
				_action("outer", "region_lava:survey_b", "远侧石脊", "observe", "调查远侧石脊", "远侧石脊绕出更大一圈，却能避开眼前的熔流。它值得标下来，让赶路的人有得选。", [], {"prompt": "沿安全石脊查看远侧来路。"})]),
			_step("留在石脊上", "在两条已调查绕行线中选一条，修复对应方向的标识。", [
				_action("choice", "region_lava:choice", "熔河绕行图", "choice", "选择石脊绕行线", "选定的石脊线留在了图上。带好标识，沿安全落脚处把这条路接起来。", [], {"choices": [{"id": "near", "title": "近侧石脊", "consequence": "修复近侧石脊的绕行标识", "risk": "靠近熔流；熔岩伤害仍生效，须留在石脊上"}, {"id": "outer", "title": "远侧外缘", "consequence": "修复远侧外缘的绕行标识", "risk": "绕行更远；熔岩伤害仍生效，须留在石脊上"}], "rules": "标识与验收路线依选择确定；熔岩伤害持续生效，不提供免疫。", "prompt": "两条石脊都已查看：近侧更贴熔流，外缘绕得更远。选一条接到补给点。"}),
				_action("work", "region_lava:work_near", "近侧绕行标识", "repair", "修复绕行标识", "耐热标识固定在石脊上，指向下一处落脚点。看清标识再迈步，熔流仍在旁边流动。", ["choice"], {"destination_by_choice": {"near": "region_lava:work_near", "outer": "region_lava:work_outer"}, "prompt": "把绕行标识固定在选定石脊上。"})]),
			_step("边界上的补给点", "亲自走完所选接近线，在石脊尽头启用补给点。", [
				_action("walk", "region_lava:station", "石脊补给点", "route", "验收熔河绕行线", "沿石脊一路走到尽头，补给点和沿途标识接在了一起。这条绕行路终于可以交给后来的人。", [], {"route_corner_count_by_choice": {"near": 4, "outer": 4}, "choice_stage": "region_lava:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_lava:work_near", "region_lava:station"], "outer": ["region_lava:work_outer", "region_lava:station"]}, "prompt": "留在石脊上，沿所选标识走到补给点。"}),
				_action("station", "region_lava:station", "石脊补给点", "repair", "启用石脊补给", "边界上的补给点收拾好了。你为经过这里的人留下一处停脚的地方，也留下避开熔流的路。", ["walk"], {"service": "region_lava_station", "prompt": "启用石脊尽头的补给点。", "rules": "补给不免疫熔岩伤害；后续生态变化不会抹去已完成工程。"})])]),
	]

static func random_templates() -> Array:
	if not _groups.has("random_templates"): _groups["random_templates"] = _seal(_random_templates())
	return _groups["random_templates"]

static func _random_templates() -> Array:
	return [

		_chain("random_wounded", "野外伤者", "local", "random", 1, [
			_step("野外伤者", "确认登记伤者的需求，取专用急救物资后返回身旁救助。", [
				_action("request", "random_wounded:giver", "伤者留下的呼救记号", "read", "辨读呼救记号", "歪斜的记号指向附近的伤者，另一笔标着急救物资。留下记号的人，至少还想让别人找到他。", [], {"prompt": "辨认路旁的呼救记号。"}),
				_action("aid", "random_wounded:parts", "封存急救物资", "recover", "取急救物资", "急救包取到手了，封条与呼救记号上的纹样一致。先带回伤者身边。", ["request"], {"quest_item": "random_wounded:aid", "prompt": "收好封存的急救物资。", "rules": "专用急救包不占通用可售库存，不扣除玩家自备补给。"}),
				_action("rescue", "random_wounded:target", "野外伤者", "rescue", "完成现场救助", "伤者撑着地坐起，呼吸渐渐稳下来：我还以为，那记号没人看得懂。", ["aid"], {"prompt": "带着急救物资回到伤者身边施救。", "rules": "此人救助仅完成一次；重载不会重置伤情或奖励。"})])]),
		_chain("random_parcel", "散落包裹", "local", "random", 2, [
			_step("散落包裹", "核对包裹封签，实地回收，再亲手还给登记收件人。", [
				_action("request", "random_parcel:giver", "包裹认领告示", "read", "读认领告示", "告示画着包裹封签，下面写着收件人的等候处。字迹很急，怕的是有人捡到却不知该交给谁。", [], {"prompt": "读一读包裹认领告示。"}),
				_action("parcel", "random_parcel:target", "散落的封签包裹", "recover", "回收包裹", "包裹的封签与告示相同。外头沾了尘土，封口还好，可以带去交还。", ["request"], {"quest_item": "random_parcel:parcel", "prompt": "核对散落包裹的封签，收好它。"}),
				_action("return", "random_parcel:return", "包裹收件人", "deliver", "亲手交还包裹", "收件人反复看过封签，才松开握紧的手：就是这只，劳你把它送回来。", ["parcel"], {"consumes": "random_parcel:parcel", "prompt": "把包裹交给等候的收件人。", "rules": "同一包裹只交付一次；放弃、离线和读档不刷新。"})])]),
		_chain("random_sign", "断裂路标", "local", "random", 3, [
			_step("断裂路标", "读断裂说明，取本路标的专用部件，到原处修复。", [
				_action("request", "random_sign:giver", "路标维修留言", "read", "读维修留言", "维修留言压在断木下：备件就放在一旁，请把横梁扶正。箭头朝错了，后面的人会越走越远。", [], {"prompt": "拿起路标旁的维修留言。"}),
				_action("parts", "random_sign:parts", "路标专用备件", "recover", "取路标备件", "支脚与横梁上的刻记相合，正是这根路标缺的部件。带回断裂处就能动手了。", ["request"], {"quest_item": "random_sign:parts", "prompt": "取出刻记吻合的路标备件。"}),
				_action("repair", "random_sign:target", "断裂的路标", "repair", "立起路标", "支脚扎稳，横梁归位。路标重新指着来路，不再低垂向泥地。", ["parts"], {"prompt": "用取回的备件修好路标。", "rules": "专用部件不能交给其他路标；每处维修只奖励一次。"})])]),
		_chain("random_rocks", "岩缝近道", "local", "random", 4, [
			_step("岩缝近道", "核对近道两端，打碎登记碎岩，再亲自穿过缺口。", [
				_action("request", "random_rocks:giver", "岩缝近道草图", "read", "核对近道草图", "草图沿石缝画了一条短线，两端都留着接近的标记。拦在中间的是碎岩，清开后也许能少绕一程。", [], {"prompt": "对照草图，找到近道的两端。"}),
				_action("break", "random_rocks:target", "登记的近道碎岩", "obstacle", "检查碎岩缺口", "挡路的碎岩已被打散，岩缝露出通行的空隙。还得亲自穿过去，看看另一端。", ["request"], {"barrier_id": "random_rocks:barrier", "prompt": "击碎这处近道的岩障，再检查缺口。", "rules": "仅认此处登记岩障；其他碎岩不推进本任务。"}),
				_action("cross", "random_rocks:return", "近道另一端", "route", "穿过新开缺口", "你穿过新开的缺口，来到草图另一端。那条短线如今是一段真正走得通的路。", ["break"], {"routes": ["passage"], "route_waypoints": ["random_rocks:target", "random_rocks:return"], "prompt": "从刚打开的岩缝穿到近道另一端。", "rules": "须穿过新开缺口；绕到两个端点不能代替通行验证。"})])]),
		_chain("random_medicine", "紧缺药包", "local", "random", 5, [
			_step("紧缺药包", "当面核实药包需求，取已知专用物资并确认唯一交付。", [
				_action("request", "random_medicine:giver", "药包求助人", "talk", "核实药包需求", "巡守还等着那包药，封存处就在附近。劳你替我取来，认准封签，别拿错了。", [], {"prompt": "求助人指了指封存药物的位置。"}),
				_action("medicine", "random_medicine:parts", "登记药包物资", "recover", "取封存药包", "药包封签与求助人描述的一样。拿稳了，巡守还在等它。", ["request"], {"quest_item": "random_medicine:medicine", "prompt": "核对封签，取出这次需要的药包。", "rules": "使用专用任务药包，不扣除恢复快捷栏或背包里的自备补给。"}),
				_action("deliver", "random_medicine:target", "等待药包的巡守", "deliver", "确认交付药包", "巡守接过药包，仔细检查封口：来得正好，这下心里踏实些了。", ["medicine"], {"consumes": "random_medicine:medicine", "prompt": "把药包亲手交给等待的巡守。", "rules": "药包交付一次后消耗，不能再次交给其他人。"})])]),
		_chain("random_message", "留守讯息", "local", "random", 6, [
			_step("留守讯息", "接受当地已知留守人的讯息，核对封签并送到另一名接收者。", [
				_action("request", "random_message:giver", "留守传信人", "talk", "听留守讯息", "接应人就在这一带，却不知道我还守着这里。替我带个讯息过去吧，让他别再往回找。", [], {"prompt": "留守传信人把一只封套推到你面前。"}),
				_action("message", "random_message:target", "留守讯息封套", "recover", "取讯息封套", "封套注明了写下讯息的时刻。那是留守人当时看到的情形，送到时也许已有变化。", ["request"], {"quest_item": "random_message:message", "prompt": "收好留守讯息，核对接收者。"}),
				_action("deliver", "random_message:return", "当地接应人", "deliver", "交付留守讯息", "接应人看过署名和时刻，点点头：知道他还留着话就好。眼下的路，我再亲自看看。", ["message"], {"consumes": "random_message:message", "prompt": "把封套交到当地接应人手中。", "rules": "保留来源与时间；历史目击不持续追踪目标。"})])]),
		_chain("random_nest", "巢区临道", "local", "random", 7, [
			_step("巢区临道", "核对真实临路巢穴，暂时捣巢或现场确认绕行，再提交结果。", [
				_action("request", "random_nest:giver", "临道巢区告示", "read", "核对巢区线索", "路边告示提醒来人：巢区挨近通路，经过前先看清。留字的人画了绕行线，也标出了巢穴的位置。", [], {"prompt": "读临道巢区告示，核对眼前位置。"}),
				_action("result", "random_nest:target", "实际临路巢区", "ecology", "确认巢区处置", "巢区眼下的情况和你的处置已记下。带回路牌上，下一位行人才知道该留心什么。", ["request"], {"ecology_mode": "nest_resolution", "prompt": "查看这处临路巢穴，选择暂时捣巢或确认绕行。", "rules": "仅本次接取后的捣巢事件可记讨伐；现场绕行也能完成调查。"}),
				_action("report", "random_nest:return", "临道记录牌", "deliver", "写下当前路线说明", "路牌添上了这次处理的时间与方式。后来的人能据此判断，却仍得留心巢区的新动静。", ["result"], {"prompt": "把当前路线说明写回临道记录牌。", "rules": "巢穴抑制结束后可重建；不会因此重发任务奖励。"})])]),
		_chain("random_migration", "迁徙目击", "local", "random", 8, [
			_step("迁徙目击", "读取有真实来源的迁移线索，到场核对，再记录当前结果。", [
				_action("request", "random_migration:giver", "迁移目击记录", "read", "读迁移线索", "目击记录写着迁出、迁入的地点和发生时刻。那道边界上有东西走过，如今还留不留得住踪迹，要到场看看。", [], {"prompt": "读迁移目击记录，辨认来路和去路。"}),
				_action("site", "random_migration:target", "迁移线索现场", "observe", "核对迁移现场", "你核对了现场的留痕和眼前活动。过去的那次迁移有了今日的对照，离开的也如实记作离开。", ["request"], {"ecology_mode": "migration_state", "prompt": "沿已知线索到场，查看现在的活动。", "rules": "目标已离开时可以据实完成调查，不等待或制造新迁移。"}),
				_action("report", "random_migration:return", "目击回执点", "deliver", "提交目击核对", "旧目击与这次观察各写在自己的时刻旁。回头再看，便能分清哪里是过去，哪里是你今天见到的。", ["site"], {"prompt": "回到目击回执点，留下本次核对结果。"})])]),
		_chain("random_camp", "据点余患", "local", "random", 9, [
			_step("据点余患", "核对健康当地族群与能力范围，有限处理或在目标变化后勘察结案。", [
				_action("request", "random_camp:giver", "当地据点委托牌", "read", "核对当地委托", "委托牌只要求给这条来路减轻一点压力。数目写得克制，末尾又添了一句：先看现场，别追着清空。", [], {"prompt": "查看当地据点委托与限定的处理数目。", "rules": "仅可达、战力匹配且余量充足时发布；全球同种不足六只不发狩猎单。"}),
				_action("result", "random_camp:target", "登记的当地据点", "ecology", "回报据点情况", "本次处理与据点当前的变化已经分开记下。够了就回去，空下来的地方也不必再追出一场战斗。", ["request"], {"ecology_mode": "camp_resolution", "prompt": "按限定数目处理据点；目标变化时在现场复查。", "rules": "只计真实玩家贡献并保留当地余量；目标迁出或自然消失可据实调查。"}),
				_action("report", "random_camp:return", "当地委托回执点", "deliver", "确认据点结案", "回执记下了你做过的事，也记下据点已发生的变化。这一趟有了交代，路上的新情况留待来人再看。", ["result"], {"prompt": "把处理结果与现场变化带回委托回执点。", "rules": "不补刷怪物凑数，自然死亡不计猎杀。"})])]),
		_chain("random_runes", "废墟符记", "local", "random", 10, [
			_step("废墟符记", "读取独立遗迹线索，按灯、路、人操作三枚现场符记。", [
				_action("request", "random_runes:giver", "废墟外的留字", "read", "读遗迹留字", "废墟外留着一句话：天黑了，先想想怎样等一个归来的人。旁边还有三行刻字。", [], {"prompt": "读废墟外的留字。"}),
				_action("record", "random_runes:record", "三行符记说明", "read", "读机关顺序", "第一行：点灯。第二行：辨路。第三行：等人。三枚符记依着灯、路、人排列。", ["request"], {"prompt": "沿三行刻字慢慢读下去。", "rules": "次序错误只清空未完成输入，不删除已取得记录。"}),
				_action("runes", "random_runes:target", "废墟符记机关", "puzzle", "完成符记次序", "灯、路、人依次回应。三行刻字旁的光亮起，好像那个等待的夜晚终于有了下文。", ["record"], {"puzzle_order": ["lamp", "road", "person"], "puzzle_objects": ["random_runes:rune_a", "random_runes:rune_b", "random_runes:rune_c"], "prompt": "依灯、路、人的次序触碰现场符记。", "rules": "同一机关只奖励一次，离线或读档不会刷新。"})])]),
	]

static func world_arcs() -> Array:
	if not _groups.has("world_arcs"): _groups["world_arcs"] = _seal(_world_arcs())
	return _groups["world_arcs"]

static func _world_arcs() -> Array:
	return [

		_chain("world_migration", "迁徙的长路", "world", "world", 1, [
			_step("沿线的两个地点", "依据已获知的真实迁移线索，分别到两处沿线地点调查。", [
				_action("route_a", "world_migration:route_a", "迁徙来路观察点", "observe", "调查迁徙来路", "记录中的个体确实曾从这一带离开。沿着留痕与旧记录，这一处的来路有了着落。", [], {"ecology_mode": "world_migration_origin", "prompt": "沿已知迁移记录调查来路观察点。"}),
				_action("route_b", "world_migration:route_b", "迁徙去路观察点", "observe", "调查迁徙去路", "去路观察点已核对。过去走过的路和如今留下的活动，终于能放到一起看。", [], {"ecology_mode": "world_migration_destination", "prompt": "到去路观察点，查看这段迁移留下的线索。"})]),
			_step("现在走到哪里", "向观察员核对当前状态，区分仍继续、已停止与失去踪迹。", [
				_action("status", "world_migration:observer", "沿线观察员", "observe", "核对当前迁徙状态", "沿线观察员合上旧页：继续走、停下来，或再也找不到踪迹，都值得写清。你看到什么，我们就留什么。", [], {"ecology_mode": "world_migration_status", "prompt": "与沿线观察员核对眼下的迁徙状态。", "rules": "当前状态依据已验证事实；完成调查不要求再发生一次迁移。", "questions": [{"label": "找不到踪迹，也能写吗？", "answer": "当然。写不清在哪里，也要写清我们看过哪里。空白比编一个去向更可靠。"}]})]),
			_step("把长路留下", "在记录板提交两地调查与当前状态，完成这一次世界调查。", [
				_action("archive", "world_migration:record_board", "迁徙路线记录板", "deliver", "提交迁徙路线记录", "两处调查与当前状态被收进同一份档案。迁徙没有为谁停住，但这段已经走过的长路留了下来。", [], {"prompt": "把两地调查和当前状态交到路线记录板。", "rules": "结案采样保存不变；可查看当前状态与历史来源，后续变化不重复支付。"})])]),
		_chain("world_decline", "最后的足迹", "world", "world", 2, [
			_step("已经获知的足迹", "依有来源的濒危或永久灭绝线索，亲自调查已知地点。", [
				_action("site", "world_decline:last_site", "最后已知活动地", "observe", "调查已知足迹", "这里曾留下活动的记录。眼前还剩下什么、哪些已经无从判断，都记在了这次调查里。", [], {"ecology_mode": "world_decline_site", "prompt": "沿已知线索查看最后记录过活动的地方。", "rules": "调查由持续濒危或已发生的永久灭绝线索触发；不奖励清空物种。"})]),
			_step("减少的原因", "在证据柱核对仍存、迁出、自然死亡与玩家造成的永久灭绝。", [
				_action("cause", "world_decline:evidence_post", "衰退证据柱", "observe", "核对衰退记录", "记录一页页对过，能确认的变化已写明。没有踪迹的地方，原因不明就仍留着问号。", [], {"ecology_mode": "world_decline_status", "prompt": "核对证据柱上的事件与当前种群状态。", "rules": "区分仍濒危、回升、自然消失和玩家永久灭绝；单次死亡不证明之后衰退的原因。"})]),
			_step("留给来者的警示", "亲自立下警示，再把这次有限调查交给观察员。", [
				_action("warning", "world_decline:warning_sign", "足迹警示牌", "repair", "立下足迹警示", "警示牌添上了调查的时刻与所见。后来的人会知道这里发生过什么，也知道还有什么不能断言。", [], {"prompt": "把本次核实的状态与时间写上警示牌。"}),
				_action("archive", "world_decline:observer", "物种记录观察员", "deliver", "提交足迹调查", "观察员把调查收进图鉴：要是它们回来，我们再添一页；要是没有，也别让这页白白留下。", ["warning"], {"prompt": "将足迹调查交给观察员。", "rules": "档案仅保存已发生事实，不保证自然恢复；本次调查只奖励一次。", "questions": [{"label": "这些记录能改变什么？", "answer": "至少下一位来调查的人，不必再把同样的错误走一遍。"}]})])]),
		_chain("world_relief", "彼此的接应", "world", "world", 3, [
			_step("两地正在等什么", "在已到访三种地形后，分别确认两处新增接应点的实际待办。", [
				_action("need_a", "world_relief:need_a", "第一处接应需求", "talk", "确认第一处需求", "我们这边还缺一份接应物资。把该送来的那份交到这里就好，另一边也有人在等，别全挪给我们。", [], {"prompt": "听第一处居民说明眼下缺少什么。"}),
				_action("need_b", "world_relief:need_b", "第二处接应需求", "talk", "确认第二处需求", "这里也留了收货的位置。去看看物资上的去向吧，送对了地方，来的人才能接着歇下来。", [], {"prompt": "向第二处居民核实接应需求。"})]),
			_step("各有去向的物资", "将两份不同编号的专用物资交到各自接应处。", [
				_action("supply_a", "world_relief:supply_a", "第一份接应物资", "deliver", "交付第一份物资", "第一份物资交到接应处，收货人在封签旁做了记号。这里等的东西终于到了。", [], {"supply_id": "world_relief:parcel_a", "prompt": "把第一份专用物资送到它标明的接应处。", "rules": "两份物资各有固定去向，不能重复交付或相互挪用。"}),
				_action("supply_b", "world_relief:supply_b", "第二份接应物资", "deliver", "交付第二份物资", "第二份物资交到了它标明的接应处。收货人核过封签，把这一份的去向记了下来。", [], {"supply_id": "world_relief:parcel_b", "prompt": "把第二份专用物资送到另一处接应点。"})]),
			_step("接应之后", "回访两处接应点，在协调台确认新增居民与服务的实际变化。", [
				_action("return_a", "world_relief:need_a", "第一处接应居民", "talk", "回访第一处接应", "居民拍了拍已经摆好的物资：收到了，这回能留出地方接人。谢谢你还回来问一声。", [], {"prompt": "回到第一处接应点，问问物资是否用上了。"}),
				_action("return_b", "world_relief:need_b", "第二处接应居民", "talk", "回访第二处接应", "第二处居民把回执递给你：我们这边妥当了。把这张带回去，免得协调的人一直悬着心。", [], {"prompt": "探望第二处接应点，听听他们的答复。"}),
				_action("settle", "world_relief:coordination_post", "接应协调台", "repair", "确认两地接应", "两张回执并排放好，去向与回访都有了交代。协调台备起联合补给，两边终于能彼此接住来人。", ["return_a", "return_b"], {"service": "world_relief_station", "prompt": "把两地回执送回协调台，确认接应安排。", "rules": "完成后开放联合补给；不改变世界市场或资源模拟。"})])]),
		_chain("world_watchnet", "灯火相望", "world", "world", 4, [
			_step("选择三处灯火", "主线完成且至少三条区域工程完工后，选择三个真实可用节点。", [
				_action("plan", "world_watchnet:planning_board", "守望网络配置板", "configure", "选择三个守望节点", "三处站点已经圈定。接下来把三套装置分别安好，让图上的灯火真正连起来。", [], {"node_count": 3, "rules": "仅选三个不同的已完成区域节点；提交后配置固定。主线与至少三项区域工程须已完成。", "prompt": "已有的站点亮着各自的灯。先选三处相互联络，再去把装置一一安好。"})]),
			_step("让节点彼此识别", "亲自安装三套各有编号的守望标识。", [
				_action("node_1", "world_watchnet:node_1", "第一套守望装置", "repair", "安装第一套标识", "第一套标识安上了，这处站点有了自己的联络记号。灯旁留下的标记与线路图相合。", [], {"node_index": 0, "prompt": "把第一套守望标识安在选定节点。"}),
				_action("node_2", "world_watchnet:node_2", "第二套守望装置", "repair", "安装第二套标识", "第二套装置认下了这里的标识。这处灯火的位置，已经能在线路图上清楚辨认。", [], {"node_index": 1, "prompt": "在第二个选定节点安装守望标识。"}),
				_action("node_3", "world_watchnet:node_3", "第三套守望装置", "repair", "安装第三套标识", "第三套装置稳稳落位，这处站点留下了自己的守望标识。灯下的记号与选定的去处一致。", [], {"node_index": 2, "prompt": "到第三个选定节点安装对应的守望标识。"})]),
			_step("灯火相望", "确认三个节点真正可用，提交最终线路配置与世界档案。", [
				_action("archive", "world_watchnet:record_board", "最终守望档案", "deliver", "提交整体配置", "三处灯火被连在同一张线路图上。往后赶路的人，可以从这一端去到另一端，再找到回来时的灯。", [], {"service": "world_watchnet_station", "prompt": "确认三处装置可用，将线路图交入守望档案。", "rules": "完工后可在三节点之间选择远征；要求脱离战斗，不恢复生命或精力，生态继续运行。"})])]),
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
