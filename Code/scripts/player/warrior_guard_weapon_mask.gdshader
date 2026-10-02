shader_type canvas_item;

// TS Warrior Guard 原始192格心画布，切帧÷2后以格心对称裁剪。
// 只移除原画举在头顶的剑：薄荷钢刃三色 + 右侧极窄外描边。
// 头盔蓝色、脸肤色、盾和脚点原样保留；不绘造新的上下英雄视图。
void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	vec2 source = vec2(96.0) + (UV - vec2(0.5)) / TEXTURE_PIXEL_SIZE * 2.0;
	bool blade_box = source.x >= 76.0 && source.x <= 108.0 && source.y < 80.0;
	bool steel = distance(texel.rgb, vec3(156.0, 190.0, 170.0) / 255.0) < 0.015
		|| distance(texel.rgb, vec3(212.0, 237.0, 194.0) / 255.0) < 0.015
		|| distance(texel.rgb, vec3(104.0, 140.0, 138.0) / 255.0) < 0.015;
	bool outer_edge = source.x >= 97.0 && source.x <= 108.0 && source.y < 77.0
		&& distance(texel.rgb, vec3(22.0, 28.0, 46.0) / 255.0) < 0.015;
	if ((blade_box && steel) || outer_edge) {
		COLOR.a = 0.0;
	}
}
