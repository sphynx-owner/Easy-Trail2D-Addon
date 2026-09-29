shader_type canvas_item;

render_mode blend_add;

#define DEBUG

#ifdef DEBUG
#define BLEND_DIV 0.5

#define TIME_INFLUENCE_MUL 0.0
#else
#define BLEND_DIV 0.25

#define TIME_INFLUENCE_MUL 0.25
#endif

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

instance uniform vec2 manual_stretch_offset;

instance uniform float manual_stretch_time = 0.0;

// from https://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare/
// and https://blog.demofox.org/2022/01/01/interleaved-gradient-noise-a-different-kind-of-low-discrepancy-sequence/
// (section: Derivation Of IGN And Extensions) for animation of the noise.
float interleaved_gradient_noise(vec2 uv, int FrameId){
	uv += float(FrameId) * 5.588238;
	
	 vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
	
	return fract(magic.z * fract(dot(uv, magic.xy)));
}

varying flat vec2 stretch_offset;

varying flat int atlas_frame;

varying flat vec2 total_scale;

varying flat vec2 atlas_uv_offset;

varying flat float age;

varying flat float lifespan;

varying flat float stretch_time;

void vertex() {
	// We get the offset along which we stretch the texture
	stretch_offset = manual ? manual_stretch_offset : INSTANCE_CUSTOM.xz;
	
	// This is the texture size, as sprites resize
	// Their vertices to fit their texture automatically
	vec2 source_texture_size = 1.0 / TEXTURE_PIXEL_SIZE;
	
	// This is the total scale to apply on the texture, we take the snapshot 
	// resolution scale and the atlas dimensions into account as those need to
	// be inversed
	total_scale =
	1.0 / (snapshot_resolution_scale * vec2(float(atlas_h_frames), float(atlas_v_frames)));
	
	// The final size of the output texture in world pixels
	vec2 texture_final_size = source_texture_size * total_scale;
	
	// get an integer frame count
	int atlas_frame_count = atlas_h_frames * atlas_v_frames;
	
	// get the atlas_frame to use
	atlas_frame = manual ? manual_atlas_frame : int(round(COLOR.g));
	
	// in case of falty frame vs frame count, we modulate
	atlas_frame = (atlas_frame + atlas_frame_count) % atlas_frame_count;
	
	// get the integer frame coord of the current frame (row, column)
	ivec2 atlas_frame_coord =
	ivec2(atlas_frame % atlas_h_frames, atlas_frame / atlas_h_frames);
	
	// We get the uv offset for the current frame in the atlas in pixels
	atlas_uv_offset =
	source_texture_size * vec2(atlas_frame_coord)
	/ vec2(ivec2(atlas_h_frames, atlas_v_frames));
	
	// This scales the UV so that it is a consistent global size, in this
	// case the scale of a single global pixel
	vec2 uv_scale =
	texture_final_size
	* snapshot_resolution_scale + abs(stretch_offset * snapshot_resolution_scale);
	
	// We scale the source UV to be in world space
	UV *= uv_scale;
	
	// We add the world space atlas frame offset
	UV += atlas_uv_offset;
	
	// We shift the UV to always be at the end of the offset, note that the
	// final change depends on the direction of the offset.
	UV -= max(vec2(0), stretch_offset * snapshot_resolution_scale);
	
	// We transform the UV back to UV space.
	UV *= TEXTURE_PIXEL_SIZE;
	
	// We scale the vertex so that it reflects the final size of the
	// texture, and then expand it so that it behaves like a bounding box for
	// the stretched texture
	VERTEX = VERTEX * total_scale;
	
	// We only extend the vertices in the direction of the offset.
	VERTEX = VERTEX + vec2(
		VERTEX.x > 0.0 ? max(stretch_offset.x, 0.0) : min(stretch_offset.x, 0.0),
		VERTEX.y > 0.0 ? max(stretch_offset.y, 0.0) : min(stretch_offset.y, 0.0)
	);
	
	// get the age to use
	age = manual ? manual_age : INSTANCE_CUSTOM.y;
	
	// get the stretch_time to use
	stretch_time = manual ? manual_stretch_time : COLOR.r;
	
	// get the lifespan to use
	lifespan = manual ? manual_lifespan : INSTANCE_CUSTOM.w;
}

