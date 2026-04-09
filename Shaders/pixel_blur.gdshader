shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float blur_amount : hint_range(0.0, 10.0) = 0.0;
uniform float pixel_size : hint_range(1.0, 16.0) = 4.0;

void fragment() {
    // 1. Pixelation Logic
    vec2 size = vec2(textureSize(screen_texture, 0));
    vec2 pixelated_uv = floor(SCREEN_UV * size / pixel_size) / (size / pixel_size);
    
    // 2. Multi-sample Blur (Box blur style)
    vec4 col = vec4(0.0);
    float count = 0.0;
    
    // Only apply blur if amount > 0 for performance
    if (blur_amount > 0.0) {
        for (float x = -blur_amount; x <= blur_amount; x += 1.0) {
            for (float y = -blur_amount; y <= blur_amount; y += 1.0) {
                // Offset UV by screen pixel size times the loop index
                vec2 offset = vec2(x, y) / size * pixel_size; 
                col += texture(screen_texture, pixelated_uv + offset);
                count += 1.0;
            }
        }
        col /= count;
    } else {
        col = texture(screen_texture, pixelated_uv);
    }

    // 3. Optional: Darken the background slightly to make UI pop
    col.rgb *= mix(1.0, 0.4, clamp(blur_amount / 5.0, 0.0, 1.0));
    
    COLOR = col;
}
