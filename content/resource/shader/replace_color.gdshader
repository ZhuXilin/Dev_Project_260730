shader_type canvas_item;

// ---- 颜色替换 ----
uniform vec3 target_color_1 : source_color = vec3(0.1216, 0.2196, 0.9373);
uniform vec3 target_color_2 : source_color = vec3(1.0, 0.7490, 0.6863);
uniform vec3 assign_color_1 : source_color = vec3(0.8784, 0.0, 0.3725);
uniform vec3 assign_color_2 : source_color = vec3(1.0, 0.6549, 0.7529);
uniform float tolerance : hint_range(0.0, 0.5) = 0.05;

// ---- 受击效果 ----
uniform vec2 hit_offset_amount = vec2(0.0);
uniform float hit_duration = 0.15;
uniform float hit_elapsed = 0.0;
uniform vec3 hit_flash_color = vec3(1.0, 1.0, 1.0);
uniform bool hit_enable_flash = false;

// ---- 描边 ----
uniform bool  outline_enabled = false;
uniform vec3  outline_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 8.0) = 1.0;
uniform int   outline_direction = 0;   // 0=外 1=内 2=双向


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
    vec2 texel_size = 1.0 / vec2(textureSize(TEXTURE, 0));

    // ---- 颜色替换（半透明边缘也替换）----
    if (final_alpha > 0.05) {
        if (distance(pixel_color, target_color_1) < tolerance) {
            final_color = assign_color_1;
        } else if (distance(pixel_color, target_color_2) < tolerance) {
            final_color = assign_color_2;
        }
    }

    // ---- 描边（先做，让受击闪光能覆盖它）----
    if (outline_enabled && outline_width > 0.0) {
        int w = int(ceil(outline_width));
        bool is_opaque = final_alpha > 0.5;

        // 外描边
        if (!is_opaque && (outline_direction == 0 || outline_direction == 2)) {
            bool near_opaque = false;
            for (int i = 1; i <= w; i++) {
                for (int j = 0; j < 8; j++) {
                    vec2 d;
                    if      (j == 0) d = vec2( 1.0,  0.0);
                    else if (j == 1) d = vec2(-1.0,  0.0);
                    else if (j == 2) d = vec2( 0.0,  1.0);
                    else if (j == 3) d = vec2( 0.0, -1.0);
                    else if (j == 4) d = vec2( 0.7071,  0.7071);
                    else if (j == 5) d = vec2(-0.7071,  0.7071);
                    else if (j == 6) d = vec2( 0.7071, -0.7071);
                    else             d = vec2(-0.7071, -0.7071);
                    vec2 check_uv = UV + d * float(i) * texel_size;
                    if (texture(TEXTURE, check_uv).a > 0.5) {
                        near_opaque = true;
                        break;
                    }
                }
                if (near_opaque) break;
            }
            if (near_opaque) {
                final_color = outline_color;
                final_alpha = 1.0;
            }
        }

        // 内描边
        if (is_opaque && (outline_direction == 1 || outline_direction == 2)) {
            bool near_transparent = false;
            for (int i = 1; i <= w; i++) {
                for (int j = 0; j < 8; j++) {
                    vec2 d;
                    if      (j == 0) d = vec2( 1.0,  0.0);
                    else if (j == 1) d = vec2(-1.0,  0.0);
                    else if (j == 2) d = vec2( 0.0,  1.0);
                    else if (j == 3) d = vec2( 0.0, -1.0);
                    else if (j == 4) d = vec2( 0.7071,  0.7071);
                    else if (j == 5) d = vec2(-0.7071,  0.7071);
                    else if (j == 6) d = vec2( 0.7071, -0.7071);
                    else             d = vec2(-0.7071, -0.7071);
                    vec2 check_uv = UV + d * float(i) * texel_size;
                    if (texture(TEXTURE, check_uv).a <= 0.5) {
                        near_transparent = true;
                        break;
                    }
                }
                if (near_transparent) break;
            }
            if (near_transparent) {
                final_color = outline_color;
            }
        }
    }

    // ---- 受击闪光（最后做，覆盖前面所有）----
    if (hit_enable_flash && hit_elapsed < hit_duration) {
        final_color = hit_flash_color;
    }

    COLOR.rgb = final_color;
    COLOR.a = final_alpha;
}