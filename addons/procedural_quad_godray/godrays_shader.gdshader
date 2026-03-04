shader_type spatial;
render_mode cull_disabled, fog_disabled, shadow_to_opacity, depth_draw_opaque;

uniform vec3 light_color : source_color = vec3(1.0, 0.8, 0.4); // Beam color
uniform vec3 emission_color : source_color = vec3(1.0, 0.8, 0.4); // Emission color
uniform float emission_strength = 3.0; // Emission intensity multiplier
uniform float base_alpha = 0.025;                      // Beam base transparency
uniform bool use_edge_fade = false;                   // Toggle edge fade effect
uniform sampler2D gradient_texture : source_color;   // Gradient texture for alpha mask
uniform bool use_gradient_mask = true;              // Toggle gradient mask effect
uniform bool debug_distance_mode = false;            // Debug mode: red=close, blue=far
uniform float debug_near_distance = 5.0;             // Distance considered "near" (red)
uniform float debug_far_distance = 50.0;             // Distance considered "far" (blue)
uniform bool use_distance_fade = true;               // Toggle distance fade effect
uniform float distance_fade_start = 100.0;            // Distance where fade starts
uniform float distance_fade_end = 0.0;             // Distance where fade ends (fully transparent)
uniform float depth_fade_distance : hint_range(0.01, 10.0) = 10.0; // World units for fade softness
uniform bool use_depth_fade = true; // Toggle depth fade effect
uniform bool use_depth_blur = true; // Toggle depth blur effect
uniform float depth_blur_size : hint_range(0.1, 5.0) = 1.0; // Size of the blur kernel in pixels
uniform int depth_blur_samples : hint_range(1, 5) = 3; // Number of samples per axis (3x3, 5x5, etc)
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;

// Shadow control uniforms
uniform bool use_hard_shadows = true; // Toggle between hard and soft shadows
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.5; // Threshold for hard shadow cutoff

// View angle fade uniforms
uniform bool use_view_angle_fade = true; // Toggle view angle fade effect
uniform float fade_angle_start : hint_range(0.0, 90.0) = 30.0; // Angle in degrees where fade starts
uniform float fade_angle_end : hint_range(0.0, 90.0) = 5.0; // Angle in degrees where fade ends (fully transparent)
uniform vec3 godray_direction = vec3(0.0, -1.0, 0.5); // Direction the godrays are pointing (from light source)
uniform bool debug_view_angle = false; // Debug: show angle as color (red=aligned, green=perpendicular)

varying mat4 world_mat;
varying vec3 world_vertex;

float getDepth(vec2 screen_uv, float raw_depth, mat4 inv_projection_matrix) {
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, raw_depth);
	vec4 view_space = inv_projection_matrix * vec4(ndc, 1.0);
	view_space.xyz /= view_space.w;
	return -view_space.z;
}

// Box blur depth sampling function
float sampleDepthBlurred(vec2 screen_uv, mat4 inv_projection_matrix) {
    if (!use_depth_blur) {
        // Single sample if blur is disabled
        float scene_depth = texture(DEPTH_TEXTURE, screen_uv).r;
        return getDepth(screen_uv, scene_depth, inv_projection_matrix);
    }

    // Calculate pixel size for blur offset
    vec2 pixel_size = depth_blur_size / vec2(textureSize(DEPTH_TEXTURE, 0));

    float total_depth = 0.0;
    int total_samples = 0;

    // Box blur sampling
    for (int x = -depth_blur_samples; x <= depth_blur_samples; x++) {
        for (int y = -depth_blur_samples; y <= depth_blur_samples; y++) {
            vec2 offset = vec2(float(x), float(y)) * pixel_size;
            vec2 sample_uv = screen_uv + offset;

            // Check if sample is within valid UV range
            if (sample_uv.x >= 0.0 && sample_uv.x <= 1.0 && sample_uv.y >= 0.0 && sample_uv.y <= 1.0) {
                float scene_depth = texture(DEPTH_TEXTURE, sample_uv).r;
                total_depth += getDepth(sample_uv, scene_depth, inv_projection_matrix);
                total_samples++;
            }
        }
    }

    // Return average depth
    return total_samples > 0 ? total_depth / float(total_samples) : 0.0;
}

void vertex() {
    // Store world matrix and world vertex for calculations
    world_mat = INV_VIEW_MATRIX;
    world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    // Standard vertex transformation - no billboarding
    VERTEX = VERTEX;
}

