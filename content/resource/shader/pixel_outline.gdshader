shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // 描边颜色，默认白色
uniform int outline_width : hint_range(1, 4) = 1; // 描边粗细（像素）
uniform bool outline_enabled = true; // 开关

void fragment() {
	// 获取图片的原始尺寸（例如 24x24）
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 pixel_size = 1.0 / tex_size;
	
	// 采样当前像素颜色
	vec4 tex_color = texture(TEXTURE, UV);
	vec4 final_color = vec4(0.0); // 默认全透明
	
	// 如果当前像素本身就不透明，直接输出原色（保留内部细节）
	if (tex_color.a > 0.1) {
		final_color = tex_color;
	} 
	// 如果开启了描边，并且当前像素是透明的，尝试向外寻找不透明的邻居
	else if (outline_enabled) {
		bool is_outline = false;
		
		// 遍历周围 8 个方向（上下左右 + 四个斜角）
		for (int x = -outline_width; x <= outline_width; x++) {
			for (int y = -outline_width; y <= outline_width; y++) {
				if (x == 0 && y == 0) continue;
				
				vec2 offset_uv = UV + vec2(float(x), float(y)) * pixel_size;
				
				// 防止采样越界
				if (offset_uv.x < 0.0 || offset_uv.x > 1.0 || offset_uv.y < 0.0 || offset_uv.y > 1.0) {
					continue;
				}
				
				// 如果邻居是不透明的，说明当前像素处于边缘，需要画描边
				if (texture(TEXTURE, offset_uv).a > 0.1) {
					is_outline = true;
					break;
				}
			}
			if (is_outline) break;
		}
		
		if (is_outline) {
			final_color = outline_color;
		}
	}
	
	// 统一输出颜色
	COLOR = final_color;
}