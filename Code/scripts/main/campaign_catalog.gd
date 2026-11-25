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
		_chapter("watch_c2_forest", "林间盟书", "forest", 2, [
			_step("古树盟书", "与林中药师白榆交谈，读一读古树下的盟书抄本。", [
				_action("herbalist", "c2:herbalist", "林中药师白榆", "talk", "打听旧哨所", "白榆收起药囊。「在下白榆，在这林边行医。阿苇伤了腿，偏不肯离开东边歇脚处，守着不肯走。少侠先去看看古树下那份盟书，他认得上头的巡林符记。」", [], {"prompt": "林中药师白榆停下理药的手。「哨所那头，总算来人了？我正惦记林子里的阿苇。」", "questions": [{"label": "你怎么认得这份盟书？", "answer": "「这些年，来求药的有人族，也有鳞族巡林人。符记是跟他们学的。盟书上写了什么，在下知道；远征队后来怎样，在下不知道。」"}, {"label": "阿苇为何不肯回来？", "answer": "「他在等走散的同伴。前几天检修烽灯摔伤了腿，嘴上只念叨一句：不能让后来的人白跑一趟。」"}]}),
				_action("old_pact", "c2:old_pact", "盟书抄本", "read", "读盟书抄本", "抄本上记着一百六十年前的义路盟：人族让出林下通路，鳞族巡林人标出险地巢穴、接应过路之人，地精巧匠打理灯火。\n盟书写道：『路当共行，义字当先。借路不占地，求援不诱敌，四方按季轮值。』旧盟之后另附当季值守的名栏，末页却被人撕去了。", ["herbalist"], {"prompt": "古树下压着一份盟书抄本。纸角折了又折，末尾缺了一页。", "questions": [{"label": "这份盟书为何少有人提起？", "answer": "白榆在旁批注：十二年前歉收，人族伐木队把小路拓成运炭车道，毁了鳞族的育幼林；报仇的人烧断粮桥，连不相干的村子也跟着挨饿。有人从此封路，也有人仍悄悄替对面修灯。"}]})]),
			_step("林下通道", "看巡路人留下的方位刻记，按线索依次触碰灯石，开门取残页。", [
				_action("route_marks", "c2:route_marks", "巡路人的方位刻记", "read", "辨认方位刻记", "刻记把晨露、日影与归鸟连成一线：北→东→西。\n照这个次序触碰三处灯石，便能打开藏盟书的石门。", [], {"prompt": "巡路人的方位刻记还在。三枚刻印分别朝着北、东、西，细细的连线藏在苔痕下。", "rules": "灯石次序为北→东→西。按错了只会从头再来，到手的线索不会丢。"}),
				_action("runes", "c2:forest_gate", "盟书石门", "puzzle", "对符记", "北、东、西三处灯火依次亮起。盟书石门应声松动，门后的残页露了出来。", ["route_marks"], {"puzzle_order": ["north", "east", "west"], "puzzle_objects": ["c2:rune_north", "c2:rune_east", "c2:rune_west"], "opens": "c2:forest_gate", "prompt": "盟书石门上三道纹路各通向一块灯石。巡路人的刻记写着：北→东→西。"}),
				_action("torn_record", "c2:torn_record", "门后的残页", "recover", "取门后的残页", "残页正对得上抄本后附的当季值守栏，落款是「远征队信使阿苇」。\n『粮草未到，我且在东侧歇脚处守候。沈渡答应从沼泽回信；若有人回来，莫让他白跑。』\n这是近来添上的一笔，并非旧盟上的签名。", ["runes"], {"prompt": "门后的残页压在尘土里，纸边正与盟书抄本的缺口相合。"})]),
			_step("留在林地的人", "找到受伤的远征队信使，取林间药匣送回包扎。", [
				_action("liaison", "c2:liaison", "远征队信使阿苇", "talk", "查看伤势", "阿苇撑着地想站起来，又坐了回去。「在下是远征队送信的。前几天去倒灯壳里的积水，回来伤了腿。林间药匣在树根那边，有劳少侠取来。」", [], {"prompt": "阿苇抬手遮着光。「是谁？……哨所来的？别站在路当中，过来。」", "questions": [{"label": "你一直在这里等谁？", "answer": "「沈渡，还有走散的同伴。鳞族的符记我认得，已替他们一路留好了寻到这儿的记号。」"}, {"label": "你想过回平原么？", "answer": "「想。可沈渡答应回信，我也答应下来，要接住后来的人。总得先让他们知道，我往哪里去。」"}]}),
				_action("aid_cache", "c2:aid_cache", "林间药匣", "recover", "取出药囊", "林间药匣里还有干爽的绷带和封好的伤药。你收起药囊，信使正等着你回去。", ["liaison"], {"quest_item": "c2:aid", "prompt": "林间药匣的扣环被树根顶住，匣里的药囊还封得严严实实。", "rules": "药囊算任务物件，单独保管，不占随身行囊，也不动快捷栏里的药。"}),
				_action("rescue", "c2:liaison", "远征队信使阿苇", "rescue", "替信使包扎", "绷带扎紧，阿苇松开捂着伤口的手。「这儿我暂时守得住。灯料木箱里还有灯芯和遮光片。把灯点亮，先把『我还在』这四个字送出去。」", ["aid_cache"], {"prompt": "阿苇瞧见药囊，把伤腿慢慢挪到身前。「来吧。扎紧些。等路通了，我也想回去看看。」"})]),
			_step("第一盏灯", "取灯芯与遮光片，修好熄了的林间烽灯。", [
				_action("signal_parts", "c2:signal_parts", "灯料木箱", "recover", "取灯芯与遮光片", "灯料木箱里留着遮光片和旧灯芯，上头还印着地精工坊的尺寸记号。旁边是远征队分装好的油布袋；物件早已备齐，只等有人装回去。", [], {"quest_item": "c2:signal_parts", "prompt": "灯料木箱的木盖翘起一角，里面有零件相碰的轻响。"}),
				_action("beacon", "c2:beacon", "熄了的林间烽灯", "repair", "修好林间烽灯", "你倒净灯壳里的积水，换掉受潮的灯芯。林间烽灯重新亮起。\n阿苇把沼泽的旧坐标递来：「六周前我们头一回分队，一路去沼泽，一路去丘陵。若见着沈渡，告诉他，我还在等他的回信。」", ["signal_parts"], {"service": "forest_station", "next_chapter": "watch_c3_swamp", "prompt": "熄了的林间烽灯挂着水痕，焦黑的灯芯湿在底座上。灯料备齐了，阿苇在一旁等着这盏灯。"})])]),
		_chapter("watch_c3_swamp", "沼泽双途", "swamp", 3, [
			_step("漂来的行囊", "察看图腾刻文与灵龛布条，找到漂来的远征行囊。", [
				_action("totem", "c3:totem_record", "沉睡图腾的刻文", "read", "察看图腾刻文", "沉睡图腾的刻文旁留着一个眼熟的绳结，打法同哨所的记号一般。绳尾指向枯木灵龛，那里还挂着一截布条。", [], {"prompt": "水痕爬上了沉睡图腾。刻文旁系着一个绳结，这结法有些眼熟。"}),
				_action("shrine", "c3:shrine_record", "枯木灵龛的布条", "read", "读灵龛布条", "布条上写着：『近路能走。若赶不上，到外缘相候。』\n两句话笔迹深浅不一，末尾指向搁浅在泥岸的远征行囊。", ["totem"], {"prompt": "枯木灵龛的布条被泥水浸暗。得把它摊开，才看得清叠在一处的字。"}),
				_action("satchel", "c3:satchel", "漂来的远征行囊", "recover", "取回远征行囊", "行囊的防水封套里有两份路书，一份写着『走浅滩』，另一份却把这四个字划去了。纸角各有一枚日期，后半截被泥水糊住。\n夹在里头的回信只起了个头：『闻川，这次先信我的鞋底……』", ["shrine"], {"quest_item": "c3:satchel_record", "prompt": "漂来的远征行囊搁浅在泥岸上。外皮湿透，封套却还系得紧紧的。"})]),
			_step("两份路书", "读受潮的旧路书，近路与外环各走一遭察看。", [
				_action("old_route", "c3:old_route", "受潮的旧路书", "read", "读受潮的旧路书", "两份路书通向同一个渡口，一条穿过浅滩，一条沿着枯木外缘。日期受了潮，眼下还认不全。\n先去两边察看；图上记的只是从前，今日走不走得通，得到跟前才知道。", [], {"prompt": "受潮的旧路书摊在眼前。几处路口改了又改，单看其中一张，说不通。"}),
				_action("route_near", "c3:route_near", "近路勘察桩", "observe", "勘察浅滩近路", "近路从浅滩间穿过，石障处的缺口通到渡口。你把眼前的动静一一记下；要走这条短路，须得缺口过得去人。", ["old_route"], {"prompt": "近路勘察桩朝着浅滩。渡口就在另一头，先看看石障处的缺口过不过得去人。"}),
				_action("route_outer", "c3:route_outer", "外环勘察桩", "observe", "勘察枯木外缘", "外缘的路绕向西边，一连拐过两道弯。你把这里的动静记下。\n两边都看过了，便可到渡口路线图前拿主意。", ["old_route"], {"prompt": "外环勘察桩靠着枯木。路往西伸出去，到视野尽头拐了个弯。"})]),
			_step("渡口", "在渡口路线图上选定一条路，沿路走到幸存者身边，取药包扎。", [
				_action("route_choice", "c3:route_choice", "渡口路线图", "choice", "选择路线", "你在渡口路线图上圈出了要走的路。渡口就在前头，沿选定的路过去吧。", [], {"choices": [{"id": "near", "title": "走浅滩近路"}, {"id": "outer", "title": "绕枯木外缘"}], "prompt": "渡口在沼泽另一头。浅滩近路短，须先打碎岩障、穿过缺口；枯木外缘路长，须绕过西边两道弯。\n你打算从哪边过去？", "rules": "定下之后，沿所选之路前往渡口。近路须打碎岩障、穿过缺口；外缘须走过西边两道弯。半途离开或倒下，可从最后经过的路标接着走。"}),
				_action("reach", "c3:survivor", "艄公沈渡", "route", "走到渡口", "沈渡的手停在行囊封套上。「阿苇让你来的？这包东西还在……俺原本是这渡口的艄公，路是俺一脚踏出来的。先劳你拿旁边药匣里的药，俺这手抖得使不上劲。」", ["route_choice"], {"routes": ["near", "outer"], "route_by_choice": {"near": ["c3:route_near", "c3:survivor"], "outer": ["c3:route_outer", "c3:survivor"]}, "prompt": "幸存者听见脚步声，抬头报上名号：「沈渡。你从哪边过来的？把行囊拿近些，让我瞧瞧。」"}),
				_action("aid", "c3:aid_cache", "渡口药匣", "recover", "取出渡口药囊", "渡口药匣外头的油布没破，药和包扎用的东西都还干爽。你收好药囊，该回到幸存者身边了。", ["reach"], {"quest_item": "c3:aid", "prompt": "渡口药匣半陷在泥里，外头裹着一层油布。", "rules": "这份药囊算任务物件，单独保管，不占随身行囊，也不动自带的伤药。"}),
				_action("rescue", "c3:survivor", "艄公沈渡", "rescue", "为幸存者包扎", "包扎停当，沈渡的手稳了，握得住行囊了。「阿苇还在就好。俺不能叫他一直等一句没写完的话。这两份路书俺认得，给俺一点工夫，把日期认清楚。」", ["aid"], {"prompt": "沈渡伸出受伤的手。「昨儿在泥岸找行囊，又划开了伤口。多谢，包好了，俺就能把那封信接着写下去。」"})]),
			_step("未写完的回信", "听幸存者讲来历，取未写完的回信，点亮沼泽烽灯。", [
				_action("account", "c3:survivor", "艄公沈渡", "talk", "听行囊的来历", "沈渡擦去纸角的泥痕：「六周前，头一拨人走浅滩；三周前，接第二拨人时旧路已断，只得绕外缘。这渡口前后两次接应，各走各的路，每回只送走一拨人；各站那时都还有人守着，谁也没在纸上扯谎。」\n他把回信铺开：「路变了，信却没追上已经动身的人。」", [], {"prompt": "沈渡把两份路书并排铺开，指着不同的日期。「同一个地方，两回经过。俺早该把变故写信告诉闻川。」", "questions": [{"label": "你同闻川很熟？", "answer": "「老搭档了。他信图，俺信鞋底。如今俺只盼这句拌嘴的话，能当着面说给他听。」"}, {"label": "你为何还守在这儿？", "answer": "「阿苇替俺留了路，俺也得接住从丘陵回来的人。等大伙都得了新的去向，俺才能安心回平原。」"}]}),
				_action("reply", "c3:reply_record", "未写完的回信", "recover", "收起未写完的回信", "沈渡在旧回信下头补了今日的落款：\n『闻川，这次先信我的鞋底。浅滩变了，记得改图。附上你要的绞盘草图。阿苇和俺都还在；等路通了，平原见。』\n你收好这封总算写完的回信。", ["account"], {"quest_item": "c3:reply", "prompt": "未写完的回信铺在渡口。沈渡补上最后几行，折好交到你手上，托你亲手送到闻川身边。"}),
				_action("beacon", "c3:beacon", "沼泽烽灯", "repair", "点亮沼泽烽灯", "沼泽烽灯亮起。沈渡在路书上添了入丘陵的落脚处：「把信交给闻川。也告诉阿苇，俺欠的那句回话，总算托你送出去了。」", ["reply"], {"service": "swamp_station", "next_chapter": "watch_c4_hill", "prompt": "沼泽烽灯蒙着水汽，最后一处接头还断着。幸存者守在渡口，只等这儿重新亮起来。"})])]),
		_chapter("watch_c4_hill", "丘陵封关", "hill", 4, [
			_step("封门人的名册", "与金石先生闻川交谈，读一读旧驻守名册。", [
				_action("scholar", "c4:scholar", "金石先生闻川", "talk", "打听封门人", "闻川展开沈渡的回信，读到「鞋底」二字，笑了。「老艄公还肯同我拌嘴。好，我改图。先看旧驻守名册，封存文书的人，把去向留在了里头。」", [], {"prompt": "金石先生闻川伸手要接那封回信，又停住了。「沈渡写的？给我瞧瞧。他总说我的图追不上他的鞋底。」", "questions": [{"label": "你一直在等这封信？", "answer": "「等的是他们的下落。如今知道沈渡和阿苇都还在，平原那顿团圆饭就有盼头了。」"}, {"label": "山寨的门封了？", "answer": "「南门能走。封住的是文书密室，绞盘断了。先修好它，再照眼下山寨里的光景找路；旧图保不了今日的平安。」"}]}),
				_action("roster", "c4:roster", "旧驻守名册", "read", "读旧驻守名册", "名册上列着阿苇、沈渡和掌图人罗墨。三周前的封存栏写着：『去向留在原件上，待后来人核对。』\n旁边附着一幅草图，画着绞盘缺掉的齿轮和轴销。", ["scholar"], {"prompt": "旧驻守名册摊在石台上。几行姓名旁画着去向的箭头，封存一栏另有人的签字。", "rules": "这份文书靠绞盘和现场的通路打开，不必银钥匙；山寨里的宝箱，仍照原来的钥匙规矩。"})]),
			_step("断开的绞盘", "取绞盘零件，装好断开的绞盘，打开文书密室的入口。", [
				_action("parts", "c4:winch_parts", "绞盘零件", "recover", "取绞盘零件", "齿轮和轴销还在。你收齐绞盘零件，照名册上的草图便能装回断开的绞盘。", [], {"quest_item": "c4:winch_parts", "prompt": "绞盘零件散放在旧包布里。齿轮上磨亮的缺口，与草图标记正好对得上。"}),
				_action("winch", "c4:winch", "断开的绞盘", "repair", "装好绞盘，用力拉动", "轴销归位，绞盘重新咬合。你用力一拉，文书密室入口的栅门缓缓升起。\n接下来得去山寨南门瞭望处，看看怎样走近那份文书。", ["parts"], {"opens": "c4:archive_gate", "prompt": "断开的绞盘垂着松弛的绳索。带来的齿轮和轴销，正好补上空位。"})]),
			_step("牛头王的山寨", "察看牛头王山寨，讨伐、西侧绕行或入空寨一探，取封关文书。", [
				_action("fortress", "c4:fortress_record", "山寨南门瞭望处", "read", "察看山寨光景", "山寨南门旁的旧图标出了封关文书的位置。走正面，须同仍在寨中的牛头王照面；摇动西侧绕行绞盘，能打开另一条通路。\n若寨中已空，便把眼前的光景照实记下。", [], {"prompt": "站在山寨南门瞭望处，认得出通往文书的方向。先看清眼前的光景，别只凭一张旧图往里闯。", "rules": "亲手击败过这寨里的牛头王、从西侧绕行，或查明寨中眼下空无一人，三条路皆可走近文书。绕行与探空寨不算击杀。"}),
				_action("passage", "c4:bypass_control", "西侧绕行绞盘", "encounter", "定下进寨之路", "你记下了这一回进寨的经过。通往封关文书的入口就在前头，那几页纸还等着人取出来。", ["fortress"], {"boss_species": "牛头王", "choices": ["defeated", "bypass", "absent"], "opens": "c4:archive_gate", "prompt": "封关文书就在山寨另一头。摇动西侧绕行绞盘可开侧路；若走正面，先确认牛头王已不再拦路。", "rules": "绕行、亲手讨伐与探空寨各记各的，不能算作击杀之功。牛头王日后再复生，也不会撤销这一回的修复或重复发赏。"}),
				_action("archive", "c4:archive", "封关文书", "recover", "取封关文书", "封关文书记着三周前的第二次分队：一队修路、接伤员，一队带着总图去雪原。救人和开路一再来回抽调人手，原定的轮换一拖再拖。\n检修栏里记着沼泽油料见底、雪地转轴须每日除冰；至于后来为何断了音信，这里还没有交代。", ["passage"], {"quest_item": "c4:archive", "prompt": "封关文书的封皮落满灰尘。里头夹着几页路线图，格式同沼泽那封回信一样。"})]),
			_step("第二次分队", "扶助掌图人罗墨，取第二次分队坐标，修好丘陵烽灯。", [
				_action("keeper", "c4:map_keeper", "掌图人罗墨", "talk", "扶起掌图人", "罗墨把一张卷了边的总图底稿护在怀里。「韩铎统领教我画图。原件上的日期和批注，学生一处也没涂掉。先去雪原寻他吧，后头那几处空白，得由他亲口说明。」\n你扶稳他，把散落的纸页收拢。", [], {"prompt": "负伤的掌图人罗墨一手扶墙，一手护图。「脚下留神，那是他们走过的路。先帮我把纸拾起来。」", "questions": [{"label": "你是统领的学生？", "answer": "「他教我：图不替画图的人遮丑。我敬他，所以有疑窦的地方，也留着原来的日期，等寻着人再核对。」"}, {"label": "你为何还留在这儿？", "answer": "「腿伤走不远，原件也不能丢。等能回平原了，我想同老师坐下来，把这些空白一处一处补上。」"}]}),
				_action("coordinates", "c4:snow_coordinates", "第二次分队坐标", "recover", "取第二次分队坐标", "罗墨在坐标页上指出雪原冰封祭坛旁的落脚处：「总图原件随韩铎统领到了这里。后来如何，请他亲口解释。我在这儿等你们带消息回来。」", ["keeper"], {"quest_item": "c4:snow_coordinates", "prompt": "坐标页卷了边，墨线却还清楚。页边画着一枚箭头，指向雪原那一处。"}),
				_action("beacon", "c4:beacon", "丘陵烽灯", "repair", "修好丘陵烽灯", "丘陵烽灯亮起。闻川把送到的回信收好，罗墨摊开总图底稿：「去寻韩铎统领吧。告诉他，原件还在，学生也还在。我们等他回来，一道把后头的路补完。」", ["coordinates"], {"service": "hill_station", "next_chapter": "watch_c5_snow", "prompt": "丘陵烽灯的接头已经露了出来。灯火一通，这里便有人照看回程的路。"})])]),
		_chapter("watch_c5_snow", "雪原回声", "snow", 5, [
			_step("冰封祭坛", "读冰封祭坛刻文，打碎冰障，取祭坛中的石牌。", [
				_action("altar", "c5:altar_record", "冰封祭坛刻文", "read", "读冰封祭坛刻文", "冰封祭坛的刻文写着：『后来的人，请从薄冰处取石牌。我若还在，沿背面的接应记号来寻。』\n封住祭坛的冰障上有一道裂纹，出手一击，便能打开缺口。", [], {"prompt": "祭坛刻文被积雪遮住一半。有人在最后一行刻得极深，像是怕后来的人看漏。"}),
				_action("ice", "c5:ice_barrier", "封住祭坛的冰障", "obstacle", "察看冰障缺口", "碎冰落下，祭坛中的石牌露了出来。缺口已容得下人通过。", ["altar"], {"prompt": "封住祭坛的冰障横在面前。先打碎这处薄冰，再从缺口进去。"}),
				_action("tablet", "c5:tablet", "祭坛中的石牌", "recover", "取祭坛中的石牌", "石牌背面刻着远征统领留下的接应记号，箭头指向避风处。最后一笔没有刻完。", ["ice"], {"quest_item": "c5:tablet", "prompt": "祭坛中的石牌覆着一层雪。背面似乎还刻着一组接应记号。"})]),
			_step("雪下的守望", "寻到统领，取雪地药匣，回到他身边救治。", [
				_action("leader", "c5:leader", "远征统领韩铎", "talk", "察看统领伤势", "韩铎想接过石牌，手却抬不起来。「周照寻来的新巡守？我留的记号，总算有人看见了。雪地药匣在冰脊那边，先劳动你取来。撤守的事，我自会说明。」", [], {"prompt": "远征统领韩铎靠在避风处。「竟还有人寻到这儿来。前几天除冰摔伤后，我一直在等消息……且让我缓一缓。」", "questions": [{"label": "你认得周照？", "answer": "「我们同走过许多路。他肯把差事交给你，是信你肯亲眼去看。我也该把原件交出来，不能只叫你信我一句话。」"}, {"label": "你在这里等什么？", "answer": "「等一个能把消息带回去的人。原图由罗墨替我留着；令是我下的，我得把它说明白。」"}]}),
				_action("aid", "c5:aid_cache", "雪地药匣", "recover", "取出雪地药囊", "雪地药匣的封口还完好。你取出药囊，里头的绷带没有受潮。统领就在避风处等你。", ["leader"], {"quest_item": "c5:aid", "prompt": "雪地药匣埋在浅雪里，露出的扣环上结了霜。", "rules": "药囊算任务物件，单独保管；救治统领不扣随身行囊和快捷栏里的药。"}),
				_action("rescue", "c5:leader", "远征统领韩铎", "rescue", "救治统领", "包扎停当，韩铎坐直了些。「撤守令是我签的。伤员先撤，许多人因此捡回一条命。我知道接应的地方会少下去，却以为余下各站还连得起来。后来灯一盏一盏灭了，这是我没有算到的。」\n他指了指手记：「别只听我一面之词，去对一对日期。」", ["aid"], {"prompt": "统领把伤处挪到亮处，示意你动手。\n「你都走到这儿了，我没有理由再瞒着。」"})]),
			_step("前后不合的手记", "读撤守手记和分队路书，在对证板上按先后排好三份记录。", [
				_action("withdrawal", "c5:withdrawal_log", "撤守手记", "read", "读撤守手记", "十天前的撤守手记写着：『开路与救伤不停抽走人手，各站已抽不出轮换的人。先撤伤员与部分驻守，留下余下各站接力。』\n签名是韩铎。附注里认了接应之地会缩小，却没有料到音信会全断。", [], {"prompt": "撤守手记正翻在签名那一页。墨迹比前头的巡路记录更深。"}),
				_action("route_log", "c5:route_log", "分队路书", "read", "读分队路书", "分队路书的补记，晚于撤守令：先是灯壳积水，随后灯芯断油，再有雪站转轴冻住。没人日日排水、添油、除冰，旧灯机接连停下，改道的消息也送不出去。\n这些变故，都出在撤守之后。", [], {"prompt": "分队路书上画满了路线，最后几行却只剩下往来的记录。"}),
				_action("causality", "c5:evidence_board", "失联对证板", "puzzle", "排定先后", "几份记录终于接上了：先是分队，人手耗尽后撤守，无人照料的灯机接连停下，各站这才断了音信。\n韩铎没有辩解：「我救回了人，也小看了这些旧灯，也没留足备用传讯的法子。回平原之后，原件与经过，我一并交代。」", ["withdrawal", "route_log"], {"puzzle_order": ["split", "withdrawal", "lost"], "prompt": "把丘陵文书和两份手记按先后放上对证板：分队之后下了撤守令，撤守之后各站才断了音信。", "rules": "正确次序：分队→撤守→失联。排错了只重来没排完的部分，手记不会丢。"})]),
			_step("最后的坐标", "听统领的打算，取最后的坐标，点亮雪原烽灯。", [
				_action("plans", "c5:leader", "远征统领韩铎", "talk", "听统领的打算", "「三个月前我们动身，为的就是让世界之心重新跳动，少叫人彻夜守灯。」韩铎摊开一张机关图。\n「旧塔里原有一套省力的慢传之法：调准之后，光走密闭的定灯路，外头的转轴不必再日夜转动，照料起来也就稀疏了。把沿途修好的这几处灯火接上去，阿苇、沈渡、罗墨和我便能回平原团聚，再轮班巡查。」", [], {"prompt": "韩铎望着重新接上的路线。「最后一处在熔岩山寨。这一回，要让消息接着走下去，也要让等候的人回得了家。」", "questions": [{"label": "世界之心停了多久？", "answer": "「四十年前，矿脉衰减，商路改道，各处不愿再出钱出力，盟会散了，灯枢也就封存了。此后全靠人手，一盏盏烽灯接力。我们这一回断了音信，正是那些老灯一盏接一盏停了。」"}, {"label": "回平原之后，远路交给谁照看？", "answer": "「省力的慢传之路，传的不过寥寥几句灯语和口信。灯油零件仍要人添，各站仍要人巡，我们轮班出去；救人从平原动身。赶路的人莫要以为灯亮着，就随时有人送药上门。」"}, {"label": "去熔岩之前，须备些什么？", "answer": "「用法与零件是大伙找回来的，是你把它们接到了一处。先回营检点行装、带足补给。龟王若还在，这一趟便免不了真刀真枪。」"}], "rules": "熔岩之行建议：Lv6 或同等装备，先强化装备、备足补给。只赶主线也许仍是 Lv3；在场的熔岩龟王须亲手击败。"}),
				_action("coordinates", "c5:lava_coordinates", "最后的坐标", "recover", "取最后的坐标", "最后的坐标指向熔岩山寨的落脚处。纸背抄着远征队核对过的口诀：\n『西封旧路，东续新灯，中定节拍。』\n韩铎把用法那一页递来：「这不是只有你读得懂。我们做到了这一步，接下来托付你，把大伙留下的法子用上。」", ["plans"], {"quest_item": "c5:lava_coordinates", "prompt": "最后的坐标压在路书底下。纸背还抄着三句灯枢的用法口诀。"}),
				_action("beacon", "c5:beacon", "雪原烽灯", "repair", "点亮雪原烽灯", "你清开结冰的转轴，雪原烽灯亮起。韩铎望着来路：「我先守住这一头。等灯枢接通，我就带着手记回平原。罗墨和周照要问的，我都答。」", ["coordinates"], {"service": "snow_station", "next_chapter": "watch_c6_lava", "prompt": "雪原烽灯还连着旧线。灯火一通，留在避风处的统领便能照看这一头。"})])]),
		_chapter("watch_c6_lava", "熔火之心", "lava", 6, [
			_step("熔河之间", "读熔河界碑，沿石脊走到避火路标。", [
				_action("hazard", "c6:hazard_record", "熔河界碑", "read", "读熔河界碑", "熔河界碑上刻着：『沿石脊而行。熔流踏得进去，却是步步灼人。』\n旁边的箭头指向避火路标。", [], {"prompt": "灼热的风卷过界碑，字迹被熏黑了一半。动身的人在碑角补刻了一行提醒。", "rules": "踏进熔岩会不住受伤。竹水壶只能回魔，挡不住熔岩灼身。"}),
				_action("approach", "c6:route_approach", "避火路标", "observe", "察看避火之路", "你走到避火路标旁。石脊通向山寨外围，熔流从两边绕过。\n先到龟王山寨瞭望处看看，统领留下的路还通向何方。", ["hazard"], {"prompt": "避火路标立在石脊上，山寨的轮廓已看得清。"})]),
			_step("龟王盘踞之地", "察看龟王山寨，击败在场的龟王或查明空寨，取灯枢遗录。", [
				_action("fortress", "c6:fortress_record", "龟王山寨瞭望处", "read", "察看龟王光景", "山寨外的记录标出了灯枢铁锁与灯枢遗录的位置。\n龟王若还盘踞在此，须先击败它；寨中若已无龟王，查明光景便可继续。", [], {"prompt": "龟王山寨瞭望处留着一张烧焦的草图。通往灯枢的路要穿过山寨，图上没有画侧路。", "rules": "活着的熔岩龟王在场时，须亲手讨伐；眼下确无活口时，可现场查明。不必等它复生，也无需金钥匙。"}),
				_action("passage", "c6:bypass_control", "灯枢铁锁", "encounter", "打开灯枢通路", "你把寨中的经过记下，灯枢的路已可前行。灯枢遗录就在里头。", ["fortress"], {"boss_species": "熔岩龟王", "choices": ["defeated", "absent"], "opens": "c6:core_gate", "prompt": "灯枢铁锁仍扣着通路。先确认熔岩龟王已败在你手下，或寨中眼下确实空无一人，再往里走。", "rules": "只有你亲手了结的才算讨伐；探空寨另记一笔。首领日后再复生，也不会撤销这回通路、主线进度或已领的赏。"}),
				_action("core_record", "c6:core_record", "灯枢遗录", "recover", "取灯枢遗录", "灯枢遗录写明：一百六十年前，义路盟的人族村寨筹料让路，地精巧匠打造灯机，鳞族巡林人定下符记与接应之路，同心共建世界之心。\n各地原本交换粮米、矿器与药材，却常因封路、误传和走失而起争端，这才合修了一条公用的灯路。\n灯机借地心之火而转，寥寥几句灯语与口信，随着同一个节拍一盏盏传下去。夜里灯火明灭有律，宛如大地的心跳，『世界之心』的名字由此而来。", ["passage"], {"quest_item": "c6:core_record", "prompt": "灯枢遗录压在石台上。机关图上的三条线，分别通向西、东、中三条灯路。", "questions": [{"label": "三条灯路各管什么？", "answer": "西路封存：隔开年久失修的旧支路；东路续灯：接上沿途修好的灯火；中路定拍：让各处灯火同起同落，一灯缓缓传一灯。只接通这一回亲手修好的几处灯火。"}, {"label": "这儿能改变整个天下么？", "answer": "遗录所记，不过一套传灯的机关。灯枢救不回已经死去的人和族类，改不了天时，也替赶路的人探不了未知的路。没修的旧支路，依旧封存。"}]})]),
			_step("世界之心", "依次接通西、东、中三条灯路，再唤醒世界之心。", [
				_action("core_order", "c6:heart", "世界之心", "puzzle", "对一对灯枢次序", "西路隔开了失修的旧支路，东路接上了沿途修好的灯火，中路的节拍开始应和。\n你照远征队留下的用法调准了一切，世界之心只待最后一步。", [], {"puzzle_order": ["west", "east", "center"], "puzzle_objects": ["c6:core_west", "c6:core_east", "c6:core_center"], "prompt": "世界之心还没有亮。照灯枢遗录所记，依次接通西、东、中三条灯路。", "rules": "灯路次序：西→东→中。三条灯路接通后，还须在世界之心旁亲手唤醒。"}),
				_action("activate", "c6:heart", "世界之心", "repair", "唤醒世界之心", "世界之心亮起。阿苇的符记、沈渡走过的路、闻川核过的记录、罗墨护住的总图底稿，还有韩铎留下的用法，终于接在了同一条灯路上。\n修好的几处灯火开始一盏缓缓传一盏。各站传来短短的回话：「收到。回平原见。」", ["core_order"], {"service": "heart_station", "prompt": "中路的灯火已经接通，世界之心发出低沉的回响。唤醒它，沿途修好的各站便连成一线。", "rules": "世界之心只接通修好的几处，传寥寥几句灯语与口信。远方仍要人巡、要人送补给；它改不了天时、野外的族类、巢穴与迁徙，也唤不回亡者。"})]),
			_step("归途团聚", "记下四人团聚与轮班之约，把归途的消息传回各站。", [
				_action("ending", "c6:ending_council", "归途名册", "conclude", "记下团聚约定", "你把大伙共同议定的归途写进名册：阿苇、沈渡、罗墨、韩铎回平原团聚，往后轮班巡查。\n阿苇不必再等一句无处可送的回话，沈渡的信终于送到了，罗墨保住了原件，韩铎会直面所有的追问。周照早已为他们留好了席位。", [], {"prompt": "归途名册旁，四站的回话一一到齐。灯火相传已稳，大伙都答应回平原，把下一班巡查排在同一张桌上。", "rules": "四位远征队员一同回到平原，补给也随之集中到一处；远方的烽灯继续相传。轮班巡查是往后的约定，并非人人当真日日巡走。第一章的石安仍守着哨所，检查点与回城照旧可用。"}),
				_action("settle", "c6:beacon", "熔岩烽灯", "repair", "传出归途的音信", "归途的音信从熔岩烽灯传出。阿苇、沈渡、罗墨、韩铎依约回到平原，同桌商定下一班巡查；闻川收到了沈渡的信，周照终于等回了旧同伴。\n石安仍守着哨所。你在那里接下的头一趟差事，总算有了能当面说出的下文。", ["ending"], {"service": "ending_station", "ending": true, "prompt": "熔岩烽灯旁摊着归途名册。把四人的归途与轮班之约送出去，再循着驿站回平原同他们相见。"})])]),

	]

