@tool
class_name HexGrid3D
extends Node3D

## 3D Hex Grid node with editor support for painting tiles

signal cell_changed(axial_coord: Vector2i)
signal grid_cleared

## Grid configuration
@export_group("Grid Settings")
@export var grid_width: int = 10:
	set(value):
		grid_width = max(1, value)
		_update_guide_grid()
		
@export var grid_height: int = 10:
	set(value):
		grid_height = max(1, value)
		_update_guide_grid()

@export var hex_size: float = 1.0:
	set(value):
		hex_size = max(0.1, value)
		_rebuild_all_cells()
		_update_guide_grid()

## Scale factor for placed meshes (0.0-1.0). 1.0 = full hex size, 0.9 = 90% etc.
@export_range(0.1, 1.0, 0.01) var mesh_scale: float = 1:
	set(value):
		mesh_scale = clamp(value, 0.1, 1.0)
		_rebuild_all_cells()

@export var pointy_top: bool = true:
	set(value):
		if value != pointy_top:
			pointy_top = value
			# Clear all placed tiles when orientation changes - they won't align anyway
			clear_all_tiles()
			_update_guide_grid()
		else:
			pointy_top = value

## Visual settings
@export_group("Visual Settings")
@export var show_guide_grid: bool = true:
	set(value):
		show_guide_grid = value
		_update_guide_visibility()

@export var guide_grid_color: Color = Color(0.5, 0.5, 0.5, 0.5):
	set(value):
		guide_grid_color = value
		_update_guide_material()

@export var guide_grid_height: float = 0.01:
	set(value):
		guide_grid_height = value
		_update_guide_grid()

## Grid data resource (serialized)
@export var grid_data: HexGridData:
	set(value):
		grid_data = value
		if grid_data:
			_sync_from_data()

## Available tile resources for painting
@export var tile_palette: Array[HexTileResource] = []

## Internal references
var _guide_mesh_instance: MeshInstance3D
var _cell_container: Node3D
var _cell_instances: Dictionary = {}  # Vector2i -> MeshInstance3D


func _ready() -> void:
	_setup_containers()
	_update_guide_grid()
	if grid_data:
		_sync_from_data()


func _setup_containers() -> void:
	# Cell container
	_cell_container = get_node_or_null("CellContainer")
	if not _cell_container:
		_cell_container = Node3D.new()
		_cell_container.name = "CellContainer"
		add_child(_cell_container, false, Node.INTERNAL_MODE_BACK)
	
	# Guide grid mesh
	_guide_mesh_instance = get_node_or_null("GuideGrid")
	if not _guide_mesh_instance:
		_guide_mesh_instance = MeshInstance3D.new()
		_guide_mesh_instance.name = "GuideGrid"
		add_child(_guide_mesh_instance, false, Node.INTERNAL_MODE_BACK)


func _update_guide_visibility() -> void:
	if _guide_mesh_instance:
		_guide_mesh_instance.visible = show_guide_grid


func _update_guide_material() -> void:
	if _guide_mesh_instance and _guide_mesh_instance.mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = guide_grid_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_guide_mesh_instance.material_override = mat


func _update_guide_grid() -> void:
	if not is_inside_tree():
		return
	
	_setup_containers()
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	
	# Generate hex outline for each cell in the grid
	var coords := HexMath.get_grid_coords(grid_width, grid_height, pointy_top)
	
	for axial in coords:
		var center := HexMath.axial_to_world(axial, hex_size, pointy_top)
		center.y = guide_grid_height
		_add_hex_outline(st, center)
	
	var mesh := st.commit()
	_guide_mesh_instance.mesh = mesh
	_update_guide_material()
	_update_guide_visibility()


func _add_hex_outline(st: SurfaceTool, center: Vector3) -> void:
	# For pointy-top: first vertex points up (angle = -PI/2 or 90 degrees from +X toward -Z)
	# For flat-top: first vertex points right (angle = 0), giving flat edge on top
	var angle_offset := -PI / 2.0 if pointy_top else 0.0
	var corners: Array[Vector3] = []
	
	for i in range(6):
		var angle := angle_offset + i * PI / 3.0
		var corner := Vector3(
			center.x + hex_size * cos(angle),
			center.y,
			center.z + hex_size * sin(angle)
		)
		corners.append(corner)
	
	for i in range(6):
		st.add_vertex(corners[i])
		st.add_vertex(corners[(i + 1) % 6])


