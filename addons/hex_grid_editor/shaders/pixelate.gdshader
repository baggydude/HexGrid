shader_type spatial;
render_mode unshaded;

uniform vec2 target_resolution = vec2(640.0, 360.0);
uniform sampler2D screen_texture: hint_screen_texture, filter_nearest;

void fragment() {
	vec2 uv = SCREEN_UV;
	uv *= target_resolution;
	uv = floor(uv) + vec2(0.5);
	uv /= target_resolution;
	vec4 color = texture(screen_texture, uv);

	ALBEDO = color.rgb;
	ALPHA = color.a;
}