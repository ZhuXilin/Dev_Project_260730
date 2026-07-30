shader_type canvas_item;

uniform vec4 color : source_color = vec4(0.6, 0.3, 0.2, 1.0);

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    float gray = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
    COLOR = vec4(gray * color.rgb, tex.a * color.a);
}