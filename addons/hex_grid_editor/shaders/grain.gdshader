shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 ground_color : source_color = vec4(1.0);

uniform vec4 variant_color_dark : source_color = vec4(1.0);
uniform vec4 variant_color_light : source_color = vec4(1.0);
uniform float variant_threshold_dark : hint_range(0.0, 1.0) = 0.995;
uniform float variant_threshold_light : hint_range(0.0, 1.0) = 0.995;

global uniform int cel_cuts : hint_range(1, 8, 1) = 8;
global uniform float cloud_scale = 0.1;
global uniform vec2 cloud_speed = vec2(0.03);
global uniform sampler2D cloud_texture : source_color, filter_linear_mipmap, repeat_enable;

uniform int groups = 6;
uniform float fps = 5.0f;
uniform float noise_strength = 1.0;

varying vec3 _base_pos;
varying mat4 _world_matrix;
varying vec3 _vertex;
varying float _random_pos;

void vertex() {
	// Billboard
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		vec4(0.0, 1.0, 0.0, 0.0),
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	
	//Get random pos
	_random_pos = fract(sin(dot(NODE_POSITION_WORLD.xz.xy, vec2(12.9898,78.233))) * 43758.5453123);
	// Calculate base position for lighting
	_base_pos = NODE_POSITION_WORLD + vec3(0.0, 0.07, 0.0);
	NORMAL = vec3(0.0, 1.0, 0.0);
	// Set World matrix
	_world_matrix = INV_VIEW_MATRIX;
	// Wind calculation
	float g = floor(_random_pos * float(groups)) / float(groups);
	float t = floor((TIME + g * 10.0) * fps) / fps;
	VERTEX.x += sin(PI * t) * VERTEX.y * 0.2;
}

void fragment() {
	_vertex = VERTEX;
	LIGHT_VERTEX = (VIEW_MATRIX * vec4(_base_pos, 1.0)).xyz;
	
	float is_dark = step(variant_threshold_dark, _random_pos) * (1.0 - step(variant_threshold_light, _random_pos));
	float is_light = step(variant_threshold_light, _random_pos);
	vec3 base = mix(ground_color.rgb, variant_color_dark.rgb, is_dark);
	ALBEDO = mix(base, variant_color_light.rgb, is_light) * COLOR.rgb;
	ALPHA = texture(albedo_texture, UV).a;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_amount = NdotL + (ATTENUATION - 1.0);

	if (LIGHT_IS_DIRECTIONAL) {
		vec3 ray_dir = -LIGHT;
		ray_dir = mat3(_world_matrix) * ray_dir;
		vec3 ray_start = _base_pos;
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