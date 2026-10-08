shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 1.0;

// mask 的 UV 坐标映射（屏幕顶/底对应 mask 的 UV.y）
uniform float uv_y_top : hint_range(-100.0, 100.0) = 0.0;
uniform float uv_y_bottom : hint_range(-100.0, 100.0) = 1.0;

// 遮罩底色
uniform vec3 bg_color : source_color = vec3(0.11, 0.11, 0.11);

// ★ 扫描模式：
//   0 = 揭示（顶部先透明，露出面板）
//   1 = 遮蔽（顶部先不透明，盖住面板）
// 两者 progress 都是 0→1，都是"从上往下"扫
uniform int mode = 0;

void fragment() {
	float threshold = mix(uv_y_top, uv_y_bottom, progress);

	if (mode == 0) {
		// 揭示：threshold 以上的区域透明
		if (UV.y < threshold) {
			COLOR = vec4(0.0);
		} else {
			COLOR = vec4(bg_color, 1.0);
		}
	} else {
		// 遮蔽：threshold 以上的区域不透明
		if (UV.y < threshold) {
			COLOR = vec4(bg_color, 1.0);
		} else {
			COLOR = vec4(0.0);
		}
	}
}