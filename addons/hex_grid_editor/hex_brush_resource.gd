@tool
class_name HexBrushResource
extends Resource

## Resource defining a hex brush type with scene variations and gameplay properties

@export var name: String = "Default Brush"
@export var is_blocked: bool = false
@export var movement_cost: float = 1.0

## Array of PackedScene variations for this brush.
## Each scene must contain a MeshInstance3D child named "Base" for height scaling.
@export var variations: Array[PackedScene] = []


func _init(
	p_name: String = "Default Brush",
	p_blocked: bool = false,
	p_cost: float = 1.0
) -> void:
	name = p_name
	is_blocked = p_blocked
	movement_cost = p_cost
