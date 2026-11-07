shader_type sky;
// Deep space, all procedural: three layers of stars (a few bright ones, many faint ones),
// a faint two-colour nebula and a soft glow around the sun. No textures, so it is ours
// and sharp at any resolution.

uniform vec3 nebula_a : source_color = vec3(0.16, 0.05, 0.22);
uniform vec3 nebula_b : source_color = vec3(0.02, 0.12, 0.2);
uniform float nebula_strength = 0.55;
uniform float star_brightness = 1.0;
uniform vec3 sun_direction = vec3(0.6, 0.35, 0.72);
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.72);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		sum += amp * value_noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

// One layer of stars: each cell of a grid around the viewer holds at most one star.
float stars(vec3 dir, float cells, float density, float size) {
	vec3 p = dir * cells;
	vec3 cell = floor(p);
	float brightness = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 c = cell + vec3(float(x), float(y), float(z));
				if (hash13(c + 17.0) > density) {
					continue;
				}
				vec3 star = c + hash33(c);
				float d = length(p - star);
				float twinkle = 0.6 + 0.4 * hash13(c + 3.0);
				brightness += twinkle * smoothstep(size, 0.0, d);
			}
		}
	}
	return brightness;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float n = fbm(dir * 2.2 + vec3(4.0, 1.0, 7.0));
	float m = fbm(dir * 3.7 + vec3(-2.0, 5.0, 3.0));
	vec3 nebula = (nebula_a * smoothstep(0.45, 0.85, n) + nebula_b * smoothstep(0.5, 0.9, m)) * nebula_strength;
	float s = stars(dir, 90.0, 0.10, 0.09) * 0.55 + stars(dir, 220.0, 0.12, 0.12) * 0.35 + stars(dir, 40.0, 0.05, 0.06) * 1.4;
	// Stars shine a little more through the nebula, as if lit by it.
	vec3 star_tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.9, 0.8), hash13(floor(dir * 90.0)));
	vec3 color = nebula + star_tint * s * star_brightness * (0.8 + nebula_strength * n);
	float sun = max(dot(dir, normalize(sun_direction)), 0.0);
	color += sun_color * (pow(sun, 900.0) * 6.0 + pow(sun, 40.0) * 0.12);
	COLOR = color;
}
