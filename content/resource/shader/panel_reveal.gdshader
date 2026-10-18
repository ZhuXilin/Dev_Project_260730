shader_type canvas_item;

// 扫描进度
uniform float progress : hint_range(0.0, 1.0) = 1.0;

// 遮罩底色（使用与 UI 面板一致的深灰色，而不是纯黑）
uniform vec3 bg_color : source_color = vec3(0.11, 0.11, 0.11);

// 扫描模式：
//   0 = 打开（从上往下揭示）
//   1 = 关闭（从下往上遮蔽）
uniform int mode = 0;

void fragment() {
	float threshold;

	if (mode == 0) {
		// 打开：遮罩从顶部撤退
		threshold = progress;
		if (UV.y < threshold) {
			COLOR = vec4(0.0); // 透明，露出面板和文字
		} else {
			COLOR = vec4(bg_color, 1.0); // 纯色，盖住面板
		}
	} else {
		// 关闭：遮罩从底部往上覆盖
		threshold = 1.0 - progress;
		if (UV.y > threshold) {
			COLOR = vec4(bg_color, 1.0); // 纯色，盖住面板
		} else {
			COLOR = vec4(0.0); // 透明
		}
	}
}