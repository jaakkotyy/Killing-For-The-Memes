shader_type canvas_item;
// Fullscreen twin of crt_screen.gdshader, used while zoomed into a monitor. Same curvature
// math, so the picture doesn't jump when the 3D screen hands over to this overlay;
// CrtZoom maps mouse positions through the same curve (CrtMonitor.curve_uv).

uniform float curvature = 0.18;
uniform float scanlines = 240.0;
uniform float brightness = 1.15;

void fragment() {
	vec2 centred = UV * 2.0 - 1.0;
	centred *= 1.0 + curvature * dot(centred.yx, centred.yx) * 0.25;
	vec2 uv = centred * 0.5 + 0.5;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec3 picture = texture(TEXTURE, uv).rgb;
	float scan = 0.82 + 0.18 * sin(uv.y * scanlines * 6.2832);
	float vignette = smoothstep(1.6, 0.45, length(centred));
	COLOR = vec4(picture * scan * vignette * brightness, inside * COLOR.a);
}
