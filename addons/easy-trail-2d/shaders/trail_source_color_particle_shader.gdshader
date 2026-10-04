shader_type canvas_item;

render_mode blend_mix;

uniform sampler2D alpha_texture: repeat_disable;

instance uniform int atlas_h_frames;

instance uniform int atlas_v_frames;

// The resolution scale of the image, used to maintain the particle's global size
instance uniform float snapshot_resolution_scale = 1.0;

varying flat int atlas_frame;

varying flat vec2 total_scale;

varying flat vec2 atlas_uv_offset;

varying flat float age;

varying flat float lifespan;

void vertex() {
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
	atlas_frame = int(round(COLOR.g));
	
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
	vec2 uv_scale = texture_final_size * snapshot_resolution_scale;
	
	// We scale the source UV to be in world space
	UV *= uv_scale;
	
	// We add the world space atlas frame offset
	UV += atlas_uv_offset;
	
	// We transform the UV back to UV space.
	UV *= TEXTURE_PIXEL_SIZE;
	
	// We scale the vertex so that it reflects the final size of the
	// texture, and then expand it so that it behaves like a bounding box for
	// the stretched texture
	VERTEX = VERTEX * total_scale;
	
	// get the age to use
	age = INSTANCE_CUSTOM.y;
	
	// get the lifespan to use
	lifespan = INSTANCE_CUSTOM.w;
}

void fragment() {
	// The alpha of the fragment
	vec4 color = vec4(0);
	
	// Whether the fragment is visible at all
	float visible = 0.0;
	
	if (UV.x > 0.0 && UV.x < 1.0 && UV.y > 0.0 && UV.y < 1.0) {
		color = texelFetch(TEXTURE, ivec2(UV / TEXTURE_PIXEL_SIZE), 0);
	}
	
	float final_time = age / lifespan;
	
	color.a *= texture(alpha_texture, vec2(final_time, 0.5)).r;
	
	COLOR = color;
}