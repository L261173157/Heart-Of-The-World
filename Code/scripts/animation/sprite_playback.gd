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

## 移动循环切向时保留归一化步相；同名续播不触碰帧进度。
## 仅 walk 同族循环间适用，攻击／受击等事件动作仍由 restart 从首帧启动。
static func transition_loop(sprite: AnimatedSprite2D, anim: StringName) -> void:
	if sprite.animation == anim:
		if not sprite.is_playing():
			sprite.play(anim)
		return
	var frames := sprite.sprite_frames
	var phase := 0.0
	var preserve := frames.has_animation(sprite.animation) and frames.get_animation_loop(sprite.animation) \
		and frames.get_animation_loop(anim) and String(sprite.animation).begins_with("walk") \
		and String(anim).begins_with("walk")
	if preserve:
		var elapsed := 0.0
		for index in sprite.frame:
			elapsed += frames.get_frame_duration(sprite.animation, index)
		elapsed += sprite.frame_progress * frames.get_frame_duration(sprite.animation, sprite.frame)
		phase = elapsed / maxf(duration(frames, sprite.animation) * frames.get_animation_speed(sprite.animation), 0.001)
	sprite.play(anim)
	if preserve:
		var remaining := phase * duration(frames, anim) * frames.get_animation_speed(anim)
		for index in frames.get_frame_count(anim):
			var weight := frames.get_frame_duration(anim, index)
			if remaining < weight or index == frames.get_frame_count(anim) - 1:
				sprite.set_frame_and_progress(index, clampf(remaining / weight, 0.0, 1.0))
				break
			remaining -= weight

## 六姿势维持可读步态，而非把显示器刷新率当成素材帧率。
## 怪物以本物种正常速度归一化；按实际位移等比例推进步频，慢走不设高帧率下限来制造滑步。
static func locomotion_speed(frames: SpriteFrames, anim: StringName, ground_speed: float,
		reference_speed: float, reference_fps: float, minimum_fps: float, maximum_fps: float) -> float:
	var authored_fps := frames.get_animation_speed(anim)
	if authored_fps <= 0.0:
		return 1.0
	var ratio := maxf(ground_speed, 0.0) / maxf(reference_speed, 1.0)
	var fps := clampf(reference_fps * ratio, minimum_fps, maximum_fps)
	return fps / authored_fps