## Place a tile at the given axial coordinate
func place_tile(axial_coord: Vector2i, tile: HexTileResource, rotation_degrees: float = 0.0, height_scale: float = 1.0) -> void:
	if not tile:
		return

	# Check bounds
	var offset := HexMath.axial_to_offset(axial_coord, pointy_top)
	if not HexMath.is_in_bounds(offset, grid_width, grid_height):
		return

	# Ensure data resource exists
	if not grid_data:
		grid_data = HexGridData.new()
		grid_data.grid_width = grid_width
		grid_data.grid_height = grid_height
		grid_data.hex_size = hex_size
		grid_data.mesh_scale = mesh_scale
		grid_data.pointy_top = pointy_top

	# Calculate world position at placement time
	var world_pos := HexMath.axial_to_world(axial_coord, hex_size, pointy_top)
	world_pos.y = tile.height_offset

	# Update data - store position, orientation, and height scale used at placement
	grid_data.set_cell(axial_coord, tile, rotation_degrees, world_pos, pointy_top, height_scale)

	# Update visual
	_create_or_update_cell_instance(axial_coord, tile, rotation_degrees, world_pos, pointy_top, height_scale)

	cell_changed.emit(axial_coord)

	if Engine.is_editor_hint():
		notify_property_list_changed()


## Remove a tile at the given axial coordinate
func remove_tile(axial_coord: Vector2i) -> void:
	if grid_data:
		grid_data.remove_cell(axial_coord)
	
	if _cell_instances.has(axial_coord):
		_cell_instances[axial_coord].queue_free()
		_cell_instances.erase(axial_coord)
	
	cell_changed.emit(axial_coord)


## Get tile data at coordinate
func get_tile_at(axial_coord: Vector2i) -> Dictionary:
	if grid_data:
		return grid_data.get_cell(axial_coord)
	return {}


## Check if coordinate has a tile
func has_tile_at(axial_coord: Vector2i) -> bool:
	if grid_data:
		return grid_data.has_cell(axial_coord)
	return false


## Clear all tiles
func clear_all_tiles() -> void:
	if grid_data:
		grid_data.clear()
	
	for cell in _cell_instances.values():
		cell.queue_free()
	_cell_instances.clear()
	
	grid_cleared.emit()


## Convert world position to axial coordinates
func world_to_axial(world_pos: Vector3) -> Vector2i:
	var local_pos := to_local(world_pos)
	return HexMath.world_to_axial(local_pos, hex_size, pointy_top)


## Convert axial coordinates to world position
func axial_to_world(axial_coord: Vector2i) -> Vector3:
	var local_pos := HexMath.axial_to_world(axial_coord, hex_size, pointy_top)
	return to_global(local_pos)


## Snap a world position to the nearest hex center
func snap_to_hex(world_pos: Vector3) -> Vector3:
	var axial := world_to_axial(world_pos)
	return axial_to_world(axial)


## Check if axial coordinate is within grid bounds
func is_in_bounds(axial_coord: Vector2i) -> bool:
	var offset := HexMath.axial_to_offset(axial_coord, pointy_top)
	return HexMath.is_in_bounds(offset, grid_width, grid_height)


func _create_or_update_cell_instance(axial_coord: Vector2i, tile: HexTileResource, rotation_degrees: float, world_pos: Vector3, placed_pointy_top: bool, height_scale: float = 1.0) -> void:
	_setup_containers()

	var instance: MeshInstance3D

	if _cell_instances.has(axial_coord):
		instance = _cell_instances[axial_coord]
	else:
		instance = MeshInstance3D.new()
		_cell_container.add_child(instance, false, Node.INTERNAL_MODE_BACK)
		_cell_instances[axial_coord] = instance

	# Set mesh
	instance.mesh = tile.mesh

	# Set material
	if tile.material_override:
		instance.material_override = tile.material_override
	else:
		instance.material_override = null

	# Set position (use the stored world position)
	instance.position = Vector3(world_pos.x, 0, world_pos.z)

	# Set rotation - mesh is already oriented correctly, just apply user rotation
	instance.rotation_degrees.y = rotation_degrees

	# Set scale to fit within hex bounds
	# mesh_scale of 1.0 means the mesh fills the hex, 0.95 gives a small gap
	# height_scale affects only the Y axis (1.0 = original, 2.0 = twice as tall)
	var scale_factor := hex_size * mesh_scale
	instance.scale = Vector3(scale_factor, scale_factor * height_scale, scale_factor)

	# Store metadata
	instance.set_meta("axial_coord", axial_coord)
	instance.set_meta("tile_resource", tile)
	instance.set_meta("rotation_degrees", rotation_degrees)
	instance.set_meta("world_position", world_pos)
	instance.set_meta("placed_pointy_top", placed_pointy_top)
	instance.set_meta("height_scale", height_scale)


