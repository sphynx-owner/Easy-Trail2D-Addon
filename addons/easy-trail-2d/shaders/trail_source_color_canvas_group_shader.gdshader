shader_type canvas_item;

#define BLEND_DIV 0.25

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

instance uniform bool inverse_srgb = true;

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	
	if (inverse_srgb) {
		c.rgb = pow(c.rgb, vec3(1.0 / 2.4));
	}
	
	COLOR = c;
}