void fragment() {
	// The offset along the width of the trail, used to
	// sample 
	float side_offset = 0.0;
	
	// The alpha of the fragment
	float alpha = 0.0;
	
	// Whether the fragment is visible at all
	float visible = 0.0;
	
	// The time of the fragment. For stretched particles that time varies
	// along the stretch.
	float time = 0.0;
	
	// If the particle is stretched at all
	if (stretch_offset != vec2(0)) {
		// we get a UV-space stretch offset
		vec2 scaled_stretch_offset = stretch_offset * snapshot_resolution_scale * TEXTURE_PIXEL_SIZE;
		
		// We extract a perpendicular normal to the offset
		vec2 offset_perpen = normalize(vec2(-scaled_stretch_offset.y, scaled_stretch_offset.x));
		
		// the step length between samples
		float time_step =  1.0 / float(sample_count);
		
		// we get a jitter that would spread the sampling more evenly. Instead of
		// the sampled result being many duplicated silhouettes matching the sample count,
		// we spread them more evenly and as a result they lose opacity
		// slightly on thinner edges.
		float jitter = interleaved_gradient_noise(SCREEN_UV / SCREEN_PIXEL_SIZE, game_frame);
		
		for (int i = 0; i < sample_count; i++) {
			// We start from the end. The reason is that we want
			// to sample along a particular direction so that it
			// takes precedence, resulting in a more consistent time value
			// that decays with the silhouette of the sprite.
			float t = 1.0 - (float(i) + jitter) * time_step;
			
			// We get a sample position given the offset and the time
			vec2 temp_uv = UV + scaled_stretch_offset * t;
			
			// We normalize the sample position to be locally to uv space of the
			// target frame
			vec2 normalized_temp_uv = (temp_uv - atlas_uv_offset * TEXTURE_PIXEL_SIZE) / (total_scale * snapshot_resolution_scale);
			
			// If that uv is out of bounds, we don't want to use it, as it could 
			// otherwise show clamped or repeated color values.
			if (normalized_temp_uv.x < 0.0 || normalized_temp_uv.x > 1.0 || normalized_temp_uv.y < 0.0 || normalized_temp_uv.y > 1.0) {
				continue;
			}
			
			// We sample the texture at the uv (texel fetching cause it is cleaner and faster)
			vec4 texture_sample = texelFetch(TEXTURE, ivec2(temp_uv / TEXTURE_PIXEL_SIZE), 0);
			
			// If the found alpha is greater than the current alpha, we use that
			// sample. The idea is that higher alpha is taking precedence.
			if (texture_sample.a > alpha) {
				alpha = texture_sample.a;
				time = t;
				side_offset = 1.0 - (dot(normalized_temp_uv - 0.5, offset_perpen) + 0.5);
				visible = 1.0;
			}
		}
	}
	else {
		if (UV.x > 0.0 && UV.x < 1.0 && UV.y > 0.0 && UV.y < 1.0) {
			alpha = texelFetch(TEXTURE, ivec2(UV / TEXTURE_PIXEL_SIZE), 0).a;
		}
		
		visible = step(0.00001, alpha);
		
		// Setting the time to 1 as that is the neutral value in the case of this
		// implementation.
		time = 1.0;
	}
	
	float final_time = ((1.0 - time) * stretch_time + age) / lifespan;
	
	float influence = 1.0 - final_time * TIME_INFLUENCE_MUL;
	
	COLOR = vec4(
#ifdef DEBUG
		float(manual),
		float(atlas_frame) / 10.0,
		1.0,
		0.5
#else
		// Because influence is on a per-particle basis, we cannot
		// divide it's accumulated value on the canvas group, it has
		// to be taken into account in here. Since the alpha channel
		// multiplies itself before adding itself to the colr with blend_add
		// we need to apply it the sqare root of the influence, and account for
		// that in the data channels so that the full influence is applied to them.
		final_time * sqrt(influence),
		side_offset * sqrt(influence),
		alpha * sqrt(influence),
		BLEND_DIV * sqrt(influence)
#endif
	) * visible * step(final_time, 0.999);
}