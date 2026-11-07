shader_type spatial;
// A planet from the artist's planets.blend: the procedural colour baked to a texture
// (tools/blender/build_planets.py) and the source material's glowing rim, a fresnel
// emission that shows only on the side the sun lights.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 rim_color : source_color = vec3(0.9, 0.3, 0.3);
uniform float rim_energy = 4.0;
uniform float rim_power = 3.0;
uniform vec3 sun_direction = vec3(0.6, 0.35, 0.72);

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, rim_power);
	float lit = smoothstep(-0.25, 0.6, dot(world_normal, normalize(sun_direction)));
	EMISSION = rim_color * rim_energy * fresnel * lit;
}
