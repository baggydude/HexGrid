@tool
class_name HexGridData
extends Resource

## Serializable data representing all cells in a hex grid

## Dictionary mapping Vector2i (axial coords) to cell data
## Each entry: {
##   "scene_path": String,          # Path to tile .tscn file
##   "rotation_degrees": float,
##   "world_position": Vector3,     # Stored position for persistence
##   "placed_pointy_top": bool,     # Orientation when placed
##   "height_scale": float          # Height multiplier (1.0 = normal)
## }
@export var cells: Dictionary = {}

## Grid configuration (used for guide grid, not for cell positions)
@export var grid_width: int = 10
@export var grid_height: int = 10
@export var hex_size: float = 1.0
@export var pointy_top: bool = true

func set_cell(axial_coord: Vector2i, scene_path: String, rotation_deg: float, world_pos: Vector3, was_pointy_top: bool, height_scale: float = 1.0) -> void:
	cells[axial_coord] = {
		"scene_path": scene_path,
		"rotation_degrees": rotation_deg,
		"world_position": world_pos,
		"placed_pointy_top": was_pointy_top,
		"height_scale": height_scale
	}

func remove_cell(axial_coord: Vector2i) -> void:
	cells.erase(axial_coord)

func get_cell(axial_coord: Vector2i) -> Dictionary:
	return cells.get(axial_coord, {})

func has_cell(axial_coord: Vector2i) -> bool:
	return cells.has(axial_coord)

func clear() -> void:
	cells.clear()
