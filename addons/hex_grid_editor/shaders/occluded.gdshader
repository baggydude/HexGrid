shader_type spatial;
render_mode depth_test_disabled, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform vec4 occluded_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	//MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		//INV_VIEW_MATRIX[0],
		//vec4(0.0, 1.0, 0.0, 0.0),
		//INV_VIEW_MATRIX[2],
		//MODEL_MATRIX[3]
	//);
}

void fragment() {
    vec4 tex = texture(albedo_texture, UV);
    if (tex.a < 0.1) discard;

    float scene_depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	bool occluded = FRAGCOORD.z < scene_depth;

    if (occluded) {
	    ALBEDO = occluded_color.rgb;
		//EMISSION = occluded_color.rgb;
    } else if (!occluded) {
        ALBEDO = tex.rgb;
    } else {
        discard;
    }

    ALPHA = tex.a;
}