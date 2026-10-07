## 获批世界观与单结局的信息层次合同；真实路径/输入由 complete_story 与生命周期覆盖。
extends SceneTree
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
const Layout := preload("res://scripts/ecology/campaign_layout.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
func content(id: String) -> String:
	return JSON.stringify(Catalog.chain(id))
func _initialize() -> void:
	var c2 := content("watch_c2_forest")
	var c3 := content("watch_c3_swamp")
	var c4 := content("watch_c4_hill")
	var c5 := content("watch_c5_snow")
	var c6 := content("watch_c6_lava")
	var opening := FileAccess.get_file_as_string("res://scripts/main/outpost_quest.gd")
	for fact: String in ["周照", "石安", "短途信", "工钱", "石匠"]: check(opening.contains(fact), "开场轻量身份与两个独立人物："+fact)
	for fact: String in ["一百六十年前", "共路盟", "人类", "蜥蜴", "地精", "借路不占地", "求援不诱敌", "按季维护", "当季值守", "十二年前", "运炭", "育幼林", "粮桥"]: check(c2.contains(fact), "林间旧约事实完整："+fact)
	for fact: String in ["六周前", "三周前", "两次不同", "沈渡", "闻川", "鞋底", "平原见"]: check(c3.contains(fact), "沼泽路书与回信闭环："+fact)
	check(not c2.contains("撤守令") and not c3.contains("撤守令") and not c4.contains("撤守命令") and not c4.contains("撤守令"), "前四章不提前确认第五章撤守命令")
	check(c4.contains("原件") and c4.contains("日期") and c4.contains("学生") and c4.contains("闻川"), "丘陵保存原件及师友关系")
	for fact: String in ["十天前", "三个月前", "四十年前", "矿脉衰减", "贸易改道", "封存", "人工烽灯", "积水", "断油", "转轴冻住", "撤守之后", "没留足备用传讯", "回平原", "轮值巡检"]: check(c5.contains(fact), "雪原给出完整因果与共同归途："+fact)
	for fact: String in ["一百六十年前", "人类聚落", "地精工匠", "蜥蜴巡林者", "地热", "有限灯码与短讯", "低负荷", "旧支路", "小网络", "阿苇", "沈渡", "罗墨", "韩铎", "石安"]: check(c6.contains(fact), "中枢独立说明建造者与结局："+fact)
	var ending := Catalog.action("watch_c6_lava:s4", "watch_c6_lava:s4:ending")
	check(ending.kind == "conclude" and not ending.has("choices"), "终章不是二选一，也不保留隐藏结局按钮")
	check(not c5.contains("分散派驻") and not c5.contains("集中安置") and not c6.contains("分散派驻") and not c6.contains("集中安置"), "最后两章没有旧二结局预告")
	var names := {"c2:herbalist":"白榆", "c2:liaison":"阿苇", "c3:survivor":"沈渡", "c4:scholar":"闻川", "c4:map_keeper":"罗墨", "c5:leader":"韩铎"}
	for id: String in names: check(str(Layout.OBJECTS[id].title).contains(names[id]), "同一稳定实体使用姓名："+id)
	check(not content("side_herbalist").contains("白榆"), "独立支线草药师未合并为白榆")
	check(content("side_patrol").contains("不能") and content("side_patrol").contains("死讯"), "名册不是死亡证明")
	check(content("side_letter").contains("老同伴") and content("side_letter").contains("还没有消息"), "迟来信件保留寄信者现状未知")
	check(content("side_troll").contains("不能断言"), "巨魔当前占地不能证明历史杀害")
	check(c6.contains("不能改变天气") and c6.contains("不能复活") and c6.contains("未知道路"), "世界之心能力边界明确")
	print("=== CAMPAIGN LORE CONTRACT %s (%d checks, %d failures) ===" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
