## 物品目录（玩法 v7 P0）：id → 表现层元数据（中文名 / 图标 / 类型 / 描述）。
## 职责边界（铁律 5 的延续）：
##   本表只存元数据与图标；价格与掉落在 EconomyMath（纯逻辑，随迁服务端），
##   恢复比例在 CharacterStats.ITEM_HP_FRAC / ITEM_MP_FRAC——desc 动态拼接，
##   数值改动文案自动跟进，不出现第二份手抄副本。
## 图标源：assets/na/items/（CC0 Ninja Adventure），按需 load + 静态缓存
## （HUD 物品栏/商店/快捷槽共享同一份纹理）。
class_name ItemCatalog

const ITEMS := {
	# --- 消耗品（商店补给 + Boss 附加掉落；效果比例见 CharacterStats） ---
	"onigiri": {"name": "饭团", "kind": "consumable", "icon": "res://assets/na/items/onigiri.png"},
	"sushi": {"name": "寿司", "kind": "consumable", "icon": "res://assets/na/items/sushi.png"},
	"medipack": {"name": "医疗包", "kind": "consumable", "icon": "res://assets/na/items/medipack.png"},
	"life-pot": {"name": "生命药剂", "kind": "consumable", "icon": "res://assets/na/items/life-pot.png"},
	"water-pot": {"name": "竹水壶", "kind": "consumable", "icon": "res://assets/na/items/water-pot.png"},
	# --- 材料（按物种确定性掉落；卖钱出口 + P1 collect 任务交付储备） ---
	"beaf": {"name": "兽肉", "kind": "material", "icon": "res://assets/na/items/beaf.png"},
	"fish": {"name": "鲜鱼", "kind": "material", "icon": "res://assets/na/items/fish.png"},
	"shrimp": {"name": "鲜虾", "kind": "material", "icon": "res://assets/na/items/shrimp.png"},
	"octopus": {"name": "章鱼足", "kind": "material", "icon": "res://assets/na/items/octopus.png"},
	"tea-leaf": {"name": "茶叶", "kind": "material", "icon": "res://assets/na/items/tea-leaf.png"},
	"scroll-fire": {"name": "火之卷轴", "kind": "material", "icon": "res://assets/na/items/scroll-fire.png"},
	"scroll-rock": {"name": "岩之卷轴", "kind": "material", "icon": "res://assets/na/items/scroll-rock.png"},
}

static var _tex_cache: Dictionary = {}


static func knows(id: String) -> bool:
	return ITEMS.has(id)


static func name_of(id: String) -> String:
	return str(ITEMS.get(id, {}).get("name", id))


static func kind_of(id: String) -> String:
	return str(ITEMS.get(id, {}).get("kind", "material"))


static func is_consumable(id: String) -> bool:
	return kind_of(id) == "consumable"


static func icon_of(id: String) -> Texture2D:
	if not _tex_cache.has(id):
		var path := str(ITEMS.get(id, {}).get("icon", ""))
		_tex_cache[id] = load(path) if path != "" else null
	return _tex_cache[id]


## 描述：消耗品动态拼接恢复比例（单一真源在 CharacterStats），材料标注可售卖
static func desc_of(id: String) -> String:
	if CharacterStats.ITEM_HP_FRAC.has(id):
		return "回复 %d%% 生命" % roundi(float(CharacterStats.ITEM_HP_FRAC[id]) * 100.0)
	if CharacterStats.ITEM_MP_FRAC.has(id):
		return "回复 %d%% 精力" % roundi(float(CharacterStats.ITEM_MP_FRAC[id]) * 100.0)
	return "材料，可售予行商"


## 按定义顺序取某类物品 id 列表（商店补给页 / 物品栏分区消费）
static func ids_of_kind(kind: String) -> Array[String]:
	var out: Array[String] = []
	for id in ITEMS:
		if str(ITEMS[id]["kind"]) == kind:
			out.append(id)
	return out
