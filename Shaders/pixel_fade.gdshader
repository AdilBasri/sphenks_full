shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float pixel_size : hint_range(1.0, 100.0) = 1.0;

// Pseudo-random function based on UV
float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
    float x = FRAGCOORD.x - mod(FRAGCOORD.x, pixel_size);
    float y = FRAGCOORD.y - mod(FRAGCOORD.y, pixel_size);
    float r = random(vec2(x, y));
    
    // progress = 0 depends on r being 0 (all black)
    // progress = 1 depends on r being 1 (all visible)
    if (r < progress) {
        discard; // Transparent
    } else {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0); // Black
    }
}
