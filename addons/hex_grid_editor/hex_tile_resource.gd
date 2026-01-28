@tool
class_name HexTileResource
extends Resource

## Resource defining a hex tile type with its mesh and gameplay properties

@export var tile_name: String = "Default Tile"
@export var mesh: Mesh
@export var material_override: Material
@export var is_blocked: bool = false
@export var movement_cost: float = 1.0
@export var height_offset: float = 0.0

## Preview color used in the editor palette
@export var preview_color: Color = Color.WHITE

## Optional metadata for custom gameplay properties
@export var custom_properties: Dictionary = {}

func _init(
	p_name: String = "Default Tile",
	p_mesh: Mesh = null,
	p_blocked: bool = false,
	p_cost: float = 1.0
) -> void:
	tile_name = p_name
	mesh = p_mesh
	is_blocked = p_blocked
	movement_cost = p_cost
