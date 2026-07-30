shader_type canvas_item;

// ---- 颜色替换（原有功能） ----
uniform vec3 target_color_1 : source_color = vec3(0.1216, 0.2196, 0.9373);
uniform vec3 target_color_2 : source_color = vec3(1.0, 0.7490, 0.6863);
uniform vec3 assign_color_1 : source_color = vec3(0.8784, 0.0, 0.3725);
uniform vec3 assign_color_2 : source_color = vec3(1.0, 0.6549, 0.7529);
uniform float tolerance : hint_range(0.0, 0.5) = 0.01;

// ---- 受击效果（原有功能） ----
uniform vec2 hit_offset_amount = vec2(0.0);
uniform float hit_duration = 0.15;
uniform float hit_elapsed = 0.0;
uniform vec3 hit_flash_color = vec3(1.0, 1.0, 1.0);
uniform bool hit_enable_flash = false;

// ---- 描边功能（外部描边） ----
uniform vec3 outline_color : source_color = vec3(1.0, 1.0, 1.0); // 默认白色
uniform float outline_width = 1.0; // 默认1像素宽，向外扩展

void vertex() {
    if (hit_duration > 0.0 && hit_elapsed < hit_duration) {
        float progress = hit_elapsed / hit_duration;
        float offset_scale = sin(progress * 3.14159);
        VERTEX += hit_offset_amount * offset_scale;
    }
}

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    vec3 pixel_color = tex_color.rgb;
    vec3 final_color = pixel_color;
    float final_alpha = tex_color.a;

    // ---- 颜色替换（仅作用于原图不透明区域） ----
    if (final_alpha > 0.5) {
        if (distance(pixel_color, target_color_1) < tolerance) {
            final_color = assign_color_1;
        } else if (distance(pixel_color, target_color_2) < tolerance) {
            final_color = assign_color_2;
        }
    }

    // ---- 受击闪光（覆盖替换） ----
    if (hit_enable_flash && hit_elapsed < hit_duration) {
        final_color = hit_flash_color;
    }

    // ---- 外部描边（在透明区域生成，覆盖所有） ----
    if (outline_width > 0.0 && final_alpha < 0.5) { // 仅对透明像素处理
        vec2 texel_size = 1.0 / vec2(textureSize(TEXTURE, 0));
        int width_pixels = int(ceil(outline_width));
        bool near_opaque = false;
        float alpha_threshold = 0.5;

        // 检查周围像素是否有不透明的
        for (int i = 1; i <= width_pixels; i++) {
            float dist = float(i);
            vec2 offsets[4] = vec2[4](
                vec2(0.0, -dist),
                vec2(0.0,  dist),
                vec2(-dist, 0.0),
                vec2( dist, 0.0)
            );
            for (int j = 0; j < 4; j++) {
                vec2 uv_check = UV + offsets[j] * texel_size;
                float alpha_check = texture(TEXTURE, uv_check).a;
                if (alpha_check > alpha_threshold) {
                    near_opaque = true;
                    break;
                }
            }
            if (near_opaque) break;
        }

        if (near_opaque) {
            final_color = outline_color;
            final_alpha = 1.0; // 描边完全不透明
        }
        // 否则保持透明（不绘制）
    }

    COLOR.rgb = final_color;
    COLOR.a = final_alpha;
}