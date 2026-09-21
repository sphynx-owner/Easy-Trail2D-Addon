shader_type canvas_item;

render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec4 silhouette_color: source_color = vec4(0, 0, 1, 0.5);
uniform bool use_canvas_group_alpha_curve = false;

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);

	if (use_canvas_group_alpha_curve) {
		c.a /= c.b;
	}

	if (c.a > 0.0001) {
		c.rgb /= c.a;
		c = vec4(silhouette_color.xyz, silhouette_color.a * c.a);
	}

	COLOR = c;
}