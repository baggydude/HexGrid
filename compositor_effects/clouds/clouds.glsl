#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 1, binding = 0) uniform sampler2D noise_texture;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;
    float time;
    float scroll_speed;
    float shadow_min;
    float noise_scale;
    float pad0;
    float pad1;
} params;

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = ivec2(params.screen_size);

    if (uv.x >= size.x || uv.y >= size.y) return;

    vec2 suv = (vec2(uv) + 0.5) / params.screen_size;
    vec2 noise_uv = suv * params.noise_scale + vec2(params.time * params.scroll_speed, params.time * params.scroll_speed * 0.4);

    float cloud = texture(noise_texture, noise_uv).r;
    float shadow_factor = mix(params.shadow_min, 1.0, cloud);

    vec4 color = imageLoad(color_image, uv);
    color.rgb *= shadow_factor;
    imageStore(color_image, uv, color);
}