static func side_chains() -> Array:
	if not _groups.has("side_chains"): _groups["side_chains"] = _seal(_side_chains())
	return _groups["side_chains"]

static func _side_chains() -> Array:
	return [

		_chain("side_patrol", "旧日巡队", "plains", "side", 1, [
			_step("旧日巡队的徽记", "问一问接班的巡守，读旧日巡队名册，到旧歇脚处寻回徽记。", [
				_action("request", "side_patrol:giver", "新巡守", "talk", "听巡守的请求", "他们把旧巡队的差事交到我手上，却没人提起过那些人的名字。少侠能替我看看旧名册么？旧歇脚处还留着他们的徽记。", [], {"prompt": "新巡守把一枚空扣翻来覆去地看，见你停下脚步，才说起旧日巡队。", "questions": [{"label": "你为何在意他们的名字？", "answer": "空位可以补上，人却不该只剩一个空位。我想知道，自己接的是谁的班。"}]}),
				_action("record", "side_patrol:record", "旧日巡队名册", "read", "对一对姓名", "旧名册上写着轮班与接应之人的姓名。徽记纹样对得上，离开的日期却空着。它能证明谁在这里守过，却不能替每一个没回来的名字，写下死讯。", ["request"], {"prompt": "名册最后几页磨得发薄。翻到旧巡队换岗的那一天。"}),
				_action("badge", "side_patrol:target", "遗留的身份徽记", "recover", "寻回徽记", "徽记背面的刻字与名册一一相合。你把它收好，这一回，能给新巡守带回几个确切的姓名了。", ["record"], {"quest_item": "side_patrol:badge", "prompt": "旧歇脚处压着一枚徽记。拂去尘土，对一对背面的刻字。"})]),
			_step("新巡守的归处", "为新巡守选定驻守之处，亲手在选定的驻地挂上徽记。", [
				_action("station", "side_patrol:resolution", "巡守驻地名册", "choice", "选择巡守驻地", "新巡守在你选定的驻地名下落了笔：好，就去那里。徽记挂上，我们便算接下了这一班。", [], {"choices": [{"id": "camp", "title": "营中接应", "consequence": "新巡守驻在营中，接应初来乍到的人，并提供驻站补给", "risk": "到营中驻守处挂上徽记后生效"}, {"id": "forest", "title": "林间传信", "consequence": "新巡守驻在林间，帮着传递音信，并提供驻站补给", "risk": "到林间驻守处挂上徽记后生效"}], "rules": "选定之后，到对应的驻守处挂上徽记。第一章的哨所巡守不会迁走。", "prompt": "新巡守合上名册：营中要人接应，林间要人传信。叫我接哪一班？"}),
				_action("settle", "side_patrol:station_camp", "营中驻守处", "repair", "挂上徽记，驻守于此", "徽记挂上了驻守处的木架。新巡守摸了摸刻字：我便在这里接下这一班。歇会儿吧，给你留了一份补给。", ["station"], {"destination_by_choice": {"camp": "side_patrol:station_camp", "forest": "side_patrol:station_forest"}, "service": "patrol_station", "prompt": "把徽记挂到选定的驻守处，让来往的人认得这位新巡守。", "rules": "选定的驻守处可买东西，另有一份驻站补给；补给只给一次。"})])]),
		_chain("side_herbalist", "一药两难", "forest", "side", 2, [
			_step("学徒留下的记录", "听草药师说失散学徒的去向，寻回那页用药记录。", [
				_action("request", "side_herbalist:giver", "草药师", "talk", "询问学徒", "学徒把药封好了，偏生没带回用药的记录。我不敢只凭记性就叫人服下。劳烦替我寻回那页纸，先弄清这药原是留给谁的。", [], {"prompt": "草药师按着一张缺了页的药单。且听听他在担心什么。", "questions": [{"label": "不能再配一包么？", "answer": "手头只有学徒封好的这一包。先寻回用药记录，我才敢把它交出去。"}]}),
				_action("record", "side_herbalist:record", "学徒用药记录", "read", "读用药记录", "学徒写道：伤者等药救命，站里的存药也空了。纸上圈了又圈，到头来只封得出这一包。", ["request"], {"prompt": "用药记录上有两处圈记。展开纸页，看看学徒留下的话。"}),
				_action("medicine", "side_herbalist:medicine", "学徒封存药包", "recover", "收好封存药包", "药包的封条还完好。纸上那两处圈记有了分量：这包药带走之后，只能送往一处。", ["record"], {"quest_item": "side_herbalist:medicine", "prompt": "药包还放在封存处。验一验封条，收好它。", "rules": "这包药单独保管，算任务物件；送出一次便用掉，卖不得。"})]),
			_step("一药两难", "定下这包药是救眼前伤者，还是留给站点做储备，再亲手送去。", [
				_action("purpose", "side_herbalist:resolution", "药包用途牌", "choice", "决定药包用途", "用途牌上留下了你的抉择。草药师收起笔：带上这一包药，送到你选定的那一头去吧。", [], {"choices": [{"id": "patient", "title": "救助伤者", "consequence": "这一包药用于救助眼前伤者", "risk": "这包药用掉便没了；这一回储备处不开放补给"}, {"id": "reserve", "title": "留作站点储备", "consequence": "这一包药送进站点储备，驻站补给重新开放", "risk": "这包药用掉便没了；伤者没拿到这包药；他的生死，此处不作断言"}], "rules": "送伤者，便是救人一命；送储备处，便是重开驻站补给。二者只可选一，须亲自送到选定之处。", "prompt": "用途牌上两处圈记都还在：把药送到眼前伤者手里，还是留给站点做储备？"}),
				_action("deliver", "side_herbalist:patient", "等待药包的伤者", "deliver", "交付这一份药", "药包交到了你选定的人手里。封条拆下收好，另一头的圈记，仍旧留在药单上。", ["purpose"], {"destination_by_choice": {"patient": "side_herbalist:patient", "reserve": "side_herbalist:station_reserve"}, "consumes": "side_herbalist:medicine", "service": "herbalist_reserve", "service_choices": ["reserve"], "prompt": "把这一包药亲手送到选定之处。", "rules": "这包药只送得一次。送了伤者，储备处便不开放。"})])]),
		_chain("side_hunter", "收起的悬赏", "plains", "side", 3, [
			_step("旧日的猎数", "对一对猎户的旧账、现场的足迹和生态记录，分清这些死亡从何而来。", [
				_action("request", "side_hunter:giver", "营地猎户", "talk", "听猎人质疑", "旧账上还记着那么多，眼前连脚印都稀了。少侠且慢拔刀。帮俺对一遍猎数，看看我们究竟漏了什么。", [], {"prompt": "猎户把悬赏压在账本底下，没有递给你。且听他说说疑处。", "questions": [{"label": "你疑心旧账写错了？", "answer": "俺疑心的是：拿昨天的数目，替今天下断语。脚印少了，总得弄个明白。"}]}),
				_action("book", "side_hunter:record", "旧日猎账", "read", "读旧猎数", "旧账一笔笔记着从前的猎数，后头的空白，却没说清那些减少去了哪里。要知道今日还剩多少，只有到猎场上去看。", ["request"], {"prompt": "账页上的数目改过几回。看看哪些有日期，哪些只剩下空白。"}),
				_action("survey", "side_hunter:target", "猎场足迹勘察桩", "observe", "辨认猎场足迹", "脚印、眼前的活物，还有这些时日里发生的死亡，已一一分开记下。猎户那张旧悬赏，须得重新掂量。", ["book"], {"ecology_mode": "hunter_counts", "prompt": "停在足迹旁，对一对眼前的动静与这些时日里的变化。", "rules": "所见只及记录在案的这段时日；去向不明的不算作死亡。"})]),
			_step("收起的悬赏", "依眼下的族群光景，或除患留余，或亲手立一块绕行的警示牌。", [
				_action("choice", "side_hunter:resolution", "猎户的新决定", "choice", "决定如何收尾", "猎户依你的意思改了安排：就这么办。到猎场上去办妥，再把光景记下来。", [], {"choices": [{"id": "local", "title": "看准了再除患", "consequence": "只动手除去一只合乎条件的当地活物，给族群留下余量", "risk": "须现场的活物仍对得上；目标有变，须回现场再看"}, {"id": "warning", "title": "收起悬赏并警示", "consequence": "收起悬赏，在旧猎场立下绕行警示", "risk": "不必猎杀；仍须亲自到警示牌前办妥"}], "rules": "除患须现场有走得到、打得过、且族群余量够的活物；立警示牌则不必猎杀。", "prompt": "猎户把决定交给你：附近若还有余量，便只除一只；也可以收起悬赏，立一块绕行的警示牌。"}),
				_action("result", "side_hunter:warning_sign", "旧猎场警示牌", "ecology", "回报猎场情况", "猎户看完你带回的结果，把旧悬赏折了起来：往后打这儿过的人，至少该知道眼前是什么光景。", ["choice"], {"destination_by_choice": {"local": "side_hunter:target", "warning": "side_hunter:warning_sign"}, "ecology_mode": "hunter_resolution", "prompt": "按选定的法子处置猎场，再把见到的变化记在这里。", "rules": "猎杀只算这一回你亲手了结的；活物少了或走了，便照眼前的实情查明，不会凭空多出怪物。"})])]),
		_chain("side_scholar", "残缺拓片", "hill", "side", 4, [
			_step("残缺拓片", "听拓碑先生说明缺口，到遗迹原碑前对一对，寻回遗失的拓片。", [
				_action("request", "side_scholar:giver", "拓碑先生", "talk", "询问拓印缺口", "这页拓片少了一角，偏生是记着旧道用途的那一行。在下不愿凭空补字。原碑还在，遗失的拓片兴许就在近旁。", [], {"prompt": "先生把缺角对着光，示意你看那一行断字。", "questions": [{"label": "为何一定要寻原物？", "answer": "猜对一个字不难，猜错一个字也不难。难的是后来的人，会把它当成真的。"}]}),
				_action("inscription", "side_scholar:record", "旧道铭文", "read", "对原碑铭文", "旧道铭文上留着三种手艺的印记：人族石匠的定位线，地精灯座的尺寸符，鳞族巡林人的方向刻记。\n碑下压着还能用的机关件。若取它来开近道，这一段字便要留下缺口。", ["request"], {"prompt": "贴近原碑，沿着拓片缺失之处细细查找。"}),
				_action("rubbing", "side_scholar:target", "遗失的拓片", "recover", "收回拓印", "纸上的断笔与原碑吻合。拓片寻回了，是留下碑文，还是取走机关件，这一回可以想明白了再定。", ["inscription"], {"quest_item": "side_scholar:rubbing", "prompt": "石边露出卷起的纸角。小心取回，同原碑对一对。"})]),
			_step("原样还是拆取", "选定保留铭文或拆取机关件，再到现场把这事办成。", [
				_action("choice", "side_scholar:resolution", "铭文去留书", "choice", "决定铭文去留", "先生记下你的决定，朝旧道望了一眼：想清楚了，就到原处动手吧。", [], {"choices": [{"id": "preserve", "title": "原样保留并补记", "consequence": "保留原铭文，补齐学者记录", "risk": "这一回不会取碑下机关件来开近道"}, {"id": "component", "title": "拆取部件开近道", "consequence": "拆取机关件，打开旧近道", "risk": "原碑铭文会留下缺口；须把机关件送到机关门装上"}], "rules": "保留，便补全铭文的记录；拆取，便打开一段近道，也留下铭文的缺口。", "prompt": "先生的手停在碑文缺角旁：保住这些字，还是取下机关件，让旧近道重新开通？"}),
				_action("resolve", "side_scholar:record", "旧道铭文", "repair", "到现场办妥", "你的抉择在旧道上留下了痕迹。往后打这儿过的人，会看见保留下来的字，或是那条重新开通的近道。", ["choice"], {"destination_by_choice": {"preserve": "side_scholar:record", "component": "side_scholar:shortcut_gate"}, "opens_choice": {"component": "side_scholar:shortcut_gate"}, "prompt": "在选定之处办妥：补记铭文，或装好取出的机关件。"})])]),
		_chain("side_merchant", "泥中货箱", "swamp", "side", 5, [
			_step("泥中货箱", "问清货箱的箱号，对一对货单，再到货箱落下的地方取回。", [
				_action("request", "side_merchant:giver", "赶路的行商", "talk", "询问失落货物", "那只箱子陷在泥岸，我一个人拖不动。两处站点都等着货，我却只带了这一箱。先劳你寻回货单，莫连该送往哪儿都弄错了。", [], {"prompt": "行商鞋边的泥还没干。他指着湿透的货单，欲言又止。", "questions": [{"label": "两头都在等这一箱？", "answer": "是啊。货单上写得满满的，箱子却只有这一只。近的不能不管，远的也不能装作没瞧见。"}]}),
				_action("waybill", "side_merchant:record", "湿透的货单", "read", "对一对箱号", "货单上列着浅滩近路和枯木外缘两处要用货的地方，正是沈渡走过的两条接应之路；箱号却只有一个。水渍没能替行商划去任何一头。", ["request"], {"prompt": "摊开湿货单，认清箱号与两处去向。"}),
				_action("crate", "side_merchant:crate", "落下的封存货箱", "recover", "回收货箱", "泥岸里的封箱与货单对得上。箱盖还结实，这批货可以送了。", ["waybill"], {"quest_item": "side_merchant:crate", "prompt": "察看泥岸货箱上的封签，确认无误便带上。", "rules": "封箱算任务物件，单独保管，不进随身行囊，也不会再冒出第二只。"})]),
			_step("这一箱送往何处", "选定一处茶棚，把这唯一一只封箱送到它的站点。", [
				_action("destination", "side_merchant:resolution", "货物去向牌", "choice", "选择收货站", "行商把你选的站点圈了出来：就送这边。货箱交到收货台，这一趟才算有了着落。", [], {"choices": [{"id": "near", "title": "近路茶棚", "consequence": "把唯一货箱送往近路，重开近路茶棚", "risk": "外缘茶棚收不到这箱货"}, {"id": "outer", "title": "外缘茶棚", "consequence": "把唯一货箱送往外缘，重开外缘茶棚", "risk": "近路茶棚收不到这箱货"}], "rules": "只有选定的茶棚恢复补给；须到那处茶棚亲手交出这唯一一只货箱。", "prompt": "行商望着一箱货、两处去向：送近路，方便来往；送外缘，能接住更远的人。你选哪头？"}),
				_action("deliver", "side_merchant:station_near", "近路收货台", "deliver", "交付封存货箱", "收货人在箱号旁签了字，动手把货摆上补给台。行商总算不必再抱着那张货单发愁。", ["destination"], {"destination_by_choice": {"near": "side_merchant:station_near", "outer": "side_merchant:station_outer"}, "consumes": "side_merchant:crate", "service": "merchant_station", "prompt": "把封箱送到选定站点的收货台。", "rules": "补给只由选定的站点给出；另一头没收到这箱货。"})])]),
		_chain("side_watchman", "望不见的旗", "hill", "side", 6, [
			_step("望不见的旗", "读瞭望人的值守簿，亲自查一查被山脊挡住的视线。", [
				_action("request", "side_watchman:giver", "瞭望人", "talk", "问问望不见的号旗", "低处那面旗望不见了。许是倒了，许是叫岩脊挡住了。劳动你走近瞧瞧，俺不想凭这点影子，就报一场袭击。", [], {"prompt": "瞭望人眯起眼望向低处，手停在还没写完的值守簿上。", "questions": [{"label": "望不见旗，意味着什么？", "answer": "只意味着俺这儿望不见。旗倒了，还是路叫什么挡了，都得走过去才晓得。"}]}),
				_action("record", "side_watchman:record", "值守视线草图", "read", "读视线草图", "草图上，旧旗与望台之间横着一段岩脊。近处好照看，高处能望见另一条来路。", ["request"], {"prompt": "顺着草图上的视线，认清旧旗和岩脊的位置。"}),
				_action("sight", "side_watchman:target", "旧旗视线勘察桩", "observe", "调查视线路径", "站到旧旗一旁，哪里被挡、哪里开阔，才看得真切。挪一挪旗位，胜过在望台上干猜。", ["record"], {"ecology_mode": "watch_sight", "prompt": "从旧旗旁望向岩脊，看看号旗会被何处遮住。"})]),
			_step("换岗之前", "选定近处或高处的旗位，亲手立起新旗，再记下换岗。", [
				_action("choice", "side_watchman:resolution", "新旗位置图", "choice", "选择新旗位", "新旗的位置定下来了。瞭望人把草图交到你手上：去把旗立起来，俺在这儿候着号旗。", [], {"choices": [{"id": "near", "title": "近处守望位", "consequence": "近处新旗指向入丘陵的落脚处，便于照看", "risk": "只指个大概方位；沿途光景仍须亲自查看"}, {"id": "high", "title": "高处守望位", "consequence": "高处新旗指向岩脊旧道另一端", "risk": "只有粗略方位；仍需亲自查看沿途情况"}], "rules": "近处旗指向入丘陵的落脚处；高处旗指向岩脊旧道另一头。只指个方向。", "prompt": "瞭望人摊开新图：近处容易照看，高处朝着另一条来路。这面旗立在哪一头？"}),
				_action("flag", "side_watchman:watch_near", "近处新旗位", "repair", "竖起新号旗", "新旗在选定的位置展开。瞭望人留下了新的方向说明，旧草图总算可以收起来了。", ["choice"], {"destination_by_choice": {"near": "side_watchman:watch_near", "high": "side_watchman:watch_high"}, "service": "watchman_station", "prompt": "在选定之处竖好旗杆，重新标出认得清的方向。", "rules": "方向说明看不见远处的活物，也保不了沿途平安。"})])]),
		_chain("side_letter", "冻住的信筒", "snow", "side", 7, [
			_step("冻住的信筒", "依着留下的收信记录认出信筒，亲手取出那封还没拆的信。", [
				_action("request", "side_letter:giver", "守书人", "talk", "询问无人取走的信", "这信筒冻住许久了，老朽一直没拆。写信的人走了，可候信的人还没收到。劳你看看登记，莫把它交错人了。", [], {"prompt": "守书人拂开信筒上的雪，露出一角署名。", "questions": [{"label": "为何一直没拆？", "answer": "那上头写的不是老朽的名字。老朽能替他守着，却不能替他读完。"}]}),
				_action("record", "side_letter:record", "收信登记", "read", "对一对信筒署名", "登记上的署名与信筒上的一样。信该交到那位旧队员手上；回不回、怎么回，都由他。", ["request"], {"prompt": "翻开收信登记，对一对筒口的署名。"}),
				_action("case", "side_letter:letter_case", "冻住的信筒", "recover", "取出密封信件", "筒口的积雪拂去，封着的信完完整整取了出来。署名还清楚，接下来该去寻收信的人了。", ["record"], {"quest_item": "side_letter:letter", "prompt": "打开冻住的信筒，收好里头还没拆封的信。", "rules": "信单独保管，卖不得；亲手送到之后便算交差。"})]),
			_step("收信的人", "寻到真正的收信人，在他身边把信交到手上，再听他把话说完。", [
				_action("recipient", "side_letter:recipient", "候信的旧队员", "talk", "确认收信身份", "旧队员看见封筒，先念出了登记上的署名：是给我的。我还当……先让我瞧瞧。", [], {"prompt": "把署名给旧队员看，请他认一认，这封信是不是写给自己的。"}),
				_action("deliver", "side_letter:recipient", "候信的旧队员", "deliver", "把信交到手中", "旧队员读了许久，轻声念出一句：「当时来不及解释，我回去接下一拨人了。」他把信折好：「老同伴总算把那天的事说清了。他如今身在何处，还没有消息。多谢你没把这信丢在雪地里。」", ["recipient"], {"consumes": "side_letter:letter", "prompt": "把密封的信交到旧队员手中。"}),
				_action("reply", "side_letter:resolution", "收信后的回执", "read", "收好回执", "回执上写着：『已经收到。』笔迹落得很稳，余下的空白，没有再添一句话。", ["deliver"], {"prompt": "收信后的回执放在一旁。看看旧队员留下了什么话。", "rules": "同一封信与回执只交得一次；读档续玩，不会重新寄送。"})])]),
		_chain("side_troll", "巨魔旧旗", "forest", "side", 8, [
			_step("巨魔旧旗", "认一认旧日人族的旗号，查一查巨魔王盘踞处旁的遗迹。", [
				_action("request", "side_troll:giver", "旧营故人", "talk", "听旧旗来历", "那面旗比巨魔王来得还早。我们总盯着那位大王，倒把旗下住过什么人给忘了。去看看旗背吧，那上头兴许还认得回房间的路。", [], {"prompt": "故人认出了褪色的旗，却没有先说巨魔王。", "questions": [{"label": "非得去会一会巨魔王么？", "answer": "先寻房间吧。那位大王拦不拦路是一回事，旗下的人留下了什么，是另一回事。"}]}),
				_action("flag", "side_troll:record", "褪色的人族旗号", "read", "辨认旧旗", "旗背缝着三个小小的纹样：叶、石、灯。下头的针脚指向旧房间，像是给归来的人留的记号。", ["request"], {"prompt": "翻过褪色的旧旗，认一认背面的缝线。"}),
				_action("site", "side_troll:target", "巨魔盘踞处旧遗迹", "observe", "察看眼前的遗迹", "旧日人族的遗迹就在盘踞处旁。那位大王的踪迹要看眼前，房间的门却只认那些旧符记。", ["flag"], {"ecology_mode": "troll_state", "prompt": "走近遗迹，巨魔王的踪迹与旧房间的入口，分别察看。", "rules": "巨魔王可会可不会；眼下没有活口，也能接着查房间，不必等它，也不会硬叫它复生。"}),
				_action("challenge", "side_troll:target", "巨魔盘踞处旧遗迹", "boss", "记下这一战的胜负", "巨魔王倒下的经过已记下。你转身望向旧房间，那面旗里的疑问还在那儿。", ["site"], {"optional": true, "boss_species": "巨魔王", "prompt": "记下这一回亲手会巨魔王的结果。", "rules": "只算这一回你亲手讨伐的；这一战可打可不打，不碍着查房间，也不另发剧情奖励。"})]),
			_step("遗留的房间", "在房间外按叶、石、灯的次序触碰符记，开了门，再亲手取回记录。", [
				_action("runes", "side_troll:room_runes", "旧房间符记", "puzzle", "排列旧房间符记", "叶、石、灯依次亮起。门后的尘土动了一动，旧房间总算重新朝着来路开了门。", [], {"puzzle_order": ["leaf", "stone", "lamp"], "puzzle_objects": ["side_troll:rune_leaf", "side_troll:rune_stone", "side_troll:rune_lamp"], "opens": "side_troll:room_gate", "prompt": "照旧旗上的次序，触碰叶、石、灯三枚符记。", "rules": "按错了只清掉没按完的那一段；开这房间不必巨魔王的掉落物。"}),
				_action("record", "side_troll:room_record", "旧房间住客簿", "recover", "取回房间记录", "薄册上列着借宿之人与离开的日期。人族曾在这里歇脚，后来确实走了；眼下巨魔王在不在，要看现场。仅凭这面旧旗，断不能说那位大王害了所有住过的人。", ["runes"], {"quest_item": "side_troll:room_record", "prompt": "门内还留着一本住客簿。进去取回它。"})])]),
	]

