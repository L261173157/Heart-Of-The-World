## 动作时长从 SpriteFrames 元数据读取；不改资源、伤害、冷却或物理窗口。
## Tiny Swords 与 Enemy Pack 帧数不同，禁止再沿用「全是四帧」的固定倍速。
extends RefCounted

static func duration(frames: SpriteFrames, anim: StringName) -> float:
	if frames == null or not frames.has_animation(anim):
		return 0.0
	var fps := frames.get_animation_speed(anim)
	if fps <= 0.0:
		return 0.0
	var total := 0.0
	for index in frames.get_frame_count(anim):
		total += frames.get_frame_duration(anim, index)
	return total / fps

## 预留一物理帧，让末帧完成事件先于状态计时器到期；短动作保持原速后停末帧。
static func speed_for_window(frames: SpriteFrames, anim: StringName, window: float) -> float:
	var margin := 1.0 / float(Engine.physics_ticks_per_second)
	return maxf(1.0, duration(frames, anim) / maxf(window - margin, margin))

## play(同名) 会续播而非重播；每次动作事件显式从第零帧开始。
static func restart(sprite: AnimatedSprite2D, anim: StringName, speed := 1.0) -> void:
	sprite.stop()
	sprite.speed_scale = speed
	sprite.play(anim)
	sprite.set_frame_and_progress(0, 0.0)
