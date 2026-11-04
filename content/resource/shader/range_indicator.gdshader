shader_type canvas_item;
render_mode unshaded;

uniform vec4 base_color : source_color = vec4(0.3, 0.5, 1.0, 1.0);

// 内部填充透明度
uniform float fill_alpha : hint_range(0.0, 1.0) = 1.0;
// 边框透明度（比内部稍微实一点点）
uniform float border_alpha_mult : hint_range(0.0, 2.0) = 1.5; 
// 边框宽度
uniform float border_width : hint_range(0.0, 4.0) = 1.0;

void fragment() {
	float px_size = 16.0; 
	vec2 pixel = UV * px_size;
	
	float dist_x = min(pixel.x, px_size - pixel.x);
	float dist_y = min(pixel.y, px_size - pixel.y);
	float dist = min(dist_x, dist_y);
	
	if (dist < border_width) {
		// ★ 边框：不再提亮发光，而是保持原色，把透明度拉高一点点
		// 这样在草地/水上就是一条柔和的实色线，不会刺眼
		COLOR = vec4(base_color.rgb, min(base_color.a * border_alpha_mult, 1.0));
	} else {
		// ★ 内部：非常淡的填充
		COLOR = vec4(base_color.rgb, base_color.a * fill_alpha);
	}
}