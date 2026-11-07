shader_type spatial;
// Glowing CRT glass: curved picture, scanlines, vignette. Shows `screen_texture` when
// `has_picture` is set (the search terminal's SubViewport), otherwise idle static.

uniform sampler2D screen_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_picture = false;
uniform vec3 idle_tint : source_color = vec3(0.35, 0.95, 0.7);
uniform float brightness : hint_range(0.0, 8.0) = 1.8;
uniform float curvature : hint_range(0.0, 0.5) = 0.18;
uniform float scanlines = 240.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.04;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 centred = UV * 2.0 - 1.0;
	centred *= 1.0 + curvature * dot(centred.yx, centred.yx) * 0.25;
	vec2 uv = centred * 0.5 + 0.5;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);

	vec3 picture;
	if (has_picture) {
		picture = texture(screen_texture, uv).rgb;
	} else {
		float frame = floor(TIME * 15.0);
		float grain = hash(floor(uv * vec2(180.0, 135.0)) + frame + seed);
		float roll = smoothstep(0.92, 1.0, fract(uv.y * 0.6 - TIME * 0.12 + seed));
		picture = idle_tint * (0.14 + 0.16 * grain + 0.25 * roll);
	}
	float scan = 0.7 + 0.3 * sin(uv.y * scanlines * 6.2832);
	float vignette = smoothstep(1.45, 0.35, length(centred));
	float wobble = 1.0 - flicker * hash(vec2(floor(TIME * 30.0), seed));
	vec3 glow = picture * scan * vignette * wobble * inside * brightness;

	ALBEDO = vec3(0.01);
	EMISSION = glow;
	ROUGHNESS = 0.3;
	SPECULAR = 0.35;
}
