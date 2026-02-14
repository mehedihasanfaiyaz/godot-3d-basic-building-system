shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 grid_color : source_color = vec4(0.0, 0.8, 1.0, 0.2);
uniform float grid_size = 4.0;
uniform float minor_grid_size = 2.0;
uniform float line_width = 0.04;
uniform float territory_size = 40.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Local coordinates relative to the territory center
	vec3 local_pos = world_pos - (MODEL_MATRIX * vec4(0, 0, 0, 1)).xyz;
	
	// Major Lines (4m foundations)
	vec2 grid = abs(fract(local_pos.xz / grid_size - 0.5) - 0.5) / (line_width / grid_size);
	float line = min(grid.x, grid.y);
	float major_mask = 1.0 - smoothstep(0.0, 1.0, line);
	
	// Minor Lines (2m small foundations)
	vec2 minor_grid = abs(fract(local_pos.xz / minor_grid_size - 0.5) - 0.5) / ((line_width * 0.5) / minor_grid_size);
	float minor_line = min(minor_grid.x, minor_grid.y);
	float minor_mask = 1.0 - smoothstep(0.0, 1.0, minor_line);
	
	// Border
	float half_size = territory_size / 2.0;
	float border_dist = max(abs(local_pos.x), abs(local_pos.z));
	float border_mask = smoothstep(half_size - 0.1, half_size, border_dist);
	
	float final_mask = max(major_mask, minor_mask * 0.4);
	final_mask = max(final_mask, border_mask);
	
	ALBEDO = grid_color.rgb;
	// Fade out near camera
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float fade = clamp(1.0 - (dist / (territory_size * 1.5)), 0.0, 1.0);
	
	ALPHA = final_mask * grid_color.a * fade;
}
