shader_type canvas_item;

// progress: 0 = 全部遮住, 1 = 全部显示
uniform float progress : hint_range(0.0, 1.0) = 1.0;

// ★ mask 的 UV 坐标系映射：
//   uv_y_top    = 屏幕顶部对应的 UV.y（可能 <0 或 >1）
//   uv_y_bottom = 屏幕底部对应的 UV.y
uniform float uv_y_top : hint_range(-100.0, 100.0) = 0.0;
uniform float uv_y_bottom : hint_range(-100.0, 100.0) = 1.0;

// 遮罩底色（与面板底色一致，避免露馅）
uniform vec3 bg_color : source_color = vec3(0.11, 0.11, 0.11);

void fragment() {
	// 用 progress 在 [uv_y_top, uv_y_bottom] 之间插值，得到当前扫描线位置
	float threshold = mix(uv_y_top, uv_y_bottom, progress);
	if (UV.y < threshold) {
		COLOR = vec4(0.0);              // 透明，露出下面的 Panel
	} else {
		COLOR = vec4(bg_color, 1.0);    // 不透明，遮住
	}
}