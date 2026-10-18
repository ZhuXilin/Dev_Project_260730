shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform int mode = 0;

void fragment() {
	// FRAGCOORD.y 是当前像素在屏幕上的绝对 Y 坐标
	// SCREEN_PIXEL_SIZE.y 的值为 1.0 / 屏幕高度
	// 两者相乘，即可得到当前像素在全屏中的 Y 轴比例（0.0 到 1.0）
	float screen_y_ratio = FRAGCOORD.y * SCREEN_PIXEL_SIZE.y;
	
	if (mode == 0) {
		// 打开：从上往下扫。高于扫描线的像素丢弃（透明），低于的保留（显示）
		if (screen_y_ratio > progress) {
			discard;
		}
	} else {
		// 关闭：从下往上扫。高于阈值的像素丢弃（透明），低于的保留（显示）
		if (screen_y_ratio > (1.0 - progress)) {
			discard;
		}
	}
}