@tool
extends MeshInstance3D
@onready var water: MeshInstance3D = $"../Water"
var water_material

func _process(_delta: float) -> void:

	if water_material == null:
		water_material = water.get_surface_override_material(0)

	if water_material != null:
		water_material.set_shader_parameter("player_uv_position", Vector2(global_position.x, global_position.z))
	
