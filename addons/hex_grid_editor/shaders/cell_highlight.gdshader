shader_type spatial;
render_mode blend_mix, depth_draw_disabled, cull_disabled;

uniform vec4 glow_color : source_color = vec4(0.0, 0.8, 1.0, 0.5);
uniform float glow_intensity : hint_range(0.0, 10.0) = 2.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 1.5;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed * 3.14159265);
	ALBEDO = glow_color.rgb;
	EMISSION = glow_color.rgb * glow_intensity * pulse;
	ALPHA = glow_color.a;
}