void fragment() {
    // Apply soft fade at beam ends using UV.x if use_edge_fade is true
    float fade = use_edge_fade ? smoothstep(0.0, 0.1, UV.x) * (1.0 - smoothstep(0.9, 1.0, UV.x)) : 1.0;

    // Sample gradient texture for alpha mask (using UV.x for left-to-right gradient)
    float gradient_alpha = use_gradient_mask ? texture(gradient_texture, vec2(UV.y, 0.5)).r : 1.0;

    // Calculate distance from camera
    vec3 world_pos = world_vertex;
    // Extract camera position from view matrix (inverse of view matrix translation)
    vec3 camera_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    float distance_to_camera = length(world_pos - camera_pos);

    // Distance fade calculation
    float distance_fade = 1.0;
    if (use_distance_fade) {
        distance_fade = smoothstep(distance_fade_end, distance_fade_start, distance_to_camera);
        distance_fade = clamp(distance_fade, 0.0, 1.0);
    }

    // View angle fade calculation
    float view_angle_fade = 1.0;
    float debug_angle_degrees = 0.0; // For debug visualization

    if (use_view_angle_fade || debug_view_angle) {
        // Calculate camera's view direction in world space
        vec3 camera_forward = (INV_VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz;
        camera_forward = normalize(camera_forward);

        // Normalize the godray direction
        vec3 ray_direction = normalize(godray_direction);

        // Calculate the dot product (cosine of angle between vectors)
        // dot = 1.0 when perfectly aligned, -1.0 when opposite, 0.0 when perpendicular
        float dot_product = dot(camera_forward, ray_direction);

        // Convert dot product to angle in degrees
        float angle_radians = acos(clamp(abs(dot_product), 0.0, 1.0));
        debug_angle_degrees = degrees(angle_radians);

        if (use_view_angle_fade) {
            // Apply fade based on angle thresholds
            // Small angle = camera looking in same direction as godrays = fade out
            if (debug_angle_degrees <= fade_angle_end) {
                view_angle_fade = 0.0; // Fully transparent when aligned
            } else if (debug_angle_degrees <= fade_angle_start) {
                // Smooth fade: fade out as angle gets smaller (more aligned)
                view_angle_fade = smoothstep(fade_angle_end, fade_angle_start, debug_angle_degrees);
            }
            // else view_angle_fade remains 1.0 (fully visible when perpendicular or opposite)
        }
    }

    // --- Depth fade with optional blur ---
    float depth_fade = 1.0;
    if (use_depth_fade) {
        // Early exit if alpha is already very low to avoid expensive depth calculations
        float current_alpha = base_alpha * fade * gradient_alpha * distance_fade * view_angle_fade;
        if (current_alpha > 0.001) {
            // Use blurred depth sampling
            float scene_linear_depth = sampleDepthBlurred(SCREEN_UV, INV_PROJECTION_MATRIX);
            float frag_linear_depth = getDepth(SCREEN_UV, FRAGCOORD.z, INV_PROJECTION_MATRIX);
            float depth_diff = scene_linear_depth - frag_linear_depth;
            depth_fade = smoothstep(0.0, depth_fade_distance, depth_diff);
        }
    }

    // Debug distance coloring: red for close, blue for far
    // OR debug view angle coloring: red for aligned, green for perpendicular
    vec3 debug_color = vec3(1.0);
    if (debug_distance_mode) {
        float distance_factor = clamp((distance_to_camera - debug_near_distance) / (debug_far_distance - debug_near_distance), 0.0, 1.0);
        debug_color = mix(vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), distance_factor); // Red to Blue
    } else if (debug_view_angle) {
        // Debug view angle: red when aligned (0°), green when perpendicular (90°)
        float angle_factor = clamp(debug_angle_degrees / 90.0, 0.0, 1.0);
        debug_color = mix(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), angle_factor); // Red to Green
    }

    // Calculate final alpha
    float final_alpha = base_alpha * fade * gradient_alpha * distance_fade * depth_fade * view_angle_fade;

    // Early discard for very transparent pixels to help with overdraw
    if (final_alpha < 0.00001) {
        discard;
    }

    ALBEDO = (debug_distance_mode || debug_view_angle) ? debug_color : light_color;
    EMISSION = (debug_distance_mode || debug_view_angle) ? debug_color * emission_strength * fade : emission_color * emission_strength * fade;
    ALPHA = final_alpha;
}

void light() {
    // Only process directional lights to avoid clustering artifacts
    if (LIGHT_IS_DIRECTIONAL) {
        if (use_hard_shadows) {
            // Create hard shadow cutoff for regular shadows
            float shadow_factor = step(shadow_threshold, ATTENUATION);
            if (shadow_factor < 0.5) {
                discard;
            }
        } else {
            // Smooth shadow behavior for regular shadows
            ALPHA *= ATTENUATION;
            if (ALPHA < 0.001) {
                discard;
            }
        }
    }
    // Ignore omni/spot lights completely
}