static func regional_arcs() -> Array:
	if not _groups.has("regional_arcs"): _groups["regional_arcs"] = _seal(_regional_arcs())
	return _groups["regional_arcs"]

static func _regional_arcs() -> Array:
	return [

		_chain("region_plains", "三岔茶棚", "plains", "regional", 1, [
			_step("察看旧补给点", "旧近路仓与外缘接应处各去看一看，弄清两处原本作何用处。", [
				_action("near", "region_plains:survey_a", "旧近路仓", "read", "察看近路仓旧签", "旧签上写着给新巡守备粮，如今货架却空着。要叫这里重新接得住来往的人，须得先把补给的路寻回来。", [], {"prompt": "察看近路仓的旧签与货架。"}),
				_action("outer", "region_plains:survey_b", "外缘接应处", "observe", "调查外缘接应处", "外缘接应处更远，却朝着另一条来路。站在这里才明白，旧图为何没有只画近路。", [], {"prompt": "走到外缘接应处，看看它照顾的是哪一条路。"})]),
			_step("集中还是分设", "定下补给如何摆布，带着专门的物件到选定的活计处装上。", [
				_action("choice", "region_plains:choice", "补给布置图", "choice", "定下补给布置", "选定的补给之路已在图上圈明。带上标识，到对应的活计处，把这条路落到实处。", [], {"choices": [{"id": "near", "title": "集中在近路", "consequence": "补给集中在近路，完工后到茶棚领取", "risk": "沿近路走验之后开放；站中饭团只有一份"}, {"id": "outer", "title": "分设在外缘", "consequence": "补给分设到外缘，完工后两处都能领", "risk": "茶棚与外缘货台共用一份饭团，领了一处便没了"}], "rules": "集中，只开放茶棚；分设，另开放外缘货台，两处共用一份饭团。", "prompt": "补给图上，近路便于照看，外缘能多接一条来路。补给是集中一处，还是分两头摆？"}),
				_action("work", "region_plains:work_near", "近路补给木架", "repair", "挂上补给标识", "补给标识挂稳了，选定的来路总算有了清楚的方向。沿着它走一遍，看能不能一路走到茶棚。", ["choice"], {"destination_by_choice": {"near": "region_plains:work_near", "outer": "region_plains:work_outer"}, "prompt": "把标识挂到选定的补给木架上。"})]),
			_step("三岔口的一条路", "走完选定的补给之路，到茶棚里看一看可用的补给。", [
				_action("walk", "region_plains:station", "三岔茶棚", "route", "试走补给之路", "标识把你引到了茶棚，沿途的拐弯也都走过了。下一拨赶路的人，可以认着这些记号寻来。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_plains:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_plains:work_near", "region_plains:station"], "outer": ["region_plains:work_outer", "region_plains:station"]}, "prompt": "从选定的活计处沿路标走到茶棚，再把这条路对一对。"}),
				_action("station", "region_plains:station", "三岔茶棚", "repair", "开张茶棚", "三岔茶棚的补给台支了起来。来人可以在这儿歇一歇脚，再看清下一段路。", ["walk"], {"service": "region_plains_station", "choice_stage": "region_plains:s2", "service_endpoints_by_choice": {"near": ["region_plains:station"], "outer": ["region_plains:station", "region_plains:work_outer"]}, "prompt": "挂好茶棚最后一块标识，收拾站中的补给。", "rules": "饭团只有一份。分设两处的领取点共用这一份，领过一处，另一处便不再给。"})])]),
		_chain("region_forest", "树下边界", "forest", "regional", 2, [
			_step("巢区与来路", "巢穴与行人来路各查一遍，记下眼下两相冲突之处。", [
				_action("clue", "region_forest:guide", "林缘巡路人", "talk", "询问巢区旧路", "旧图上这处曾是巢穴，我把认得的路给你标上。今日里头还住没住着东西，得请少侠走近瞧瞧。别只照着旧图就动手。", [], {"ecology_mode": "nest_clue", "prompt": "林缘巡路人摊开旧图，手指停在林下的一处记号上。"}),
				_action("nest", "region_forest:survey_a", "林下巢穴勘察桩", "observe", "察看林下巢穴", "巢穴与眼前的动静已对过了。旧图能带你寻到这儿，接下来路怎么让，还得看今日的光景。", ["clue"], {"ecology_mode": "nest_survey", "prompt": "走近巢址，看看巢穴和四周还有没有动静。"}),
				_action("trail", "region_forest:survey_b", "林间来路勘察桩", "observe", "对一来路", "行人的来路在林缘拐了开去，同巢穴的地界并不全然相合。多绕几步，也许就能给两头都留出余地。", [], {"prompt": "沿林间来路看看，哪里绕得开巢穴。"})]),
			_step("捣巢还是绕行", "定下是暂时捣了眼前的巢穴，还是在林缘立起绕行的标识。", [
				_action("choice", "region_forest:choice", "林下边界图", "choice", "选择处理方式", "处置的法子写在了边界图上。到选定之处动手，再看看这条路怎样接回树下。", [], {"choices": [{"id": "near", "title": "看准了再捣巢", "consequence": "暂且捣毁眼前的巢穴，再沿巢穴之路走验", "risk": "巢穴日后仍可能重筑；须先有对得上的当地活物"}, {"id": "outer", "title": "标出林缘绕行", "consequence": "标出林缘绕行之路，给来路和巢穴留出余地", "risk": "不必猎杀；仍须沿外缘之路走上一遭"}], "rules": "捣巢只能压一压繁衍，须有对得上的现场活物；绕行不必猎杀。巢穴有了变化，须再来看。", "prompt": "行人的路贴着巢穴地界。是暂且捣巢、腾出通行的空当，还是沿林缘标出一条绕行之路？"}),
				_action("work", "region_forest:work_near", "巢区落脚处", "ecology", "记下巢区处置", "这一回处置的光景已记下。现在沿选定的路走回守望之处，看看标识该朝向哪边。", ["choice"], {"ecology_mode": "nest_resolution", "destination_by_choice": {"near": "region_forest:work_near", "outer": "region_forest:work_outer"}, "prompt": "在选定的活计处看看捣巢之后的光景，或标出林缘绕行之路。", "rules": "只记这一回的捣巢或现场察看；巢穴自己的变化，不算你捣的。"})]),
			_step("树下的新标识", "亲手走完选定的路，在林下站点修好对应方向的标识。", [
				_action("walk", "region_forest:station", "树下凉亭", "route", "试走林下之路", "一路走来，标识与来路总算对上了。回到树下，已知道该怎样把下一位行人引过来。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_forest:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_forest:work_near", "region_forest:station"], "outer": ["region_forest:work_outer", "region_forest:station"]}, "prompt": "沿选定的路一段一段走到树下凉亭。"}),
				_action("sign", "region_forest:station", "树下凉亭", "repair", "修复方向标识", "新标识朝着你刚走过的路，凉亭里重新备起了补给。林下的路有了交代，路过巢穴地界时仍须留神。", ["walk"], {"service": "region_forest_station", "prompt": "固定方向标识，收拾树下凉亭。"})])]),
		_chain("region_swamp", "两条归路", "swamp", "regional", 3, [
			_step("动工前的两条路", "近路与外缘再走一遍，这一回要记下动工的地方。", [
				_action("near", "region_swamp:survey_a", "泥岸近路工地", "observe", "测近路障碍", "近路上横着一段碎岩，湿痕一直渗到石缝里。要从这儿过，须先打出容人通过的口子。", [], {"prompt": "沿泥岸近路查看堵住通路的碎岩。"}),
				_action("outer", "region_swamp:survey_b", "枯木外缘工地", "observe", "测外缘接应处", "枯木外缘有一处架得起补给台的地方。路绕得远，至少能叫人停下脚，把下一段路看清。", [], {"prompt": "查看外缘的落脚处，量好支架与标识的位置。"})]),
			_step("开路或搭棚", "选定是破开路册所记的岩障，还是在外缘搭起绕行的茶棚。", [
				_action("choice", "region_swamp:choice", "归路工程图", "choice", "选择归路工程", "归路的工程定下来了。先到选定之处动工，再用脚走通图上那条线。", [], {"choices": [{"id": "near", "title": "破除近路岩障", "consequence": "打碎近路岩障，接通较短归路", "risk": "须穿过这一回新开的岩缝，走到茶棚"}, {"id": "outer", "title": "外缘搭起茶棚", "consequence": "在外缘搭起绕行茶棚的木架", "risk": "路程更远；须沿外缘一段一段走验"}], "rules": "近路须打碎指定的岩障；外缘须搭起木架。水面的规矩不变。", "prompt": "归路图上记着两桩活：打通近路碎岩，或在外缘搭茶棚。先叫哪一条路好走些？"}),
				_action("work", "region_swamp:work_near", "近路岩障", "repair", "看过动工的结果", "选定之处的活做完了。还得用脚走一遍，才能把这条归路指给别人。", ["choice"], {"destination_by_choice": {"near": "region_swamp:work_near", "outer": "region_swamp:work_outer"}, "obstacle_by_choice": {"near": "region_swamp:near_barrier"}, "prompt": "破开近路岩障，或在外缘搭好茶棚木架，再查一遍。"})]),
			_step("脚下的归路", "沿新修的路走上一遭，再开张归路茶棚。", [
				_action("walk", "region_swamp:station", "归路茶棚", "route", "亲身走验归路", "你从这一回修好的路段走到了茶棚。脚下这条归路，总算同工程图接上了。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_swamp:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_swamp:work_near", "region_swamp:station"], "outer": ["region_swamp:work_outer", "region_swamp:station"]}, "prompt": "沿新修的路段走到茶棚；近路须穿过刚打开的缺口。"}),
				_action("station", "region_swamp:station", "归路茶棚", "repair", "开张归路茶棚", "归路茶棚的标识立稳了，补给也有了去处。下一个走出泥岸的人，能在这儿缓一口气。", ["walk"], {"service": "region_swamp_station", "prompt": "收拾茶棚，开张归路补给。"})])]),
		_chain("region_hill", "岩脊旧道", "hill", "regional", 4, [
			_step("旧道两端", "寻到岩脊旧道的两头，查清哪里叫碎岩堵住、哪里还留着机关。", [
				_action("south", "region_hill:survey_a", "岩脊旧道南端", "read", "察看南端标记", "南端的旧标记指着碎岩后的缝隙。堵路的是这段碎石，旧道仍有打通的可能。", [], {"prompt": "擦去南端标记上的灰，看看它指向哪里。"}),
				_action("north", "region_hill:survey_b", "岩脊旧道北端", "observe", "调查北端机关", "北端还留着一处机关。它连着另一道门，能从这一头接回旧路。", [], {"prompt": "察看北端机关与门之间的牵连。"})]),
			_step("碎岩与旧机关", "选定是破开碎岩，还是扳动北端机关，开出一条真正走得通的路。", [
				_action("choice", "region_hill:choice", "岩脊工程牌", "choice", "选择开路方法", "开路的一头选好了。旧道还等着你动手，碎岩和机关都不会自己让出路口。", [], {"choices": [{"id": "near", "title": "破除南端碎岩", "consequence": "破除南端碎岩，从缺口接回旧道", "risk": "须亲手打碎指定的岩障，穿过新开的缺口"}, {"id": "outer", "title": "操作北端机关", "consequence": "修好北端机关，打开另一处旧道入口", "risk": "须在北端扳动机关，再穿过门走验旧道"}], "rules": "南端须打碎碎岩、穿过缺口；北端须扳动机关、穿过开启的门。", "prompt": "旧道南端堵着碎岩，北端还留着机关。选一头开路，再到接应处看看。"}),
				_action("work", "region_hill:work_near", "南端碎岩", "repair", "确认旧道开通", "旧道在选定的一头打通了。先别急着立通行牌，走到另一头看看。", ["choice"], {"destination_by_choice": {"near": "region_hill:work_near", "outer": "region_hill:work_outer"}, "obstacle_by_choice": {"near": "region_hill:near_barrier"}, "opens_choice": {"outer": "region_hill:shortcut_gate"}, "prompt": "清开南端碎岩，或修好北端机关，检查眼前的入口。"})]),
			_step("岩脊凉亭", "走通修好的旧道，到山脊凉亭挂上最后一块标识。", [
				_action("walk", "region_hill:station", "岩脊凉亭", "route", "试走旧道", "从打开的入口一路走来，凉亭就在眼前。那些指向旧道的记号，重新有了着落。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_hill:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_hill:work_near", "region_hill:station"], "outer": ["region_hill:work_outer", "region_hill:station"]}, "prompt": "穿过选定的入口，沿旧道走到岩脊凉亭。"}),
				_action("station", "region_hill:station", "岩脊凉亭", "repair", "开张岩脊凉亭", "凉亭里亮起了标识，补给摆在伸手可及的地方。山脊那头的来人，如今有了认得出的去处。", ["walk"], {"service": "region_hill_station", "prompt": "挂好最后一块标识，开张岩脊凉亭。"})])]),
		_chain("region_snow", "白地归途", "snow", "regional", 5, [
			_step("看得见的路标", "在白地两头各寻到看得见的路标，认清开阔之路与借掩之路。", [
				_action("open", "region_snow:survey_a", "开阔地旧路标", "read", "辨认开阔线路标", "旧路标指着开阔地，路短，前头却少有遮拦。远处的方向看得清，自己也同样显眼。", [], {"prompt": "拂开路标上的积雪，辨认开阔线。"}),
				_action("cover", "region_snow:survey_b", "冰脊后旧路标", "observe", "察看借掩之路", "冰脊后的路拐弯更多，走起来也长。顺着地势绕行，能借到一路的遮蔽。", [], {"prompt": "沿冰脊察看借掩之路的拐弯。"})]),
			_step("短路与掩护", "选短的开阔之路，还是长的借掩之路，在对应之处搭好歇脚的棚子。", [
				_action("choice", "region_snow:choice", "白地归途图", "choice", "选择休整线", "歇脚之路已在图上标明。把棚子搭到选定的路旁，再沿那些路标走一遍。", [], {"choices": [{"id": "near", "title": "短开阔线", "consequence": "把歇脚棚搭在较短的开阔之路", "risk": "地势少遮拦；须沿此路走到歇脚处"}, {"id": "outer", "title": "长的借掩之路", "consequence": "把歇脚棚搭在较长的借掩之路", "risk": "拐弯和路程更多；须沿此路走到歇脚处"}], "rules": "选哪条路，便决定歇脚棚搭在哪、走验哪条路；不添冻伤或饥饿的规矩。", "prompt": "开阔之路较短，冰脊后的借掩之路拐弯更多。歇脚棚搭在哪条归路旁？"}),
				_action("work", "region_snow:work_near", "开阔线歇脚棚", "repair", "安装休整设施", "歇脚棚在选定的路旁立住了。回头还看得见来时的标识，接下来得把它们连到歇脚处。", ["choice"], {"destination_by_choice": {"near": "region_snow:work_near", "outer": "region_snow:work_outer"}, "prompt": "架好休整设施，把路标转向所选线路。"})]),
			_step("归途有人留灯", "沿选定的路走到歇脚处，看清归途的标识与补给。", [
				_action("walk", "region_snow:station", "白地歇脚处", "route", "试走白地归途", "选定的路标一路把你引到歇脚处。白地上那些容易走混的拐弯，如今都有了认得出的记号。", [], {"route_corner_count_by_choice": {"near": 2, "outer": 4}, "choice_stage": "region_snow:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_snow:work_near", "region_snow:station"], "outer": ["region_snow:work_outer", "region_snow:station"]}, "prompt": "沿选定的路一段一段走到白地歇脚处。"}),
				_action("station", "region_snow:station", "白地歇脚处", "repair", "点亮休整标识", "标识亮了起来，补给摆上歇脚处。归来的人纵然一时辨不清远处，也有这一点方向可寻。", ["walk"], {"service": "region_snow_station", "prompt": "点亮休整标识，整理白地补给。"})])]),
		_chain("region_lava", "熔河之界", "lava", "regional", 6, [
			_step("熔流的两侧", "到跟前往看熔岩灼人的地界两头，记下走得过的石脊。", [
				_action("near", "region_lava:survey_a", "近侧熔流边界", "observe", "调查近侧边界", "近侧熔流的地界已看清。石脊可以落脚，跨进熔流仍会灼伤。记路时须把这条界线看牢。", [], {"prompt": "在石脊上察看近侧熔流，莫为了察看踩进灼热之地。"}),
				_action("outer", "region_lava:survey_b", "远侧石脊", "observe", "调查远侧石脊", "远侧石脊绕出更大一圈，却能避开眼前的熔流。值得标下来，叫赶路的人有得选。", [], {"prompt": "沿安全石脊查看远侧来路。"})]),
			_step("留在石脊上", "两条绕行之路都已看过，选一条，修好对应方向的标识。", [
				_action("choice", "region_lava:choice", "熔河绕行图", "choice", "选择石脊绕行线", "选定的石脊之路留在了图上。带好标识，沿着落脚得稳之处把这条路接起来。", [], {"choices": [{"id": "near", "title": "近侧石脊", "consequence": "修复近侧石脊的绕行标识", "risk": "贴近熔流；熔岩照样灼人，须留在石脊上"}, {"id": "outer", "title": "远侧外缘", "consequence": "修复远侧外缘的绕行标识", "risk": "绕得更远；熔岩照样灼人，须留在石脊上"}], "rules": "标识与走验之路依你的选择而定；熔岩伤人照旧，并不护身。", "prompt": "两条石脊都看过了：近侧更贴熔流，外缘绕得更远。选一条接到茶棚。"}),
				_action("work", "region_lava:work_near", "近侧绕行标识", "repair", "修复绕行标识", "耐热的标识钉牢在石脊上，指向下一处落脚点。看清标识再迈步，熔流仍在身旁流淌。", ["choice"], {"destination_by_choice": {"near": "region_lava:work_near", "outer": "region_lava:work_outer"}, "prompt": "把绕行标识固定在选定石脊上。"})]),
			_step("地界上的茶棚", "亲手走完选定的路，在石脊尽头开张茶棚。", [
				_action("walk", "region_lava:station", "石脊茶棚", "route", "试走熔河绕行之路", "沿石脊一路走到尽头，茶棚同沿途的标识接在了一处。这条绕行之路，总算可以交给后来的人。", [], {"route_corner_count_by_choice": {"near": 4, "outer": 4}, "choice_stage": "region_lava:s2", "routes": ["near", "outer"], "route_by_choice": {"near": ["region_lava:work_near", "region_lava:station"], "outer": ["region_lava:work_outer", "region_lava:station"]}, "prompt": "留在石脊上，沿选定的标识走到茶棚。"}),
				_action("station", "region_lava:station", "石脊茶棚", "repair", "开张石脊茶棚", "地界上的茶棚收拾好了。你给打这儿过的人留下一处歇脚之地，也留下一条避开熔流的路。", ["walk"], {"service": "region_lava_station", "prompt": "开张石脊尽头的茶棚。", "rules": "补给挡不住熔岩灼身；日后野外的变化，抹不去已完工的这些活计。"})])]),
	]

