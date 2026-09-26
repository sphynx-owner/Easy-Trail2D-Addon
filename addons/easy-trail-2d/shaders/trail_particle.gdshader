shader_type canvas_item;

render_mode blend_add;

#define BLEND_DIV 0.5

#define ALPHA_DIV 0.5

instance uniform int atlas_h_frames;

instance uniform int atlas_v_frames;

// The resolution scale of the image, used to maintain the particle's global size
instance uniform float snapshot_resolution_scale = 1.0;

instance uniform int sample_count = 5;

instance uniform int game_frame;

instance uniform bool manual = false;

instance uniform int manual_atlas_frame = 0;

instance uniform float manual_lifespan = 0.0;

instance uniform float manual_age = 0.0;

instance uniform vec2 manual_offset;

instance uniform float manual_stretch_time = 0.0;

// from https://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare/
// and https://blog.demofox.org/2022/01/01/interleaved-gradient-noise-a-different-kind-of-low-discrepancy-sequence/
// (section: Derivation Of IGN And Extensions) for animation of the noise.
float interleaved_gradient_noise(vec2 uv, int FrameId){
	uv += float(FrameId) * 5.588238;
	
	 vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
	
	return fract(magic.z * fract(dot(uv, magic.xy)));
}

varying flat vec2 offset;

varying flat vec2 total_scale;

varying flat vec2 atlas_uv_offset;

varying flat float age;

varying flat float lifespan;

varying flat float stretch_time;

void vertex() {
	// We get the offset along which we stretch the texture
	offset = manual ? manual_offset : INSTANCE_CUSTOM.xz;
	
	// We get the atlas dimensions into float values
	float h_frames = float(atlas_h_frames);
	
	float v_frames = float(atlas_v_frames);
	
	// This is the texture size, as sprites resize
	// Their vertices to fit their texture automatically
	vec2 source_texture_size = 1.0 / TEXTURE_PIXEL_SIZE;
	
	// This is the total scale to apply on the texture, we take the snapshot resolution scale
	// and the atlas dimensions into account as those need to be inversed
	total_scale = vec2(1) / snapshot_resolution_scale / vec2(h_frames, v_frames);
	
	// The final size of the output texture in world pixels
	vec2 texture_final_size = source_texture_size * total_scale;
	
	float atlas_frame_count = float(atlas_h_frames * atlas_v_frames);
	
	float atlas_frame = floor(manual ? float(manual_atlas_frame) : COLOR.g);
	
	atlas_frame = clamp(atlas_frame, 0.0, atlas_frame_count - 1.0);
	
	// We get the uv offset for the current frame in the atlas in pixels
	atlas_uv_offset = vec2(mod(atlas_frame, h_frames) / h_frames, floor((atlas_frame + 0.5) / h_frames) / v_frames) * source_texture_size;
	
	// This scales the UV so that it is a consistent global size, in this case the scale of a single global pixel
	vec2 uv_scale = texture_final_size * snapshot_resolution_scale + abs(offset * snapshot_resolution_scale);
	
	// We scale the uv and then offset it by the atlas frame offset
	UV *= uv_scale;
	
	UV += atlas_uv_offset;
	
	// This is so that the uv always starts at the end of the offset
	UV -= max(vec2(0), offset * snapshot_resolution_scale);
	
	UV *= TEXTURE_PIXEL_SIZE;
	
	// We scale the vertex so that it reflects the final size of the texture, and then expand it so that
	// it behaves like a bounding box for the stretched texture
	VERTEX = VERTEX * total_scale;
	
	VERTEX = VERTEX + vec2(VERTEX.x > 0.0 ? max(offset.x, 0.0) : min(offset.x, 0.0), VERTEX.y > 0.0 ? max(offset.y, 0.0) : min(offset.y, 0.0));
	
	age = manual ? manual_age : INSTANCE_CUSTOM.y;
	
	stretch_time = manual ? manual_stretch_time : COLOR.r;
	
	lifespan = manual ? manual_lifespan : INSTANCE_CUSTOM.w;
}

void fragment() {
	vec2 scaled_offset = offset * snapshot_resolution_scale * TEXTURE_PIXEL_SIZE;
	
	vec2 normalized_offset = normalize(scaled_offset);
	
	vec2 offset_perpen = vec2(-normalized_offset.y, normalized_offset.x);
	
	float time_step =  1.0 / float(sample_count);
	
	// must be done this way so that the error between snapshot genertor viewports would be reduced to a minimum
	float jitter = interleaved_gradient_noise(SCREEN_UV / SCREEN_PIXEL_SIZE, game_frame);
	
	float time = 0.0;
	
	float side_offset = 0.0;
	
	float alpha = 0.0;
	
	vec2 initial_uv = UV + scaled_offset;
	
	if (offset == vec2(0) && initial_uv.x > 0.0 && initial_uv.x < 1.0 && initial_uv.y > 0.0 && initial_uv.y < 1.0) {
		alpha = texelFetch(TEXTURE, ivec2(initial_uv / TEXTURE_PIXEL_SIZE), 0).a;
	}
	
	bool visible = false;
	
	if (offset != vec2(0)) {
		for (int i = -1; i < sample_count + 1; i++) {
			float t = 1.0 - (float(i) + jitter) * time_step;
			
			float clamped_t = clamp(t, 0.0, 1.0);
			
			vec2 temp_uv = UV + scaled_offset * clamped_t;
			
			vec2 normalized_temp_uv = (temp_uv - atlas_uv_offset * TEXTURE_PIXEL_SIZE) / (total_scale * snapshot_resolution_scale);
			
			if (normalized_temp_uv.x < 0.0 || normalized_temp_uv.x > 1.0 || normalized_temp_uv.y < 0.0 || normalized_temp_uv.y > 1.0) {
				continue;
			}
			
			vec4 texture_sample = texelFetch(TEXTURE, ivec2(temp_uv / TEXTURE_PIXEL_SIZE), 0);
			
			if (texture_sample.a > alpha) {
				alpha = texture_sample.a;
				time = t;
				side_offset = (dot(normalized_temp_uv - 0.5, offset_perpen) * 2.0 + 0.5);
				visible = true;
			}
		}
		
		if (visible) {
			float final_time = ((1.0 - time) * stretch_time + age) / lifespan;
			
			float influence = 1.0 - final_time * 0.5;
			
			COLOR = vec4(
				final_time * BLEND_DIV * influence,
				side_offset * BLEND_DIV * influence,
				alpha * BLEND_DIV * influence,
				BLEND_DIV * influence
			);
		}
		else {
			COLOR = vec4(0);
		}
	}
	else {
		float final_time = age / lifespan;
		
		float influence = 1.0 - final_time * 0.5;
		
		COLOR = vec4(
			final_time * BLEND_DIV * influence,
			side_offset * BLEND_DIV * influence,
			alpha * BLEND_DIV * influence,
			BLEND_DIV * influence
		) * step(0.000001, alpha);
	}
}