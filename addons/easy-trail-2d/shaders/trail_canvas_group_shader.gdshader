shader_type canvas_item;

#define EPSILON 0.000001

#define ALPHA_DIV 0.5

render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform sampler2D trail_texture: repeat_disable;

uniform sampler2D alpha_texture: repeat_disable;

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	
	float mul = 1.0 / max(EPSILON, c.a / ALPHA_DIV);
	
	float time = c.r * mul;
	
	float side_offset = c.g * mul;
	
	float alpha = c.b * mul;
	
	vec2 trail_uv = vec2(time, side_offset);
	
	vec4 color = texture(trail_texture, trail_uv);
	
	COLOR = max(vec4(0), vec4(color.rgb, color.a * alpha * step(time, 1.0)));//vec4(trail_uv, 0, step(time, 1.0));//
	
	COLOR.a *= texture(alpha_texture, trail_uv).r;
}