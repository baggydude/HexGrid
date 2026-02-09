@tool
extends Node3D

@onready var outer_1: MeshInstance3D = $Outer1
@onready var outer_2: MeshInstance3D = $Outer2


var scroll_speed: float = 0.1

func _process(delta: float) -> void:
	var material1 = outer_1.get_surface_override_material(0)
	material1.uv1_offset.x += scroll_speed * delta
	var material2 = outer_2.get_surface_override_material(0)
	material2.uv1_offset.y -= scroll_speed * delta
