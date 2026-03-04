@tool
extends CompositorEffect
class_name Pixelate

@export var target_resolution: Vector2 = Vector2(640.0, 480.0)
@export var dither_amount: float = 0
@export var num_colors: float = 128.0

var rd := RenderingServer.get_rendering_device()
var shader: RID
var pipeline: RID
var depth_sampler: RID
var normal_roughness_sampler: RID

func _init() -> void:
	needs_normal_roughness = true
	var shader_file := preload("pixelate.glsl")
	var shader_spirv := shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)
	depth_sampler = rd.sampler_create(RDSamplerState.new())
	normal_roughness_sampler = rd.sampler_create(RDSamplerState.new())

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	var render_scene_buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var size := render_scene_buffers.get_internal_size()

	var inv_proj_mat := render_data.get_render_scene_data().get_cam_projection().inverse()
	var inv_proj_mat_array := PackedVector4Array([inv_proj_mat.x, inv_proj_mat.y, inv_proj_mat.z, inv_proj_mat.w])

	# mat4 = 64 bytes, then we pack the rest as float32
	# must be multiple of 16 bytes total: mat4(64) + 8 floats(32) = 96 bytes
	var extra := PackedFloat32Array([
		size.x, size.y,        # raster_size
		target_resolution.x, target_resolution.y,
		dither_amount,
		num_colors,
		0.0, 0.0               # pad to 32 bytes
	])

	var push_constants := inv_proj_mat_array.to_byte_array()
	push_constants.append_array(extra.to_byte_array())

	var color_layer_uniform := RDUniform.new()
	color_layer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	color_layer_uniform.binding = 0
	color_layer_uniform.add_id(render_scene_buffers.get_color_layer(0))

	var depth_layer_uniform := RDUniform.new()
	depth_layer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	depth_layer_uniform.binding = 1
	depth_layer_uniform.add_id(depth_sampler)
	depth_layer_uniform.add_id(render_scene_buffers.get_depth_layer(0))

	var normal_roughness_layer_uniform := RDUniform.new()
	normal_roughness_layer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	normal_roughness_layer_uniform.binding = 2
	normal_roughness_layer_uniform.add_id(normal_roughness_sampler)
	normal_roughness_layer_uniform.add_id(render_scene_buffers.get_texture("forward_clustered", "normal_roughness"))

	var bindings: Array[RDUniform] = [
		color_layer_uniform,
		depth_layer_uniform,
		normal_roughness_layer_uniform
	]

	var groups := Vector3i(
		(size.x + 7) / 8,
		(size.y + 7) / 8,
		1
	)

	var uniform_set := rd.uniform_set_create(bindings, shader, 0)
	var compute_list := rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list, groups.x, groups.y, groups.z)
	rd.compute_list_end()

	rd.free_rid(uniform_set)
