## 特效节点池（静态工具）：高频打击特效的 new/queue_free 改为隐藏回池复用。
## 池按 kind 分桶；节点由调用方首次创建，take() 优先复用（失效引用自动过滤——
## 世界卸载时池中节点随父节点释放，残留的悬空引用在下一次 take 时被丢弃）。
## 使用约定（违反 = 复用后状态串台）：
##   ① take() 后调用方必须重置全部可视状态（位置/缩放/颜色/modulate/翻转）；
##   ② 节点上的在途 tween 一律 set_meta("vfx_tween", tween) 登记——release 会先杀；
##   ③ 动画结束回调调 release()（hide 回池），不 queue_free
class_name VfxPool
extends RefCounted

static var _pools: Dictionary = {}


static func take(kind: String) -> Node:
	var pool: Array = _pools.get(kind, [])
	while not pool.is_empty():
		var node: Node = pool.pop_back()
		if is_instance_valid(node):
			node.visible = true
			return node
	return null


static func release(node: Node, kind: String) -> void:
	if not is_instance_valid(node):
		return
	if node.has_meta("vfx_tween"):
		var tween: Variant = node.get_meta("vfx_tween")
		if tween is Tween and (tween as Tween).is_valid():
			(tween as Tween).kill()
		node.remove_meta("vfx_tween")
	node.visible = false
	if not _pools.has(kind):
		_pools[kind] = []
	(_pools[kind] as Array).append(node)
