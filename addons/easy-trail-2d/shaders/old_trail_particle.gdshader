shader_type canvas_item;

render_mode blend_mix;

uniform float snapshot_resolution_scale = 1.0;
uniform int particles_anim_h_frames;
uniform int particles_anim_v_frames;

void vertex() {
	VERTEX /= snapshot_resolution_scale;

	float h_frames = float(particles_anim_h_frames);
	float v_frames = float(particles_anim_v_frames);

	VERTEX.xy /= vec2(h_frames, v_frames);

	float particle_total_frames = float(particles_anim_h_frames * particles_anim_v_frames);
	float particle_frame = floor(INSTANCE_CUSTOM.z * float(particle_total_frames));

	particle_frame = clamp(particle_frame, 0.0, particle_total_frames - 1.0);

	UV /= vec2(h_frames, v_frames);
	UV += vec2(mod(particle_frame, h_frames) / h_frames, floor((particle_frame + 0.5) / h_frames) / v_frames);
}
