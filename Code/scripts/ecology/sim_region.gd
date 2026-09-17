## 模拟区域（纯数据，RefCounted）。
## 对应《策划纲要》地图系统：世界地图由小型地图/区域组成，区域决定承载量。
## v4 起真实世界的区域来自 BiomeMap 噪声群系斑块（归属判定走
## EcologySim.region_of_point → BiomeMap 采样，犬牙边界不可矩形判定）；
## 本类的 center/size 退化为"名义锚点与名义覆盖范围"（表现层撒布个体、
## 绘制小地图参考用）；contains_point 仅服务于测试合成的矩形区域世界。
class_name SimRegion
extends RefCounted

var id: String = ""
var display_name: String = ""
var center: Vector2 = Vector2.ZERO
## 区域名义覆盖矩形（斑块格距大小；真实斑块边界以 BiomeMap 采样为准）
var size: Vector2 = Vector2(1100, 700)

## 地形类型（plains/forest/snow/swamp/hill/lava），
## 与 SpeciesData.habitats 匹配决定哪些物种能在此生存繁衍
var terrain: String = "plains"

## 威胁系数：该地域生物的强度/经验倍率（形成由浅入深的冒险梯度）
var threat: float = 1.0

## 区域资源承载上限（策划：资源与族群数量决定繁殖），全物种共享，形成种间竞争
var capacity: int = 10

## 相邻区域 id 列表（扩张方向）
var neighbor_ids: Array[String] = []


func contains_point(point: Vector2) -> bool:
	var half := size / 2.0
	return point.x >= center.x - half.x and point.x < center.x + half.x \
			and point.y >= center.y - half.y and point.y < center.y + half.y


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"terrain": terrain,
		"threat": threat,
		"alive": 0,
		"capacity": capacity,
	}
