shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest;

uniform int groups = 6;
uniform float fps = 5.0f;

varying vec3 _base_pos;
varying float _random_pos;

void vertex() {
	// Billboard
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);

	//Get random pos
	_random_pos = fract(sin(dot(NODE_POSITION_WORLD.xz.xy, vec2(12.9898,78.233))) * 43758.5453123);

	// Calculate base position for lighting
	_base_pos = NODE_POSITION_WORLD + vec3(0.0, 0.07, 0.0);
	NORMAL = vec3(0.0, 1.0, 0.0);

	// Wind calculation
	float g = floor(_random_pos * float(groups)) / float(groups);
	float t = floor((TIME + g * 10.0) * fps) / fps;
	VERTEX.x += sin(PI * t) * VERTEX.y * 0.2;
}

void fragment() {
	LIGHT_VERTEX = (VIEW_MATRIX * vec4(_base_pos, 1.0)).xyz;
	ALBEDO = texture(albedo_texture, UV).rgb * COLOR.rgb;
	ALPHA = texture(albedo_texture, UV).a;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}