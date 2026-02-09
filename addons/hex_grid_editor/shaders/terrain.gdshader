shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform int cel_cuts : hint_range(1, 8, 1) = 3;
uniform float cloud_scale = 0.1;
uniform vec2 cloud_speed = vec2(0.03);
uniform sampler2D cloud_texture : source_color, filter_linear_mipmap, repeat_enable;

uniform vec4 color_albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float noise_strength = 1.0;

varying mat4 _world_matrix;
varying vec3 _vertex;

void vertex() {
	_world_matrix = INV_VIEW_MATRIX;
}

void fragment() {
	_vertex = VERTEX;
	vec4 albedo_tex = texture(texture_albedo, UV);
	ALBEDO = color_albedo.rgb * albedo_tex.rgb;
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_amount = NdotL + (ATTENUATION - 1.0);

	if (LIGHT_IS_DIRECTIONAL) {
		vec3 ray_dir = -LIGHT;
		ray_dir = mat3(_world_matrix) * ray_dir;
		vec3 ray_start = (INV_VIEW_MATRIX * vec4(_vertex, 1.0f)).xyz;

		vec3 n = vec3(0.0, 1.0, 0.0);
		vec3 PO = vec3(0.0, 1.0, 0.0);
		vec3 v = PO - ray_start;

		float t = dot(normalize(v), n) * length(v) / dot(ray_dir, n);
		vec3 P = ray_start + t * ray_dir;

		vec2 uv = P.xz;
		vec2 uv_offset = vec2(TIME, TIME) * cloud_speed;
		vec4 rg = texture( cloud_texture, uv * cloud_scale + uv_offset) * noise_strength;

		float clouds = smoothstep(0.2, 1.0, 1.0 - rg.r);
		diffuse_amount -= clouds;
	}

	float cuts_inv = 1.0f / float(cel_cuts);
	float diffuse_stepped = clamp(diffuse_amount + mod(1.0f - diffuse_amount, cuts_inv), 0.0f, 1.0f);

	vec3 diffuse = ALBEDO.rgb * LIGHT_COLOR / PI;
	diffuse *= diffuse_stepped;

	DIFFUSE_LIGHT += diffuse;
}