static func random_templates() -> Array:
	if not _groups.has("random_templates"): _groups["random_templates"] = _seal(_random_templates())
	return _groups["random_templates"]

static func _random_templates() -> Array:
	return [

		_chain("random_wounded", "野外伤者", "local", "random", 1, [
			_step("野外伤者", "看清伤者的呼救，取封存的药囊，回到他身边救治。", [
				_action("request", "random_wounded:giver", "伤者留下的呼救记号", "read", "辨读呼救记号", "歪歪斜斜的记号指着近旁的伤者，另一笔标着药囊所在。留下记号的人，至少还盼着有人寻见他。", [], {"prompt": "辨认路旁的呼救记号。"}),
				_action("aid", "random_wounded:parts", "封存的药囊", "recover", "取出药囊", "药囊取到手了，封条同呼救记号上的纹样一致。先带回伤者身边。", ["request"], {"quest_item": "random_wounded:aid", "prompt": "收好封存的药囊。", "rules": "这只药囊单独保管，不占卖得的物件，也不动你自备的补给。"}),
				_action("rescue", "random_wounded:target", "野外伤者", "rescue", "完成现场救助", "伤者撑着地坐起，呼吸渐渐匀了：我还当那记号没人看得懂。", ["aid"], {"prompt": "带着药囊回到伤者身边施救。", "rules": "这人只救得一次；读档不会让他再伤一回，也不会再发赏。"})])]),
		_chain("random_parcel", "遗落的包裹", "local", "random", 2, [
			_step("遗落的包裹", "对一对包裹封签，到落下的地方取回，再亲手交到收件人手上。", [
				_action("request", "random_parcel:giver", "包裹认领告示", "read", "读认领告示", "告示上画着包裹的封签，下头写着收件人等候的地方。字迹潦草，怕的是有人捡到了，却不知该交给谁。", [], {"prompt": "读一读包裹认领告示。"}),
				_action("parcel", "random_parcel:target", "遗落的封签包裹", "recover", "回收包裹", "包裹的封签同告示上的一样。外头沾了尘土，封口还完好，可以带去交还。", ["request"], {"quest_item": "random_parcel:parcel", "prompt": "对一对包裹的封签，收好它。"}),
				_action("return", "random_parcel:return", "包裹收件人", "deliver", "亲手交还包裹", "收件人把封签看了又看，才松开攥紧的手：就是这只，有劳你送回来。", ["parcel"], {"consumes": "random_parcel:parcel", "prompt": "把包裹交给等候的收件人。", "rules": "同一个包裹只交得一次；放弃、离线、读档，都不会再冒出一只。"})])]),
		_chain("random_sign", "断裂路标", "local", "random", 3, [
			_step("断裂路标", "读一读留言，取来这根路标专用的部件，到原处修好。", [
				_action("request", "random_sign:giver", "路标下的留言", "read", "读维修留言", "留言压在断木底下：替换的部件就搁在一旁，劳驾把横梁扶正。箭头指错了，后头的人会越走越远。", [], {"prompt": "拿起路标旁的维修留言。"}),
				_action("parts", "random_sign:parts", "路标替换部件", "recover", "取路标备件", "支脚同横梁上的刻记相合，正是这根路标缺的部件。带回断裂之处便能动手了。", ["request"], {"quest_item": "random_sign:parts", "prompt": "取出刻记吻合的路标备件。"}),
				_action("repair", "random_sign:target", "断裂的路标", "repair", "立起路标", "支脚扎稳，横梁归位。路标重新指着来路，不再垂头朝着泥地。", ["parts"], {"prompt": "用取回的备件修好路标。", "rules": "这部件只配得上这一根路标；每处维修只发一回赏。"})])]),
		_chain("random_rocks", "岩缝近道", "local", "random", 4, [
			_step("岩缝近道", "看清近道的两头，打碎路册所记的碎岩，再亲手穿过缺口。", [
				_action("request", "random_rocks:giver", "岩缝近道草图", "read", "核对近道草图", "草图沿着石缝画了一条短线，两头都留着进路的记号。拦在当中的是碎岩，清开了也许能少绕一程。", [], {"prompt": "对照草图，找到近道的两端。"}),
				_action("break", "random_rocks:target", "近道碎岩", "obstacle", "检查碎岩缺口", "挡路的碎岩已打散，岩缝露出通行的空隙。还得亲手穿过去，看看另一头。", ["request"], {"barrier_id": "random_rocks:barrier", "prompt": "击碎这处近道的岩障，再检查缺口。", "rules": "只算这一处路册所记的岩障；别处的碎岩不算。"}),
				_action("cross", "random_rocks:return", "近道另一端", "route", "穿过新开缺口", "你穿过新开的缺口，来到草图上的另一头。那条短线，如今成了一段真正走得通的路。", ["break"], {"routes": ["passage"], "route_waypoints": ["random_rocks:target", "random_rocks:return"], "prompt": "从刚打开的岩缝穿到近道另一端。", "rules": "须穿过新开的缺口；绕到两头去站一站，不算走过。"})])]),
		_chain("random_medicine", "救急药包", "local", "random", 5, [
			_step("救急药包", "当面问清药包的去处，取来封存的药囊，亲手交到等药的人手上。", [
				_action("request", "random_medicine:giver", "求药人", "talk", "问清药包去处", "巡守还等着那包药，封存处就在近旁。劳你替我取来，认准封签，莫拿错了。", [], {"prompt": "求助人指了指封存药物的位置。"}),
				_action("medicine", "random_medicine:parts", "封存的药囊", "recover", "取封存药包", "药包的封签同求药人所说的一样。拿稳了，巡守还等着它。", ["request"], {"quest_item": "random_medicine:medicine", "prompt": "核对封签，取出这次需要的药包。", "rules": "用的是任务药包，不扣快捷栏或行囊里自备的补给。"}),
				_action("deliver", "random_medicine:target", "候药的巡守", "deliver", "确认交付药包", "巡守接过药包，细细验过封口：来得正好，这下心里踏实了。", ["medicine"], {"consumes": "random_medicine:medicine", "prompt": "把药包亲手交给等待的巡守。", "rules": "药包送出一次便用掉了，不能再送别人。"})])]),
		_chain("random_message", "留守口信", "local", "random", 6, [
			_step("留守口信", "听留守之人交代口信，对准封签，送到另一位接信人手上。", [
				_action("request", "random_message:giver", "留守传信人", "talk", "听留守口信", "接应人就在这一带，却不知道我还守在这儿。替我带个口信过去吧，叫他别再往回寻了。", [], {"prompt": "留守传信人把一只封套推到你面前。"}),
				_action("message", "random_message:target", "留守口信封套", "recover", "取讯息封套", "封套上记着写下口信的时辰。那是留守之人当时所见，送到时情形也许已有变故。", ["request"], {"quest_item": "random_message:message", "prompt": "收好留守口信，核对接收者。"}),
				_action("deliver", "random_message:return", "当地接应人", "deliver", "交付留守口信", "接应人看过署名与时辰，点点头：知道他还留着话就好。眼下的路，我再亲自去瞧瞧。", ["message"], {"consumes": "random_message:message", "prompt": "把封套交到当地接应人手中。", "rules": "署名与时辰都留着；那是当时所见，并不一直追着目标看。"})])]),
		_chain("random_nest", "巢穴临道", "local", "random", 7, [
			_step("巢穴临道", "到跟前往看临路的巢穴，或暂时捣巢，或当场认清绕行之路，再交上结果。", [
				_action("request", "random_nest:giver", "临道巢区告示", "read", "核对巢区线索", "路边的告示提醒来人：巢穴挨着通路，经过之前先看清楚。留字的人画了绕行之路，也标出了巢穴所在。", [], {"prompt": "读临道巢区告示，核对眼前位置。"}),
				_action("result", "random_nest:target", "眼前的临路巢穴", "ecology", "确认巢区处置", "巢穴眼下的光景同你的处置已记下。带回到路牌上，下一位行人才知道该留神什么。", ["request"], {"ecology_mode": "nest_resolution", "prompt": "查看这处临路巢穴，选择暂时捣巢或确认绕行。", "rules": "只把接下之后捣的巢记作讨伐；当场认清绕行之路，也算查完。"}),
				_action("report", "random_nest:return", "临道记录牌", "deliver", "写下当前路线说明", "路牌上添了这一回处理的时辰与法子。后来的人能据此判断，却仍须留神巢穴的新动静。", ["result"], {"prompt": "把当前路线说明写回临道记录牌。", "rules": "压制过后巢穴仍会重筑；不会因此再发一回赏。"})])]),
		_chain("random_migration", "迁徙见闻", "local", "random", 8, [
			_step("迁徙见闻", "读有来历的迁徙线索，到跟前往看，再记下眼下的结果。", [
				_action("request", "random_migration:giver", "迁徙见闻记录", "read", "读迁移线索", "见闻记录上写着从何处迁出、往何处迁入，还有发生的时辰。那道地界上有生灵走过，如今还寻不寻得到踪迹，得到跟前往看。", [], {"prompt": "读迁移目击记录，辨认来路和去路。"}),
				_action("site", "random_migration:target", "迁移线索现场", "observe", "核对迁移现场", "你对过了现场的留痕与眼前的动静。从前的迁徙有了今日的对照，走远了的，也照实记作走远了。", ["request"], {"ecology_mode": "migration_state", "prompt": "沿已知线索到场，查看现在的活动。", "rules": "目标已然离开，照实记下便算查完；不必等，也不会凭空造出一场迁徙。"}),
				_action("report", "random_migration:return", "见闻回执处", "deliver", "提交目击核对", "旧日见闻与这一回的察看，各记在各自的时辰旁。回头再看，便分得清哪是往事，哪是你今日亲眼所见。", ["site"], {"prompt": "回到目击回执点，留下本次核对结果。"})])]),
		_chain("random_camp", "除患留余", "local", "random", 9, [
			_step("除患留余", "到跟前往看当地族群与自身本事，除患留余；活物有了变故，便照实查明结案。", [
				_action("request", "random_camp:giver", "当地巢穴委托牌", "read", "核对当地委托", "委托牌上只求给这条来路减几分凶险。数目写得克制，末尾又添一句：先看现场，莫赶尽杀绝。", [], {"prompt": "查看当地据点委托与限定的处理数目。", "rules": "只有走得到、打得过、族群余量够的时候才发；天下同族不足六只，不接这单。"}),
				_action("result", "random_camp:target", "当地巢穴", "ecology", "回报据点情况", "这一回出手同巢穴眼下的变故已分开记下。够了便回去，空下来的地方，不必再追出一场恶斗。", ["request"], {"ecology_mode": "camp_resolution", "prompt": "按限定数目处理据点；目标变化时在现场复查。", "rules": "只算你亲手了结的，并给当地留下余量；目标迁走或自行消失，照实查明便罢。"}),
				_action("report", "random_camp:return", "当地委托回执处", "deliver", "确认据点结案", "回执上记了你做过的事，也记了巢穴已有的变故。这一趟有了交代，路上的新动静，留给来日的人再看。", ["result"], {"prompt": "把处理结果与现场变化带回委托回执点。", "rules": "不会凭空添怪物凑数；自然老死的，不算你猎的。"})])]),
		_chain("random_runes", "废墟符记", "local", "random", 10, [
			_step("废墟符记", "读一读遗迹的留字，照灯、路、人的次序触碰现场三枚符记。", [
				_action("request", "random_runes:giver", "废墟外的留字", "read", "读遗迹留字", "废墟外留着一句话：天黑了，且先想想，怎样等一个归来的人。旁边还有三行刻字。", [], {"prompt": "读废墟外的留字。"}),
				_action("record", "random_runes:record", "三行符记说明", "read", "读机关顺序", "第一行：点灯。第二行：辨路。第三行：等人。三枚符记依着灯、路、人排列。", ["request"], {"prompt": "沿三行刻字慢慢读下去。", "rules": "按错了只清掉没按完的，已得的记录不会丢。"}),
				_action("runes", "random_runes:target", "废墟符记机关", "puzzle", "完成符记次序", "灯、路、人依次应和。三行刻字旁的灯亮了，仿佛那个等候的夜晚，总算有了下文。", ["record"], {"puzzle_order": ["lamp", "road", "person"], "puzzle_objects": ["random_runes:rune_a", "random_runes:rune_b", "random_runes:rune_c"], "prompt": "依灯、路、人的次序触碰现场符记。", "rules": "同一处机关只发一回赏；离线、读档都不会重来。"})])]),
	]