func _sync_from_data() -> void:
	if not grid_data:
		return

	# Clear existing instances
	for cell in _cell_instances.values():
		cell.queue_free()
	_cell_instances.clear()

	# Update grid settings from data
	grid_width = grid_data.grid_width
	grid_height = grid_data.grid_height
	hex_size = grid_data.hex_size
	mesh_scale = grid_data.mesh_scale if grid_data.mesh_scale > 0 else 0.95
	pointy_top = grid_data.pointy_top

	# Rebuild cells using their stored positions
	for axial_coord in grid_data.cells:
		var cell_data: Dictionary = grid_data.cells[axial_coord]
		var tile: HexTileResource = cell_data.get("tile_resource")
		var rotation: float = cell_data.get("rotation_degrees", 0.0)
		var world_pos: Vector3 = cell_data.get("world_position", Vector3.ZERO)
		var placed_pointy: bool = cell_data.get("placed_pointy_top", pointy_top)
		var height_scale: float = cell_data.get("height_scale", 1.0)

		# If no stored position (legacy data), calculate it
		if world_pos == Vector3.ZERO:
			world_pos = HexMath.axial_to_world(axial_coord, hex_size, placed_pointy)
			if tile:
				world_pos.y = tile.height_offset

		if tile:
			_create_or_update_cell_instance(axial_coord, tile, rotation, world_pos, placed_pointy, height_scale)


func _rebuild_all_cells() -> void:
	if not grid_data:
		return

	# Rebuild using stored positions - cells don't move
	for axial_coord in _cell_instances:
		var instance: MeshInstance3D = _cell_instances[axial_coord]
		var tile: HexTileResource = instance.get_meta("tile_resource")
		var world_pos: Vector3 = instance.get_meta("world_position")
		var rotation: float = instance.get_meta("rotation_degrees")
		var height_scale: float = instance.get_meta("height_scale") if instance.has_meta("height_scale") else 1.0

		# Position stays the same (uses stored world_pos)
		# Only update Y for height offset changes
		if tile:
			world_pos.y = tile.height_offset
		instance.position = world_pos

		# Apply user rotation only
		instance.rotation_degrees.y = rotation

		# Update scale (height_scale affects only Y axis)
		var scale_factor := hex_size * mesh_scale
		instance.scale = Vector3(scale_factor, scale_factor * height_scale, scale_factor)


## Optional: Call this if you want to remap all tiles to the current orientation
func remap_tiles_to_current_orientation() -> void:
	if not grid_data:
		return

	for axial_coord in _cell_instances:
		var instance: MeshInstance3D = _cell_instances[axial_coord]
		var tile: HexTileResource = instance.get_meta("tile_resource")
		var rotation: float = instance.get_meta("rotation_degrees")
		var height_scale: float = instance.get_meta("height_scale") if instance.has_meta("height_scale") else 1.0

		# Recalculate position with current orientation
		var world_pos := HexMath.axial_to_world(axial_coord, hex_size, pointy_top)
		world_pos.y = tile.height_offset if tile else 0.0
		instance.position = world_pos

		# Apply user rotation only
		instance.rotation_degrees.y = rotation

		# Update stored metadata
		instance.set_meta("world_position", world_pos)
		instance.set_meta("placed_pointy_top", pointy_top)

		# Update grid data
		if tile:
			grid_data.set_cell(axial_coord, tile, rotation, world_pos, pointy_top, height_scale)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if tile_palette.is_empty():
		warnings.append("No tile resources in palette. Add HexTileResource items to the Tile Palette.")
	return warnings
