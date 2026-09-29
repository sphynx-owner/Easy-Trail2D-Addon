shader_type canvas_item;

//#define DEBUG

#define BLEND_DIV 0.25

render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform sampler2D trail_texture : repeat_disable;

uniform sampler2D alpha_texture : repeat_disable;

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	
#ifdef DEBUG
	COLOR = vec4(c.a, c.r, c.g, step(0.00001, c.a));
#else
	// We normalize the data
	c.rgb /= (c.a / BLEND_DIV);
	
	float time = c.r;
	
	float side_offset = c.g;
	
	float alpha = c.b;
	
	vec2 trail_uv = vec2(time, side_offset);
	
	vec4 color = texture(trail_texture, trail_uv);
	
	COLOR = max(vec4(0), vec4(color.rgb, color.a * alpha * step(time, 2)));
	
	COLOR.a *= texture(alpha_texture, trail_uv).r;
#endif
}