static func world_arcs() -> Array:
	if not _groups.has("world_arcs"): _groups["world_arcs"] = _seal(_world_arcs())
	return _groups["world_arcs"]

static func _world_arcs() -> Array:
	return [

		_chain("world_migration", "迁徙的长路", "world", "world", 1, [
			_step("沿线的两个地点", "依着已知的迁徙线索，沿路两处地方各去查探一番。", [
				_action("route_a", "world_migration:route_a", "迁徙来路察看处", "observe", "调查迁徙来路", "记录中的生灵，确曾从这一带走出去。循着留痕与旧记录，这一处的来路有了着落。", [], {"ecology_mode": "world_migration_origin", "prompt": "沿已知迁移记录调查来路观察点。"}),
				_action("route_b", "world_migration:route_b", "迁徙去路察看处", "observe", "调查迁徙去路", "去路已对过。从前走过的路，同如今留下的动静，总算能放在一处看了。", [], {"ecology_mode": "world_migration_destination", "prompt": "到去路观察点，查看这段迁移留下的线索。"})]),
			_step("现在走到哪里", "同看山人对一对眼下情形：是仍在赶路，是停了，还是失了踪迹。", [
				_action("status", "world_migration:observer", "沿线看山人", "observe", "核对当前迁徙状态", "沿线的看山人合上旧簿：还在走、停下，还是再也寻不见踪迹，都该写个明白。你见了什么，我们便留什么。", [], {"ecology_mode": "world_migration_status", "prompt": "同沿线的看山人对一对眼下的迁徙情形。", "rules": "眼下的情形只认查证过的事实；查完便罢，不必再等一场迁徙。", "questions": [{"label": "寻不见踪迹，也写得上么？", "answer": "自然写得上。写不清它去了哪儿，也要写清我们看过哪儿。留白，总强过编一个去处。"}]})]),
			_step("把长路留下", "把两地的查探与眼下的情形交到记事板上，了结这一桩天地间的查访。", [
				_action("archive", "world_migration:record_board", "迁徙路线记事板", "deliver", "交上迁徙路线记录", "两地的查探与眼下的情形，收进了同一册簿子。迁徙不曾为谁停下，但这一段走过的长路，留了下来。", [], {"prompt": "把两地调查和当前状态交到路线记录板。", "rules": "了结时的记录原样留存；可回看眼下情形与来历，日后的变故不再发赏。"})])]),
		_chain("world_decline", "最后的足迹", "world", "world", 2, [
			_step("已经获知的足迹", "依着有来历的濒危或灭绝线索，亲自到已知的地方查探。", [
				_action("site", "world_decline:last_site", "最后已知活动地", "observe", "调查已知足迹", "这里曾留下活动的记录。眼前还剩些什么、哪些已无从判断，都记在了这一回的查探里。", [], {"ecology_mode": "world_decline_site", "prompt": "沿已知线索查看最后记录过活动的地方。", "rules": "查探由一脉濒危或业已灭绝的线索引出；清空一族，没有赏。"})]),
			_step("减少的原因", "到对证柱前，分清是仍在、是迁走、是自然老死，还是叫人赶尽杀绝。", [
				_action("cause", "world_decline:evidence_post", "衰亡对证柱", "observe", "核对衰退记录", "记录一页页对过，能确认的变故已写明。寻不见踪迹的地方，缘由不明，便仍旧留着个问号。", [], {"ecology_mode": "world_decline_status", "prompt": "核对证据柱上的事件与当前种群状态。", "rules": "分清是仍在濒危、已见回升、自然消失，还是叫人灭尽；单看一回死亡，证明不了日后衰亡的缘由。"})]),
			_step("留给来者的警示", "亲手立下警示，再把这一回有限的查访交给看山人。", [
				_action("warning", "world_decline:warning_sign", "足迹警示牌", "repair", "立下足迹警示", "警示牌上添了查访的时辰与所见。后来的人会知道这里出过什么事，也知道哪些还不能断言。", [], {"prompt": "把本次核实的状态与时间写上警示牌。"}),
				_action("archive", "world_decline:observer", "记兽簿的看山人", "deliver", "交上足迹查访", "看山人把查访收进图鉴：它们若回来，我们再添一页；若不回来，也别叫这一页白白留着。", ["warning"], {"prompt": "把足迹查访交给看山人。", "rules": "簿子里只记已发生的事，保不了它们自行复原；这一回查访只发一回赏。", "questions": [{"label": "这些记录，能改变什么？", "answer": "至少下一位来查访的人，不必把同样的弯路再走一遍。"}]})])]),
		_chain("world_relief", "两地相望", "world", "world", 3, [
			_step("两地在等什么", "到过三种地形之后，分别到两处新设的接应处，问清各自还缺什么。", [
				_action("need_a", "world_relief:need_a", "第一处的接应之需", "talk", "问清第一处所需", "俺们这儿还缺一份接应的物资。该送来的那份送到这儿就好，另一头也有人等着，别全挪给俺们。", [], {"prompt": "听第一处的乡亲说说眼下缺什么。"}),
				_action("need_b", "world_relief:need_b", "第二处的接应之需", "talk", "问清第二处所需", "这里也留了收货的地方。去看看物资上写的去处吧，送对了地方，来的人才歇得下来。", [], {"prompt": "向第二处的乡亲问清接应所需。"})]),
			_step("各有去向的物资", "把两份各有编号的物资，分别送到各自的接应处。", [
				_action("supply_a", "world_relief:supply_a", "第一份接应物资", "deliver", "交付第一份物资", "第一份物资送到了接应处，收货人在封签旁做了个记号。这儿等的东西总算到了。", [], {"supply_id": "world_relief:parcel_a", "prompt": "把第一份专用物资送到它标明的接应处。", "rules": "两份物资各有各的去处，不能重送，也不能挪来挪去。"}),
				_action("supply_b", "world_relief:supply_b", "第二份接应物资", "deliver", "交付第二份物资", "第二份物资送到了标明的接应处。收货人验过封签，把这一份的去处记了下来。", [], {"supply_id": "world_relief:parcel_b", "prompt": "把第二份物资送到另一处接应处。"})]),
			_step("接应之后", "再回两处接应处探望，到接应总处说定新来的乡亲与补给的变故。", [
				_action("return_a", "world_relief:need_a", "第一处的乡亲", "talk", "回访第一处接应", "乡亲拍了拍摆好的物资：收到了，这一回能腾出地方接人。多谢你还回来问一声。", [], {"prompt": "回到第一处接应处，问问物资可曾用上。"}),
				_action("return_b", "world_relief:need_b", "第二处的乡亲", "talk", "回访第二处接应", "第二处的乡亲把回执递给你：俺们这边妥当了。把这张带回去，省得张罗的人一直悬着心。", [], {"prompt": "探望第二处接应处，听听他们的回话。"}),
				_action("settle", "world_relief:coordination_post", "接应总处", "repair", "确认两地接应", "两张回执并排放好，去处与回访都有了交代。接应总处备起了两处合用的补给，两头总算能彼此接住来人。", ["return_a", "return_b"], {"service": "world_relief_station", "prompt": "把两地回执送回协调台，确认接应安排。", "rules": "办成之后开放两处合用的补给；不改世上的市价与资源的运化。"})])]),
		_chain("world_watchnet", "灯火相望", "world", "world", 4, [
			_step("选择三处灯火", "主线走完、且至少三项区域工程完工之后，选定三处确实可用的灯位。", [
				_action("plan", "world_watchnet:planning_board", "守望灯网排定板", "configure", "选定三处守望灯位", "三处站点已经圈定。接下来把三套物件分别安好，叫图上的灯火真正连成一线。", [], {"node_count": 3, "rules": "只能选三处不同的、已完工的区域站点；交定之后不可再改。主线与至少三项区域工程须已完工。", "prompt": "灯枢眼下只接回了修好的远征主线，新设的区域站还须亲手接上。先选三处确实可用的灯位，再去把物件一一安好。"})]),
			_step("让灯火彼此相认", "亲手安上三套各有编号的守望标识。", [
				_action("node_1", "world_watchnet:node_1", "第一套守望之物", "repair", "安上第一套标识", "第一套标识安上了，这处站点有了自己的联络记号。灯旁留下的记号，同灯路图相合。", [], {"node_index": 0, "prompt": "把第一套守望标识安在选定的灯位。"}),
				_action("node_2", "world_watchnet:node_2", "第二套守望之物", "repair", "安上第二套标识", "第二套物件认下了这里的标识。这处灯火的位置，已能在灯路图上认得清清楚楚。", [], {"node_index": 1, "prompt": "在第二处选定的灯位安上守望标识。"}),
				_action("node_3", "world_watchnet:node_3", "第三套守望之物", "repair", "安上第三套标识", "第三套物件稳稳落位，这处站点留下了自己的守望标识。灯下的记号，同选定的去处一致。", [], {"node_index": 2, "prompt": "到第三处选定的灯位安上对应的守望标识。"})]),
			_step("灯火相望", "查明三处灯位确实可用，交上最终的灯路图与这方天地的簿册。", [
				_action("archive", "world_watchnet:record_board", "守望总册", "deliver", "交上全部布置", "三处灯火连在了同一张灯路图上。往后赶路的人，可以从这一头走到那一头，再寻见归来时的那盏灯。", [], {"service": "world_watchnet_station", "prompt": "查明三套物件可用，把灯路图交进守望总册。", "rules": "完工之后，可在三处灯位之间择路远行；须脱开战团，不回血也不回精力，野外生态照常运转。"})])]),
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
