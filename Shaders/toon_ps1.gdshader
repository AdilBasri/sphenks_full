shader_type spatial;
render_mode diffuse_toon, specular_toon, vertex_lighting;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float jitter_strength : hint_range(0.0, 1.0) = 0.1;
uniform float resolution_scale : hint_range(16.0, 1024.0) = 256.0;
uniform int color_steps : hint_range(2, 32) = 4;
uniform float dither_grain : hint_range(0.0, 1.0) = 0.45;
uniform float affine_warp : hint_range(0.0, 1.0) = 0.8; // PS1 texture "swimming"

// Bayer 4x4 matrix for PS1-style dithering
const mat4 bayer_matrix = mat4(
    vec4(0.0, 8.0, 2.0, 10.0),
    vec4(12.0, 4.0, 14.0, 6.0),
    vec4(3.0, 11.0, 1.0, 9.0),
    vec4(15.0, 7.0, 13.0, 5.0)
) / 16.0;

varying vec2 v_uv;
varying float v_depth;
varying float v_w_coord;

void vertex() {
    vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    
    // 1. PS1 Vertex Jitter Logic
    vec2 snap_res = vec2(resolution_scale) * (VIEWPORT_SIZE.x / VIEWPORT_SIZE.y);
    
    if (jitter_strength > 0.0) {
        clip_pos.xyz /= clip_pos.w;
        clip_pos.xy = floor(clip_pos.xy * snap_res * (1.0 / jitter_strength)) / (snap_res * (1.0 / jitter_strength));
        clip_pos.xyz *= clip_pos.w;
    }
    
    POSITION = clip_pos;
    v_depth = clip_pos.z / clip_pos.w;
    
    // 2. Affine Texture Mapping Simulation (The "Swimming" Effect)
    // We pass UV * w to the fragment shader. 
    // By dividing it back by w in frag, we mimic the lack of perspective correction if done manually.
    float w = clip_pos.w;
    v_uv = mix(UV, UV * w, affine_warp);
    v_w_coord = mix(1.0, w, affine_warp);
}

void fragment() {
    // Reconstruct UVs from the varying to get the "warp"
    vec2 final_uv = v_uv / v_w_coord;
    
    vec4 tex = texture(albedo_texture, final_uv);
    vec3 color = tex.rgb * albedo_color.rgb;
    
    // 3. Darker "Crushed" Gamma for that murky look
    color = pow(color, vec3(1.2)); 
    
    // 4. Posterization (Color Quantization)
    float steps = float(color_steps);
    color = floor(color * steps + 0.5) / steps;
    
    ALBEDO = color;
}

void light() {
    // Cel-Shading with Heavy Dithering
    float dot_nl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
    
    ivec2 screen_uv = ivec2(FRAGCOORD.xy) % 4;
    float dither_val = bayer_matrix[screen_uv.x][screen_uv.y];
    
    dot_nl += (dither_val - 0.5) * dither_grain;
    
    // Step the lighting (Even more aggressive steps)
    float light_ramp = floor(dot_nl * float(color_steps)) / float(color_steps);
    
    DIFFUSE_LIGHT += light_ramp * ATTENUATION * LIGHT_COLOR;
}
