shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Distortion
uniform float distortion_strength : hint_range(-1.0, 1.0) = 0.15;
uniform float scale : hint_range(0.1, 2.0) = 0.95;

// CRT Effects
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.1;
uniform float noise_intensity : hint_range(0.0, 1.0) = 0.05;
uniform float chromatic_aberration : hint_range(0.0, 0.1) = 0.003;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float brightness : hint_range(0.0, 2.0) = 1.1;

// Colorblind Mode: 0:Off, 1:Protanopia, 2:Deuteranopia, 3:Tritanopia, 4:Grayscale
uniform int colorblind_mode : hint_range(0, 4) = 0;

float rand(vec2 co) {
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

vec3 apply_colorblind(vec3 color, int mode) {
    if (mode == 1) { // Protanopia
        return vec3(
            dot(color, vec3(0.56667, 0.43333, 0.0)),
            dot(color, vec3(0.55833, 0.44167, 0.0)),
            dot(color, vec3(0.0, 0.24167, 0.75833))
        );
    } else if (mode == 2) { // Deuteranopia
        return vec3(
            dot(color, vec3(0.625, 0.375, 0.0)),
            dot(color, vec3(0.7, 0.3, 0.0)),
            dot(color, vec3(0.0, 0.3, 0.7))
        );
    } else if (mode == 3) { // Tritanopia
        return vec3(
            dot(color, vec3(0.95, 0.05, 0.0)),
            dot(color, vec3(0.0, 0.43333, 0.56667)),
            dot(color, vec3(0.0, 0.475, 0.525))
        );
    } else if (mode == 4) { // Grayscale
        float gray = dot(color, vec3(0.299, 0.587, 0.114));
        return vec3(gray);
    }
    return color;
}

void fragment() {
    // 1. Coordinates relative to center (-0.5 to 0.5)
    vec2 p = UV - 0.5;
    
    // 2. Calculate distance and barrel distortion
    float r2 = dot(p, p);
    float f = 1.0 + distortion_strength * r2;
    
    // 3. Transform coordinates
    vec2 distorted_uv = p * f * scale + 0.5;
    
    // 4. Sample with Chromatic Aberration
    vec2 r_uv = (p * (f + chromatic_aberration)) * scale + 0.5;
    vec2 g_uv = distorted_uv;
    vec2 b_uv = (p * (f - chromatic_aberration)) * scale + 0.5;
    
    // OOB Check (Clip to black)
    if (distorted_uv.x < 0.0 || distorted_uv.x > 1.0 || distorted_uv.y < 0.0 || distorted_uv.y > 1.0) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        float r_val = texture(screen_texture, r_uv).r;
        float g_val = texture(screen_texture, g_uv).g;
        float b_val = texture(screen_texture, b_uv).b;
        
        vec3 result = vec3(r_val, g_val, b_val);
        
        // Colorblind Correction
        if (colorblind_mode > 0) {
            result = apply_colorblind(result, colorblind_mode);
        }
        
        // 5. Scanlines
        float scanline = sin(distorted_uv.y * 800.0) * 0.5 + 0.5;
        result *= mix(1.0, 1.0 - scanline_intensity, scanline);
        
        // 6. Static Noise
        float noise = rand(distorted_uv + TIME) * noise_intensity;
        result += noise;
        
        // 7. Vignette
        float mask = 1.0 - smoothstep(0.4, 0.65, length(p) * 1.1);
        result = mix(result, result * mask, vignette_intensity);
        
        // 8. Global Brightness Boost
        result *= brightness;
        
        COLOR = vec4(result, 1.0);
    }
}
