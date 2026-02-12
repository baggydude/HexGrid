@tool
class_name HexGrid3D
extends Node3D

## 3D Hex Grid node with editor support for painting hex brushes (scene-based)

signal cell_changed(axial_coord: Vector2i)
signal grid_cleared

const DEFAULT_BRUSH_PATH := "res://addons/hex_grid_editor/brushes/"

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
		_update_guide_grid()

@export var pointy_top: bool = true:
	set(value):
		if value != pointy_top:
			pointy_top = value
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

## Path to folder containing HexBrushResource .tres files
@export var brush_resource_folder: String = DEFAULT_BRUSH_PATH:
	set(value):
		brush_resource_folder = value
		_scan_brush_folder()

## Brush palette (auto-populated from brush_resource_folder)
var brush_palette: Array[HexBrushResource] = []

## Internal references
var _guide_mesh_instance: MeshInstance3D
var _cell_container: Node3D
var _cell_instances: Dictionary = {}  # Vector2i -> Node3D (instantiated scene)


func _ready() -> void:
	_setup_containers()
	_update_guide_grid()
	_scan_brush_folder()
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


func _scan_brush_folder() -> void:
	brush_palette.clear()
	var dir := DirAccess.open(brush_resource_folder)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			var res := ResourceLoader.load(brush_resource_folder.path_join(file_name))
			if res is HexBrushResource:
				brush_palette.append(res)
		file_name = dir.get_next()
	brush_palette.sort_custom(func(a: HexBrushResource, b: HexBrushResource) -> bool: return a.name < b.name)


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


## Place a brush scene at the given axial coordinate
func place_brush(axial_coord: Vector2i, brush: HexBrushResource, variation_index: int = 0, rotation_degrees: float = 0.0, height_scale: float = 1.0) -> void:
	if not brush:
		return
	if brush.variations.is_empty():
		return
	variation_index = clampi(variation_index, 0, brush.variations.size() - 1)

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
		grid_data.pointy_top = pointy_top

	# Calculate world position at placement time
	var world_pos := HexMath.axial_to_world(axial_coord, hex_size, pointy_top)

	# Update data
	grid_data.set_cell(axial_coord, brush, variation_index, rotation_degrees, world_pos, pointy_top, height_scale)

	# Update visual
	_create_or_update_cell_instance(axial_coord, brush, variation_index, rotation_degrees, world_pos, pointy_top, height_scale)

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


func _create_or_update_cell_instance(axial_coord: Vector2i, brush: HexBrushResource, variation_index: int, rotation_degrees: float, world_pos: Vector3, placed_pointy_top: bool, height_scale: float = 1.0) -> void:
	_setup_containers()

	# Remove existing instance if present (scenes must be fully replaced)
	if _cell_instances.has(axial_coord):
		_cell_instances[axial_coord].queue_free()
		_cell_instances.erase(axial_coord)

	# Instantiate the scene variation
	var scene: PackedScene = brush.variations[variation_index]
	if not scene:
		return

	var instance: Node3D = scene.instantiate()
	_clear_owners(instance)
	_cell_container.add_child(instance, false, Node.INTERNAL_MODE_BACK)
	_cell_instances[axial_coord] = instance

	# Apply rotation on Y axis
	instance.rotation_degrees.y = rotation_degrees

	# Place scene at hex center on the grid plane
	instance.position = Vector3(world_pos.x, 0, world_pos.z)

	# Only scale the Base MeshInstance3D child's Y for height
	# Base mesh origin is at top, body extends in -Y direction
	# height_scale stretches it further downward, creating a pillar effect
	var base_node := instance.find_child("Base", true, false) as MeshInstance3D
	if base_node:
		base_node.scale.y = height_scale

	# Store metadata on the instance for later retrieval
	instance.set_meta("axial_coord", axial_coord)
	instance.set_meta("brush_resource", brush)
	instance.set_meta("variation_index", variation_index)
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
	pointy_top = grid_data.pointy_top

	# Rebuild cells using their stored positions
	for axial_coord in grid_data.cells:
		var cell_data: Dictionary = grid_data.cells[axial_coord]
		var brush: HexBrushResource = cell_data.get("brush_resource")
		var variation_index: int = cell_data.get("variation_index", 0)
		var rotation: float = cell_data.get("rotation_degrees", 0.0)
		var world_pos: Vector3 = cell_data.get("world_position", Vector3.ZERO)
		var placed_pointy: bool = cell_data.get("placed_pointy_top", pointy_top)
		var height_scale: float = cell_data.get("height_scale", 1.0)

		# If no stored position (legacy data), calculate it
		if world_pos == Vector3.ZERO:
			world_pos = HexMath.axial_to_world(axial_coord, hex_size, placed_pointy)

		if brush and not brush.variations.is_empty():
			variation_index = clampi(variation_index, 0, brush.variations.size() - 1)
			_create_or_update_cell_instance(axial_coord, brush, variation_index, rotation, world_pos, placed_pointy, height_scale)


func _rebuild_all_cells() -> void:
	if not grid_data:
		return

	# Update existing instances without re-instantiating
	for axial_coord in _cell_instances:
		var instance: Node3D = _cell_instances[axial_coord]
		var world_pos: Vector3 = instance.get_meta("world_position")
		var height_scale: float = instance.get_meta("height_scale") if instance.has_meta("height_scale") else 1.0
		var rotation: float = instance.get_meta("rotation_degrees") if instance.has_meta("rotation_degrees") else 0.0

		# Apply rotation
		instance.rotation_degrees.y = rotation

		# Place at grid plane
		instance.position = Vector3(world_pos.x, 0, world_pos.z)

		# Only scale Base's Y for height
		var base_node := instance.find_child("Base", true, false) as MeshInstance3D
		if base_node:
			base_node.scale.y = height_scale


static func _clear_owners(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owners(child)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if brush_palette.is_empty():
		warnings.append("No brush resources found. Add HexBrushResource .tres files to: " + brush_resource_folder)
	return warnings
