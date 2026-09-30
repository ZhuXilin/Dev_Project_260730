shader_type canvas_item;

// progress: 0 = 全部遮住, 1 = 全部显示
uniform float progress : hint_range(0.0, 1.0) = 1.0;

// 遮罩底色（与面板底色一致，避免露馅）
uniform vec3 bg_color : source_color = vec3(0.11, 0.11, 0.11);

void fragment() {
	// progress = 0:   UV.y 全部 > 0   → 全部遮住
	// progress = 1:   UV.y 全部 < 1   → 全部透明（露出面板）
	// 中间值:         上方透明，下方遮住 → 从上往下"刷出"
	if (UV.y < progress) {
		COLOR = vec4(0.0);              // 透明，露出下面的 Panel
	} else {
		COLOR = vec4(bg_color, 1.0);    // 不透明，遮住
	}
}