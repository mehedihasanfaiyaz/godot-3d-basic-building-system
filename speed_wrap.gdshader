shader_type canvas_item;

uniform float speed_intensity : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 center = vec2(0.5, 0.5);
    vec2 to_center = uv - center;
    float dist = length(to_center);
    
    // 1. Radial Blur / Zoom Blur Effect
    vec3 col = vec3(0.0);
    float blur_samples = 10.0;
    float blur_strength = speed_intensity * 0.07; // REDUCED: was 0.12
    
    for(float i = 0.0; i < blur_samples; i++) {
        float scale = 1.0 - (i / blur_samples) * blur_strength * dist;
        col += texture(screen_texture, center + to_center * scale).rgb;
    }
    col /= blur_samples;
    
    // 2. Vignette (Darken edges)
    float vignette = 1.0 - smoothstep(0.3, 1.0, dist); // Softer edge
    col *= mix(1.0, 0.6, (1.0 - vignette) * speed_intensity); // Less darkening
    
    // 3. Simple Speed Lines / Noise on edges
    float angle = atan(to_center.y, to_center.x);
    float lines = sin(angle * 60.0 + speed_intensity * 30.0);
    lines *= smoothstep(0.4, 0.6, dist); // Only at very edges
    
    col = mix(col, vec3(1.0), lines * speed_intensity * 0.08); // Subtle lines
    
    COLOR = vec4(col, 1.0);
}
