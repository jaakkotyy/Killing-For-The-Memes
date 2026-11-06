shader_type spatial;
// Player body: one mesh, clothing painted by vertex-colour masks written by
// tools/blender/build_player.py (R = shirt, G = trousers, B = shoes, rest = skin).
// Normal and AO maps are baked from the artist's high-poly sculpt.

uniform vec3 skin_color : source_color = vec3(0.78, 0.58, 0.46);
uniform vec3 shirt_color : source_color = vec3(0.6, 0.55, 0.3);
uniform vec3 trouser_color : source_color = vec3(0.18, 0.17, 0.16);
uniform vec3 shoe_color : source_color = vec3(0.08, 0.06, 0.05);
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap;
uniform sampler2D ao_map : hint_default_white, filter_linear_mipmap;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.8;
// Grime darkens cloth unevenly so every shirt looks worn for days.
uniform float grime : hint_range(0.0, 1.0) = 0.35;
// 0..1 fades the body to grey for spectators (M5).
uniform float desaturate : hint_range(0.0, 1.0) = 0.0;

varying vec3 masks;
varying vec3 model_pos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash(i), n100 = hash(i + vec3(1, 0, 0));
	float n010 = hash(i + vec3(0, 1, 0)), n110 = hash(i + vec3(1, 1, 0));
	float n001 = hash(i + vec3(0, 0, 1)), n101 = hash(i + vec3(1, 0, 1));
	float n011 = hash(i + vec3(0, 1, 1)), n111 = hash(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	// glTF stores colours linear; the masks were authored as plain 0..1 values.
	masks = pow(clamp(COLOR.rgb, 0.0, 1.0), vec3(1.0 / 2.2));
	model_pos = VERTEX;
}

void fragment() {
	float shirt = smoothstep(0.42, 0.58, masks.r);
	float trousers = smoothstep(0.42, 0.58, masks.g);
	float shoes = smoothstep(0.42, 0.58, masks.b);
	float cloth = clamp(shirt + trousers + shoes, 0.0, 1.0);

	vec3 color = skin_color;
	color = mix(color, shirt_color, shirt);
	color = mix(color, trouser_color, trousers);
	color = mix(color, shoe_color, shoes);

	float stains = noise(model_pos * 9.0) * 0.6 + noise(model_pos * 31.0) * 0.4;
	color *= mix(1.0, 0.55 + 0.45 * stains, grime * cloth);
	float ao = texture(ao_map, UV).r;
	color *= mix(1.0, ao, ao_strength);
	float grey = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(grey) * 0.8, desaturate);

	ALBEDO = color;
	ROUGHNESS = mix(0.5, 0.92, cloth);
	SPECULAR = mix(0.45, 0.2, cloth);
	NORMAL_MAP = texture(normal_map, UV).rgb;
	// Clothes hide most of the sculpted muscle detail.
	NORMAL_MAP_DEPTH = mix(1.0, 0.3, shirt + trousers);
	// Cheap skin warmth where light wraps around thin parts.
	BACKLIGHT = vec3(0.25, 0.06, 0.03) * (1.0 - cloth);
}
