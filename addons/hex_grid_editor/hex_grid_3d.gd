@tool
class_name HexGrid3D
extends Node3D

## 3D Hex Grid node with editor support for painting hex tiles (scene-based)

signal cell_changed(axial_coord: Vector2i)
signal grid_cleared

const DEFAULT_TILE_PATH := "res://addons/hex_grid_editor/tiles/"

## Grid configuration
@export_group("Grid Settings")
@export var grid_width: int = 10:
	set(value):
		grid_width = max(1, value)
		if grid_data:
			grid_data.grid_width = grid_width
		_update_guide_grid()

@export var grid_height: int = 10:
	set(value):
		grid_height = max(1, value)
		if grid_data:
			grid_data.grid_height = grid_height
		_update_guide_grid()

## Outer radius: distance from hex center to vertex, in meters
@export_range(0.1, 100.0, 0.01, "suffix:m") var hex_size: float = 1.0:
	set(value):
		hex_size = max(0.1, value)
		if grid_data:
			grid_data.hex_size = hex_size
		_update_guide_grid()

@export var pointy_top: bool = true:
	set(value):
		if value != pointy_top:
			pointy_top = value
			if grid_data:
				grid_data.pointy_top = pointy_top
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

## Path to folder containing tile .tscn scene files
@export var tile_scene_folder: String = DEFAULT_TILE_PATH:
	set(value):
		tile_scene_folder = value
		_scan_tile_folder()

## Tile palette: scene_path -> PackedScene (auto-populated from tile_scene_folder)
var tile_palette: Dictionary = {}

## Internal references
var _guide_mesh_instance: MeshInstance3D
var _cell_container: Node3D
var _cell_instances: Dictionary = {}  # Vector2i -> Node3D (instantiated scene)


func _ready() -> void:
	_setup_containers()
	_update_guide_grid()
	_scan_tile_folder()
	if grid_data:
		_sync_from_data()


func _setup_containers() -> void:
	# Cell container
	_cell_container = get_node_or_null("CellContainer")
	if not _cell_container:
		_cell_container = Node3D.new()
		_cell_container.name = "CellContainer"
		add_child(_cell_container)

	# Guide grid mesh
	_guide_mesh_instance = get_node_or_null("GuideGrid")
	if not _guide_mesh_instance:
		_guide_mesh_instance = MeshInstance3D.new()
		_guide_mesh_instance.name = "GuideGrid"
		add_child(_guide_mesh_instance)


func _scan_tile_folder() -> void:
	tile_palette.clear()
	var dir := DirAccess.open(tile_scene_folder)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tscn"):
			var path := tile_scene_folder.path_join(file_name)
			var scene := ResourceLoader.load(path) as PackedScene
			if scene:
				tile_palette[path] = scene
		file_name = dir.get_next()


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


## Place a tile scene at the given axial coordinate
func place_tile(axial_coord: Vector2i, scene_path: String, rotation_degrees: float = 0.0, height_scale: float = 1.0) -> void:
	var scene: PackedScene = tile_palette.get(scene_path)
	if not scene:
		scene = ResourceLoader.load(scene_path) as PackedScene
		if not scene:
			return
		tile_palette[scene_path] = scene

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
	grid_data.set_cell(axial_coord, scene_path, rotation_degrees, world_pos, pointy_top, height_scale)

	# Update visual
	_create_or_update_cell_instance(axial_coord, scene, scene_path, rotation_degrees, world_pos, pointy_top, height_scale)

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


func _create_or_update_cell_instance(axial_coord: Vector2i, scene: PackedScene, scene_path: String, rotation_degrees: float, world_pos: Vector3, placed_pointy_top: bool, height_scale: float = 1.0) -> void:
	_setup_containers()

	# Remove existing instance if present (scenes must be fully replaced)
	if _cell_instances.has(axial_coord):
		_cell_instances[axial_coord].queue_free()
		_cell_instances.erase(axial_coord)

	var instance: Node3D = scene.instantiate()
	_cell_container.add_child(instance)
	if Engine.is_editor_hint() and get_tree():
		_set_owners(instance, get_tree().edited_scene_root)
	_cell_instances[axial_coord] = instance

	# Apply rotation on Y axis
	instance.rotation_degrees.y = rotation_degrees

	# Place scene at hex center, offset Y by height_scale
	instance.position = Vector3(world_pos.x, height_scale, world_pos.z)

	# Only scale the Base MeshInstance3D child's Y for height
	var base_node := instance.find_child("Base", true, false) as MeshInstance3D
	if base_node:
		base_node.scale.y = height_scale

	# Store metadata on the instance for later retrieval
	instance.set_meta("axial_coord", axial_coord)
	instance.set_meta("scene_path", scene_path)
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

	# Node properties are the source of truth - sync TO data
	grid_data.grid_width = grid_width
	grid_data.grid_height = grid_height
	grid_data.hex_size = hex_size
	grid_data.pointy_top = pointy_top

	# Rebuild cells using their stored positions
	for axial_coord in grid_data.cells:
		var cell_data: Dictionary = grid_data.cells[axial_coord]
		var scene_path: String = cell_data.get("scene_path", "")
		var rotation: float = cell_data.get("rotation_degrees", 0.0)
		var world_pos: Vector3 = cell_data.get("world_position", Vector3.ZERO)
		var placed_pointy: bool = cell_data.get("placed_pointy_top", pointy_top)
		var height_scale: float = cell_data.get("height_scale", 1.0)

		if scene_path.is_empty():
			continue

		# If no stored position (legacy data), calculate it
		if world_pos == Vector3.ZERO:
			world_pos = HexMath.axial_to_world(axial_coord, hex_size, placed_pointy)

		var scene := ResourceLoader.load(scene_path) as PackedScene
		if scene:
			_create_or_update_cell_instance(axial_coord, scene, scene_path, rotation, world_pos, placed_pointy, height_scale)


static func _set_owners(node: Node, new_owner: Node) -> void:
	node.owner = new_owner
	for child in node.get_children():
		_set_owners(child, new_owner)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if tile_palette.is_empty():
		warnings.append("No tile scenes found. Add .tscn files to: " + tile_scene_folder)
	return warnings
