@tool
extends CompositorEffect
class_name CloudShadowEffect

@export var shadow_min: float = 0.25
@export var scroll_speed: float = 0.005
@export var noise_scale: float = 1.0
@export var noise_texture: NoiseTexture2D

var rd := RenderingServer.get_rendering_device()
var shader: RID
var pipeline: RID
var _time: float = 0.0
var _noise_texture_rid: RID
var _noise_sampler_rid: RID
var _noise_uploaded: bool = false

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	var shader_file := preload("clouds.glsl")
	var shader_spirv := shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if shader.is_valid():
			rd.free_rid(shader)
		if _noise_texture_rid.is_valid():
			rd.free_rid(_noise_texture_rid)
		if _noise_sampler_rid.is_valid():
			rd.free_rid(_noise_sampler_rid)

func _upload_noise() -> bool:
	if noise_texture == null:
		return false
	var img: Image = noise_texture.get_image()
	if img == null:
		return false
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var fmt := RDTextureFormat.new()
	fmt.width = img.get_width()
	fmt.height = img.get_height()
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	_noise_texture_rid = rd.texture_create(fmt, RDTextureView.new(), [img.get_data()])
	if not _noise_texture_rid.is_valid():
		return false
	var sampler_state := RDSamplerState.new()
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_noise_sampler_rid = rd.sampler_create(sampler_state)
	return _noise_sampler_rid.is_valid()

func _render_callback(p_effect_callback_type: int, p_render_data: RenderData) -> void:
	if p_effect_callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return

	if not _noise_uploaded:
		_noise_uploaded = _upload_noise()
		if not _noise_uploaded:
			return

	var render_scene_buffers: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
	if not render_scene_buffers:
		return

	var size := render_scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	_time += 0.016

	var push_constant := PackedFloat32Array([
		float(size.x), float(size.y),
		_time, scroll_speed,
		shadow_min, noise_scale,
		0.0, 0.0
	])

	var groups := Vector3i(int(ceil(size.x / 8.0)), int(ceil(size.y / 8.0)), 1)

	for view in render_scene_buffers.get_view_count():
		var color_uniform := RDUniform.new()
		color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		color_uniform.binding = 0
		color_uniform.add_id(render_scene_buffers.get_color_layer(view))

		var noise_uniform := RDUniform.new()
		noise_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		noise_uniform.binding = 0
		noise_uniform.add_id(_noise_sampler_rid)
		noise_uniform.add_id(_noise_texture_rid)

		var set0 := UniformSetCacheRD.get_cache(shader, 0, [color_uniform])
		var set1 := UniformSetCacheRD.get_cache(shader, 1, [noise_uniform])

		var compute_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, set0, 0)
		rd.compute_list_bind_uniform_set(compute_list, set1, 1)
		rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
		rd.compute_list_dispatch(compute_list, groups.x, groups.y, groups.z)
		rd.compute_list_end()
