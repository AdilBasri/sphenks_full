shader_type spatial;
render_mode cull_front, unshaded, vertex_lighting;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_width : hint_range(0.0, 10.0) = 1.2;
uniform float jitter_strength : hint_range(0.0, 1.0) = 0.1;
uniform float resolution_scale : hint_range(16.0, 1024.0) = 256.0;

void vertex() {
    // Offset vertex along normal for outline
    vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX + NORMAL * outline_width * 0.01, 1.0);
    
    // Sync PS1 Vertex Jitter Logic with Base Mesh
    vec2 snap_res = vec2(resolution_scale) * (VIEWPORT_SIZE.x / VIEWPORT_SIZE.y);
    
    if (jitter_strength > 0.0) {
        clip_pos.xyz /= clip_pos.w;
        clip_pos.xy = floor(clip_pos.xy * snap_res * (1.0 / jitter_strength)) / (snap_res * (1.0 / jitter_strength));
        clip_pos.xyz *= clip_pos.w;
    }
    
    POSITION = clip_pos;
}

void fragment() {
    ALBEDO = outline_color.rgb;
    ALPHA = outline_color.a;
}
