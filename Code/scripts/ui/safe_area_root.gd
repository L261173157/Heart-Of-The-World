class_name SafeAreaRoot
extends Control
## iOS 安全区内收（刘海/Dynamic Island/Home 指示条/屏幕圆角）。
## 挂在全屏锚点的根 Control 上：子节点全部相对它定位，收 Root 即整体
## 收进安全区（此前只有游戏内 HUD 有此处理，主菜单裸奔——版本号落在
## 圆角裁切区）。
## 安全区是窗口坐标（iOS points），Control 偏移是拉伸后的画布单位——
## canvas_items 拉伸下二者差一个缩放系数（iPhone 横屏画布 720 高对
## 390pt ≈0.54），不换算只内缩一半左右，血条仍会伸进刘海 15~25pt。
## 重算时机：入树 / 视口尺寸变化 / 回前台——iOS 上旋转、键盘弹出等
## 场景 NOTIFICATION_WM_SIZE_CHANGED 不可靠，统一走这三条。

func _ready() -> void:
	apply_to(self)
	get_viewport().size_changed.connect(func() -> void: apply_to(self))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		apply_to(self)


## 静态工具：给任意全屏 Control 套安全区内收。根节点已被场景脚本占用、
## 无法再挂本类时（如主菜单）直接调用。
static func apply_to(c: Control) -> void:
	var win := c.get_window()
	var win_rect := Rect2i(win.position, win.size)
	var safe := DisplayServer.get_display_safe_area().intersection(win_rect)
	if not safe.has_area():
		return
	var xf := win.get_final_transform()
	c.offset_left = (safe.position.x - win_rect.position.x) / xf.get_scale().x
	c.offset_top = (safe.position.y - win_rect.position.y) / xf.get_scale().y
	c.offset_right = (safe.end.x - win_rect.end.x) / xf.get_scale().x
	c.offset_bottom = (safe.end.y - win_rect.end.y) / xf.get_scale().y
