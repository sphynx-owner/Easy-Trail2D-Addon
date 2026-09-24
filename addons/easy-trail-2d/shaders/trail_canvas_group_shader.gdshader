shader_type canvas_item;

#define BLEND_DIV 0.25

#define EPSILON 0.000001

render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform sampler2D trail_texture: repeat_disable;

uniform sampler2D alpha_curve: repeat_disable;

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	
	float time = (c.r / BLEND_DIV) / max(EPSILON, c.b / BLEND_DIV);
	
	float side_offset = (c.g / BLEND_DIV) / max(EPSILON, c.b / BLEND_DIV);
	
	float alpha = (c.a / BLEND_DIV) / max(EPSILON, c.b / BLEND_DIV);
	
	vec2 trail_uv = vec2(time, side_offset);
	
	vec4 color = texture(trail_texture, trail_uv);
	
	COLOR = vec4(color.rgb, color.a * alpha * step(time, 1.0));
	
	COLOR.a *= texture(alpha_curve, vec2(trail_uv.x, 0.5)).r;
}