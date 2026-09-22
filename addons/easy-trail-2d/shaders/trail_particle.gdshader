shader_type canvas_item;

render_mode blend_add;

// The resolution scale of the image, used to maintain the particle's global size
instance uniform float snapshot_resolution_scale = 1.0;

instance uniform int particles_anim_h_frames;
instance uniform int particles_anim_v_frames;

instance uniform bool use_local_sample_resolution = false;
instance uniform float local_sample_resolution = 5;
// Per 100 world units
instance uniform float global_sample_resolution = 10;
instance uniform float max_global_sample_resolution = 20;

instance uniform bool use_noise = true;

instance uniform bool use_override_offset = false;
instance uniform vec2 override_offset;
instance uniform int override_current_frame = 0;
instance uniform float override_particle_lifetime = 0;

instance uniform bool use_canvas_group_alpha_curve = false;
uniform sampler2D alpha_curve: repeat_disable;
instance uniform float time_spread;

instance uniform float lifetime = 1.0;

#define EPSILON 0.0000000001

#define UV_INSIDE(IN_UV) step(IN_UV.x, 1) * step(IN_UV.y, 1) * step(0, IN_UV.x) * step(0, IN_UV.y)


// from https://www.shadertoy.com/view/ftKfzc
// ----------------------------------------------------------
float interleaved_gradient_noise(vec2 uv){
	uv += float(TIME* 43.343975)  * (vec2(47, 17) * 0.695);

    vec3 magic = vec3( 0.06711056, 0.00583715, 52.9829189 );

    return fract(magic.z * fract(dot(uv, magic.xy)));
}
// ----------------------------------------------------------

varying flat vec2 offset;
varying flat vec2 total_scale;
varying flat vec2 animation_uv_offset;
varying flat float particle_lifetime;

void vertex() {
	// We get the offset along which we stretch the texture
	offset = use_override_offset ? override_offset : INSTANCE_CUSTOM.xw;

	// We get the atlas dimensions into float values
	float h_frames = float(particles_anim_h_frames);
	float v_frames = float(particles_anim_v_frames);

	// This is the texture size, as sprites resize
	// Their vertices to fit their texture automatically
	vec2 origin_texture_size = abs(VERTEX) * 2.0;

	// This is the total scale to apply on the texture, we take the snapshot resolution scale
	// and the atlas dimensions into account as those need to be inversed
	total_scale = vec2(1) / snapshot_resolution_scale / vec2(h_frames, v_frames);

	// The final size of the output texture in world pixels
	vec2 texture_final_size = origin_texture_size * total_scale;

	float particle_total_frames = float(particles_anim_h_frames * particles_anim_v_frames);
	float particle_frame = floor(use_override_offset ? float(override_current_frame) : INSTANCE_CUSTOM.z);

	particle_frame = clamp(particle_frame, 0.0, particle_total_frames - 1.0);

	// We get the uv offset for the current frame in the atlas in pixels
	animation_uv_offset = vec2(mod(particle_frame, h_frames) / h_frames, floor((particle_frame + 0.5) / h_frames) / v_frames) * origin_texture_size;

	// This scales the UV so that it is a consistent global size, in this case the scale of a single global pixel
	vec2 uv_scale = texture_final_size * snapshot_resolution_scale + abs(offset * snapshot_resolution_scale);

	// We scale the uv and then offset it by the atlas frame offset
	UV *= uv_scale;
	UV += animation_uv_offset;

	// This is so that the uv always starts at the end of the offset
	UV -= max(vec2(0), offset * snapshot_resolution_scale);
	UV *= TEXTURE_PIXEL_SIZE;

	// We scale the vertex so that it reflects the final size of the texture, and then expand it so that
	// it behaves like a bounding box for the stretched texture
	VERTEX = VERTEX * total_scale;
	VERTEX = VERTEX + vec2(VERTEX.x > 0.0 ? max(offset.x, 0.0) : min(offset.x, 0.0), VERTEX.y > 0.0 ? max(offset.y, 0.0) : min(offset.y, 0.0));

	particle_lifetime = use_override_offset ? override_particle_lifetime : INSTANCE_CUSTOM.y;
}

void fragment() {
	float alpha = texture(alpha_curve, vec2(particle_lifetime)).r;

	COLOR.a *= alpha;

	if(offset != vec2(0)) {
		float offset_distance = length(offset * snapshot_resolution_scale);
		vec2 scaled_offset = offset * snapshot_resolution_scale * TEXTURE_PIXEL_SIZE;

		vec2 temp_uv = UV + scaled_offset * 0.;
		vec2 normalized_temp_uv = (temp_uv - animation_uv_offset * TEXTURE_PIXEL_SIZE) / (total_scale * snapshot_resolution_scale);
		float custom_uv_inside = UV_INSIDE(normalized_temp_uv);
		COLOR = vec4(0, particle_lifetime, 0, COLOR.a) * vec4(1, 1 ,1, custom_uv_inside);//texture(TEXTURE, temp_uv) * vec4(1, 1 ,1, custom_uv_inside);//

		float sample_count = trunc(use_local_sample_resolution ? local_sample_resolution : min(max(offset_distance, EPSILON) * global_sample_resolution / 100.0, max_global_sample_resolution));
		float time_step =  1.0 / sample_count;
		// must be done this way so that the error between snapshot genertor viewports would be reduced to a minimum
		float time = use_noise ? interleaved_gradient_noise(trunc(abs(SCREEN_UV - 0.5) / SCREEN_PIXEL_SIZE)) * time_step : 0.;

		for(float i = 0.0; i <= sample_count; i += 1.0)
		{
			float clamped_time = clamp(time, 0, 1);
			temp_uv = UV + scaled_offset * clamped_time;
			normalized_temp_uv = (temp_uv - animation_uv_offset * TEXTURE_PIXEL_SIZE) / (total_scale * snapshot_resolution_scale);
			custom_uv_inside = UV_INSIDE(normalized_temp_uv);
			vec4 texture_sample = texture(TEXTURE, temp_uv) * vec4(1, 1 ,1, custom_uv_inside);
			COLOR = vec4(mix(COLOR, vec4(clamped_time, particle_lifetime, 0, 1), texture_sample.a).xyz, texture_sample.a + COLOR.a * (1.0 - texture_sample.a));//vec4(mix(COLOR, texture_sample, 1.0 - COLOR.a).xyz, COLOR.a + texture_sample.a * (1.0 - COLOR.a));//
			time += time_step;
		}
		
		if (use_canvas_group_alpha_curve) {
			float relative_time_spread = time_spread / lifetime;
			float fragment_lifetime = COLOR.r * relative_time_spread + (1. / relative_time_spread - 1.) * relative_time_spread;
			float fragment_life = COLOR.g;
			float alpha_sample = fragment_lifetime - fragment_life;
			COLOR.a *= texture(alpha_curve, vec2(1. - alpha_sample)).r;
			COLOR.b = 0.25 / COLOR.a;
			COLOR.a *= 0.25;
		}
	}
	//vec2 normalized_uv = (custom_uv - animation_uv_offset * TEXTURE_PIXEL_SIZE) / (total_scale * snapshot_resolution_scale);
	//COLOR = vec4(normalized_uv, step(normalized_uv.x, 1.0) * step(normalized_uv.y, 1.0) * step(0, normalized_uv.x) * step(0, normalized_uv.y), 1);
}