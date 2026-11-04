shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 0.8, 0.2, 1.0); // 默认亮黄色
uniform int outline_width : hint_range(1, 4) = 1;

void fragment() {
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 pixel_size = 1.0 / tex_size;
	vec4 tex_color = texture(TEXTURE, UV);
	
	if (tex_color.a > 0.1) {
		// 原图区域：直接输出，不受任何干扰
		COLOR = tex_color;
	} else {
		// 透明区域：向四周寻找是否有不透明的像素
		bool is_outline = false;
		for (int x = -outline_width; x <= outline_width; x++) {
			for (int y = -outline_width; y <= outline_width; y++) {
				if (x == 0 && y == 0) continue;
				vec2 offset_uv = UV + vec2(float(x), float(y)) * pixel_size;
				if (offset_uv.x < 0.0 || offset_uv.x > 1.0 || offset_uv.y < 0.0 || offset_uv.y > 1.0) continue;
				if (texture(TEXTURE, offset_uv).a > 0.1) {
					is_outline = true;
					break;
				}
			}
			if (is_outline) break;
		}
		
		if (is_outline) {
			COLOR = outline_color;
		} else {
			COLOR = vec4(0.0);
		}
	}
}